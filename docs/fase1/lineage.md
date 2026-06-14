# Linaje de Datos (Data Lineage)

## ¿Qué es el Data Lineage?

El **Data Lineage** o registro de procedencia es el mapa/historial que permite
reconstruir el ciclo de vida de un dato: su origen, los procesos que lo
trasladan, las transformaciones que sufre en el camino y el lugar donde queda
almacenado de forma definitiva.

Para la **Fase 1**, el propósito de este documento es registrar el recorrido
exacto que sigue cada conjunto de datos desde su **fuente original** hasta la
**zona de aterrizaje (Sandbox/Bronze)**, evidenciando que no se aplicaron
alteraciones destructivas sobre los valores originales y dejando trazabilidad
auditable mediante columnas técnicas (`ingestion_timestamp`, `source_system`,
`source_file`, identificadores de origen, etc.).

## Catálogo de Linaje — Fuente → Sandbox

Cada fila del siguiente catálogo describe un flujo de datos completo: sistema
de origen, formato en que se encuentra el dato, mecanismo de extracción
empleado, transformaciones aplicadas durante la Fase 1 (si las hay) y la tabla
de destino dentro del Sandbox/Bronze.

| Sistema Origen | Formato Original | Método de Extracción | Transformación (Fase 1) | Destino (Sandbox/Bronze) |
|----------------|-------------------|------------------------|---------------------------|----------------------------|
| **INE Guatemala** (Bucket S3 `ss2-ingestion-ine-datasets-raw`) | `.xlsx` (reporte visual, multi-hoja, particionado por `year=YYYY/`) | `boto3` + `openpyxl` + `pandas`, orquestado desde un notebook Databricks (`s3-ine-ingestion-script.ipynb`) | Localiza la hoja `contenido` y resuelve, mediante una cascada de coincidencia (exacta → posicional → similitud textual), las 5 hojas objetivo (p. ej. *"Defunciones por sexo, según edad y causas de muerte"*); detecta automáticamente la fila de encabezado real y descarta las filas de metadata propias del formato INE. Normaliza los nombres de columna (`clean_name`, `dedupe_columns`). No se realizan agregaciones ni filtrado de registros. | `sandbox_bronze_ss2.ine_defunciones_sexo_edad_causas_muerte` y 5 tablas Delta equivalentes (una por hoja objetivo), con una fila por año |
| **MSPAS** (Dropbox, carpeta `/mspas`) | `.csv` (uno o más archivos por subcarpeta) | API REST de Dropbox (autenticación OAuth2 mediante refresh token), orquestado desde un notebook Databricks (`dropbox-mspas-ingestion-script.ipynb`) | Ninguna sobre los valores (copia fiel) — únicamente se normalizan los nombres de columna a snake_case (`clean_name`, `dedupe_columns`) y se resuelven columnas de tipo mixto (`object` → `double`/`string`) para permitir la inferencia de esquema en Spark | `sandbox_bronze_ss2.dbx_<carpeta>` (una tabla Delta por subcarpeta de Dropbox) |
| **OMS — WHO Mortality Database Portal** (Google Drive — **Costa Rica**) | `.csv` (export WHO, con 8 líneas de metadata previas al encabezado) | Google Drive API v3 (cuenta de servicio), orquestado desde un notebook Databricks (`gdrive-oms-ingestion-script.ipynb`) | Se descartan las 8 líneas de metadata del export (`skiprows=8`), se normalizan los nombres de columna y se resuelven columnas de tipo mixto. No se altera el valor de los indicadores de mortalidad. | `sandbox_bronze_ss2.who_costa_rica` |
| **OMS — WHO Mortality Database Portal** (archivo local cargado a un Volumen de Databricks — **Guatemala**) | `.csv` (mismo formato del export WHO) | Lectura directa desde un Volumen de Unity Catalog (`open()` + `pandas.read_csv`), orquestado desde un notebook Databricks (`localvolume-oms-ingestion-script.ipynb`) | Idéntica al pipeline de Google Drive: se descartan las 8 líneas de metadata, se normalizan los nombres de columna y se resuelven columnas de tipo mixto | `sandbox_bronze_ss2.who_guatemala` |


## Trazabilidad extremo a extremo

