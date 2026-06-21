# Listado de Reglas de Transformación (Bronze → Silver)

!!! success "Stage y Gold implementados"
    Las reglas descritas aquí están verificadas contra el código real de los
    4 notebooks de Silver en `transformation-scripts/stage/` y los 7
    notebooks de Gold en `transformation-scripts/gold/` (no solo el diseño
    del plan). Las pruebas de calidad correspondientes están en
    `transformation-scripts/tests/` (`test_silver_*.ipynb` y
    `test_gold_dw.ipynb`).

## Principio rector: marcar, no destruir

La capa Silver corrige **forma, tipo y calidad estructural** de los datos
provenientes de Bronze. La única excepción al principio "no destruir" son
los **subtotales pre-calculados de INE**: se filtran directamente en Silver
(no se marcan con una columna booleana) porque son estructuralmente inútiles
para análisis granular y su presencia duplicaría conteos en cualquier
agregación de Gold. Ninguna otra regla de negocio filtra filas en Silver.

## Tabla de reglas

| Regla | Aplica a | Detalle | Estado |
|-------|----------|---------|--------|
| Cast `anio` → `INT` | MSPAS (todas), INE (5 tablas), WHO (2 tablas) | `anio` puede llegar como `DOUBLE` en `dbx_morbilidad_enfermedades_cronicas_2015_a_2025`; WHO la recibe como `year` y se renombra | ✅ Implementada |
| Cast `total/hombres/mujeres` → `INT` | INE (5 tablas) | Tipos inconsistentes entre tablas hermanas de la misma fuente | ✅ Implementada |
| `casos_total = COALESCE(casos, cantidad)` | MSPAS (las 3 tablas `dbx_*`) | `casos` y `cantidad` tienen nulls cruzados; en `enfermedades_cronicas` (que solo trae `casos`) se agrega `cantidad=NULL` vía `ensure_column` antes del `COALESCE`, dando el mismo resultado (`casos_total = casos`). Columnas originales `casos`/`cantidad` se eliminan tras calcular `casos_total` | ✅ Implementada |
| Filtrar subtotales INE-edad | INE-edad (3 tablas) | Se filtran filas donde `causa_de_muerte IN ('Todas las causas', 'Otras causas')` — no existe columna `es_subtotal`; Silver entrega solo datos granulares | ✅ Implementada |
| Filtrar subtotales INE-geo residencia | `ine_defunciones_depto_residencia` | Filtra `departamento_de_residencia = 'Todos los departamentos'` Y `codigo_cie_10 = 'Todas las causas'` (dos subtotales independientes) | ✅ Implementada |
| Filtrar subtotales INE-geo causas externas | `ine_defunciones_causas_externas` | Filtra únicamente `departamento_de_ocurrencia = 'Todos los departamentos'` (esta tabla no tiene fila de subtotal por causa) | ✅ Implementada |
| Validación de cuadratura | INE (5 tablas) | `validate_cuadratura()` compara `total == hombres + mujeres` sobre una muestra de 5 000 filas y emite **solo un `logger.warning`** si falla — no agrega columna a la tabla Silver ni filtra nada | ✅ Implementada |
| Normalizar código de causa (`cie_10_norm`) | INE (5 tablas), MSPAS (3 tablas) | `normalize_cie10()`: quita `:` y espacios (`J:18:0`→`J180`); además resuelve dos casos especiales de texto: `'Todas las causas'`/`'Todas las causas externas'`→`'A00-Y98'`, `'Otras causas'`→`'R99'`. Columna original (`codigo_cie_10` / `cie_10`) se conserva | ✅ Implementada |
| Descomponer campo combinado de causas externas | `ine_defunciones_causas_externas` | Bronze trae un solo campo `causas_externas_codigo_cie_10` con texto + rango, ej. `"Accidentes de transporte (V01-V99)"`. Silver lo separa en `causa_de_muerte` (texto antes del paréntesis) y `cie_10_norm` (rango dentro del paréntesis, vía `regexp_extract`); filas con esta columna `NULL` en Bronze se descartan porque no aportan causa | ✅ Implementada |
| Renombrar y normalizar columnas WHO | WHO (2 tablas) | `indicator_code`→`codigo_causa`, `indicator_name`→`nombre_causa`, `number`→`defunciones` (cast `BIGINT`), `year`→`anio`, `country`→`pais`; tres columnas de tasa con nombres largos en inglés → `pct_causa_total_muertes`, `tasa_estandarizada_x100k`, `tasa_mortalidad_x100k`. Se eliminan `age_group` (formato `[25-29]` redundante) y la columna de linaje específica de cada origen (`volume_path` en Guatemala, `gdrive_file_id` en Costa Rica) | ✅ Implementada |
| Normalizar `sexo` | WHO (2 tablas) | `'Female'`→`'F'`, `'Male'`→`'M'`, `'All'`→`'Ambos'`; cualquier otro valor se conserva sin cambio | ✅ Implementada |
| Normalizar `grupo_etario` | WHO (2 tablas) | Desde `age_group_code`: casos especiales `'Age_all'`→`'Todas'`, `'Age_unknown'`→`'Desconocido'`, `'Age85_over'`→`'85+'`, `'Age00'`→`'0'`; patrón general `'Age25_29'`→`'25-29'` (quita prefijo `Age`, `_`→`-`) | ✅ Implementada |
| Traducir `nombre_causa` al español | WHO (2 tablas) | LEFT JOIN contra catálogo inline `_OMS_INDICATOR_ROWS` (código OMS → nombre en español, ~190 filas con todos los indicadores observados incluyendo `CG0395`→`'COVID-19'`); si el código no matchea, se conserva el nombre en inglés original vía `COALESCE` | ✅ Implementada |
| Preservar `NULL` en tasas WHO | WHO (2 tablas) | No se imputa `0` en `pct_causa_total_muertes`, `tasa_estandarizada_x100k`, `tasa_mortalidad_x100k` — confirmado en test: `tasa_estandarizada_x100k` es NULL salvo en filas `grupo_etario='Todas'`, comportamiento heredado de la fuente, no introducido por la transformación | ✅ Implementada |
| Resolver `departamento_oficial` | MSPAS (3 tablas), INE-geografía (2 tablas) | `LEFT JOIN` sobre `UPPER(TRIM(col_depto))` contra un catálogo de variantes → nombre oficial con tilde/casing correcto; filas sin match quedan con `departamento_oficial = NULL`, **no se descartan** | ✅ Implementada — ⚠️ ver nota |
| `dropDuplicates()` | Todas (9 tablas Silver) | Reintentos de ingesta en Bronze pueden generar filas exactamente repetidas | ✅ Implementada |
| Idempotencia Silver | Todas | Todos los notebooks Silver escriben con `mode("overwrite")` + `overwriteSchema=true` — re-ejecuciones del Job no duplican datos | ✅ Implementada |
| `silver_processed_timestamp` | Todas | Columna de auditoría: timestamp de ejecución del notebook Silver (`current_timestamp()`) | ✅ Implementada |
| `silver_job_run_id` | Todas | Columna de auditoría: run id de Databricks Workflows, o `"manual"` si se ejecuta fuera de un job | ✅ Implementada |

