# Refactor isométrico — página de progreso en vivo

**Rama:** `feature/isometric` · **Iniciado:** 2026-08-25 · Actualizada por los agentes tras cada ronda.
Vista en vivo de agentes: `/workflows` en Claude Code.

## Método

Cada pieza la implementa un **builder** y la juzga un **crítico ciego con contexto fresco** que
ejecuta el juego real (`tools/screenshot_runner.gd` → PNGs) y compara dos versiones etiquetadas
A/B (sin saber cuál es cuál) contra el lenguaje visual de los RTS isométricos clásicos.
Si la nueva pierde, el crítico nombra **el mayor hueco** y el builder vuelve a entrar.
Sin número fijo de rondas (tope de seguridad: 4/pieza, se anota si se alcanza).
Entre olas, un agente fresco juega la partida completa y alisa incoherencias.

## Piezas

| # | Pieza | Estado | Rondas | Último veredicto |
|---|---|---|---|---|
| P0 | Proyección isométrica de cámara + picking + límites de cámara | ⏳ en cola | 0 | — |
| P1 | Unidades verticales (billboard): sprites, sombras, barras HP, selección | ⏳ en cola | 0 | — |
| P2 | Edificios verticales: billboard, orden Y (y-sort), preview de colocación | ⏳ en cola | 0 | — |
| P3 | Legibilidad del terreno bajo proyección: costas, agua, scatter, viñeta | ⏳ en cola | 0 | — |
| P4 | Integración HUD/mapa: rect de cámara del minimapa, marcadores, dpad | ⏳ en cola | 0 | — |
| S1 | Alisado inter-olas (partida completa) | ⏳ en cola | 0 | — |
| S2 | Alisado final + crítico de experiencia completa | ⏳ en cola | 0 | — |

## Registro de rondas

_(los agentes añaden entradas aquí, la más reciente arriba)_