```
[Fuente original]
       │  S3 key / Dropbox path / Google Drive file_id / Volume path
       ▼
[Extracción]
       │  boto3 · Dropbox API · Drive API v3 · lectura de Volumen (open)
       ▼
[Lectura y limpieza estructural]
       │  pandas (openpyxl / read_csv) → clean_name() + dedupe_columns()
       │  resolución de tipos mixtos (object → double/string)
       ▼
[Conversión a Spark DataFrame]
       │  spark.createDataFrame(...)
       │  + columnas técnicas de linaje (ingestion_timestamp, source_system, ...)
       ▼
[Tabla Bronze — sandbox_bronze_ss2.*]  ← Delta, Unity Catalog
       │
       ▼
[Stage / Silver]  ← Fase 2
       ▼
[Fact-Dimensiones / Gold]  ← Fase 2
```

## Herramientas y librerías empleadas por pipeline

Un aspecto relevante del diseño de los cuatro pipelines de Fase 1 es que
**ninguno realiza la extracción directamente con PySpark**. En su lugar, todos
siguen un patrón híbrido: la extracción y la limpieza estructural se realizan
con librerías de Python de propósito específico (de bajo nivel para cada
fuente) y **pandas** como motor de manipulación tabular en memoria; **PySpark
se introduce únicamente en el último paso**, al convertir el `DataFrame` de
pandas en un `Spark DataFrame` para escribirlo como tabla Delta en el Sandbox.
Esta decisión de diseño responde a razones distintas en cada caso, que se
documentan a continuación.

### INE — S3 (`s3-ine-ingestion-script.ipynb`)

| Herramienta | Rol en el pipeline | Justificación |
|-------------|--------------------|----------------|
| `boto3` | Descarga de los objetos `.xlsx` desde el bucket S3 mediante credenciales explícitas (Databricks Secrets) | Los clústeres *serverless* / Spark Connect no exponen `sparkContext` ni acceso directo a la JVM, por lo que `dbutils.fs` o un `DataFrameReader` de Spark no pueden emplearse de forma confiable para leer bytes binarios arbitrarios desde S3. `boto3` permite una lectura de objeto autenticada y portable, independiente del tipo de clúster. |
| `openpyxl` | Parseo del libro `.xlsx`: lectura de la hoja `contenido`, resolución de hojas objetivo y detección de la fila de encabezado real | El formato de salida del INE es un **reporte visual de Excel**, no un CSV tabular: contiene múltiples hojas, filas de metadata institucional y encabezados en posiciones variables. Spark no cuenta con un lector nativo de `.xlsx` con esta granularidad; `openpyxl` permite iterar celda por celda y aplicar la lógica de resolución en cascada (coincidencia exacta, posicional y por similitud textual) que este formato exige. |
| `pandas` | Construcción del `DataFrame` final por hoja/año, normalización de nombres de columna y resolución de tipos mixtos | Una vez aislada la porción tabular de cada hoja, el volumen de datos por archivo es modesto (un año de estadísticas vitales), por lo que **pandas resulta más eficiente y expresivo que PySpark** para operaciones de limpieza fila por fila, deduplicación de columnas y *type-casting* condicional — operaciones que en Spark requerirían UDFs o múltiples `withColumn` encadenados con mayor sobrecarga. |
| **PySpark** (`spark.createDataFrame`, `current_timestamp`, `lit`) | Conversión final a `Spark DataFrame`, adición de columnas de linaje y escritura como tabla Delta (`saveAsTable`, `mergeSchema=true`) | La escritura hacia el Sandbox **debe** pasar por Spark/Delta Lake para beneficiarse de transacciones ACID, evolución de esquema controlada y gobernanza vía Unity Catalog — capacidades que pandas no provee y que son requisito de la capa Bronze. |

### MSPAS — Dropbox (`dropbox-mspas-ingestion-script.ipynb`)

