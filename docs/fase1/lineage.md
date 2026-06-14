# Linaje de Datos (Data Lineage)

## Trazabilidad extremo a extremo — Fase 1

Cada fila en las tablas Bronze contiene columnas técnicas que permiten rastrear
el dato desde su origen hasta su destino:

```
[Fuente original]
       │  URL / archivo / Drive ID
       ▼
[Descarga / lectura]
       │  fecha y hora (ingestion_timestamp)
       ▼
[Tabla Bronze]
       │  source_system · source_file · gdrive_file_id / volume_path
       ▼
[Stage / Silver]  ← Fase 2
       ▼
[Fact-Dimensiones / Gold]  ← Fase 2
```

## Columnas de linaje por tabla

### `sandbox_bronze_ss2.who_*` (Google Drive)

| Columna | Ejemplo | Propósito |
|---------|---------|-----------|
| `ingestion_timestamp` | `2026-06-13 07:32:11` | Cuándo se ejecutó el pipeline |
| `source_system` | `WHO Mortality Database Portal (Google Drive)` | Sistema de origen |
| `source_file` | `who_mortality_db_Guatemala.csv` | Archivo original |
| `gdrive_file_id` | `1WRWauPj5DKr4jZg_mBDvCvPlGC0DkQb7` | ID en Drive — permite re-descargar la fuente exacta |
| `country` | `guatemala` | País al que corresponden los datos |

### `sandbox_bronze_ss2.local_*` (DBFS/Volume)

| Columna | Ejemplo | Propósito |
|---------|---------|-----------|
| `ingestion_timestamp` | `2026-06-13 07:45:03` | Cuándo se ejecutó el pipeline |
| `source_system` | `Local File (Databricks Volume)` | Sistema de origen |
| `source_file` | `ine_defunciones_2019.csv` | Archivo original |
| `volume_path` | `/Volumes/catalogo/sandbox_bronze_ss2/landing/ine_defunciones_2019.csv` | Ruta exacta en el Volume |

## Registro de ejecuciones

<!-- Completar con cada ejecución real del pipeline -->

| Fecha | Pipeline | Filas ingestadas | Tabla destino | Responsable |
|-------|----------|-----------------|---------------|-------------|
| <!-- fecha --> | ingesta_oms_databricks.py | <!-- n --> | `who_guatemala` | <!-- nombre --> |
| <!-- fecha --> | ingesta_oms_databricks.py | <!-- n --> | `who_costa_rica` | <!-- nombre --> |