!!! warning "Nota técnica — catálogo de departamentos no leído desde CSV en stage"
    `ref_departamentos_gt.csv` existe en `transformation-scripts/ref/` (22
    departamentos + variantes + `depto_id`), pero los notebooks de stage
    actuales (`stage_ine_geografia.ipynb`, `stage_mspas.ipynb`) **no lo leen
    desde archivo**: usan una lista Python hardcodeada (`_DEPTO_ROWS`)
    duplicada de forma idéntica en ambos notebooks, sin la columna
    `depto_id`. El contenido coincide con el CSV salvo por esa columna y por
    una fila extra en MSPAS (`'TODOS LOS DEPARTAMENTOS'` → como variante
    propia, porque esa tabla no filtra ese subtotal). Antes de construir
    `gold_dim_geografia.ipynb` conviene decidir si se migra el `JOIN` a leer
    el CSV real (más auditable, single source of truth) o si se documenta el
    hardcode como decisión intencional.

## Reglas Gold (Silver → Gold)

La capa Gold (`gold_ss2`) construye el galaxy schema (5 dimensiones + 2
fact tables) a partir de las tablas Silver. Todos los notebooks de Gold
están implementados en `transformation-scripts/gold/` y verificados por
`transformation-scripts/tests/test_gold_dw.ipynb`.

