# Fase 2 — Transformación, Arquitectura por Capas y Data Warehouse

Fase 2 construye las capas Silver y Gold sobre el Bronze poblado en Fase 1,
y agrega un Data Warehouse local en PostgreSQL como copia interoperable
del Gold en Databricks/Unity Catalog.

## Contenido

- [Arquitectura](arquitectura.md) — capas Bronze/Silver/Gold, galaxy
  schema de Gold (2 fact tables + 5 dimensiones compartidas), e
  infraestructura del DW local
- [Reglas de Transformación](reglas_transformacion.md) — listado
  auditable de las reglas aplicadas en Silver y Gold
- [Source-to-Target Mapping](source_to_target_mapping.md) — mapeo
  columna por columna Bronze → Silver → Gold (Excel/Google Sheets)
- [DW Local — Backup y Evidencia de Lectura](dw_local_evidencia_y_backup.md) —
  backup transaccional del Gold en PostgreSQL y la consulta de evidencia
  contra el DW local
