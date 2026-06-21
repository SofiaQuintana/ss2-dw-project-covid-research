-- Se ejecuta UNA sola vez, al crear el volumen de Postgres por primera vez.
-- Crea el schema espejo y un rol de solo-lectura para consumir el backup
-- sin riesgo de modificar los datos.

CREATE SCHEMA IF NOT EXISTS gold_ss2;

DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'dw_reader') THEN
    CREATE ROLE dw_reader LOGIN PASSWORD 'cambia_esto_tambien';
  END IF;
END
$$;

GRANT USAGE ON SCHEMA gold_ss2 TO dw_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA gold_ss2
  GRANT SELECT ON TABLES TO dw_reader;