| Regla | Aplica a | Detalle | Estado |
|-------|----------|---------|--------|
| Generación sintética de `dim_tiempo` | `gold_dim_tiempo.ipynb` | No lee Silver — genera filas para `anio` 2012–2025 directamente en código; `periodo_covid` = `'pre_covid'` si `anio <= 2019`, `'covid_y_post'` si `anio >= 2020` | ✅ Implementada |
| UNION DISTINCT de 3 niveles geográficos | `gold_dim_geografia.ipynb` | Nivel `pais`: de `who_guatemala`/`who_costa_rica` (`pais` normalizado con `initcap`+reemplazo de `_`) + fila placeholder `('Guatemala', 'Sin desagregar', NULL, 'pais')` para INE-edad. Nivel `departamento`: UNION de `departamento_oficial` desde las 2 tablas INE-geo + las 3 `dbx_*`, excluyendo `NULL` y la variante `'Todos los departamentos'`. Nivel `municipio`: UNION de `(departamento_oficial, municipio)` solo desde las 3 tablas MSPAS, descartando filas con `departamento`/`municipio` `NULL` | ✅ Implementada |
| `causa_sk` por `codigo_origen` unificado | `gold_dim_causa.ipynb` | UNION DISTINCT de `(codigo_origen, descripcion)` desde las 10 tablas Silver: INE-edad/geo-residencia/causas-externas y MSPAS usan **`cie_10_norm`** como `codigo_origen` (no la columna combinada `causas_externas_codigo_cie_10` planteada en el diseño inicial — Silver ya la normaliza a `cie_10_norm` para las 3 fuentes INE); WHO usa `codigo_causa`. Se descartan filas con `codigo_origen` NULL antes de asignar `causa_sk` | ✅ Implementada |
| Catálogo de grupos etarios inline + parsing regex | `gold_dim_demografia.ipynb` | El mapeo `(grupo_etario_label) → (min, max)` está hardcodeado en el notebook (`_REF_GRUPOS`, ~80 filas) — **no lee `ref_grupos_etarios.csv` desde archivo**, aunque el contenido es equivalente. Para etiquetas que no matchean el catálogo (ej. WHO `'25-29'`, `'85+'`) aplica un parser regex de respaldo: patrón `^[0-9]+-[0-9]+$` extrae min/max por split; patrón `^[0-9]+[+]$` extrae solo min | ✅ Implementada — ⚠️ ver nota |
| Fila placeholder demografía | `gold_dim_demografia.ipynb` | `(sexo='Ambos', grupo_etario_label='Sin desagregar', min=NULL, max=NULL)` se construye explícitamente para INE-geografía (sin columna de edad) | ✅ Implementada |
| `dim_fuente` con `pipeline_name`/`nivel_agregacion` manual | `gold_dim_fuente.ipynb` | Tabla de mapeo hardcodeada de 10 tablas Silver → `pipeline_name` (`stage_ine_edad`, `stage_ine_geografia`, `stage_mspas`, `stage_who`) y `nivel_agregacion` (`nacional_edad`, `departamental`, `municipal`, `nacional`); UNION DISTINCT de `(source_system, source_file)` reales por tabla | ✅ Implementada |
| `fact_defunciones`: INE-edad → placeholders fijos | `gold_fact_defunciones.ipynb` | Las 3 tablas INE-edad (`sexo_edad`, `neonatales`, `postneonatales`) joinean `causa_sk` por `cie_10_norm`, `demografia_sk` por `(sexo='Ambos', grupo_etario_label=edad)`, y usan el `geografia_sk` del placeholder `'Guatemala'/'Sin desagregar'` resuelto una sola vez al inicio del notebook (no por fila) | ✅ Implementada |
| `fact_defunciones`: INE-geografía (residencia + causas externas) | `gold_fact_defunciones.ipynb` | `geografia_sk` por `departamento_oficial` (join contra `dim_geografia` filtrado a `nivel_geo='departamento'`); `causa_sk` por `cie_10_norm`; `demografia_sk` fijo al placeholder `'Ambos'/'Sin desagregar'` (sin columna de edad en estas tablas) | ✅ Implementada |
| `fact_defunciones`: WHO | `gold_fact_defunciones.ipynb` | `pais` se renormaliza (`initcap` + `_`→espacio) antes del join contra `dim_geografia` filtrado a `nivel_geo='pais'`; `causa_sk` por `codigo_causa`; `demografia_sk` por `(sexo, grupo_etario)` exacto; `defunciones_hombres`/`defunciones_mujeres` quedan `NULL` (WHO no las reporta); `tasa_mortalidad_x100k`/`tasa_estandarizada_x100k` se preservan tal cual vienen de Silver (incluyendo NULLs) | ✅ Implementada |
| `fact_morbilidad`: geografía a nivel municipio | `gold_fact_morbilidad.ipynb` | Join contra `dim_geografia` filtrado a `nivel_geo='municipio'` por `(departamento_oficial, municipio)` exacto — a diferencia de `fact_defunciones`, que para MSPAS usaría nivel departamento; aquí se preserva el grano más fino disponible en la fuente | ✅ Implementada |
| `fact_morbilidad`: filas sin `sexo` → placeholder demografía | `gold_fact_morbilidad.ipynb` | Spark no matchea `NULL == NULL` en un join, así que las filas con `sexo` NULL en Silver se remapean explícitamente a `(sexo='Ambos', grupo_etario_label='Sin desagregar')` antes de unir con `dim_demografia`, para evitar `demografia_sk` NULL en la fact | ✅ Implementada |
| Helpers de join reutilizables | `gold_fact_defunciones.ipynb` | El notebook centraliza los joins repetidos (`join_tiempo`, `join_causa_cie10`, `join_causa_codigo`, `join_fuente`, `join_demografia_sexo_grupo`, `join_geo_depto`) para evitar duplicar la misma lógica de unión en las 4 fuentes (INE-edad, INE-geo-residencia, INE-causas-externas, WHO) | ✅ Implementada |
| `causa_sk`/`demografia_sk`/`geografia_sk`/`fuente_sk`/`tiempo_sk` como surrogate keys | Todas las dimensiones | `row_number()` sobre `Window.orderBy(...)` de las columnas naturales de cada dimensión — determinístico entre ejecuciones siempre que el conjunto de valores distintos no cambie | ✅ Implementada |
| Idempotencia Gold | Todas (`gold_dim_*`, `gold_fact_*`) | Igual que Silver: `mode("overwrite")` + `overwriteSchema=true` | ✅ Implementada |

