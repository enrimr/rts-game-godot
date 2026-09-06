# Calima: Flames of the Atlantic

Un juego de estrategia en tiempo real al estilo de Age of Empires II, ambientado en las Islas Canarias, en la encrucijada de los reinos nativos, los navegantes de la antigüedad y los invasores europeos. Construido íntegramente con [Godot 4](https://godotengine.org) y GDScript — cada sprite, sonido y voz del juego se genera de forma procedural, sin ningún recurso externo de arte o audio.

Creado por **Enrique Ismael Mendoza Robaina** ([@enrimr](https://github.com/enrimr)).

Versión actual: **0.9.8-beta** (ver [changelog](changelog_es.md)).

---

## Características principales

### Contenido
- **8 civilizaciones** en tres capas históricas (isleños nativos, navegantes de la antigüedad, invasores europeos), cada una con bonificaciones únicas, una unidad militar única y dos héroes con nombre propio
- **26 tipos de unidad** — aldeanos, una sacerdotisa sanadora, un perro pastor, tres líneas de infantería, caballería, máquinas de asedio (con un trabuquete que se despliega y repliega), barcos y 8 unidades únicas de civilización
- **16 héroes con nombre** (uno masculino + una femenina por civilización), cada uno con una habilidad activa distinta; el género del héroe se elige en el lobby
- **20 tipos de edificio** — economía, producción militar, investigación, defensa y la Maravilla
- **32 tecnologías** — las líneas de armas/armaduras de la Herrería, la ciencia de asedio de la Universidad, los ritos del Templo, cuatro mejoras de unidad y líneas económicas de tres pasos en el Campamento Maderero, el Campamento Minero y el Molino
- **Campaña**: *Las Llamas de Tamarán* — un prólogo tutorial más cuatro misiones guionizadas de la resistencia canarii contra la invasión atlante
- **3 condiciones de victoria**: Conquista, Regicidio (protege a tu héroe), Maravilla (constrúyela y consérvala)
- **5 tipos de mapa procedural** (Llanura, Estándar, Costa Volcánica, Costa Desértica, Islas) en tres tamaños, con 4 modos de recursos iniciales

### Sistemas
- **Clima dinámico** — 5 tipos de evento (calima, Tormenta Atlántica, Niebla Marina, Vientos Alisios, Ceniza Volcánica) con efectos reales sobre las estadísticas, aviso de pronóstico, resistencias por civilización y ocultación en la niebla marina
- **Terreno que importa** — campos de lava de malpaís, dunas, riscos con ventaja de visión, bosques de laurisilva y calderas, cada uno con efectos de movimiento/visión/combate y bonificaciones de tránsito por civilización
- **Controles de combate al estilo AoE2** — actitudes, formaciones de grupo, atacar-mover, patrulla, puntos de ruta encolados con Shift, grupos de control, guarnición con descargas de flechas desde los edificios, campana
- **Guerra naval y anfibia** — economía pesquera, galeras de guerra, transportes de tropas y el Invocador de Mareas atlante, que se adentra en el mar
- **Oponentes de IA completos** — economía (incluidos perros pastores y ganado), construcción con aldeanos constructores reales, objetivos militares honestos con la niebla de guerra, asaltos navales, cooperación de IA aliada y tres niveles de dificultad
- **Guardar/Cargar** — 99 ranuras, estado completo de la partida incluyendo investigaciones en curso, guarniciones y el clima en vivo
- **Niebla de guerra** — tres estados con memoria de edificios al estilo AoE2 en el mapa y el minimapa

### Multijugador
- Multijugador por **LAN e Internet** (UPnP) para hasta 4 jugadores, con host autoritativo y mundos espejo en los clientes interpolados a 15 Hz
- **Equipos y alianzas** (2v2, 2v1, ...) en escaramuza y multijugador, con compañeros de equipo de IA aliada
- Lobby unificado con colores, civilizaciones y equipos por jugador, asientos abiertos/IA/cerrados, chat, expulsión y verificación de versión
- **Reconexión a mitad de partida** (asientos reservados + resincronización completa) y **guardado/reanudación multijugador** con los jugadores originales
- **Prototipo de transporte por Steam** (lobbies, invitaciones, relé de Valve — AppID de pruebas)

### Repeticiones y kit de creador
- Cada partida se graba a sí misma (`user://replays/`); mírala desde el menú **Repeticiones** con línea de tiempo navegable, pausa, velocidades de reproducción y opción de revelar el mapa
- **Modo cine** (sin interfaz), minimapa flotante opcional y **exportación a vídeo** — renderiza una repetición completa o un clip marcado con A/B a un vídeo a 30 FPS en segundo plano
- **Modo espectador** — ¿derrotado o rendido mientras otros siguen luchando? "Ver mapa" te deja mirando la batalla en vivo (órdenes bloqueadas)

### Presentación
- Arte vectorial 100 % procedural con tres estilos de unidad seleccionables — **Clásico**, **Mejorado** (contorno a tinta + sombreado + animación extra) y **Rediseñado** (rigs basados en la ambientación) — intercambiables en vivo desde los ajustes
- Colores de equipo en unidades y edificios, arquitectura y vestimenta naval por civilización, auras de héroe, fuego/humo progresivos en los edificios dañados
- Audio totalmente sintetizado: "idiomas" de voz inventados por civilización (síntesis de formantes), efectos de sonido espaciales y música procedural
- Localización en inglés y español

---

## Civilizaciones

| Civilización | Capa | Identidad |
|---|---|---|
| **Guanches** (Tenerife) | Nativa | Edificios de piedra +20% PV, tránsito por malpaís, lanceros tempranos — Guardia del Mencey |
| **Canarii** (Gran Canaria) | Nativa | +15% recolección de comida, arqueros baratos — Arquero del Barranco (bonificación de alcance en riscos) |
| **Mahos** (Lanzarote/Fuerteventura) | Nativa | −30% coste de madera de los edificios, caballería ligera rápida, tránsito por dunas — Saqueador de Dunas |
| **Francos** (conquistadores normandos) | Invasora | −15% coste de avance de edad, +15% PV de caballería — Chevalier Normando |
| **Britanos** (corsarios ingleses) | Invasora | Alcance de arqueros +1 por edad, barcos de guerra más rápidos — Arquero de Tiro Largo |
| **Castellanos** (corona de Castilla) | Invasora | Tecnología gratuita de la Herrería por edad, espadachines resistentes — Conquistador |
| **Atlantes** (el imperio hundido) | Antigua | Visión costera +50%, sigilo en la niebla marina, barcos más rápidos — Invocador de Mareas anfibio |
| **Fenicios** (comerciantes fenicios) | Antigua | Mercado desde la Edad Oscura, contratación de mercenarios — Trirreme con espolón |

Todos los detalles: [civilizaciones](design/civilizations_es.md) · [guía del jugador](guide_es.md).

---

## Capturas de pantalla

Las galerías de estilos de unidad (capturadas por los arneses de revisión) están en el repositorio:

- [Rigs de unidades rediseñados](design/unit-redesign-gallery/a_2_redesigned_grid.png) — y [en movimiento](design/unit-redesign-gallery/a_6_redesigned_attack.png)
- [Estilo Mejorado](design/unit-enhanced-gallery/enhanced_grid.png) vs [Clásico](design/unit-enhanced-gallery/classic_grid.png)

---

## Primeros pasos

### Jugar

- [Godot 4.6](https://godotengine.org/download) o posterior (build estándar, sin C#)

```bash
git clone https://github.com/enrimr/age-of-empires-clone-godot.git
cd age-of-empires-clone-godot
```

Abre **Godot → Import**, selecciona `project/project.godot` y pulsa **F5**.

### Aprender a jugar

- **[Referencia rápida](gameplay_es.md)** — controles y atajos de teclado
- **[Player's Guide (EN)](guide_en.md)** / **[Guía del Jugador (ES)](guide_es.md)** — el manual completo: civilizaciones, economía, árbol de tecnologías, combate, multijugador, repeticiones, campaña

### Tests

Las instrucciones para ejecutar la suite de tests y los arneses de revisión están en la documentación en inglés: [catálogo de arneses](testing/harnesses.md).

---

## Arquitectura

Notas de diseño y arquitectura (en inglés): [visión general](architecture/overview.md) · [detalles de los sistemas](architecture/systems.md). Entre los principios: patrón de comandos (`GameCommand` a través de `CommandBus`, base de las repeticiones y el multijugador), comunicación entre sistemas solo mediante señales (EventBus), datos en archivos `Resource` (nunca hardcodeados), multijugador con host autoritativo y aleatoriedad de simulación determinista (`MatchRng`).

---

## Licencia

[CC BY-NC 4.0](../LICENSE) — Libre para usar y modificar con atribución, sin uso comercial.

Copyright © 2026 Enrique Ismael Mendoza Robaina.

---

## Agradecimientos

Inspirado en Age of Empires II y en la historia de las Islas Canarias.

Construido con [Godot Engine](https://godotengine.org). Tests con [GUT](https://github.com/bitwes/Gut). Redes de Steam mediante [GodotSteam](https://godotsteam.com).

---

## Enlaces

- [Referencia rápida de juego](gameplay_es.md) — controles y atajos
- [Player's Guide](guide_en.md) / [Guía del Jugador](guide_es.md) — el manual completo
- [Visión general de la arquitectura](architecture/overview.md) · [Detalles de diseño de los sistemas](architecture/systems.md)
- [Documento de diseño del juego](design/game-design-document_es.md)
- [Referencia de civilizaciones](design/civilizations_es.md)
- [Registro de cambios](changelog_es.md)