| Herramienta | Rol en el pipeline | Justificación |
|-------------|--------------------|----------------|
| `requests` | Autenticación OAuth2 (refresco de token) y llamadas a la API REST de Dropbox (`list_folder`, `files/download`) | Dropbox no ofrece un conector nativo para Spark ni para Databricks; su API es puramente REST/HTTP. `requests` es la herramienta estándar y mínima para este tipo de integración, sin dependencias adicionales. |
| `pandas` (`read_csv` con `sep=None, engine="python"`) | Parseo de cada CSV descargado, normalización de columnas y resolución de tipos mixtos antes de concatenar | Los archivos de MSPAS son **CSV de tamaño moderado** y con posibles inconsistencias de separador o comillas mal escapadas. El motor `python` de pandas permite *sniffing* automático del delimitador y un manejo de errores fila por fila (`on_bad_lines="skip"`) que sería más costoso de implementar en Spark, donde el esquema y el delimitador deben conocerse de antemano para una lectura distribuida eficiente. Al ser archivos pequeños, el procesamiento en memoria con pandas no representa un cuello de botella. |
| **PySpark** (`spark.createDataFrame`, `current_timestamp`, `lit`) | Conversión a `Spark DataFrame`, adición de `ingestion_timestamp` y `source_system`, y escritura Delta (`saveAsTable`, modo `overwrite`, `mergeSchema=true`) | Igual que en el caso anterior, la persistencia en el Sandbox requiere las garantías transaccionales y de catálogo de Delta Lake/Unity Catalog, por lo que PySpark se reserva exclusivamente para esta fase de escritura. |

### OMS — Google Drive (`gdrive-oms-ingestion-script.ipynb`) — Costa Rica

Este pipeline ingesta el archivo `who_mortality_db_CostaRica.csv` y produce la
tabla `sandbox_bronze_ss2.who_costa_rica`.

| Herramienta | Rol en el pipeline | Justificación |
|-------------|--------------------|----------------|
| `google-api-python-client` (`googleapiclient.discovery`, `MediaIoBaseDownload`) junto con `google.oauth2.service_account` | Autenticación mediante cuenta de servicio y descarga del archivo CSV alojado en Google Drive hacia un buffer en memoria | Al igual que con Dropbox, Google Drive expone su funcionalidad mediante una API propia (Drive API v3) sin equivalente nativo en Spark. El SDK oficial de Google es la vía más directa y segura (mediante credenciales de cuenta de servicio gestionadas como Databricks Secrets) para acceder a un archivo específico por `file_id`. |
| `pandas` (`read_csv` con `skiprows=8, sep=None`) | Lectura del CSV exportado por el portal de la OMS, descartando las líneas de metadata, y normalización de columnas | El export de la OMS incluye un bloque fijo de metadata (región, país, fecha de exportación, etc.) antes del encabezado real. pandas permite omitir estas líneas de forma directa (`skiprows`) y, dado que cada archivo corresponde a un solo país, el volumen de datos es manejable en memoria sin necesidad de procesamiento distribuido. |
| **PySpark** (`spark.createDataFrame`, `current_timestamp`, `lit`) | Conversión a `Spark DataFrame`, adición de columnas de linaje (`source_system`, `source_file`, `gdrive_file_id`, `country`) y escritura Delta | Misma justificación que en los pipelines anteriores: la capa Bronze exige Delta Lake/Unity Catalog para auditoría, versionado y evolución de esquema. |

### OMS — Archivo local / Databricks Volume (`localvolume-oms-ingestion-script.ipynb`) — Guatemala

Este pipeline ingesta el archivo `who_mortality_db_Guatemala.csv`, previamente
cargado a un Volumen de Unity Catalog, y produce la tabla
`sandbox_bronze_ss2.who_guatemala`.

| Herramienta | Rol en el pipeline | Justificación |
|-------------|--------------------|----------------|
| `open()` (I/O estándar de Python) | Lectura del archivo CSV directamente desde un Volumen de Unity Catalog | Los Volúmenes de Unity Catalog se exponen como rutas POSIX dentro del sistema de archivos del clúster, por lo que pueden leerse con las primitivas estándar de Python sin necesidad de SDKs externos ni credenciales adicionales — a diferencia de Google Drive o Dropbox, que requieren autenticación contra un servicio remoto. |
| `pandas` (`read_csv` con `skiprows=8, sep=None`) | Parseo del CSV (mismo formato de export WHO) y normalización de columnas | Se reutiliza deliberadamente la misma lógica del pipeline de Google Drive (`clean_name`, `dedupe_columns`, `skiprows=8`) para garantizar que un archivo WHO produzca el **mismo esquema** sin importar si se ingresó por Drive o por carga manual a un Volumen. El volumen de datos (un archivo por país) sigue siendo adecuado para pandas. |
| **PySpark** (`spark.createDataFrame`, `current_timestamp`, `lit`) | Conversión a `Spark DataFrame`, adición de columnas de linaje (`source_system`, `source_file`, `volume_path`, `country`) y escritura Delta | Consistente con los demás pipelines: la escritura final hacia `sandbox_bronze_ss2` se realiza siempre vía PySpark/Delta para mantener una única vía de ingreso a la capa Bronze, independientemente del origen de los datos. |

