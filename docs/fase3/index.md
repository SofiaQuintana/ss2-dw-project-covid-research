# Fase 3 — Machine Learning, Visualización Analítica e Interoperabilidad BI

!!! info "Documentación disponible en Google Drive"
    La documentación completa de la Fase 3 está disponible en:
    **[Carpeta Fase 3 — Google Drive](https://drive.google.com/drive/u/3/folders/1DzDgBGiFRfbDw8EdrTQp932aCmgi2tBd)**

## Contenido

- [Arquitectura — Fase 3](arquitectura.md): expansión de la capa de
  consumo sobre el Gold ya estable de Fase 2.
- [Análisis y Hallazgos](analisis.md): comparativa Pre/Post-COVID,
  modelo de ML (Lasso en SageMaker) y recomendaciones de política pública.
- Modelo de ML en Amazon SageMaker + Databricks
- Visualizaciones en Power BI (Power Query + DAX)
- Visualizaciones en segunda herramienta BI (Tableau)
- Análisis comparativo Pre-COVID / Post-COVID
- Recomendaciones de política basadas en evidencia

## Arquitectura

Fase 3 **no modifica el pipeline de datos**: reutiliza el modelo
dimensional Gold (`gold_ss2`) construido en Fase 2 y expande la **capa de
consumo** con tres clientes que leen del mismo Gold —**AWS SageMaker**
(ML), **Power BI** y **Tableau** (BI). La novedad arquitectónica frente a
Fase 2 es la incorporación de SageMaker como tercer consumidor. Ver el
detalle en [Arquitectura — Fase 3](arquitectura.md).
