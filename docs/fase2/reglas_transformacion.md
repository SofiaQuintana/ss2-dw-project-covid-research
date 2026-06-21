# Listado de Reglas de Transformación (Bronze → Silver)

!!! success "Stage layer implementado"
    Las reglas descritas aquí están verificadas contra el código real de los
    4 notebooks en `transformation-scripts/stage/` (no solo el diseño del
    plan). Las pruebas de calidad correspondientes están en
    `transformation-scripts/tests/`. La capa Gold (dimensiones y fact tables)
    todavía no se ha implementado — ver [Próximos pasos](#proximos-pasos).

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

## Catálogos de referencia

| Catálogo | Ubicación | Contenido real | Usado por stage actual |
|----------|-----------|------------------|--------------------------|
| `ref_departamentos_gt.csv` | `transformation-scripts/ref/` | 22 departamentos oficiales + variantes de escritura, con `depto_id` numérico | No (ver nota técnica arriba) — pendiente de adoptar en Gold |
| `ref_grupos_etarios.csv` | `transformation-scripts/ref/` | Mapeo de etiquetas de grupo etario heterogéneas (`"<1 año"`, `"1 a 4 años"`, `"10 a 14 años"`, ...) a rangos numéricos `(grupo_etario_anios_min, grupo_etario_anios_max)`, con columna `fuente_formato` | No — Silver no construye `dim_demografia`; se usará en `gold_dim_demografia.ipynb` |
| `oms_indicator_mapping.csv` | `transformation-scripts/ref/` | Código OMS → nombre en inglés/español + rango CIE-10 equivalente | Parcialmente — `stage_who.ipynb` usa una copia inline (`_OMS_INDICATOR_ROWS`, solo código→español) en vez de leer este CSV completo |

## Trazabilidad por fuente

| Fuente | Notebook Silver | Tablas Bronze → Silver | Responsable (Plan v3) |
|--------|------------------|--------------------------|--------------------------|
| INE — edad | `transformation-scripts/stage/stage_ine_edad.ipynb` | `ine_defunciones_sexo_edad_causas_muerte`→`ine_defunciones_sexo_edad`, `ine_defunciones_neonatales_sexo_edad_causas_muerte`→`ine_defunciones_neonatales`, `ine_defunciones_postneonatales_sexo_edad_causas_muerte`→`ine_defunciones_postneonatales` | Sofía Quintana |
| INE — geografía | `transformation-scripts/stage/stage_ine_geografia.ipynb` | `ine_defunciones_sexo_depto_residencia_causas_muerte`→`ine_defunciones_depto_residencia`, `ine_defunciones_causas_externas_sexo_depto_ocurrencia`→`ine_defunciones_causas_externas` | Sofía Quintana |
| MSPAS | `transformation-scripts/stage/stage_mspas.ipynb` | `dbx_primeras_causas_de_morbilidad_2015_a_2025`, `dbx_morbilidad_enfermedades_cronicas_2015_a_2025`, `dbx_morbilidad_grupo_materno_infantil_2012_a_2025` (mismo nombre en Silver) | Jeffrey Menéndez |
| WHO | `transformation-scripts/stage/stage_who.ipynb` | `who_guatemala`, `who_costa_rica` (mismo nombre en Silver) | Roberto Bautista |

Pruebas de verificación (lectura `limit()`, sin `count()` de tabla completa
salvo donde se indica): `transformation-scripts/tests/test_silver_ine.ipynb`,
`test_silver_mspas.ipynb`, `test_silver_who.ipynb`.

## Issues conocidos que motivan estas reglas

### 1. Normalización de código de causa entre fuentes

| Fuente | Formato en Silver | Columna usada como `codigo_origen` en `dim_causa` (Gold, planeado) |
|--------|--------------------|------------------------------------------------------------------------|
| INE — edad/geo residencia | `cie_10_norm` (ej. `J18`, o `A00-Y98`/`R99` para subtotales — ya filtrados, no llegan a Silver) | `cie_10_norm` |
| INE — causas externas | `cie_10_norm` = rango extraído del campo combinado (ej. `V01-V99`) | `cie_10_norm` |
| MSPAS | `cie_10_norm` (ej. `J:18:0`→`J180`) | `cie_10_norm` |
| WHO | `codigo_causa` (indicador OMS, ej. `CG0395`, no es CIE-10) | `codigo_causa` |

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

### 4. Doble conteo INE-edad vs. INE-geografía (riesgo en Gold, no en Silver)

INE-edad (con `edad`, sin departamento) e INE-geo-residencia (con
departamento, sin edad) son dos cortes distintos de **las mismas
defunciones** a nivel nacional. Silver los mantiene como tablas separadas
correctamente. El riesgo aparece en Gold/consumo: si ambas alimentan
`fact_defunciones` sin filtrar por `dim_fuente.source_system`, sumar
`total_defunciones` sin ese filtro duplica las muertes contadas. Se debe
documentar explícitamente en la documentación de usuario del DW (no es una
regla de Silver, pero nace de cómo Silver preserva el grano de cada fuente).

### 5. Grupos etarios heterogéneos

`ref_grupos_etarios.csv` existe como mapeo manual (valores finitos y
conocidos por fuente), pero **todavía no se consume** en ningún notebook
Silver — se usará en `gold_dim_demografia.ipynb` para traducir
`grupo_etario`/`edad` a `(grupo_etario_anios_min, grupo_etario_anios_max)`.

## Próximos pasos

- Implementar la capa Gold (`gold_dim_*.ipynb`, `gold_fact_*.ipynb`) —
  ninguno de estos notebooks existe aún en `transformation-scripts/gold/`.
- Decidir y documentar si `gold_dim_geografia.ipynb` migra el `JOIN` de
  departamento a leer `ref_departamentos_gt.csv` directamente, en vez de
  reutilizar las listas hardcodeadas de `stage_ine_geografia.ipynb` /
  `stage_mspas.ipynb` (ver nota técnica arriba).
- Conectar `oms_indicator_mapping.csv` completo (incluye rango CIE-10
  equivalente por indicador) si se necesita esa columna en `dim_causa`;
  actualmente `stage_who.ipynb` solo usa el mapeo código→nombre en español.
- Esta tabla es la base directa para completar las pestañas `INE_edad`,
  `INE_geografia`, `MSPAS` y `WHO` del `source-to-target-mapping.xlsx`.
