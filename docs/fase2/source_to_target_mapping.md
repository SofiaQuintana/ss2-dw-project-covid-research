# Source-to-Target Mapping

El mapeo columna por columna de Bronze → Silver → Gold se mantiene como
hoja de cálculo, no en Markdown, porque el criterio de la hoja de
calificación ("Modelado y arquitectura", 10 pts) pide explícitamente un
archivo `source-to-target-mapping.xlsx`.

[**Abrir el Source-to-Target Mapping (Google Sheets)**](https://docs.google.com/spreadsheets/d/1dG82u_RNubLsc00ZwO-f5n9Wg222JlvT/edit?usp=sharing&ouid=108219715578182799145&rtpof=true&sd=true){ .md-button .md-button--primary }

## Qué contiene

El archivo tiene 6 pestañas. Las primeras 4 cubren Bronze → Silver por
fuente; las últimas 2 cubren Silver → Gold:

| Pestaña | Cobertura |
|---------|-----------|
| `INE_edad` | 3 tablas Bronze → Silver (sexo y edad, neonatales, postneonatales) |
| `INE_geografia` | 2 tablas Bronze → Silver (departamento de residencia, causas externas) |
| `MSPAS` | 3 tablas Bronze → Silver (primeras causas, enfermedades crónicas, grupo materno-infantil) |
| `WHO` | 2 tablas Bronze → Silver (Guatemala, Costa Rica) |
| `Gold_Dims` | Silver → Gold de las 5 dimensiones (`dim_tiempo`, `dim_geografia`, `dim_causa`, `dim_demografia`, `dim_fuente`) |
| `Gold_Facts` | Silver → Gold de las 2 fact tables (`fact_defunciones`, `fact_morbilidad`) |

Cada fila documenta una transformación concreta: tabla y columna de
origen, la regla aplicada en español (con ejemplos de valores reales,
no solo el nombre de la función), y tabla y columna de destino. Las filas
que eliminan subtotales completos se marcan en naranja claro.

## Referencia cruzada

[Reglas de Transformación](reglas_transformacion.md) documenta las mismas
reglas en formato narrativo, agrupadas por capa (Silver/Gold) en vez de por
columna — útil para entender el "por qué" de cada regla.
