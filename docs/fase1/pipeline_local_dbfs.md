# Pipeline: Archivos Locales — DBFS/Volume → Bronze

**Script:** `pipelines/fase1/ingesta_local_databricks.py`  
**Tabla destino:** `sandbox_bronze_ss2.local_<sufijo>`

## Cómo subir un archivo antes de ejecutar el pipeline

1. En Databricks, ir a **Catalog** en el menú lateral.
2. Navegar al catálogo → `sandbox_bronze_ss2` → seleccionar o crear un **Volume** (ej. `landing`).
3. Clic en **Upload to this Volume** y subir el archivo CSV.
4. Copiar la ruta que muestra Databricks:
   ```
   /Volumes/tu_catalogo/sandbox_bronze_ss2/landing/nombre_archivo.csv
   ```
5. Pegar esa ruta en el campo `volume_path` del diccionario `LOCAL_FILES` en el script.

## Flujo del pipeline

```
Databricks Volume (/Volumes/...)
      │
      │  dbutils.fs.open() → BytesIO
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
 Delta Table (sandbox_bronze_ss2.local_<sufijo>)
```

## Parámetros configurables

| Parámetro | Valor actual | Descripción |
|-----------|-------------|-------------|
| `WRITE_MODE` | `overwrite` | Sobrescribe la tabla en cada ejecución |
| `TARGET_SCHEMA` | `sandbox_bronze_ss2` | Esquema en Unity Catalog |
| `METADATA_LINES` | `7` | Líneas de cabecera del CSV OMS a ignorar (ajustar si la fuente es distinta) |

## Archivos configurados

```python
LOCAL_FILES = [
    {
        "table_suffix": "ine_defunciones_2019",
        "volume_path": "/Volumes/tu_catalogo/sandbox_bronze_ss2/landing/ine_defunciones_2019.csv",
        "file_name": "ine_defunciones_2019.csv",
    },
]
```

Para agregar más archivos: añadir una entrada al diccionario `LOCAL_FILES`.
No se requieren credenciales adicionales — Databricks tiene acceso nativo a los Volumes
del mismo workspace.

## Diferencias respecto al pipeline de Google Drive

| Aspecto | Google Drive | Local (DBFS/Volume) |
|---------|-------------|---------------------|
| Credenciales | Service account JSON (Secrets) | Ninguna |
| Descarga | Drive API v3 | `dbutils.fs.open()` |
| Metadata lineage | `gdrive_file_id` | `volume_path` |
| Prefijo de tabla | `who_` | `local_` |
| Helpers compartidos | `clean_name`, `dedupe_columns` | Idénticos |
