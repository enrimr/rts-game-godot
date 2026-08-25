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
| P0 | Proyección isométrica de cámara + picking + límites de cámara | 🔁 en iteración | 1 | la nueva pierde — gap: "Everything on the map — buildings, units, trees — is skewed flat with the terrain transform instead of standing upright on it. The TC reads as a gray floor slab and trees as pancakes. Render entities as upright, counter-transformed (billboard-style) sprites anchored to and Y-sorted on the projected diamond ground so they have vertical height, while only the ground plane carries the isometric skew." |
| P1 | Unidades verticales (billboard): sprites, sombras, barras HP, selección | ⏳ en cola | 0 | — |
| P2 | Edificios verticales: billboard, orden Y (y-sort), preview de colocación | ⏳ en cola | 0 | — |
| P3 | Legibilidad del terreno bajo proyección: costas, agua, scatter, viñeta | ⏳ en cola | 0 | — |
| P4 | Integración HUD/mapa: rect de cámara del minimapa, marcadores, dpad | ⏳ en cola | 0 | — |
| S1 | Alisado inter-olas (partida completa) | ⏳ en cola | 0 | — |
| S2 | Alisado final + crítico de experiencia completa | ⏳ en cola | 0 | — |

## Registro de rondas

- **P0 ronda 1** (nueva PIERDE, run_ok=true): "Harness ran clean: exit 0, no SCRIPT ERROR lines, all 4 PNGs saved to /tmp/calima-iso/p0-r1. Blind verdict: Set B is the isometric candidate (diamond ground plane). Its diamond orientation is correct and terrain blending survives, but the whole scene is flattened into the ground plane with no verticality, making the TC and units nearly illegible. Regressions in B beyond the flattening: (1) framing broken — 01_tc_close is not a close shot, it shows the whole map at far distance, so there is no close-up view at all; (2) 03_overview shrinks the playfield to a small patch with a large dark-gray diamond backdrop polygon artifact filling the frame; (3) units are so small/flattened they are effectively invisible in every B shot, and the TC label text is skewed/illegible. Set A is flat top-down but has readable upright buildings, visible units with health bars, correct per-shot framing, and intact HUD. Per the bar (broken/illegible projection loses to clean top-down), A wins. HUD, minimap, and resource bar are present and intact in both sets; no black frames or missing HUD." — mayor hueco: "Everything on the map — buildings, units, trees — is skewed flat with the terrain transform instead of standing upright on it. The TC reads as a gray floor slab and trees as pancakes. Render entities as upright, counter-transformed (billboard-style) sprites anchored to and Y-sorted on the projected diamond ground so they have vertical height, while only the ground plane carries the isometric skew."

_(los agentes añaden entradas aquí, la más reciente arriba)_
