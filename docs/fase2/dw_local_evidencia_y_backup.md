# DW Local — Backup y Evidencia de Lectura

El **DW local** es una copia completa de la capa Gold (`gold_ss2`) en
PostgreSQL, que sirve dos propósitos a la vez: es el **backup secundario**
del DW y es la evidencia de que el Gold se puede **leer fuera de Databricks**.
Los scripts viven en [`dw-backup/`](https://github.com/SofiaQuintana/ss2-dw-project-covid-research/tree/main/dw-backup).

## Estrategia de carga: conexión directa, no Parquet intermedio

Databricks corre en AWS y no tiene visibilidad de `localhost`, pero la
máquina local sí puede iniciar una conexión saliente hacia Databricks. Por
eso el backup **no exporta Gold a archivos Parquet intermedios** — el
script `load-postgresql.py` lee las 7 tablas de `gold_ss2` directamente vía
**`databricks-sql-connector`** contra el SQL Warehouse de Databricks, y las
inserta en PostgreSQL con `COPY` (vía `psycopg`):

```
gold_ss2 en Databricks (SQL Warehouse)
    │  databricks-sql-connector (lectura por lotes Arrow)
    ▼
load-postgresql.py
    │  psycopg COPY, una transacción
    ▼
PostgreSQL local (Docker) — schema gold_ss2
```

!!! info "Por qué no Parquet"
    Las dos tablas más grandes en Silver superan el millón de filas
    (`dbx_primeras_causas_de_morbilidad_2015_a_2025` y
    `dbx_morbilidad_grupo_materno_infantil_2012_a_2025`), pero las tablas
    Gold ya son agregados dimensionales mucho más pequeños. Conectarse
    directamente al SQL Warehouse evita el paso intermedio de exportar a un
    Volume y mantiene el backup en un solo script ejecutable.

## El backup es transaccional, no un volcado simple

`load-postgresql.py` no hace `INSERT` fila por fila ni confía en que la
carga funcione a la primera. Toda la operación corre dentro de **una sola
transacción de PostgreSQL**:

1. Ejecuta el DDL (`postgres-ddl.sql`, idempotente — `CREATE TABLE IF NOT EXISTS`) para garantizar que las 7 tablas existen.
2. `TRUNCATE` de las 7 tablas en un solo statement.
3. `COPY` por lotes (Arrow, tamaño configurable vía `BATCH_SIZE`) de cada tabla, en orden de dependencia: las 5 dimensiones primero, luego las 2 fact tables.
4. Valida que el conteo de filas en destino coincida con el conteo en origen, tabla por tabla.
5. `COMMIT` — solo si la validación del paso 4 pasó para las 7 tablas. Si cualquier paso falla, `ROLLBACK` y el backup anterior queda intacto (no hay estado intermedio corrupto).

Las claves foráneas en `postgres-ddl.sql` se declaran `DEFERRABLE INITIALLY
DEFERRED`: PostgreSQL no las valida fila por fila durante el `COPY` (lo que
sería lento), sino una sola vez al `COMMIT` — después de que las 7 tablas
ya están cargadas.

Las conexiones a Databricks y a PostgreSQL usan reintentos automáticos
(`tenacity`, backoff exponencial) para tolerar fallos de red transitorios
sin abortar todo el backup a la primera desconexión.

## Esquema replicado en PostgreSQL

`postgres-ddl.sql` replica exactamente el galaxy schema de Gold: 5
dimensiones + 2 fact tables, con los mismos nombres de columna que en
Databricks (ver [Arquitectura](arquitectura.md#modelo-dimensional-gold-galaxy-schema)
para el diagrama ERD completo). Además crea un índice por cada FK de las
fact tables — PostgreSQL no los crea automáticamente, y aceleran los joins
fact↔dim al consultar el backup.

`schema-and-role.sql` se ejecuta una sola vez, al crear el volumen de
PostgreSQL por primera vez: crea el rol `dw_reader`, de solo lectura, para
que cualquier consulta analítica contra el backup (como la demo de abajo)
no tenga permisos de escritura sobre los datos.

## Configuración

El loader corre en Docker (`dw-backup/Dockerfile`, imagen `python:3.12-slim`
+ `libpq5`) y se configura completamente por variables de entorno
(`dw-backup/.env.example` documenta cada una):

| Variable | Uso |
|----------|-----|
| `DATABRICKS_SERVER_HOSTNAME`, `DATABRICKS_HTTP_PATH`, `DATABRICKS_TOKEN` | Conexión al SQL Warehouse de origen |
| `PG_HOST`, `PG_PORT`, `PG_DB`, `PG_USER`, `PG_PASSWORD` | Conexión a PostgreSQL destino (usadas por `load-postgresql.py`) |
| `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB` | Mismas credenciales, pero leídas por la imagen oficial de Postgres al inicializar el contenedor — deben coincidir con las `PG_*` de arriba |
| `BATCH_SIZE` | Filas por lote en la lectura Arrow / escritura `COPY` (default 100 000) |

Ninguna credencial real se versiona en el repositorio — `.env.example`
documenta el formato esperado de cada variable sin valores reales.

## Evidencia de lectura: `demo-read-from-local-dw.ipynb`

Este notebook es la evidencia exigida por el criterio de aceptación: se
conecta al PostgreSQL local (no a Databricks) y ejecuta consultas
analíticas reales contra el backup ya cargado.

```bash
pip install psycopg[binary] pandas python-dotenv
docker compose up -d postgres   # levanta el contenedor de PostgreSQL
```

El notebook ejecuta, en orden:

1. **Conteo de filas por tabla** — de las 7 tablas de `gold_ss2`, como verificación rápida de que el backup cargó algo.
2. **Defunciones por año y departamento en Guatemala** — join de `fact_defunciones` con `dim_tiempo` y `dim_geografia`, filtrando `nivel_geo = 'departamento'`.
3. **Top causas de morbilidad, periodo COVID vs. pre-COVID** — join de `fact_morbilidad` con `dim_tiempo` y `dim_causa`, agrupado por `periodo_covid`.
4. **Mortalidad WHO — Guatemala vs. Costa Rica** — promedio de `tasa_mortalidad_x100k` por país y año, filtrando `nivel_geo = 'pais'` y descartando los `NULL` (preservados desde Silver).

```sql
-- Query #2 del notebook — defunciones por año y departamento
SELECT
    d.anio,
    d.periodo_covid,
    g.departamento,
    SUM(f.total_defunciones) AS defunciones
FROM gold_ss2.fact_defunciones f
JOIN gold_ss2.dim_tiempo     d ON f.tiempo_sk    = d.tiempo_sk
JOIN gold_ss2.dim_geografia  g ON f.geografia_sk = g.geografia_sk
WHERE g.nivel_geo = 'departamento'
  AND g.pais      = 'Guatemala'
GROUP BY d.anio, d.periodo_covid, g.departamento
ORDER BY d.anio, defunciones DESC
```

Las credenciales de conexión se leen desde `dw-backup/.env` (nunca se suben
a git) mediante `python-dotenv`.

## Restaurar el backup desde cero

Si el volumen de PostgreSQL se pierde o se reinicia, el backup completo se
reconstruye en dos pasos:

```bash
# 1. Levantar PostgreSQL vacío (ejecuta schema-and-role.sql al inicializar)
docker compose up -d postgres

# 2. Ejecutar el loader — aplica el DDL, trunca, copia y valida
docker compose run --rm dw-backup
```

No se necesita restaurar ningún archivo de backup externo (no hay dump
`.sql` ni Parquet que mantener sincronizado): el loader siempre lee el
estado actual de `gold_ss2` en Databricks y reconstruye PostgreSQL desde
ahí. Esto significa que el backup más reciente disponible es, por diseño,
tan reciente como la última ejecución del loader — correrlo periódicamente
(o como parte del Databricks Workflow) es lo que mantiene el backup al día.

## Referencia cruzada

[Arquitectura](arquitectura.md) documenta el diagrama de despliegue
completo (qué corre en AWS vs. en la máquina local) y el modelo dimensional
de Gold que este backup replica.