!!! warning "Nota técnica — `dim_demografia` no lee el CSV de referencia"
    Al igual que con `ref_departamentos_gt.csv` en Silver, `ref_grupos_etarios.csv`
    existe en `transformation-scripts/ref/` pero `gold_dim_demografia.ipynb`
    usa una lista Python hardcodeada (`_REF_GRUPOS`) en vez de leerlo desde
    archivo. El contenido es equivalente en intención (mapeo de etiquetas de
    edad a rangos numéricos), pero el CSV no es la fuente real consumida por
    el job. Documentar esta decisión o migrar el `JOIN` a leer el CSV es un
    ítem de mejora técnica, no un bloqueante para la entrega.

!!! info "Validación NULLs en FKs tolerados"
    `test_gold_dw.ipynb` verifica integridad referencial en las 5 FKs de
    ambas fact tables. Solo se toleran NULLs en `geografia_sk`: en
    `fact_morbilidad` para municipios MSPAS sin match en el catálogo de
    departamentos, y en `fact_defunciones` para filas INE donde
    `departamento_oficial` ya venía NULL desde Silver (departamento sin
    match en el catálogo de variantes). El resto de FKs (`tiempo_sk`,
    `causa_sk`, `demografia_sk`, `fuente_sk`) deben tener cero NULLs.

## Catálogos de referencia

| Catálogo | Ubicación | Contenido real | Usado por stage actual | Usado por Gold |
|----------|-----------|------------------|--------------------------|------------------|
| `ref_departamentos_gt.csv` | `transformation-scripts/ref/` | 22 departamentos oficiales + variantes de escritura, con `depto_id` numérico | No (ver nota técnica arriba) | No — `gold_dim_geografia.ipynb` deriva los departamentos directamente desde `departamento_oficial` ya resuelto en Silver |
| `ref_grupos_etarios.csv` | `transformation-scripts/ref/` | Mapeo de etiquetas de grupo etario heterogéneas (`"<1 año"`, `"1 a 4 años"`, `"10 a 14 años"`, ...) a rangos numéricos `(grupo_etario_anios_min, grupo_etario_anios_max)`, con columna `fuente_formato` | No — Silver no construye `dim_demografia` | No (ver nota técnica arriba) — `gold_dim_demografia.ipynb` usa una copia hardcodeada equivalente |
| `oms_indicator_mapping.csv` | `transformation-scripts/ref/` | Código OMS → nombre en inglés/español + rango CIE-10 equivalente | Parcialmente — `stage_who.ipynb` usa una copia inline (`_OMS_INDICATOR_ROWS`, solo código→español) en vez de leer este CSV completo | No — `gold_dim_causa.ipynb` solo necesita `codigo_causa`/`nombre_causa`, ya resueltos en Silver |

