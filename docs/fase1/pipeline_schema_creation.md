# Pipeline: Creación del Esquema Bronze

**Script:** `initial-scripts/schema-creation.ipynb`  
**Propósito:** Crear el esquema `sandbox_bronze_ss2` en Unity Catalog antes de ejecutar cualquier pipeline de ingesta.

## Cuándo ejecutar

Este notebook debe ejecutarse **una sola vez**, antes del primer pipeline de ingesta.
Es idempotente: usa `CREATE SCHEMA IF NOT EXISTS`, por lo que puede volver a ejecutarse
sin efecto si el esquema ya existe.

## Contenido del script

```sql
CREATE SCHEMA IF NOT EXISTS sandbox_bronze_ss2;
```

## Esquema creado

| Propiedad | Valor |
|-----------|-------|
| Nombre | `sandbox_bronze_ss2` |
| Catálogo | Catálogo activo del workspace |
| Motor | Unity Catalog (Databricks) |
| Formato de tablas | Delta Lake |

## Dependencias

- Databricks workspace activo con Unity Catalog habilitado.
- El usuario que ejecuta el notebook debe tener permisos `CREATE SCHEMA` sobre el catálogo.

## Relación con los pipelines

Todos los pipelines de ingesta (OMS, MSPAS, INE, archivos locales) apuntan al mismo
esquema `sandbox_bronze_ss2` como destino. Si el esquema no existe al momento de
escribir la tabla, Databricks lanzará un error.

| Pipeline | Tabla que crea |
|----------|---------------|
| OMS Google Drive | `sandbox_bronze_ss2.who_<pais>` |
| MSPAS Dropbox | `sandbox_bronze_ss2.dbx_<carpeta>` |
| INE S3 | `sandbox_bronze_ss2.ine_defunciones_*` |
| Archivos locales | `sandbox_bronze_ss2.local_<sufijo>` |
