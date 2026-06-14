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

## Secrets de Databricks

Todos los pipelines de ingesta obtienen credenciales desde el scope
**`ss2-bronze-layer`** de Databricks Secrets — nunca se almacenan credenciales
en el repositorio. Los secrets deben crearse manualmente en el workspace antes
de ejecutar cualquier pipeline.

```bash
databricks secrets list-secrets ss2-bronze-layer
```

| Key | Usado por |
|-----|-----------|
| `aws_access_key_id` | INE (S3) |
| `aws_secret_access_key` | INE (S3) |
| `dropbox_app_key` | MSPAS (Dropbox) |
| `dropbox_app_secret` | MSPAS (Dropbox) |
| `dropbox_token` | MSPAS (Dropbox) — refresh token OAuth2 |
| `gsa_type` | OMS (Google Drive) |
| `gsa_project_id` | OMS (Google Drive) |
| `gsa_private_key_id` | OMS (Google Drive) |
| `gsa_private_key` | OMS (Google Drive) |
| `gsa_client_email` | OMS (Google Drive) |
| `gsa_client_id` | OMS (Google Drive) |
| `gsa_auth_uri` | OMS (Google Drive) |
| `gsa_token_uri` | OMS (Google Drive) |
| `gsa_auth_provider_x509_cert_url` | OMS (Google Drive) |
| `gsa_client_x509_cert_url` | OMS (Google Drive) |
| `gsa_universe_domain` | OMS (Google Drive) |

!!! warning "Prerequisito"
    Los secrets del scope `ss2-bronze-layer` deben existir **antes** de ejecutar
    cualquier notebook de ingesta. Sin ellos, los pipelines fallarán al intentar
    obtener credenciales con `dbutils.secrets.get(...)`.

### Cómo crear un secret

```bash
databricks secrets create-scope ss2-bronze-layer
databricks secrets put-secret ss2-bronze-layer <key> --string-value "<value>"
```

Los campos del JSON de la service account de Google (`gsa_*`) corresponden a las
claves del archivo `.json` descargado desde Google Cloud IAM. Cada campo se almacena
como un secret independiente para evitar exponer el JSON completo.

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