### Síntesis del criterio de selección

En términos generales, la selección de herramientas responde a tres criterios:

1. **Disponibilidad de conector nativo en Spark.** Ninguna de las cuatro fuentes
   (S3 con lectura binaria de `.xlsx`, Dropbox, Google Drive, Volúmenes como
   bytes crudos) cuenta con un *DataFrameReader* de Spark adecuado para el
   formato o protocolo de origen; por ello, la extracción se delega a librerías
   especializadas (`boto3`, `requests`, `google-api-python-client`, `open()`).
2. **Volumen de datos por archivo.** En todos los casos, cada archivo de origen
   corresponde a una unidad relativamente pequeña (un año, un país o una
   carpeta de reportes de MSPAS), por lo que **pandas** resulta más eficiente
   que PySpark para las operaciones de limpieza estructural (detección de
   encabezados, normalización de columnas, *type-casting*), evitando la
   sobrecarga de planificación distribuida para datos que caben cómodamente en
   memoria.
3. **Requisitos de la capa Bronze.** Independientemente del origen, la
   persistencia final debe ocurrir mediante **PySpark + Delta Lake**, ya que es
   el único camino que garantiza escritura transaccional (ACID), evolución de
   esquema (`mergeSchema`) y gobernanza dentro de Unity Catalog — requisitos no
   negociables para la trazabilidad exigida en la Fase 1.

## Columnas de linaje por pipeline

Cada pipeline añade columnas técnicas distintas según el mecanismo de
extracción empleado, pero todas comparten `ingestion_timestamp` y
`source_system` como ancla común de auditoría.

### `sandbox_bronze_ss2.ine_*` (S3 → INE)

| Columna | Ejemplo | Propósito |
|---------|---------|-----------|
| `ingestion_timestamp` | `2026-06-13 08:10:42` | Momento de ejecución del pipeline |
| `source_system` | `INE_DEFUNCIONES` | Sistema de origen |
| `source_file` | `s3://ss2-ingestion-ine-datasets-raw/ine_defunciones/year=2020/...xlsx` | Ruta S3 exacta del archivo de origen (incluye la partición de año) |
| `anio` | `2020` | Año del reporte, derivado de la partición `year=YYYY/` |

### `sandbox_bronze_ss2.dbx_*` (Dropbox → MSPAS)

| Columna | Ejemplo | Propósito |
|---------|---------|-----------|
| `ingestion_timestamp` | `2026-06-13 08:15:07` | Momento de ejecución del pipeline |
| `source_system` | `MSPAS` | Sistema de origen |

!!! note
    El pipeline de MSPAS no agrega `source_file` por fila; la tabla destino
    (`dbx_<carpeta>`) ya identifica la carpeta de Dropbox de origen
    (`/mspas/<carpeta>`), y todos los CSV de esa carpeta se concatenan en la
    misma tabla.

### `sandbox_bronze_ss2.who_*` (Google Drive — OMS)

| Columna | Ejemplo | Propósito |
|---------|---------|-----------|
| `ingestion_timestamp` | `2026-06-13 07:32:11` | Momento de ejecución del pipeline |
| `source_system` | `WHO Mortality Database Portal (Google Drive)` | Sistema de origen |
| `source_file` | `who_mortality_db_CostaRica.csv` | Nombre del archivo original |
| `gdrive_file_id` | `1xh8E2--ZSe_9gMjpCjrjD4dHQkhI4hJE` | ID en Drive — permite recuperar la fuente exacta |
| `country` | `costa_rica` | País al que corresponden los datos |

### `sandbox_bronze_ss2.who_*` (Databricks Volume — OMS local)

| Columna | Ejemplo | Propósito |
|---------|---------|-----------|
| `ingestion_timestamp` | `2026-06-13 07:45:03` | Momento de ejecución del pipeline |
| `source_system` | `Local File (Databricks Volume)` | Sistema de origen |
| `source_file` | `who_mortality_db_Guatemala.csv` | Nombre del archivo original |
| `volume_path` | `/Volumes/ss2_dw_workspace/sandbox_bronze_ss2/oms_local/who_mortality_db_Guatemala.csv` | Ruta exacta en el Volumen — permite recuperar la fuente exacta |
| `country` | `guatemala` | País al que corresponden los datos |
