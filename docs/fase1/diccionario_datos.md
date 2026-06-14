# Diccionario de Datos

## Fuente F01/F02 — WHO Mortality Database (CSV)

Aplica a las tablas: `sandbox_bronze_ss2.who_guatemala`, `sandbox_bronze_ss2.who_costa_rica`

### Columnas originales de la fuente

| Columna original | Columna en Bronze (snake_case) | Tipo inferido | Descripción | Valores de ejemplo | Nulos permitidos |
|-----------------|-------------------------------|--------------|-------------|-------------------|-----------------|
| `Indicator Code` | `indicator_code` | string | Código del indicador de causa de muerte según clasificación OMS | `CG0030`, `CG0010` | No |
| `Indicator Name` | `indicator_name` | string | Nombre descriptivo del indicador | `Tuberculosis`, `Infectious and parasitic diseases` | No |
| `Year` | `year` | integer | Año de registro de la defunción | `2020`, `2019` | No |
| `Sex` | `sex` | string | Sexo del grupo reportado | `All`, `Male`, `Female` | No |
| `Age group code` | `age_group_code` | string | Código de grupo etario (formato OMS, sin normalizar en Bronze) | `Age15_19`, `Age85_over`, `Age00` | No |
| `Age Group` | `age_group` | string | Etiqueta legible del grupo etario (sin normalizar en Bronze) | `[15-19]`, `[85+]`, `[0]` | No |
| `Number` | `number` | double | Número de defunciones en el grupo | `10.0`, `209.0` | Sí |
| `Percentage of cause-specific deaths out of total deaths` | `percentage_of_cause_specific_deaths_out_of_total_deaths` | double | Porcentaje que representa esta causa sobre el total de muertes | `0.582`, `2.429` | Sí |
| `Age-standardized death rate per 100 000 standard population` | `age_standardized_death_rate_per_100_000_standard_population` | double | Tasa de mortalidad ajustada por edad por 100,000 habitantes | — | Sí (frecuentemente vacío en la fuente) |
| `Death rate per 100 000 population` | `death_rate_per_100_000_population` | double | Tasa de mortalidad cruda por 100,000 habitantes | `0.513`, `63.973` | Sí |

### Columnas técnicas de auditoría (agregadas en Bronze)

| Columna | Tipo | Descripción |
|---------|------|-------------|
| `ingestion_timestamp` | timestamp | Fecha y hora UTC en que se ejecutó el pipeline de ingesta |
| `source_system` | string | Sistema de origen (`WHO Mortality Database Portal (Google Drive)`) |
| `source_file` | string | Nombre del archivo original descargado |
| `gdrive_file_id` | string | ID del archivo en Google Drive (trazabilidad del dato hasta la fuente) |
| `country` | string | País al que corresponden los datos (`guatemala`, `costa_rica`) |

### Notas de Bronze

!!! warning "Sin normalización en esta capa"
    - `age_group_code` y `age_group` se preservan con sus valores originales de la OMS
      (`Age15_19`, `[15-19]`, `Age85_over`, `[85+]`). La estandarización ocurrirá en Stage.
    - La columna `age_standardized_death_rate_per_100_000_standard_population` está
      frecuentemente vacía en la fuente; se ingesta como `null` sin imputación.
    - Los 7 renglones de metadata del archivo (Region, Country, Export date, etc.)
      se descartan en la lectura — no son datos de defunciones sino metadata del export.

---

## Fuente F03 — INE Estadísticas Vitales (CSV Local)

Aplica a la tabla: `sandbox_bronze_ss2.local_<sufijo>`

!!! note "Pendiente"
    Completar una vez que se descargue el archivo del INE y se inspeccionen sus columnas.
    Seguir el mismo formato de tabla que la sección anterior.
