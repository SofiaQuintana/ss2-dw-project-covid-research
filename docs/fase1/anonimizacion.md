# Plan de Anonimización — EU Data Act

## Clasificación de datos

Los datos utilizados en este proyecto son **datos agregados de mortalidad** publicados
por organismos oficiales (OMS, INE). No contienen identificadores personales directos
(nombre, DPI, dirección).

| Fuente | Nivel de agregación | Identificadores personales | Clasificación |
|--------|--------------------|-----------------------------|---------------|
| OMS — WHO Mortality DB | Por año / sexo / grupo etario / causa | Ninguno | Dato agregado público |
| INE — Estadísticas Vitales | Por año / municipio / causa CIE-10 | Ninguno | Dato agregado público |
| RENAP | Por defunción individual | Potencial (si incluye nombre/DPI) | **Dato sensible** |

## Medidas aplicadas

### Datos OMS e INE (agregados)
- No requieren anonimización adicional: ya vienen agregados en la fuente.
- Se documenta la procedencia oficial para cumplir el principio de **transparencia** del EU Data Act.

### Datos RENAP (si se obtienen)

!!! warning "Pendiente de recepción"
    Si RENAP entrega microdatos individuales, se aplicarán las siguientes medidas
    **antes de ingresar a la capa Bronze**:

    1. **Eliminación de identificadores directos**: nombre, número de DPI, dirección exacta.
    2. **Generalización geográfica**: reducir municipio a departamento si el municipio
       tiene menos de 5 defunciones en el período (riesgo de re-identificación).
    3. **Generalización temporal**: redondear fecha exacta de defunción a mes/año.
    4. **K-anonimidad mínima k=5**: ninguna combinación (año, departamento, causa, sexo,
       grupo etario) debe tener menos de 5 registros.

## Cumplimiento EU Data Act

| Principio | Medida adoptada |
|-----------|----------------|
| Minimización de datos | Solo se ingestan columnas necesarias para el análisis de mortalidad |
| Transparencia | Catálogo de fuentes documenta URL, fecha de descarga y responsable |
| Integridad y confidencialidad | Credenciales en Databricks Secrets, no en el repositorio |
| Responsabilidad | Data lineage trazable de extremo a extremo mediante columnas de auditoría |

## Credenciales y secretos

Ninguna credencial se almacena en el repositorio de GitHub.  
Todos los secretos se gestionan mediante **Databricks Secrets**:

```
scope : ss2-bronze-layer
keys  : google_service_account_json
        redshift_password
        dropbox_token  (si aplica)
```
