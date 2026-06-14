# Pipeline: MSPAS — Dropbox → Bronze

**Script:** `extraction-scripts/dropbox-mspas-ingestion-script.ipynb`  
**Tabla destino:** `sandbox_bronze_ss2.dbx_<nombre_carpeta>`  
**Fuente:** Carpeta `/mspas` en Dropbox

## Flujo del pipeline

```
Dropbox (/mspas/**/*.csv)
      │
      │  OAuth2 token refresh (cada ejecución)
      │  POST /2/files/list_folder (recursive=True)
      ▼
 Lista de archivos CSV agrupados por carpeta
      │
      │  POST /2/files/download  →  pd.read_csv (sep=None, engine=python)
      ▼
 pandas DataFrame por archivo
      │
      │  clean_name() + dedupe_columns()
      │  pd.concat (todos los CSVs de la carpeta)
      ▼
 DataFrame combinado por carpeta
      │
      │  resolución de tipos mixtos (object → float/str)
      ▼
 Spark DataFrame
      │
      │  + ingestion_timestamp + source_system
      ▼
 Delta Table (sandbox_bronze_ss2.dbx_<carpeta>)
```

## Parámetros configurables

| Parámetro | Valor actual | Descripción |
|-----------|-------------|-------------|
| `WRITE_MODE` | `overwrite` | Sobrescribe la tabla en cada ejecución |
| `DROPBOX_PATH` | `/mspas` | Raíz en Dropbox desde donde se recorre el árbol |
| `TARGET_SCHEMA` | `sandbox_bronze_ss2` | Esquema en Unity Catalog |
| `SOURCE_SYSTEM` | `MSPAS` | Etiqueta de linaje añadida a cada fila |

## Credenciales

Las credenciales de Dropbox se almacenan en **Databricks Secrets**:

```python
APP_KEY      = dbutils.secrets.get(scope="ss2-bronze-layer", key="dropbox_app_key")
APP_SECRET   = dbutils.secrets.get(scope="ss2-bronze-layer", key="dropbox_app_secret")
REFRESH_TOKEN = dbutils.secrets.get(scope="ss2-bronze-layer", key="dropbox_token")
```

El access token de Dropbox **expira cada ~4 horas**. El pipeline lo refresca
automáticamente en cada ejecución usando el refresh token almacenado en Secrets,
evitando fallos por token vencido.

## Lógica de agrupación y nomenclatura

El pipeline recorre la carpeta `/mspas` de forma recursiva y agrupa los CSV por su
**carpeta inmediata padre**. Cada carpeta produce una tabla independiente:

```
/mspas/
  ├── mortalidad_2019/
  │     ├── archivo_a.csv   ┐
  │     └── archivo_b.csv   ┘→  sandbox_bronze_ss2.dbx_mortalidad_2019
  └── egresos_hospitalarios/
        └── egresos.csv     →   sandbox_bronze_ss2.dbx_egresos_hospitalarios
```

Los archivos dentro de la misma carpeta se concatenan en un solo DataFrame antes
de escribir a Delta.

## Normalización de columnas

1. `clean_name()` — convierte nombres a `snake_case`, elimina acentos y caracteres especiales.
2. `dedupe_columns()` — renombra colisiones post-normalización añadiendo sufijo `_2`, `_3`, etc.
3. Columnas `Unnamed_N` (generadas por delimitadores finales en el CSV) se eliminan automáticamente.
4. La normalización ocurre **por archivo, antes del `concat`**, para que columnas con
   distinta ortografía (e.g. `"Grupo Etario"` vs `"GrupoEtario"`) se alineen correctamente.

## Resolución de tipos mixtos

Para columnas `object` con mezcla de enteros y cadenas (habitual en datos MSPAS):

- Si ≥ 90 % de los valores no nulos son numéricos → se castea a `float`.
- De lo contrario → se castea a `str` para que Arrow lo mapee a `StringType`.

## Manejo de errores

- Un CSV con parsing incorrecto usa `on_bad_lines="skip"` como fallback.
- Si todos los archivos de una carpeta fallan, la carpeta se omite y el pipeline continúa.
- Un fallo total del pipeline re-lanza la excepción para que el job de Databricks
  marque el estado como fallido.

## Diferencias respecto a otros pipelines

| Aspecto | OMS (Google Drive) | MSPAS (Dropbox) | INE (S3) |
|---------|-------------------|-----------------|----------|
| Credenciales | Service account JSON | OAuth2 refresh token | AWS key/secret |
| Formato fuente | CSV | CSV | XLSX (multi-hoja) |
| Agrupación | Por país | Por carpeta Dropbox | Por hoja de cálculo |
| Prefijo de tabla | `who_` | `dbx_` | `ine_defunciones_*` |
| `skiprows` | 7 (metadata OMS) | No aplica | Detección automática |
