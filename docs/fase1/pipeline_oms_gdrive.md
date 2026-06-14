# Pipeline: OMS — Google Drive → Bronze

**Script:** `extraction-scripts/gdrive-oms-ingestion-script.ipynb`  
**Tabla destino:** `sandbox_bronze_ss2.who_<country>`  
**Fuente:** WHO Mortality Database Portal — archivo CSV en Google Drive (Costa Rica)

## Flujo del pipeline

```
Google Drive (CSV)
      │
      │  Drive API v3 (service account) → files.get + get_media
      ▼
 BytesIO buffer (en memoria)
      │
      │  pd.read_csv (skiprows=METADATA_LINES, sep=None, engine=python)
      ▼
 pandas DataFrame
      │
      │  clean_name() + dedupe_columns()
      │  resolución de tipos mixtos (object → float/str)
      ▼
 Spark DataFrame
      │
      │  + ingestion_timestamp + source_system
      │  + source_file + gdrive_file_id + country
      ▼
 Delta Table (sandbox_bronze_ss2.who_<country>)
```

## Parámetros configurables

| Parámetro | Valor actual | Descripción |
|-----------|-------------|-------------|
| `WRITE_MODE` | `overwrite` | Sobrescribe la tabla en cada ejecución |
| `TARGET_SCHEMA` | `sandbox_bronze_ss2` | Esquema en Unity Catalog |
| `SOURCE_SYSTEM` | `WHO Mortality Database Portal (Google Drive)` | Etiqueta de linaje añadida a cada fila |
| `METADATA_LINES` | `8` | Líneas de metadata del export OMS a ignorar antes del encabezado real |

## Credenciales

Las credenciales de la cuenta de servicio de Google se almacenan como
secretos individuales en **Databricks Secrets** (scope `ss2-bronze-layer`),
ya que Databricks Secrets solo admite valores de texto simple y no un JSON
completo:

```python
GOOGLE_SERVICE_ACCOUNT_INFO = {
    "type":                         dbutils.secrets.get(scope="ss2-bronze-layer", key="gsa_type"),
    "project_id":                   dbutils.secrets.get(scope="ss2-bronze-layer", key="gsa_project_id"),
    "private_key_id":               dbutils.secrets.get(scope="ss2-bronze-layer", key="gsa_private_key_id"),
    "private_key":                  dbutils.secrets.get(scope="ss2-bronze-layer", key="gsa_private_key"),
    "client_email":                 dbutils.secrets.get(scope="ss2-bronze-layer", key="gsa_client_email"),
    "client_id":                    dbutils.secrets.get(scope="ss2-bronze-layer", key="gsa_client_id"),
    "auth_uri":                     dbutils.secrets.get(scope="ss2-bronze-layer", key="gsa_auth_uri"),
    "token_uri":                    dbutils.secrets.get(scope="ss2-bronze-layer", key="gsa_token_uri"),
    "auth_provider_x509_cert_url":  dbutils.secrets.get(scope="ss2-bronze-layer", key="gsa_auth_provider_x509_cert_url"),
    "client_x509_cert_url":         dbutils.secrets.get(scope="ss2-bronze-layer", key="gsa_client_x509_cert_url"),
    "universe_domain":              dbutils.secrets.get(scope="ss2-bronze-layer", key="gsa_universe_domain"),
}
```

El campo `private_key` recibe un reemplazo `\\n` → `\n` antes de construir las
credenciales, ya que Databricks Secrets no preserva saltos de línea reales.

No se almacenan credenciales en el repositorio. Ver [Plan de Anonimización](anonimizacion.md).

## Archivos configurados

```python
GDRIVE_FILES = [
    {
        "country": "costa_rica",
        "file_id": "1xh8E2--ZSe_9gMjpCjrjD4dHQkhI4hJE",
        "file_name": "who_mortality_db_CostaRica.csv",
    },
]
```

Cada entrada de `GDRIVE_FILES` es una **fuente independiente** que produce su
propia tabla Bronze (`who_<country>`), sin relaciones entre países.

Para agregar un nuevo país: añadir una entrada al diccionario `GDRIVE_FILES` y
compartir el archivo de Drive con el `client_email` de la service account
(permiso de solo lectura).

!!! note "Guatemala se ingesta por otra vía"
    El archivo de Guatemala (`who_mortality_db_Guatemala.csv`) no se descarga
    desde Google Drive en este pipeline; se ingesta mediante el pipeline de
    [Archivos Locales (DBFS/Volume)](pipeline_local_dbfs.md), reutilizando la
    misma lógica de lectura y normalización.

## Normalización de columnas

1. `clean_name()` — convierte nombres a `snake_case`, transcribe `ñ → ni` y
   elimina acentos y caracteres especiales.
2. `dedupe_columns()` — renombra colisiones post-normalización añadiendo
   sufijo `_2`, `_3`, etc.
3. Columnas `unnamed_N` (generadas por delimitadores finales en el CSV) se
   eliminan automáticamente.

## Resolución de tipos mixtos

Para columnas `object` con mezcla de valores numéricos y de texto (frecuente
en los exports de la OMS, p. ej. tasas ajustadas que a veces vienen vacías):

- Si ≥ 90 % de los valores no nulos son numéricos → se castea a `float`.
- De lo contrario → se castea a `str` para que Arrow lo mapee a `StringType`.

## Manejo de errores

- Si un archivo falla (no encontrado, error de parsing), el pipeline **registra
  el error y continúa** con el siguiente archivo de `GDRIVE_FILES`. Un fallo
  aislado no aborta la ejecución completa.
- Se usa `on_bad_lines="skip"` como fallback para CSVs con comillas malformadas.
- Un fallo total del pipeline re-lanza la excepción para que el job de
  Databricks marque el estado como fallido.

## Diferencias respecto a otros pipelines

| Aspecto | OMS (Google Drive) | MSPAS (Dropbox) | INE (S3) | Local (Volume) |
|---------|--------------------|------------------|----------|------------------|
| Credenciales | Service account (campos individuales en Secrets) | OAuth2 refresh token | AWS key/secret | Ninguna |
| Formato fuente | CSV | CSV | XLSX (multi-hoja) | CSV |
| Agrupación | Por país | Por carpeta Dropbox | Por hoja de cálculo | Por archivo |
| Prefijo de tabla | `who_` | `dbx_` | `ine_defunciones_*` | `who_` |
| `METADATA_LINES` | `8` (metadata OMS) | No aplica | Detección automática | `8` (metadata OMS) |
| Metadata de linaje | `gdrive_file_id` | — | `anio` (partición S3) | `volume_path` |