## Trazabilidad por fuente

| Fuente | Notebook Silver | Tablas Bronze → Silver | Responsable (Plan v3) |
|--------|------------------|--------------------------|--------------------------|
| INE — edad | `transformation-scripts/stage/stage_ine_edad.ipynb` | `ine_defunciones_sexo_edad_causas_muerte`→`ine_defunciones_sexo_edad`, `ine_defunciones_neonatales_sexo_edad_causas_muerte`→`ine_defunciones_neonatales`, `ine_defunciones_postneonatales_sexo_edad_causas_muerte`→`ine_defunciones_postneonatales` | Sofía Quintana |
| INE — geografía | `transformation-scripts/stage/stage_ine_geografia.ipynb` | `ine_defunciones_sexo_depto_residencia_causas_muerte`→`ine_defunciones_depto_residencia`, `ine_defunciones_causas_externas_sexo_depto_ocurrencia`→`ine_defunciones_causas_externas` | Sofía Quintana |
| MSPAS | `transformation-scripts/stage/stage_mspas.ipynb` | `dbx_primeras_causas_de_morbilidad_2015_a_2025`, `dbx_morbilidad_enfermedades_cronicas_2015_a_2025`, `dbx_morbilidad_grupo_materno_infantil_2012_a_2025` (mismo nombre en Silver) | Jeffrey Menéndez |
| WHO | `transformation-scripts/stage/stage_who.ipynb` | `who_guatemala`, `who_costa_rica` (mismo nombre en Silver) | Roberto Bautista |

Pruebas de verificación Silver (lectura `limit()`, sin `count()` de tabla
completa salvo donde se indica): `transformation-scripts/tests/test_silver_ine.ipynb`,
`test_silver_mspas.ipynb`, `test_silver_who.ipynb`.

| Notebook Gold | Lee de Silver | Escribe en Gold | Responsable (Plan v3) |
|---------------|----------------|------------------|--------------------------|
| `gold_dim_tiempo.ipynb` | (ninguna — generado sintéticamente) | `gold_ss2.dim_tiempo` | Sofía Quintana |
| `gold_dim_geografia.ipynb` | `who_guatemala`, `who_costa_rica`, `ine_defunciones_depto_residencia`, `ine_defunciones_causas_externas`, 3 tablas `dbx_*` | `gold_ss2.dim_geografia` | Sofía Quintana |
| `gold_dim_causa.ipynb` | 5 tablas INE + 3 tablas `dbx_*` + 2 tablas WHO (las 10 tablas Silver) | `gold_ss2.dim_causa` | Sofía Quintana |
| `gold_dim_demografia.ipynb` | 3 tablas INE-edad, 3 tablas `dbx_*`, 2 tablas WHO | `gold_ss2.dim_demografia` | Sofía Quintana |
| `gold_dim_fuente.ipynb` | Las 10 tablas Silver (solo `source_system`/`source_file`) | `gold_ss2.dim_fuente` | Sofía Quintana |
| `gold_fact_defunciones.ipynb` | 5 tablas INE + 2 tablas WHO | `gold_ss2.fact_defunciones` | Jeffrey Menéndez |
| `gold_fact_morbilidad.ipynb` | 3 tablas `dbx_*` | `gold_ss2.fact_morbilidad` | Jeffrey Menéndez |

Pruebas de verificación Gold (4 niveles: existencia, sanity checks por
dimensión, integridad de FKs, queries analíticas end-to-end):
`transformation-scripts/tests/test_gold_dw.ipynb`.

## Issues conocidos que motivan estas reglas

### 1. Normalización de código de causa entre fuentes

