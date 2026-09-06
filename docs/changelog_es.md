# Registro de cambios

> Traducción del CHANGELOG canónico en inglés.

Todos los cambios relevantes de **Calima: Flames of the Atlantic** se documentan en este archivo.

El formato se basa en [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
y este proyecto sigue el [Versionado Semántico](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Sitio de documentación
- `docs/` es ahora un sitio estático publicable: `docs/build_site.py` convierte cada documento Markdown (manuales del jugador, GDD, arquitectura, ambientación, changelog, controles) a HTML autocontenido con tema propio y enlaces reescritos; portal en `docs/index.html`; cero enlaces rotos (comprobado en todo el sitio).

### Triángulo de contraataques
- Bonificaciones de ataque por clase (`UnitResource.attack_bonuses`, leídas en `UnitBase._strike_damage`): piqueros +12 contra caballería, caballería +4 (explorador +3) contra arqueros, arqueros +3 contra lanceros; el Perforante de Armaduras del Arquero de Tiro Largo migró a datos. Las flechas heredan la bonificación. La composición del ejército importa ahora tanto como su tamaño.
- La IA contrarresta lo que avista: `_counter_bias` desplaza la mezcla del Cuartel hacia picas/espadas/arqueros según la composición enemiga que realmente puede ver.
- Las granjas de los Francos se construyen un 20% más rápido y las descargas defensivas de los Castellanos alcanzan un 10% más lejos (las dos últimas claves de civilización declaradas pero nunca leídas, ahora conectadas); eliminada la clave muerta `castle_range`; los nombres de unidad única del lobby en translations.csv se unificaron con las filas canónicas UNIT_*.

### Bonificaciones de civilización conectadas de verdad
- Las cuatro bonificaciones anunciadas en el juego pero nunca implementadas ahora funcionan: los Fenicios construyen su Mercado desde la Edad Oscura y sus barcos cuestan un 15% menos; los Guanches entrenan Piqueros desde la Edad Oscura; las casas de los Canarii sirven también como puntos de entrega; el descuento de madera en edificios de los Mahos (×0.70) ahora se cobra de verdad — el precio del botón, la tabla de precios de la IA y el comando de colocación coinciden.
- Nuevo: reclamo de caldera — un Campamento Minero levantado a la sombra de una caldera aporta un goteo de piedra a su dueño (Costa Volcánica).
- Nuevo: vista de dunas de los Mahos — visión ×1.40 mientras una unidad mahos pisa terreno de dunas (espejo de la visión costera de los Atlantes).
 - 2026-09-02 → 2026-09-06

Todo lo posterior a la etiqueta `v0.9.8-beta`, agrupado por temas.

### Repeticiones y kit de creador
- **Cada partida se graba a sí misma** como un flujo comprimido de instantáneas (`user://replays/`, fiel por construcción — sin re-simulación), visible desde el nuevo navegador de **Repeticiones** del menú principal
- **Reproducción de repeticiones v2**: línea de tiempo navegable (los saltos hacia atrás reinician y avanzan rápido), pausa, velocidades de reproducción, opción de revelar el mapa y un botón "ver repetición" en la pantalla de fin de partida
- **Kit de creador**: modo cine (**C**, sin interfaz, minimapa flotante opcional), tarjeta de título centrada y **exportación a vídeo** en segundo plano a 30 FPS fluidos — de la partida completa o de un **clip marcado con A/B**; la barra de repetición nunca entra en el metraje exportado
- Las repeticiones no aceptan órdenes: el menú de acciones, los atajos y las rutas de órdenes por clic derecho quedan bloqueados durante la reproducción

### Campaña — *Las Llamas de Tamarán*
- Cuatro misiones canarii guionizadas contra la invasión atlante (mundos deterministas con semilla fija, objetivos secundarios, oleadas de ataque guionizadas, tipos de victoria conquista/resistir/regicidio) más un prólogo tutorial que ahora abre la misma guerra
- Informes de misión, epílogos narrativos, rampa de dificultad (límites de IA por misión), desbloqueo en cadena, progreso persistente; la misión 1 enseña el Molino y el juego de pastoreo
- Dieciséis sprites de héroe únicos — cada héroe reconocible por su historia (Don Quijote monta a Rocinante)

### Economía pastoril
- El **Molino** (punto de entrega de comida de la Edad Oscura) entrena al perro pastor **Presa Canario**: busca un animal, llévalo a casa y cobra comida por el acercamiento neto; las ovejas enemigas se convierten por el camino; mordisco de perro guardián cuando está ocioso, nunca abandona un viaje por su cuenta
- Sacerdotisa sanadora **Harimaguada** entrenada en el Templo (siempre mujer, por la ambientación): curación de seguir-y-sanar más triaje automático en reposo; el Templo hace también de hospital de campaña (las unidades guarnecidas se curan, los héroes a la mitad) y ahora luce como un **almogarén** — un santuario canario abierto de piedra seca
- Rebaños de ovejas salvajes pastan por el mapa abierto — objetivos disputados por los que compiten los perros del jugador y de la IA; el rebaño viste el color de su dueño (collares de equipo)
- La IA juega al mismo juego: construye un Molino, cría perros, pastorea animales sin dueño y sacrifica sus propias ovejas cuando escasea la comida

### Tecnologías económicas de campamento (el árbol tecnológico crece hasta 32)
- Nueve tecnologías económicas al estilo AoE2, una por edad desde la Feudal, investigadas en los propios campamentos: Campamento Maderero — *Hacha de doble filo → Sierra de arco → Sierra de dos hombres* (madera); Campamento Minero — *Picos reforzados → Minería de pozo → Galerías profundas* (oro + piedra); Molino — *Collera de tiro → Arado pesado → Rotación de cultivos* (comida). Cada paso: +15% de velocidad de recolección y +10% de carga para ese recurso
- Auditoría completa del árbol tecnológico con correcciones reales, **cola** de investigación (hasta 5 en curso por edificio, pagadas al encolar, reembolso completo al cancelar) y un glifo al estilo AoE2 para cada tecnología

### Estilos visuales de unidad
- Nuevo ajuste de **estilo de unidades** de 3 opciones, intercambiable en vivo: **Clásico** (el plano por defecto), **Mejorado** (contorno a tinta reversible + sombreado de volumen + animación procedural extra) y **Rediseñado** (rigs desde cero basados en la ambientación para cada unidad, con una máquina de estados de animación completa)

### Modo espectador y notificaciones
- Rendirse — o perderlo todo — mientras quedan bandos hostiles ya no termina la partida: el panel de derrota ofrece **Ver mapa** y sigues viendo la batalla en vivo con las órdenes bloqueadas; el resultado definitivo llega cuando la guerra realmente acaba
- Los avisos de notificación llevan ahora **botones de acción directa**: salta al evento, coloca una Casa con un clic tras un aviso de límite de población, localiza al héroe cuando está en peligro

### Renovación de la IA
- **La IA construye con aldeanos reales** — se acabaron los edificios enemigos instantáneos; un constructor camina hasta cada obra (muelles incluidos, las trampas para peces las levantan los barcos pesqueros) y las obras abandonadas reciben nueva mano de obra
- **Adquisición en reposo**: las unidades de combate ociosas (del jugador y de la IA por igual) ahora persiguen a los hostiles a la vista (~240 px) según las reglas de su actitud, en lugar de esperar a que las toquen
- **Las guerras IA contra IA ocurren de verdad**, incluidas las navales — las galeras queman los muelles y trampas para peces enemigos conocidos, los transportes zarpan con ejércitos más pequeños
- **Limpieza final**: sin nada que asediar, la IA caza a los últimos supervivientes avistados en lugar de quedarse parada

### Bajo el capó
- **Esquema de guardado v2**: las investigaciones en curso, las guarniciones, las actitudes de las unidades y la máquina de estados del clima sobreviven al ciclo de guardado; los esquemas más nuevos se rechazan con un motivo, los más antiguos cargan con valores por defecto
- **Endurecimiento del cable**: el host revalida cada colocación de los clientes y despoja a los comandos llegados por red de los privilegios exclusivamente locales
- Continuó la descomposición del HUD: extraídos la rejilla de comandos (`HudActionMenu`), el guía del tutorial (`HudTutorial`) y las tablas de acciones (`HudActionDefs`); cada precio de botón procede ahora de los mismos datos `.tres` que cobra la simulación
- "Idiomas" de voz sintetizados por civilización, voces de confirmación de órdenes y sonidos de combate con varias tomas; referencia de síntesis de audio documentada
- Las unidades terrestres ya no pueden meterse en el mar (veto de paso en las dos rutas de movimiento fuera de la malla, sonda de caos en CI); animales incluidos
- Menú principal v2 (logo centrado, botón de jugar dorado), panel de jugadores/puntuación al estilo AoE2 en el minimapa, los granjeros permanecen en su granja, las miniaturas de héroe muestran al héroe real

---

## [0.9.8-beta] - 2026-09-02 - Equipos, social de Steam y rendimiento

### Añadido
- **Equipos y alianzas** (2v2, 2v1, ...) en escaramuza y multijugador: visión compartida, victoria por equipos, ataque automático consciente de los aliados, selectores de equipo en ambos lobbies, persistidos en las partidas guardadas
- **Cooperación de la IA aliada**: los compañeros de IA envían escuadras de auxilio cuando te asaltan y anuncian sus ofensivas con un ping
- **Puntos de ruta encolados con Shift y patrulla**
- **Contratación de mercenarios terminada** en el Mercado — todas las civilizaciones, localizada, con miniaturas de unidad e insignias de recarga; los Fenicios pagan un 25% menos
- **Guardado/reanudación multijugador**: el host guarda la plantilla y la niebla por jugador; el lobby de reanudación reserva los asientos originales y la partida puede empezar con jugadores ausentes (su asiento aguanta durante la gracia de reconexión)
- **Verificación de versión**: el host rechaza a los clientes de una build distinta con un diálogo motivado; las versiones se etiquetan solo mediante `scripts/release_tag.sh`
- **Ajustes de pantalla y teclas de cámara reasignables**; contador de FPS opcional
- **Pulido de Steam**: avatares en la plantilla, rich presence, pings de minimapa aliados (Alt+clic)
- **Voces de selección de unidad sintetizadas por formantes** (gritos al estilo AoE), horneadas en un hilo de trabajo
- **Colores de equipo más marcados en cada unidad** — la tela se repinta al color del dueño conservando el sombreado

### Corregido
- Auditoría de habilidades de héroe: verificadas las habilidades de los 16 héroes, corregidos cinco errores reales (recargas de habilidades instantáneas, crash del Pacto Mercenario, embestida del Abordaje, conciencia de equipo, parentesco de la nube de Calima)
- Autenticación de reconexión por Steam-ID y un límite de frecuencia en la tubería de comandos

### Rendimiento
- Revelado incremental de la niebla de guerra (los ejércitos parados dejan de pagar por tick)
- Recuperación de física limitada a 2 pasos por fotograma — batallas de 200 contra 200 de 7.5 a 30 fps
- Eliminados los obstáculos RVO por recurso; histéresis en los recálculos de ruta de persecución; reescritura del dibujado del minimapa; las puertas de rendimiento se sumaron a la suite de tests

---

## [0.9.6-beta / 0.9.7-beta] - 2026-08-31 - Multijugador por Internet y Steam

### Añadido
- **Alojamiento por Internet mediante UPnP** desde el lobby (mapeo automático de puertos, dirección pública en la cabecera); separación LAN vs Internet en el menú principal
- **Prototipo de transporte por Steam** (GDExtension GodotSteam): lobbies públicos, invitaciones a amigos (con un selector dentro del juego cuando el overlay no está disponible), red por relé de Valve — en el AppID de pruebas
- **Reconexión a mitad de partida**: el asiento de un jugador caído se reserva (90 s de gracia), el cliente que vuelve recupera su antiguo id de jugador y una resincronización completa del estado
- **Chat multijugador**: panel en el lobby y overlay en partida (Enter), con códigos de color y líneas de sistema; cambio de nombre en el lobby (fijado a la persona de Steam en sesiones de Steam)
- Visual de la roca de asedio con eco en el cliente — la Manganela por fin lanza una piedra visible

### Corregido
- Colocación en el cliente validada contra el propio inventario del cliente (los clientes solo podían colocar casas)
- El HUD del cliente no mostraba acciones en sus propios edificios (estaba condicionado al jugador 0)

---

## [0.9.1-beta → 0.9.5-beta] - 2026-08-27 → 2026-08-31 - Patrón de comandos, controles de combate y multijugador LAN

### Arquitectura
- **Patrón de comandos**: cada orden que muta la simulación — del jugador Y de la IA — es un `GameCommand` serializable a través del `CommandBus`, sellado con el tick en un registro de partida (la base sobre la que se construyen las repeticiones y el multijugador)
- **MatchRng**: un único flujo de RNG con semilla para toda la aleatoriedad de la simulación; capa de decisión determinista (registros de comandos idénticos entre ejecuciones con semilla fija)
- División de los objetos-dios: `game_world.gd` en seis controladores de mundo (setup/victoria/cámara/selección/comandos/colocación), `map_generator.gd` en seis módulos de pipeline, el HUD en componentes autoconectados
- Tabla unificada de costes de edificio respaldada por `.tres` — jugador e IA pagan los mismos precios (la vieja tabla escrita a mano dejaba al jugador construir algunos edificios gratis)

### Combate y controles
- **Actitudes de combate al estilo AoE2** (Agresivo / Defensivo con correa / Mantener posición / No atacar), **formaciones de grupo** (Línea / Cuadro / Dispersa / Anillos) y **guarnición en edificios** (Centro Urbano 10, torres 5, una flecha extra por ocupante; los aldeanos mediante el botón Guarecerse o la Campana)
- Máquina de estados de combate canónica en `UnitBase` — las 16 unidades hoja migradas a ganchos de sobreescritura
- Las Torres de Vigilancia disparan flechas visibles; fuego/humo progresivos en los edificios dañados; barras de vida universales en los edificios (el daño a edificios era invisible antes)
- El doble clic selecciona todos los edificios de un tipo (punto de reunión y entrenamiento compartidos); insignias de cola por tipo de unidad; glifos de actitud/formación con estados activos persistentes; confirmación antes de demoler >5 edificios; Retroceso hace de Supr en macOS

### Multijugador (fases 1–2)
- **Multijugador LAN**: sesión ENet con host autoritativo, lobby unificado con asientos de jugador (Abierto/IA/Cerrado), nombre/color/civilización por jugador, expulsión, ajustes editados por el host con resumen en vivo para los clientes
- **Replicación de estado host→cliente** a 15 Hz con mundos espejo títere interpolados; colas, investigación, mercado, clima y proyectiles replicados; flujo de deltas con fotogramas clave por debajo de la MTU de ENet
- **Robustez**: las desconexiones y rendiciones se convierten en dimisiones, diálogo de host ausente, pausa replicada

### Corregido
- Reajustada la evitación RVO (las unidades rápidas tenían la velocidad capada; las multitudes se atascaban); eliminados los obstáculos RVO de los edificios (sellaban pasillos que la malla de navegación había abierto)
- El terreno intransitable se talla en la malla de navegación — las rutas rodean la lava en lugar de congelarse en el borde
- La cuadrícula de la niebla de guerra se dimensiona al mapa real (los márgenes de los mapas grandes quedaban permanentemente sin niebla)
- Las colocaciones diagonales de edificios ya no colapsan el horneado de la malla de navegación (empujón de medio píxel + escalera de alternativas)

---

## [0.9.0-beta] - 2026-08-26 - Vista isométrica e identidad de civilización

La primera beta etiquetada: el refactor isométrico fusionado tras un mes de trabajo previo de UI/UX.

### Añadido
- **Presentación isométrica**: proyección a nivel de cámara (`IsoProjection`), entidades verticales en billboard con ordenación por profundidad (`IsoBillboard`), volumetrías de edificios
- **Identidad visual por civilización**: estilos de arquitectura (`CivStyle`), vestimenta de unidades (tocados/fajines), cascos y velas de barco por civilización (`ShipDress`)
- **Cursores contextuales** (el puntero de tabona + glifos de contexto, horneado seguro en macOS)
- **Grupos de control** (Ctrl/Cmd+1–9) con chips clicables en el HUD; ESPACIO salta a la última alerta de ataque; botones de ciclo de aldeano/militar inactivo con insignias de recuento; widget de héroe persistente en Regicidio; cámara de seguimiento
- **Pasada de localización**: EN/ES para nombres de unidades/edificios, lobby, HUD; tooltips de coste enriquecidos que sustituyen a la tira de costes
- Aura de energía del héroe; los héroes aparecen delante del Centro Urbano mediante la espiral de aparición

---

## [0.6.0] - 2026-06-08 - Renovación visual

### Resumen
Una pasada de arte completa: todas las unidades, edificios, animales y el terreno se rediseñaron de polígonos de colores crípticos a figuras claramente legibles, y todas las unidades humanas tienen ahora un género visual aleatorio. Ninguna regla de juego cambió — esta versión es puramente de calidad visual, identificación y pulido.

### Añadido
- **Género visual aleatorio para todas las unidades humanas** — cada unidad humana (aldeano, infantería, caballería, arqueros, unidades únicas) es aleatoriamente hombre o mujer (50/50) al crearse, mostrado con pelo largo enmarcando la cabeza. Persistido al guardar/cargar. Los barcos, las máquinas de asedio y los animales no se ven afectados.
- **Sprites de heroína diferenciados** — las héroes femeninas ahora se leen como mujeres: pelo largo, una diadema dorada (son reinas/líderes) y un vestido acampanado, conservando su arma y su escudo.
- **Acentos de edificio en color de equipo** — los edificios llevan detalles en el color del equipo (tejados, banderas, estandartes, toldos, cúpulas, velas) para que el dueño de cada edificio sea identificable de un vistazo.
- **Sombras en el suelo** bajo cada unidad y edificio, asentándolos sobre el terreno.
- **Shader de agua animada** (oleaje por capas, ondulaciones, espuma) para océanos y costas.
- **Shader de detalle de terreno** (grano + variación tonal) para que el terreno no sea color plano.
- **Lava animada** (brillo de brasa pulsante) en las vetas de malpaís y las grietas/pozas de las calderas.
- **Océanos costeros** con playas arenosas de anchura variable y espuma en los mapas Costa Volcánica y Costa Desértica.
- **Iluminación ambiental + viñeta** por tipo de mapa para dar atmósfera.
- **Andar para los animales** — las patas de ciervos y ovejas se balancean al trote mientras se mueven.

### Cambiado
- **Todos los sprites de unidad rediseñados** en figuras reconocibles: aldeano (campesino con sombrero de paja y pico), milicia/hombre de armas/espadachín (espadachines con casco y escudo), piquero (pica), explorador/explorador pesado/caballero y caballería única (jinetes a caballo), arqueros (tensando un arco), las 8 unidades únicas de civilización, y las máquinas de asedio y los barcos (con detalle de casco, remos, velas).
- **Todos los sprites de edificio mejorados** con sombreado de sillería, líneas de sillar, almenas y detalle temático (brillo de forja, puestos de mercado, cúpulas de templo/universidad, etc.).
- **Sprites de animal rediseñados** — ciervo (con cornamenta) y oveja (lanuda), convertidos de rectángulos planos a figuras.
- **La orientación de unidades y animales** sigue ahora el destino de navegación, de modo que miran hacia donde viajan (incluso en rutas diagonales y casi verticales).
- **Bordes de terreno suavizados** — los límites de zona se funden con las vecinas siguiendo el contorno real de la zona, y las costas se redondean con anchura de playa/espuma naturalmente variable.

### Corregido
- **Movimiento de unidades a trompicones** — activada la interpolación de física 2D (el renderizado iba más rápido que el paso de física a 60 Hz sin interpolación, así que los sprites saltaban entre ticks). El movimiento es ahora suave.

---

## [0.5.1] - 2026-06-02 - Heroínas

*(Incorporado desde el antiguo `HEROINES_CHANGELOG.md`.)*

### Añadido
- **8 héroes femeninas** — una por civilización, duplicando la plantilla de héroes hasta **16** (8 hombres + 8 mujeres), cada una con una habilidad única y sus propias estadísticas `.tres`:

| Civilización | Heroína | Habilidad | Rol |
|---|---|---|---|
| Guanches | Dácil | Voz de la Montaña | Potenciadora defensiva |
| Canarii | Guayarmina | Flecha del Destino | Asesina francotiradora |
| Mahos | Tibiabin | Tormenta de Arena | Negación de área |
| Francos | Catalina de Béthencourt | Duelo de Honor | Cazadora de héroes |
| Britanos | Grace O'Malley | Abordaje | Iniciadora |
| Castellanos | Dulcinea del Toboso | Llamada a las Armas | Multiplicadora de fuerza |
| Atlantes | Cleito | Marea Creciente | Apoyo híbrido |
| Fenicios | Elissa | Pacto Mercenario | Conversión económica |

- **Selección del género del héroe** en el lobby (Aleatorio / Masculino / Femenino) con información dinámica del héroe
- Documentación de ambientación bilingüe (`docs/lore/heroes-and-heroines.md`, `docs/design/heroines-design.md`) y traducciones EN/ES

---

## [0.5.0] - 2026-06-01 - Hito listo para producción

### Resumen
Todas las funcionalidades básicas implementadas: 8 civilizaciones jugables, la plantilla de unidades completa y el árbol tecnológico de entonces, un oponente de IA completo, guardar/cargar, clima dinámico y 3 condiciones de victoria. El trabajo se centró en el pulido y la corrección de errores para alcanzar el estado listo para producción.

### Añadido
- **Comando Fuego de Cobertura** para arqueros y unidades de asedio (acercarse al alcance y atacar el suelo)
- **Proyectiles de flecha volantes** con animación de arco visual
- **Animación corporal procedural** para todas las unidades (caminar, atacar, trabajar)
- **Siluetas Polygon2D** para todas las unidades y edificios (sustituye a los marcadores ColorRect)
- **Visual de torre de piedra alta** para la Torre de Vigilancia
- Edificio **Galería de Tiro** (Edad Feudal, entrena al Arquero)
- **Comando de atacar el suelo** para unidades a distancia y de asedio
- **Posicionamiento de aparición en espiral hacia fuera** usando consultas de física para evitar el solapamiento de unidades
- **Árbol tecnológico** a través de la Herrería, la Universidad, el Templo, las mejoras de unidad y las concesiones instantáneas de los Castellanos
- **8 unidades de Héroe** con habilidades únicas (Ímpetu del Mencey, Desafío, Emboscada, Diplomacia Forzada, Saqueo, Acometida del Caballero Errante, Calima, Ruta Comercial)
- **8 unidades únicas** con mecánicas especiales (Guardia del Mencey, Arquero del Barranco, Saqueador de Dunas, Chevalier Normando, Arquero de Tiro Largo, Conquistador, Invocador de Mareas, Trirreme)
- **Sistema de clima dinámico** con 5 tipos de evento procedurales (Calima, Tormenta Atlántica, Niebla Marina, Vientos Alisios, Ceniza Volcánica)
- **Overlay de clima** con efectos visuales (lluvia, polvo, ceniza, viento, viñeta de niebla)
- Edificio **Mercado** con tasas de cambio dinámicas (por jugador, por recurso) y contratación de mercenarios
- **Juego naval** en los mapas de Islas (Muelle, Barco Pesquero, Barco de Transporte, Galera de Guerra, Trampa para Peces)
- **Asalto naval de la IA** con embarque en barcos de transporte y desembarco anfibio
- **3 condiciones de victoria** (Conquista, Regicidio, Maravilla)
- **Sistema de guardar/cargar** con 99 ranuras JSON e interfaz de metadatos
- **Sistema de límite de población** (5 por Casa, empieza en 15)
- **Audio espacial** con atenuación por distancia
- **Grupos de control** (Ctrl+1-9 para guardar, 1-9 para recuperar)
- **Cámara de seguimiento** para los grupos de unidades seleccionados
- **Minimapa** con órdenes de movimiento por clic derecho e iconos de recursos/unidades/edificios

### Corregido
1. **Fuego de Cobertura**: registrar como acción pendiente, acercarse al alcance antes de disparar
2. **Posicionamiento de aparición**: la consulta de física en espiral hacia fuera evita el solapamiento de unidades
3. **Minimapa**: corregido el revelado de racimos enteros de recursos de golpe (radio de revelado reducido al 30% del alcance de visión de la unidad)
4. **HUD de clima**: corregido el banner y la píldora descentrados en resoluciones distintas de 1920
5. **Aldeano**: corregida la firma de `_animate_body` que no coincidía (parámetro delta)
6. **Centro Urbano**: corregido el renderizado del gráfico inicial
7. **Galera de Guerra**: corregida la comprobación de PV que usaba nombres de propiedad erróneos
8. **Victoria por Conquista**: corregidas las comprobaciones de nodos DEAD/DESTROYED ausentes en la lógica de eliminación
9. **Derrota por Conquista**: corregido que nunca se disparaba para el jugador humano
10. **Regicidio**: corregida la lógica de condición de victoria por modo
11. **Mercado**: corregido el reinicio de página al refrescar la recarga (recarga de mercenarios aumentada a 2 min)
12. **Ceniza Volcánica**: corregida la aplicación de daño a edificios
13. **Obstáculos de malla de navegación**: omitir para el terreno que la civilización del jugador puede transitar
14. **Script de release**: resolver la ruta del repositorio del juego correctamente antes del cd
15. **Revelado de recursos en el minimapa**: corregido que se mostraran todos los recursos del grupo cuando solo una celda estaba explorada

### Cambiado
- **Animación del aldeano**: diferenciar las animaciones de caminar y trabajar
- **Animación de unidades**: todas las unidades tienen ahora animación corporal procedural (rotación durante el movimiento/ataque)
- **Visuales de edificios**: sustituidos los marcadores ColorRect planos por siluetas Polygon2D
- **Torre de Vigilancia**: rediseñada con una silueta poligonal de piedra alta
- **Proyectiles de flecha**: los arqueros disparan ahora flechas volantes visibles
- **Frecuencia del clima**: configurable en el lobby (Desactivado/Normal/Frecuente/Extremo)
- **Agresividad de la IA**: escala cuando se ve amenazada (PASSIVE → ALERTED → AGGRESSIVE)
- **Defensa de la base de la IA**: defiende contra enemigos cerca de cualquier edificio, no solo en el radio del Centro Urbano

### Rendimiento
- **Detección de alcance con Area2D**: los alcances de ataque usan monitorización con Area2D, sin consultas de física por fotograma
- **Consultas de física cacheadas**: las consultas espaciales se cachean y reutilizan cuando es posible
- **Aparición en espiral hacia fuera**: BuildingBase.find_spawn_pos() usa un patrón de búsqueda en anillos eficiente

---

## [0.4.0] - 2026-05-15 - Actualización naval y de clima

### Añadido
- **Juego naval** en el tipo de mapa Islas
- Edificio **Muelle** (150 de madera, entrena barcos)
- **Barco Pesquero** (recolecta FOOD_FISH del océano)
- **Barco de Transporte** (transporta 10 unidades militares)
- **Galera de Guerra** (combate naval a distancia)
- **Trampa para Peces** (75 de madera, fuente pasiva de comida en el océano)
- **Sistema de clima** con eventos procedurales
- **5 tipos de clima**: Calima, Tormenta Atlántica, Niebla Marina, Vientos Alisios, Ceniza Volcánica
- **Modificadores de estadísticas por clima**: visión, movimiento, velocidad de recolección, deriva de proyectiles, daño a edificios
- **Efectos visuales de clima**: lluvia, polvo, ceniza, viento, viñeta de niebla
- **Módulo naval de la IA** (AINaval): entrenamiento de barcos, patrullas de galeras, asaltos con transportes
- Edificio **Mercado** con comercio de recursos
- **Tecnologías de la Herrería** (Telar, Forja, Fundición de Hierro, etc.)
- Edificio **Universidad** con tecnologías avanzadas
- Edificio **Templo** con mejoras de moral

### Cambiado
- **Generación de mapas**: añadido el tipo de mapa Islas con zonas de océano
- **Sistema de terreno**: las casillas de océano marcadas como intransitables para las unidades terrestres
- **Economía de la IA**: objetivos de recursos ajustados por edad
- **Construcción de la IA**: añadida la lógica de construcción de trampas para peces

---

## [0.3.0] - 2026-04-20 - Progresión de edades y expansión militar

### Añadido
- **4 Edades**: Oscura → Feudal → del Castillo → Imperial
- **Sistema de avance de edad** con costes y temporizadores
- Unidad **Arquero** (Edad Feudal, infantería a distancia)
- Unidad **Piquero** (Edad del Castillo, anticaballería)
- **Hombre de Armas** (mejora de infantería de la Edad Feudal)
- **Espadachín** (mejora de infantería de la Edad del Castillo)
- Unidad **Explorador** (caballería de exploración con habilidad de exploración automática)
- **Explorador Pesado** (mejora de caballería de la Edad Feudal)
- **Caballero** (caballería pesada de la Edad del Castillo)
- Edificio **Establo** (entrena caballería)
- **Taller de Asedio** (Edad del Castillo, entrena unidades de asedio)
- **Ariete** (asedio cuerpo a cuerpo, ×3 contra edificios)
- **Manganela** (asedio de área, 72 px de salpicadura, alcance mínimo)
- **Trabuquete** (asedio de largo alcance de la Era Imperial, despliegue/repliegue)
- **Investigación de tecnologías** en el Cuartel (8 tecnologías)
- Lógica de **avance de edad de la IA**
- **Módulo militar de la IA** (entrenamiento, investigación, combate)

### Cambiado
- **Entrenamiento de unidades**: condicionado por los requisitos de Edad
- **Disponibilidad de edificios**: estructuras bloqueadas por Edad (Establo, Taller de Asedio, Universidad)
- **Comportamiento de la IA**: adapta la estrategia por edad

---

## [0.2.0] - 2026-03-10 - Militar y combate

### Añadido
- Edificio **Cuartel** (175 de madera, entrena infantería)
- Unidad **Milicia** (infantería de la Edad Oscura)
- **Sistema de combate cuerpo a cuerpo** con cálculo de daño
- **Sistema de combate a distancia** con proyectiles
- **Tipos de armadura** (melé/perforante)
- **Niebla de guerra** con 3 estados (sin explorar/explorado/visible)
- **Minimapa** con iconos de unidades/edificios/recursos
- **Oponente de IA** con economía y ejército básicos
- **Módulo de construcción de la IA** (colocación de edificios)
- **Módulo de economía de la IA** (gestión de aldeanos)
- **Rejilla de selección** que muestra hasta 40 unidades seleccionadas
- **Barras de vida** para unidades y edificios
- **Centro Urbano** como edificio principal de la base

### Cambiado
- **Aldeanos**: ahora pueden construir estructuras militares
- **Recolección de recursos**: entrega en el Centro Urbano, el Campamento Maderero y el Campamento Minero
- **Generación de mapas**: añadida la posición inicial del enemigo

---

## [0.1.0] - 2026-02-01 - Cimientos

### Añadido
- Configuración del proyecto de **Godot 4**
- **Aldeanos** con recolección (comida, madera, oro)
- **Nodos de recursos** (árboles, minas de oro, bayas, ovejas)
- **Edificios de entrega** (Centro Urbano, Campamento Maderero, Campamento Minero)
- Edificio **Granja** (60 de madera, comida renovable)
- Edificio **Casa** (25 de madera, +5 al límite de población)
- Edificios **Muralla y Puerta** (estructuras defensivas)
- **Generación procedural de mapas** con recursos aleatorios
- **Resource Manager** (inventarios por jugador)
- **Selection Manager** (selección de unidades, grupos de control)
- Arquitectura **EventBus** para señales desacopladas
- **Diseño orientado a datos** con archivos Resource
- **Sistema de navegación** con NavigationAgent2D
- **HUD básico** (visor de recursos, contador de población)
- **Lobby de partida** con ajustes de mapa

### Infraestructura
- Integración del **framework de tests GUT**
- **Pipeline CI/CD** con GitHub Actions
- **Documentación** (CLAUDE.md, documentos de arquitectura)
- **Sistema de subagentes** (developer, tester, code-reviewer, docs-keeper, performance-checker)

---

## Hoja de ruta (próximo)

- Prueba en vivo de lobbies de Steam en un AppID real
- Simulación lockstep (requiere movimiento de unidades determinista y sin física)
- Ajuste de equilibrio a partir de las pruebas de juego
- Más capítulos de campaña

---

## Resumen del historial de versiones

| Versión | Fecha | Descripción |
|---|---|---|
| (unreleased) | 2026-09-06 | Repeticiones y kit de creador, campaña, economía pastoril, tecnologías de campamento, estilos de unidad, espectador, renovación de la IA |
| 0.9.8-beta | 2026-09-02 | Equipos y alianzas, social de Steam, mercenarios, auditoría de héroes, guardado/reanudación MP, rendimiento |
| 0.9.6/0.9.7-beta | 2026-08-31 | Internet (UPnP) + prototipo de Steam, reconexión, chat |
| 0.9.1–0.9.5-beta | 2026-08-27→31 | Patrón de comandos, actitudes/formaciones/guarnición, multijugador LAN fases 1–2 |
| 0.9.0-beta | 2026-08-26 | Vista isométrica, identidad visual por civilización, grupos de control, localización |
| 0.6.0 | 2026-06-08 | Renovación visual: figuras legibles, género de unidades, terreno vivo |
| 0.5.1 | 2026-06-02 | Heroínas: plantilla de 16 héroes, elección de género en el lobby |
| 0.5.0 | 2026-06-01 | Un jugador listo para producción: 8 civilizaciones, clima, guardar/cargar, pulido |
| 0.4.0 | 2026-05-15 | Juego naval, sistema de clima, mercado, edificios de investigación |
| 0.3.0 | 2026-04-20 | Progresión de edades, caballería, asedio, investigación tecnológica |
| 0.2.0 | 2026-03-10 | Unidades militares, combate, niebla de guerra, oponente de IA |
| 0.1.0 | 2026-02-01 | Cimientos: aldeanos, recursos, generación de mapas |
