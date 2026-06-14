# Pipeline: Archivos Locales — Databricks Volume → Bronze

**Script:** `extraction-scripts/localvolume-oms-ingestion-script.ipynb`  
**Tabla destino:** `sandbox_bronze_ss2.who_<table_suffix>`  
**Fuente:** WHO Mortality Database Portal — archivo CSV cargado manualmente a un Volumen (Guatemala)

## Cómo subir un archivo antes de ejecutar el pipeline

1. En Databricks, ir a **Catalog** en el menú lateral.
2. Navegar al catálogo → `sandbox_bronze_ss2` → seleccionar o crear un **Volume**
   (p. ej. `oms_local`).
3. Clic en **Upload to this Volume** y subir el archivo CSV.
4. Copiar la ruta que muestra Databricks:
   ```
   /Volumes/tu_catalogo/sandbox_bronze_ss2/oms_local/nombre_archivo.csv
   ```
5. Pegar esa ruta en el campo `volume_path` del diccionario `LOCAL_FILES` en el script.

## Flujo del pipeline

```
Databricks Volume (/Volumes/...)
      │
      │  open(volume_path, "rb") → BytesIO
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
      │  + source_file + volume_path + country
      ▼
 Delta Table (sandbox_bronze_ss2.who_<table_suffix>)
```

## Parámetros configurables

| Parámetro | Valor actual | Descripción |
|-----------|-------------|-------------|
| `WRITE_MODE` | `overwrite` | Sobrescribe la tabla en cada ejecución |
| `TARGET_SCHEMA` | `sandbox_bronze_ss2` | Esquema en Unity Catalog |
| `SOURCE_SYSTEM` | `Local File (Databricks Volume)` | Etiqueta de linaje añadida a cada fila |
| `METADATA_LINES` | `8` | Líneas de metadata del export OMS a ignorar antes del encabezado real (idéntico al pipeline de Google Drive) |

## Archivos configurados

```python
LOCAL_FILES = [
    {
        "table_suffix": "guatemala",
        "volume_path": "/Volumes/ss2_dw_workspace/sandbox_bronze_ss2/oms_local/who_mortality_db_Guatemala.csv",
        "file_name": "who_mortality_db_Guatemala.csv",
    },
]
```

Cada entrada de `LOCAL_FILES` es una **fuente independiente** que produce su
propia tabla Bronze (`who_<table_suffix>`), sin relaciones entre archivos.

Para agregar más archivos: añadir una entrada al diccionario `LOCAL_FILES`
siguiendo el mismo patrón. No se requieren credenciales adicionales —
Databricks tiene acceso nativo a los Volúmenes del mismo workspace mediante
rutas POSIX.

!!! note "Costa Rica se ingesta por otra vía"
    El archivo de Costa Rica (`who_mortality_db_CostaRica.csv`) no se sube a un
    Volumen; se ingesta mediante el pipeline de
    [OMS — Google Drive](pipeline_oms_gdrive.md), reutilizando la misma
    lógica de lectura y normalización.

## Normalización de columnas

Idéntica al pipeline de Google Drive, para garantizar que un archivo WHO
produzca el mismo esquema sin importar el mecanismo de extracción:

1. `clean_name()` — convierte nombres a `snake_case`, transcribe `ñ → ni` y
   elimina acentos y caracteres especiales.
2. `dedupe_columns()` — renombra colisiones post-normalización añadiendo
   sufijo `_2`, `_3`, etc.
3. Columnas `unnamed_N` (generadas por delimitadores finales en el CSV) se
   eliminan automáticamente.

## Resolución de tipos mixtos

Para columnas `object` con mezcla de valores numéricos y de texto:

- Si ≥ 90 % de los valores no nulos son numéricos → se castea a `float`.
- De lo contrario → se castea a `str` para que Arrow lo mapee a `StringType`.

## Manejo de errores

- Si un archivo falla (no encontrado, error de parsing), el pipeline **registra
  el error y continúa** con el siguiente archivo de `LOCAL_FILES`. Un fallo
  aislado no aborta la ejecución completa.
- Se usa `on_bad_lines="skip"` como fallback para CSVs con comillas malformadas.
- Un fallo total del pipeline re-lanza la excepción para que el job de
  Databricks marque el estado como fallido.

## Diferencias respecto al pipeline de Google Drive

| Aspecto | Google Drive | Local (Volume) |
|---------|-------------|---------------------|
| Credenciales | Service account (campos individuales en Secrets) | Ninguna |
| Descarga | Drive API v3 (`files.get_media`) | `open(volume_path, "rb")` |
| `METADATA_LINES` | `8` | `8` (idéntico) |
| Metadata de linaje | `gdrive_file_id` | `volume_path` |
| Prefijo de tabla | `who_` | `who_` (mismo prefijo) |
| Helpers compartidos | `clean_name`, `dedupe_columns` | Idénticos |
