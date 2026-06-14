# Plan de Anonimización / Agregación de Datos Sensibles — EU Data Act

## Objetivo

Establecer los criterios bajo los cuales se determina si una fuente de datos
requiere anonimización o agregación antes de ingresar al Sandbox/Bronze, y
documentar las medidas — actuales y previstas — que garantizan el cumplimiento
de los principios de **minimización de datos**, **transparencia** y
**confidencialidad** exigidos por el EU Data Act.

## Clasificación de las fuentes ingestadas

Se revisaron los cuatro pipelines de extracción de la Fase 1
(`s3-ine-ingestion-script.ipynb`, `dropbox-mspas-ingestion-script.ipynb`,
`gdrive-oms-ingestion-script.ipynb`, `localvolume-oms-ingestion-script.ipynb`)
y los esquemas resultantes en `sandbox_bronze_ss2`. En ningún caso se
identificaron columnas con identificadores personales directos (nombre,
número de DPI, dirección, fecha de nacimiento individual, etc.): todas las
fuentes actuales entregan **estadísticas ya agregadas** por dimensiones como
año, sexo, grupo etario, departamento y causa de defunción (CIE-10).

| Fuente | Nivel de agregación observado | Identificadores personales | Clasificación |
|--------|--------------------------------|------------------------------|----------------|
| OMS — WHO Mortality Database (`who_costa_rica`, `who_guatemala`) | Por año, sexo, grupo etario y causa (indicador OMS) | Ninguno | Dato agregado público |
| INE — Estadísticas Vitales (`ine_defunciones_*`) | Por año, sexo, grupo etario, departamento y causa de muerte | Ninguno | Dato agregado público |
| MSPAS (`dbx_*`, vía Dropbox) | Reportes tabulares por categoría/grupo (según carpeta de origen) | Ninguno detectado en los archivos actuales | Dato agregado público |
| RENAP (pendiente — ver [Catálogo de Fuentes](catalogo_fuentes.md)) | Potencialmente por defunción individual | Posible (nombre, DPI, dirección, fecha exacta) | **Dato sensible — pendiente de evaluación** |

!!! info "Conclusión de la revisión"
    Con base en lo anterior, **las fuentes actualmente ingestadas no requieren
    anonimización adicional**, ya que llegan agregadas desde el origen. El
    plan descrito en este documento aplica de forma preventiva a **RENAP**, en
    caso de que la respuesta al oficio incluya microdatos a nivel de individuo.

## Medidas aplicadas a las fuentes actuales (OMS, INE, MSPAS)

- **No se aplica anonimización adicional**: los datos ya son agregados en el
  origen y no permiten re-identificación de personas.
- **Trazabilidad de procedencia**: cada tabla Bronze conserva columnas de
  linaje (`source_system`, `source_file`, `ingestion_timestamp`, etc., ver
  [Linaje de Datos](lineage.md)) que documentan de dónde proviene cada
  registro, cumpliendo el principio de transparencia.
- **Minimización**: los pipelines ingestan únicamente las columnas presentes
  en los reportes oficiales, sin enriquecer ni cruzar con otras fuentes que
  pudieran aumentar el riesgo de re-identificación.

## Medidas previstas para fuentes con datos sensibles (RENAP)

!!! warning "Pendiente de recepción"
    Si RENAP entrega microdatos a nivel de defunción individual, se aplicarán
    las siguientes medidas **antes de que el dato ingrese a la capa Bronze**
    (es decir, en el propio notebook de ingesta, previo al `saveAsTable`):

    1. **Eliminación de identificadores directos**: se descartan columnas como
       nombre, número de DPI y dirección exacta; no se almacenan ni siquiera de
       forma temporal en el Sandbox.
    2. **Generalización geográfica**: el municipio de residencia se reduce a
       departamento cuando la combinación (municipio, año, causa) tenga menos
       de 5 registros, para mitigar el riesgo de re-identificación.
    3. **Generalización temporal**: la fecha exacta de defunción se redondea a
       mes/año.
    4. **Umbral de k-anonimidad (k=5)**: ninguna combinación publicada de
       (año, departamento, causa, sexo, grupo etario) debe representar menos
       de 5 registros; las combinaciones por debajo del umbral se agrupan en
       categorías más amplias ("otros departamentos", "otras causas").

## Clasificación y etiquetado en Unity Catalog

Para mantener visible el nivel de sensibilidad de cada tabla del Sandbox sin
exponer información sensible en los metadatos, se adopta como buena práctica
el uso de **Governed Tags** de Unity Catalog
([Databricks — Governed tags](https://docs.databricks.com/aws/en/admin/governed-tags/)).
Los governed tags permiten definir, a nivel de cuenta, un conjunto controlado
de claves y valores permitidos, lo que evita etiquetas libres e inconsistentes
entre esquemas.

Se propone un único tag gobernado, aplicado a nivel de tabla:

| Tag | Valores permitidos | Aplicación |
|-----|---------------------|------------|
| `sensitivity` | `public_aggregated`, `sensitive_pending_review` | `public_aggregated` para todas las tablas actuales de `sandbox_bronze_ss2` (OMS, INE, MSPAS); `sensitive_pending_review` para cualquier tabla derivada de RENAP hasta que se confirme y aplique el plan de anonimización descrito arriba |

!!! note "Por qué governed tags y no comentarios libres"
    La documentación de Databricks recomienda **no incluir información
    sensible en el nombre o valor de un tag** (p. ej. nunca un nombre de
    persona), sino usar valores estandarizados y predefinidos. El tag
    `sensitivity` cumple esa recomendación: clasifica la tabla sin revelar
    contenido, y al estar gobernado a nivel de cuenta evita que cada pipeline
    defina su propia convención de etiquetado.

## Cumplimiento EU Data Act — resumen

| Principio | Medida adoptada |
|-----------|------------------|
| Minimización de datos | Solo se ingestan las columnas presentes en los reportes oficiales de OMS, INE y MSPAS |
| Transparencia | El [Catálogo de Fuentes](catalogo_fuentes.md) y el [Linaje de Datos](lineage.md) documentan origen, fecha de descarga y responsable de cada ingesta |
| Integridad y confidencialidad | Credenciales gestionadas exclusivamente mediante Databricks Secrets; ninguna se almacena en el repositorio |
| Responsabilidad y trazabilidad | Linaje extremo a extremo mediante columnas de auditoría (`ingestion_timestamp`, `source_system`, `source_file`, etc.) |
| Protección de datos sensibles | Plan de generalización y k-anonimidad (k=5) definido y listo para aplicarse a RENAP si se recibe información a nivel individual |
| Clasificación consistente | Tag gobernado `sensitivity` en Unity Catalog para distinguir tablas agregadas de tablas pendientes de revisión |

## Credenciales y secretos

Ninguna credencial se almacena en el repositorio de GitHub. Todos los
secretos se gestionan mediante **Databricks Secrets**, en el scope usado por
los cuatro pipelines de ingesta:

```
scope : ss2-bronze-layer
keys  : aws_access_key_id, aws_secret_access_key   (INE — S3)
        dropbox_app_key, dropbox_app_secret, dropbox_token   (MSPAS — Dropbox)
        gsa_type, gsa_project_id, gsa_private_key_id,
        gsa_private_key, gsa_client_email, gsa_client_id,
        gsa_auth_uri, gsa_token_uri,
        gsa_auth_provider_x509_cert_url,
        gsa_client_x509_cert_url, gsa_universe_domain   (OMS — Google Drive)
```
