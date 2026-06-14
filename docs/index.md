# Plataforma Analítica de Mortalidad End-to-End

**Seminario de Sistemas 2 — Laboratorio de Ingeniería de Datos**  
Universidad de San Carlos de Guatemala — Facultad de Ingeniería  
Catedrático: Ing. Marlon Orellana | Sección A | Escuela de Vacaciones 2026

---

## Contexto del proyecto

Este proyecto diseña y construye una plataforma de datos End-to-End para analizar cómo cambiaron los
patrones de mortalidad en Guatemala entre el período **Pre-COVID (2015–2019)** y el
período **Post-COVID (2020 en adelante)**.

## Arquitectura general

```
Fuentes heterogéneas
  (OMS · INE · MSPAS · Fuentes regionales)
          │
          ▼
    [ Sandbox / Bronze ]   ← Fase 1
          │
          ▼
       [ Stage ]           ← Fase 2
          │
          ▼
  [ Fact-Dimensiones ]     ← Fase 2
          │
          ▼
   DW Nube + DW Local      ← Fase 2
          │
          ▼
    ML + BI (Power BI      ← Fase 3
           + Tableau)
```

## Fases del proyecto

| Fase | Foco | Fecha |
|------|------|-------|
| **Fase 1** | Identificación, ingesta y sandbox | 12 Jun 2026 |
| **Fase 2** | Transformación y Data Warehouse | 19 Jun 2026 |
| **Fase 3** | Machine Learning y visualización BI | 26–30 Jun 2026 |

## Equipo

| Integrante | Identificación |
|------------|----------------|
| Sofía Alejandra Quintana Gutiérrez | 3301234591201 |
| Jeffrey Kenneth Menéndez Castillo | 3149675240901 |
| José Roberto Bautista Rojas | 2930462710901 |
