# Fase 1 — Fundamentos de Datos: Ingesta y Sandbox

## Objetivo

Identificar, obtener e ingestar datos de defunciones desde fuentes heterogéneas
hacia la capa **Sandbox/Bronze**, sin transformación destructiva, preservando la
materia prima para auditoría y reproceso.

## Entregables de esta fase

- [x] Catálogo de fuentes de datos
- [x] Pipelines de ingesta versionados en GitHub
- [x] Tablas Sandbox pobladas en Databricks (Delta)
- [x] Diccionario de datos
- [x] Plan de anonimización (EU Data Act)
- [x] Registro de linaje (data lineage)

## Convención de nomenclatura — tablas Bronze

Cada fuente produce **una tabla independiente**, sin relaciones entre ellas:

| Origen | Formato | Script | Tabla Bronze |
|--------|---------|--------|-------------|
| OMS Portal | CSV (Google Drive) | `ingesta_oms_databricks.py` | `sandbox_bronze_ss2.who_<pais>` |
| MSPAS | CSV (Dropbox) | `dropbox-mspas-ingestion-script.ipynb` | `sandbox_bronze_ss2.dbx_<carpeta>` |
| INE Defunciones | XLSX multi-hoja (S3) | `s3-ine-ingestion-script.ipynb` | `sandbox_bronze_ss2.ine_defunciones_*` |
| Archivo local | CSV (DBFS/Volume) | `ingesta_local_databricks.py` | `sandbox_bronze_ss2.local_<sufijo>` |

!!! info "Regla Bronze"
    Las tablas de esta capa contienen los datos **exactamente como vienen de la fuente**.
    La única adición permitida son columnas técnicas de auditoría con prefijo de linaje
    (`ingestion_timestamp`, `source_system`, `source_file`).

## Motor de cómputo

Databricks (PySpark + Delta Lake) sobre AWS, operando como motor de ingesta.
Las tablas se escriben en formato **Delta** dentro del esquema `sandbox_bronze_ss2`
de Unity Catalog.