| Fuente | Formato en Silver | Columna usada como `codigo_origen` en `dim_causa` (Gold, implementado) |
|--------|--------------------|------------------------------------------------------------------------|
| INE — edad/geo residencia | `cie_10_norm` (ej. `J18`, o `A00-Y98`/`R99` para subtotales — ya filtrados, no llegan a Silver) | `cie_10_norm` |
| INE — causas externas | `cie_10_norm` = rango extraído del campo combinado (ej. `V01-V99`) | `cie_10_norm` |
| MSPAS | `cie_10_norm` (ej. `J:18:0`→`J180`) | `cie_10_norm` |
| WHO | `codigo_causa` (indicador OMS, ej. `CG0395`, no es CIE-10) | `codigo_causa` |

`gold_dim_causa.ipynb` confirma esto en código: las 5 tablas INE y las 3
`dbx_*` se unen usando `cie_10_norm`, y las 2 tablas WHO usan `codigo_causa`
— ningún notebook Gold usa la columna combinada
`causas_externas_codigo_cie_10` directamente, porque Silver ya la resolvió
a `cie_10_norm`.

### 2. Subtotales INE — doble conteo

Silver **filtra** los subtotales directamente — no existe columna
`es_subtotal` en ninguna tabla Silver real. Gold recibirá solo filas
granulares y no necesitará un filtro adicional por esta razón. El total
nacional se obtendrá agregando el detalle, no leyendo una fila pre-calculada.

### 3. MSPAS — columnas de conteo duplicadas

`casos_total = COALESCE(casos, cantidad)` se aplica en las 3 tablas
`dbx_*`. Para `enfermedades_cronicas_2015_a_2025` (que en Bronze solo trae
`casos`), el notebook usa `ensure_column()` para añadir una columna
`cantidad` con valor `NULL` antes del `COALESCE`, de forma que las 3 tablas
comparten exactamente la misma lógica de transformación sin necesitar un
`if` especial por tabla.

### 4. Doble conteo INE-edad vs. INE-geografía (riesgo real en Gold — confirmado)

INE-edad (con `edad`, sin departamento) e INE-geo-residencia (con
departamento, sin edad) son dos cortes distintos de **las mismas
defunciones** a nivel nacional. Silver los mantiene como tablas separadas
correctamente, y **ambas alimentan `fact_defunciones` en
`gold_fact_defunciones.ipynb`** (se unen con `reduce(...union...)` junto con
INE-causas-externas y WHO). El riesgo es real, no solo teórico: cualquier
`SUM(total_defunciones)` sobre `fact_defunciones` sin filtrar por
`dim_fuente.pipeline_name` (`stage_ine_edad` vs. `stage_ine_geografia` vs.
`stage_who`) duplica las muertes contadas. Las queries de demostración en
`gold_fact_defunciones.ipynb` y `test_gold_dw.ipynb` (Q1, Q3, Q5) siempre
filtran por `pipeline_name` antes de agregar — ese es el patrón a replicar
en cualquier consulta nueva sobre esta fact table.

### 5. Grupos etarios heterogéneos

`ref_grupos_etarios.csv` existe como mapeo manual (valores finitos y
conocidos por fuente), pero **no se consume desde archivo** en ningún
notebook: ni Silver ni `gold_dim_demografia.ipynb` lo leen directamente.
Este último usa una copia hardcodeada equivalente (`_REF_GRUPOS`) más un
parser regex de respaldo para etiquetas no catalogadas (ver nota técnica
en la sección de reglas Gold).

## Próximos pasos

- Migrar `gold_dim_geografia.ipynb` y `gold_dim_demografia.ipynb` a leer
  `ref_departamentos_gt.csv` y `ref_grupos_etarios.csv` desde archivo en vez
  de listas hardcodeadas equivalentes (ver notas técnicas arriba) — mejora
  de auditabilidad, no bloqueante.
- Conectar `oms_indicator_mapping.csv` completo (incluye rango CIE-10
  equivalente por indicador) si se necesita esa columna en `dim_causa`;
  actualmente `stage_who.ipynb` solo usa el mapeo código→nombre en español.
- Esta tabla es la base directa para completar las pestañas `INE_edad`,
  `INE_geografia`, `MSPAS`, `WHO`, `Gold_Facts` y `Gold_Dims` del
  `source-to-target-mapping.xlsx`.
