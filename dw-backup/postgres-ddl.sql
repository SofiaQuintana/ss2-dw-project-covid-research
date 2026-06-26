-- =====================================================================
--  DDL del backup de la capa Gold (modelo galaxia: 5 dims + 2 facts)
--  Fuente de verdad del esquema. Idempotente (CREATE ... IF NOT EXISTS).
--  El loader lo ejecuta al inicio de cada corrida.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS gold_ss2;

-- ============================ Dimensiones ============================

CREATE TABLE IF NOT EXISTS gold_ss2.dim_causa (
    causa_sk      INTEGER PRIMARY KEY,
    codigo_origen TEXT NOT NULL,
    descripcion   TEXT
);

CREATE TABLE IF NOT EXISTS gold_ss2.dim_demografia (
    demografia_sk          INTEGER PRIMARY KEY,
    sexo                   TEXT NOT NULL,
    grupo_etario_label     TEXT NOT NULL,
    grupo_etario_anios_min DOUBLE PRECISION,
    grupo_etario_anios_max DOUBLE PRECISION
);

CREATE TABLE IF NOT EXISTS gold_ss2.dim_tiempo (
    tiempo_sk     INTEGER PRIMARY KEY,
    anio          INTEGER NOT NULL,
    periodo_covid TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS gold_ss2.dim_geografia (
    geografia_sk INTEGER PRIMARY KEY,
    pais         TEXT NOT NULL,
    departamento TEXT,
    municipio    TEXT,
    nivel_geo    TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS gold_ss2.dim_fuente (
    fuente_sk        INTEGER PRIMARY KEY,
    source_system    TEXT NOT NULL,
    source_file      TEXT,
    pipeline_name    TEXT,
    nivel_agregacion TEXT
);

-- =============================== Facts ===============================
-- FK DEFERRABLE INITIALLY DEFERRED: se validan al COMMIT, no fila a fila.
-- Esto acelera el COPY masivo y relaja el orden de carga dentro de la txn.

CREATE TABLE IF NOT EXISTS gold_ss2.fact_defunciones (
    tiempo_sk           INTEGER,
    geografia_sk        INTEGER,
    causa_sk            INTEGER,
    demografia_sk       INTEGER,
    fuente_sk           INTEGER,
    total_defunciones   BIGINT,
    defunciones_hombres BIGINT,
    defunciones_mujeres BIGINT,
    tasa_mortalidad_x100k    DOUBLE PRECISION,
    tasa_estandarizada_x100k DOUBLE PRECISION,
    CONSTRAINT fk_def_tiempo     FOREIGN KEY (tiempo_sk)     REFERENCES gold_ss2.dim_tiempo(tiempo_sk)         DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT fk_def_geografia  FOREIGN KEY (geografia_sk)  REFERENCES gold_ss2.dim_geografia(geografia_sk)   DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT fk_def_causa      FOREIGN KEY (causa_sk)      REFERENCES gold_ss2.dim_causa(causa_sk)           DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT fk_def_demografia FOREIGN KEY (demografia_sk) REFERENCES gold_ss2.dim_demografia(demografia_sk) DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT fk_def_fuente     FOREIGN KEY (fuente_sk)     REFERENCES gold_ss2.dim_fuente(fuente_sk)         DEFERRABLE INITIALLY DEFERRED
);

CREATE TABLE IF NOT EXISTS gold_ss2.fact_morbilidad (
    tiempo_sk     INTEGER,
    geografia_sk  INTEGER,
    causa_sk      INTEGER,
    demografia_sk INTEGER,
    fuente_sk     INTEGER,
    casos_total   BIGINT,
    CONSTRAINT fk_morb_tiempo     FOREIGN KEY (tiempo_sk)     REFERENCES gold_ss2.dim_tiempo(tiempo_sk)         DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT fk_morb_geografia  FOREIGN KEY (geografia_sk)  REFERENCES gold_ss2.dim_geografia(geografia_sk)   DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT fk_morb_causa      FOREIGN KEY (causa_sk)      REFERENCES gold_ss2.dim_causa(causa_sk)           DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT fk_morb_demografia FOREIGN KEY (demografia_sk) REFERENCES gold_ss2.dim_demografia(demografia_sk) DEFERRABLE INITIALLY DEFERRED,
    CONSTRAINT fk_morb_fuente     FOREIGN KEY (fuente_sk)     REFERENCES gold_ss2.dim_fuente(fuente_sk)         DEFERRABLE INITIALLY DEFERRED
);

-- Índices sobre las FK de las facts (Postgres NO los crea automáticamente;
-- aceleran joins fact↔dim al consultar el backup).
CREATE INDEX IF NOT EXISTS ix_def_tiempo     ON gold_ss2.fact_defunciones(tiempo_sk);
CREATE INDEX IF NOT EXISTS ix_def_geografia  ON gold_ss2.fact_defunciones(geografia_sk);
CREATE INDEX IF NOT EXISTS ix_def_causa      ON gold_ss2.fact_defunciones(causa_sk);
CREATE INDEX IF NOT EXISTS ix_def_demografia ON gold_ss2.fact_defunciones(demografia_sk);
CREATE INDEX IF NOT EXISTS ix_def_fuente     ON gold_ss2.fact_defunciones(fuente_sk);

CREATE INDEX IF NOT EXISTS ix_morb_tiempo     ON gold_ss2.fact_morbilidad(tiempo_sk);
CREATE INDEX IF NOT EXISTS ix_morb_geografia  ON gold_ss2.fact_morbilidad(geografia_sk);
CREATE INDEX IF NOT EXISTS ix_morb_causa      ON gold_ss2.fact_morbilidad(causa_sk);
CREATE INDEX IF NOT EXISTS ix_morb_demografia ON gold_ss2.fact_morbilidad(demografia_sk);
CREATE INDEX IF NOT EXISTS ix_morb_fuente     ON gold_ss2.fact_morbilidad(fuente_sk);
