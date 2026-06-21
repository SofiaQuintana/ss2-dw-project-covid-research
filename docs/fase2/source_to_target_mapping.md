# Source-to-Target Mapping

El mapeo columna por columna de Bronze → Silver → Gold se mantiene como
hoja de cálculo, no en Markdown, porque el criterio de la hoja de
calificación ("Modelado y arquitectura", 10 pts) pide explícitamente un
archivo `source-to-target-mapping.xlsx`.

[**Abrir el Source-to-Target Mapping (Google Sheets)**](https://docs.google.com/spreadsheets/d/1dG82u_RNubLsc00ZwO-f5n9Wg222JlvT/edit?usp=sharing&ouid=108219715578182799145&rtpof=true&sd=true){ .md-button .md-button--primary }

## Qué contiene

El archivo tiene 7 pestañas. Las primeras 4 cubren Bronze → Silver por
fuente; las últimas 2 cubren Silver → Gold:

| Pestaña | Cobertura |
|---------|-----------|
| `Léeme` | Portada con la guía de lectura: qué significa cada estado y cada color de fila |
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

## Cómo se generó

El archivo **no se edita a mano**: se genera con
[`transformation-scripts/generate_stm.py`](https://github.com/SofiaQuintana/ss2-dw-project-covid-research/blob/main/transformation-scripts/generate_stm.py),
un script Python que construye el `.xlsx` con `openpyxl` a partir de listas
de reglas verificadas contra el código real de los notebooks.

```bash
cd transformation-scripts
source ../../.venv/bin/activate
python generate_stm.py   # escribe ../source-to-target-mapping.xlsx
```

!!! info "Por qué un script y no un Excel editado a mano"
    Cada regla del archivo fue verificada leyendo línea por línea los 11
    notebooks de `transformation-scripts/stage/` y `transformation-scripts/gold/`
    — no se transcribió el diseño del plan de trabajo sin confirmarlo contra
    el código. Generarlo con un script permite volver a ejecutarlo cada vez
    que un notebook cambie, sin que el Excel y el código se desincronicen.

El archivo `.xlsx` generado vive en la raíz del repositorio
(`source-to-target-mapping.xlsx`) y la copia enlazada arriba en Google
Sheets es la que se comparte para revisión y defensa.

## Referencia cruzada

[Reglas de Transformación](reglas_transformacion.md) documenta las mismas
reglas en formato narrativo, agrupadas por capa (Silver/Gold) en vez de por
columna — útil para entender el "por qué" de cada regla; el Excel es la
referencia exhaustiva columna por columna que exige la hoja de calificación.
