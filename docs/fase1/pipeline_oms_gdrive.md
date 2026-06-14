# Pipeline: OMS — Google Drive → Bronze

**Script:** `pipelines/fase1/ingesta_oms_databricks.py`  
**Tabla destino:** `sandbox_bronze_ss2.who_<country>`  
**Fuentes:** F01 (Guatemala), F02 (Costa Rica)

## Flujo del pipeline

```
Google Drive (CSV)
      │
      │  Drive API v3 (service account)
      ▼
 BytesIO buffer (en memoria)
      │
      │  pandas.read_csv (skiprows=7)
      ▼
 pandas DataFrame
      │
      │  clean_name() + dedupe_columns()
      ▼
 Spark DataFrame
      │
      │  + columnas de auditoría
      ▼
 Delta Table (sandbox_bronze_ss2.who_<country>)
```

## Parámetros configurables

| Parámetro | Valor actual | Descripción |
|-----------|-------------|-------------|
| `WRITE_MODE` | `overwrite` | Sobrescribe la tabla en cada ejecución |
| `TARGET_SCHEMA` | `sandbox_bronze_ss2` | Esquema en Unity Catalog |
| `METADATA_LINES` | `7` | Líneas de cabecera del export OMS a ignorar |

## Credenciales

Las credenciales de Google Drive se almacenan en **Databricks Secrets**:

```python
dbutils.secrets.get(scope="ss2-bronze-layer", key="google_service_account_json")
```

No se almacenan credenciales en el repositorio. Ver [Plan de Anonimización](anonimizacion.md).

## Archivos configurados

```python
GDRIVE_FILES = [
    {
        "country": "guatemala",
        "file_id": "...",
        "file_name": "who_mortality_db_Guatemala.csv",
    },
    {
        "country": "costa_rica",
        "file_id": "...",
        "file_name": "who_mortality_db_CostaRica.csv",
    },
]
```

Para agregar un nuevo país: añadir una entrada al diccionario `GDRIVE_FILES` y compartir
el archivo de Drive con el `client_email` de la service account.

## Manejo de errores

- Si un archivo falla (archivo no encontrado, error de parsing), el pipeline **registra
  el error y continúa** con el siguiente archivo. Un fallo aislado no aborta la ejecución completa.
- Se usa `on_bad_lines="skip"` como fallback para CSVs con comillas malformadas.
- El status del job en Databricks refleja el fallo si el error es a nivel de pipeline completo.
