# Pipeline: INE — S3 → Bronze

**Script:** `extraction-scripts/s3-ine-ingestion-script.ipynb`  
**Tablas destino:** `sandbox_bronze_ss2.ine_defunciones_*` (5 tablas)  
**Fuente:** S3 `s3://ss2-ingestion-ine-datasets-raw/ine_defunciones/`

## Flujo del pipeline

```
S3 (ss2-ingestion-ine-datasets-raw/ine_defunciones/year=YYYY/*.xlsx)
      │
      │  dbutils.fs.ls (recursive) → lista XLSX por año
      ▼
 {year: s3_key} por partición
      │
      │  Por cada hoja objetivo × cada año:
      │
      │  boto3.get_object → bytes
      │  openpyxl.load_workbook (read_only, data_only)
      ▼
 Workbook en memoria
      │
      │  1. Leer tab "contenido" → nombres canónicos de hojas
      │  2. Resolver hoja mediante cascada 3 niveles
      │  3. Detectar fila de encabezado (manejo de 2 layouts INE)
      ▼
 pd.DataFrame por (año, hoja)
      │
      │  pd.concat (todos los años para la misma hoja)
      │  fix_mixed_type_columns()
      ▼
 Spark DataFrame
      │
      │  + ingestion_timestamp
      ▼
 Delta Table (sandbox_bronze_ss2.ine_defunciones_<sufijo>)
```

## Parámetros configurables

| Parámetro | Valor actual | Descripción |
|-----------|-------------|-------------|
| `WRITE_MODE` | `overwrite` | Sobrescribe la tabla en cada ejecución |
| `S3_BUCKET` | `ss2-ingestion-ine-datasets-raw` | Bucket S3 de origen |
| `S3_PREFIX` | `ine_defunciones/` | Prefijo dentro del bucket |
| `TARGET_SCHEMA` | `sandbox_bronze_ss2` | Esquema en Unity Catalog |
| `SOURCE_SYSTEM` | `INE_DEFUNCIONES` | Etiqueta de linaje por fila |
| `HEADER_SCAN_ROWS` | `15` | Filas máximas a escanear buscando la cabecera real |
| `FUZZY_MATCH_CUTOFF` | `0.60` | Similitud mínima para aceptar coincidencia (L3) |

## Credenciales

Las credenciales de AWS se almacenan en **Databricks Secrets**:

```python
AWS_ACCESS_KEY = dbutils.secrets.get(scope="ss2-bronze-layer", key="aws_access_key_id")
AWS_SECRET_KEY = dbutils.secrets.get(scope="ss2-bronze-layer", key="aws_secret_access_key")
```

Se usa `boto3` explícitamente (en lugar de Hadoop/Spark S3) porque los clusters
serverless de Databricks no exponen `sparkContext` ni acceso JVM.

## Tablas generadas

| Nombre canónico en INE | Tabla Delta |
|------------------------|-------------|
| Defunciones por sexo, según edad y causas de muerte | `ine_defunciones_sexo_edad_causas_muerte` |
| Defunciones por sexo, según departamento de residencia del difunto(a) y causas de muerte | `ine_defunciones_sexo_depto_residencia_causas_muerte` |
| Defunciones neonatales por sexo, según edad y causas de muerte | `ine_defunciones_neonatales_sexo_edad_causas_muerte` |
| Defunciones post-neonatales por sexo, según edad y causas de muerte | `ine_defunciones_postneonatales_sexo_edad_causas_muerte` |
| Defunciones por causas externas y sexo, según departamento de ocurrencia | `ine_defunciones_causas_externas_sexo_depto_ocurrencia` |

## Estructura del S3

Los archivos están particionados por año con la convención Hive:

```
s3://ss2-ingestion-ine-datasets-raw/
└── ine_defunciones/
      ├── year=2015/
      │     └── defunciones_2015.xlsx
      ├── year=2016/
      │     └── defunciones_2016.xlsx
      └── ...
```

Cada XLSX contiene múltiples hojas; el pipeline extrae solo las definidas en `TARGET_SHEETS`.

## Algoritmo de resolución de hojas (cascada 3 niveles)

Los archivos INE usan nombres de pestañas abreviados que no coinciden con los títulos
completos listados en la pestaña `contenido`. El pipeline resuelve esto con tres niveles:

### Nivel 1 — Coincidencia exacta
Compara el nombre objetivo contra los nombres de pestaña del workbook (sin distinguir mayúsculas).

### Nivel 2 — Posición vía pestaña `contenido`
La pestaña `contenido` lista las hojas en el mismo orden en que aparecen en el workbook.
Se busca la posición de la hoja objetivo en `contenido` (similitud ≥ 0.85) y se
retorna la pestaña de datos en esa misma posición. Es el método más confiable para INE.

### Nivel 3 — Escaneo de contenido de celdas
Si los niveles anteriores fallan, se leen las primeras `HEADER_SCAN_ROWS` filas de cada
pestaña buscando una celda cuyo texto sea similar al nombre objetivo (umbral `FUZZY_MATCH_CUTOFF`).
Es el fallback para archivos donde el orden de `contenido` no coincide.

## Detección automática de fila de encabezado

Los XLSX de INE presentan dos layouts conocidos:

- **Variante A:** varias filas de metadata institucional → fila de encabezado con fondo oscuro.
- **Variante B:** primera fila es un título combinado (merged) → segunda fila es el encabezado real.

El algoritmo descarta filas que:
- Tienen menos de `MIN_HEADER_COLS` (2) celdas no nulas.
- Contienen valores numéricos en la primera celda (fila de datos, no encabezado).
- Coinciden con `METADATA_PATTERNS` (patrones de boilerplate INE como "Instituto", "Cuadro N", "Año YYYY").
- Son filas de título combinado: una sola celda repetida en múltiples columnas.

## Normalización de columnas

Igual que los demás pipelines:

1. `clean_name()` → `snake_case`, sin acentos ni caracteres especiales.
2. `dedupe_columns()` → sufijos `_2`, `_3` en colisiones.
3. Se eliminan columnas `unnamed_N` y columnas completamente nulas.
4. Se eliminan columnas con encabezado `col_N` (celdas vacías en medio de la tabla).

## Manejo de errores

- Si un año falla (archivo corrupto, hoja no encontrada), se omite ese año y el pipeline
  continúa con los demás. El error queda registrado en el log.
- Si ningún año produce datos para una hoja objetivo, esa tabla no se escribe.
- Un fallo total re-lanza la excepción para reflejar el estado en el job de Databricks.
