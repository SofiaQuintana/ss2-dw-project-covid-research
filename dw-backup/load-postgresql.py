"""Backup full de la capa Gold (Databricks → Postgres).

Flujo (todo dentro de UNA transacción Postgres, atómica):
  1. Ejecuta el DDL (idempotente) para garantizar que las tablas existen.
  2. TRUNCATE de las 7 tablas en un solo statement.
  3. COPY por lotes de cada tabla, en orden de dependencia (dims → facts).
  4. Valida conteos origen vs destino.
  5. COMMIT. Si algo falla en 2-4 → ROLLBACK y el backup previo queda intacto.

Las FK son DEFERRABLE INITIALLY DEFERRED: se chequean al COMMIT.
"""

import logging
import os
import sys
import time

import psycopg
from databricks import sql
from tenacity import retry, stop_after_attempt, wait_exponential, wait_fixed

logging.basicConfig(
    level=logging.INFO,
    format='{"ts":"%(asctime)s","level":"%(levelname)s","msg":"%(message)s"}',
)
log = logging.getLogger("dw-backup")

# ── Configuración ──────────────────────────────────────────────────
SRC_CATALOG   = os.environ.get("SRC_CATALOG", "ss2_dw_workspace")
SRC_SCHEMA    = os.environ.get("SRC_SCHEMA", "gold_ss2")
PG_SCHEMA     = os.environ.get("PG_SCHEMA", "gold_ss2")
BATCH_SIZE    = int(os.environ.get("BATCH_SIZE", "100000"))
DDL_PATH      = os.environ.get("DDL_PATH", "/app/postgres-ddl.sql")

DIMENSIONS = ["dim_causa", "dim_demografia", "dim_fuente", "dim_geografia", "dim_tiempo"]
FACTS      = ["fact_defunciones", "fact_morbilidad"]
LOAD_ORDER = DIMENSIONS + FACTS   # dims antes que facts (dependencia FK)


# ── Conexiones ─────────────────────────────────────────────────────
@retry(stop=stop_after_attempt(3), wait=wait_exponential(multiplier=2, min=2, max=30), reraise=True)
def connect_databricks():
    return sql.connect(
        server_hostname=os.environ["DATABRICKS_SERVER_HOSTNAME"],
        http_path=os.environ["DATABRICKS_HTTP_PATH"],
        access_token=os.environ["DATABRICKS_TOKEN"],
    )


@retry(stop=stop_after_attempt(5), wait=wait_exponential(multiplier=1, min=2, max=20), reraise=True)
def connect_postgres():
    return psycopg.connect(
        host=os.environ["PG_HOST"],
        port=os.environ.get("PG_PORT", "5432"),
        dbname=os.environ["PG_DB"],
        user=os.environ["PG_USER"],
        password=os.environ["PG_PASSWORD"],
        autocommit=False,
    )


# ── Helpers ────────────────────────────────────────────────────────
@retry(stop=stop_after_attempt(3), wait=wait_fixed(2), reraise=True)
def source_count(dbx, table):
    cur = dbx.cursor()
    cur.execute(f"SELECT COUNT(*) FROM {SRC_CATALOG}.{SRC_SCHEMA}.{table}")
    n = cur.fetchone()[0]
    cur.close()
    return n


def copy_table(dbx, pg_cur, table):
    """Lee la tabla de Databricks por lotes Arrow y la inserta con COPY."""
    dcur = dbx.cursor()
    dcur.execute(f"SELECT * FROM {SRC_CATALOG}.{SRC_SCHEMA}.{table}")

    batch = dcur.fetchmany_arrow(BATCH_SIZE)
    cols = [f.name for f in batch.schema]
    col_list = ", ".join(f'"{c}"' for c in cols)

    rows = 0
    with pg_cur.copy(f'COPY {PG_SCHEMA}."{table}" ({col_list}) FROM STDIN') as cp:
        while batch.num_rows:
            for r in batch.to_pylist():
                cp.write_row(tuple(r[c] for c in cols))
            rows += batch.num_rows
            batch = dcur.fetchmany_arrow(BATCH_SIZE)
    dcur.close()
    return rows


# ── Main ───────────────────────────────────────────────────────────
def main():
    dbx = connect_databricks()
    pg = connect_postgres()
    log.info("Conexiones establecidas (Databricks + Postgres)")

    # DDL idempotente, fuera de la transacción de datos.
    with open(DDL_PATH) as f:
        pg.execute(f.read())
    pg.commit()
    log.info("DDL aplicado (tablas/índices garantizados)")

    loaded = {}
    try:
        with pg.cursor() as cur:
            cur.execute("SET CONSTRAINTS ALL DEFERRED")
            all_tables = ", ".join(f'{PG_SCHEMA}."{t}"' for t in LOAD_ORDER)
            cur.execute(f"TRUNCATE {all_tables}")
            log.info("TRUNCATE de las 7 tablas OK")

            for table in LOAD_ORDER:
                t0 = time.monotonic()
                loaded[table] = copy_table(dbx, cur, table)
                log.info(f"{table}: {loaded[table]} filas cargadas en {time.monotonic()-t0:.1f}s")

            # Validación antes de confirmar: si no cuadra, ROLLBACK.
            for table in LOAD_ORDER:
                src = source_count(dbx, table)
                if src != loaded[table]:
                    raise RuntimeError(
                        f"{table}: MISMATCH origen={src} destino={loaded[table]}"
                    )
        pg.commit()  # valida las FK DEFERRED aquí
        log.info("COMMIT OK — backup completo y validado")
    except Exception as e:  # noqa: BLE001
        pg.rollback()
        log.error(f"ROLLBACK — backup abortado: {type(e).__name__}: {e}")
        sys.exit(1)
    finally:
        pg.close()
        dbx.close()


if __name__ == "__main__":
    main()
