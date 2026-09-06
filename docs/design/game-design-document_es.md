# Documento de Diseño del Juego — Calima: Flames of the Atlantic

## Visión

Un juego de estrategia en tiempo real inspirado en Age of Empires II, ambientado en el archipiélago atlántico de las Islas Canarias entre los siglos XV y XVI. El jugador dirige una de ocho civilizaciones — desde navegantes de la antigüedad e isleños nativos hasta conquistadores europeos — a través de islas volcánicas, estrechos oceánicos y costas desérticas.

El alcance publicado cubre escaramuza para un jugador contra hasta 3 rivales de IA (con equipos), una campaña de cuatro misiones con un prólogo tutorial (*Las Llamas de Tamarán*), multijugador LAN/Internet para hasta 4 jugadores (con autoridad en el host, con reconexión y guardado/reanudación), y un sistema de repeticiones con exportación a vídeo.

---

## Ambientación

Las Islas Canarias se encuentran en el Atlántico oriental, a 100 km de la costa del noroeste de África. Fueron el primer archipiélago atlántico disputado entre potencias europeas y poblaciones indígenas, lo que las convierte en una encrucijada natural de la era de la exploración.

El juego bebe de tres capas históricas y mitológicas:

- **Antigua** — Expediciones fenicias y cartaginesas documentaron las islas siglos antes de la conquista medieval. El mito de la Atlántida, situado por los autores griegos cerca de las Columnas de Hércules, da licencia para una civilización fantástica.
- **Nativa** — Tres civilizaciones nativas distintas (Guanches, Canarii, Mahos) habitaban islas diferentes, cada una con ventajas de terreno y culturas propias.
- **Europea** — Tres potencias invasoras (Francos, Britanos, Castellanos) llegaron en momentos distintos con motivaciones distintas: colonización, piratería y conquista.

---

## Bucle central

1. Recolectar recursos (Comida, Madera, Oro, Piedra)
2. Construir una base y entrenar un ejército
3. Investigar tecnologías para mejorar las unidades
4. Avanzar a través de las Edades
5. Derrotar al enemigo

---

## Recursos

| Recurso | Fuentes | Uso principal |
|---|---|---|
| **Comida** | Granjas, caza, pesca (océano), recolección, ganado pastoreado (un perro Presa Canario, entrenado en el Molino, lleva animales al punto de entrega propio más cercano — las ovejas enemigas se convierten por el camino) | Entrenamiento de unidades |
| **Comida (Pescado)** | Nodos de peces oceánicos (`FOOD_FISH`); recolectada por Barcos Pesqueros | Entrenamiento de unidades — mismo almacén que la Comida |
| **Madera** | Árboles, bosque de Laurisilva | Edificios, barcos, arqueros |
| **Oro** | Minas de oro, comercio, habilidades de héroe | Mejoras militares, mercenarios |
| **Piedra** | Canteras, depósitos volcánicos cerca de las calderas | Castillos, torres, murallas |

`FOOD_FISH` es un valor distinto del enum `ResourceNode.ResourceType`. Los nodos de peces aparecen en el océano entre las dos islas en los mapas de tipo Islas. Los Barcos Pesqueros son la única unidad que puede recolectarlos.

---

## Progresión de Edades

| Edad | Nombre | Desbloquea |
|---|---|---|
| 0 | **Edad Oscura** | Centro Urbano, Casas, economía básica |
| 1 | **Edad Feudal** | Cuartel, Galería de Tiro, Herrería, Establo (Explorador Pesado), Mercado (Fenicios: desde la Edad Oscura) |
| 2 | **Edad del Castillo** | Castillo, Universidad, Taller de Asedio, Establo (Caballero), Centro Urbano adicional (construible), unidades únicas, tecnología avanzada |
| 3 | **Era Imperial** | Árbol tecnológico completo, unidades únicas de élite |

Avanzar requiere gastar Comida y Oro en el Centro Urbano. Cada civilización puede tener bonificaciones que alteran el coste o la velocidad del avance.

---

## Civilizaciones

Ocho civilizaciones repartidas en tres capas históricas. Consulta `civilizations_es.md` / `civilizations_en.md` para el detalle completo.

| Capa | Civilización | Identidad |
|---|---|---|
| Antigua | **Atlantes** | Maestros navales, constructores costeros, niebla de guerra (+50 % de visión a lo largo de sus costas, más difíciles de detectar en la Niebla Marina), Invocador de Mareas anfibio que se adentra en el mar |
| Antigua | **Fenicios** | Comercio, mercenarios, rutas comerciales |
| Nativa | **Guanches** | Terreno volcánico, infantería resistente, fortalezas de piedra |
| Nativa | **Canarii** | Economía, arqueros equilibrados, bonificación en terreno elevado |
| Nativa | **Mahos** | Velocidad, terreno desértico, dependencia mínima de la madera |
| Invasora | **Francos** | Avance rápido, caballería organizada, presión temprana |
| Invasora | **Britanos** | Poder naval, arqueros de largo alcance, economía de saqueo |
| Invasora | **Castellanos** | Tecnología superior en el juego tardío, infantería pesada, torres |

---

## Héroes

Cada civilización tiene una **pareja de héroes** — un héroe con nombre masculino y otro femenino (16 en total), seleccionados en la sala (`MatchConfig.hero_gender`: Aleatorio / Masculino / Femenino). Los héroes son únicos — aparecen una vez al comienzo de la partida y portan una habilidad especial. Consulta `civilizations_es.md` y `heroines-design_es.md` para el nombre y la habilidad de cada héroe.

Reglas de los héroes:
- Aparecen cerca del Centro Urbano al inicio de la partida
- No se pueden entrenar; si muere, el héroe reaparece en el Centro Urbano tras 120 s (`HERO_RESPAWN_TIME`) — excepto en Regicidio, donde la muerte del héroe es derrota inmediata
- Estadísticas equivalentes a una unidad única de la Edad del Castillo
- Una habilidad especial con un enfriamiento de 45–120 s (auditado: `tests/unit/test_hero_abilities.gd` lanza las 16)

---

## Tipos de mapa

| Mapa | Descripción | Enfoque estratégico |
|---|---|---|
| **Llanura** | Terreno llano, sin terreno especial | Apto para principiantes |
| **Estándar** | Mapa terrestre con terreno variado | Juego general |
| **Costa Volcánica** | Terreno costero con una caldera intransitable en el centro | Dos corredores terrestres, ventaja para los Guanches |
| **Costa Desértica** | Mapa árido al estilo de Lanzarote, océano al oeste | Escasez de madera, ventaja para los Mahos |
| **Islas** | Dos islas separadas por océano | Lo naval es obligatorio; Muelle, Barcos Pesqueros, Barcos de Transporte y Galeras de Guerra esenciales |

---

## Casillas de terreno

| Casilla | Movimiento | Construible | Efecto especial |
|---|---|---|---|
| Hierba | Normal | Sí | — |
| Arena / Duna | -20% infantería (pesada) | Sí | Los Mahos son inmunes a la penalización |
| Malpaís (roca volcánica) | Intransitable (recortado del navmesh) | No | Los Guanches lo atraviesan mediante la malla de malpaís de la capa 8 |
| Arena negra de lava enfriada | Normal | No | Costera/decorativa |
| Laurisilva (bosque denso) | -35% | No | Alto rendimiento de madera (bosques densos de 260 de madera), visión −30% bajo el dosel |
| Risco (borde de acantilado) | Sin paso | No | Unidades a distancia a menos de 48 px del borde del risco: +2 de alcance de ataque |
| Agua poco profunda (océano ≤120 px de la costa) | Unidades terrestres bloqueadas; anfibios a velocidad completa | No | Solo el Invocador de Mareas de los Atlantes vadea — el resto de su ejército se queda en seco |
| Océano | Unidades terrestres bloqueadas | No | Barcos y unidades anfibias; el Invocador de Mareas nada al 60% de velocidad (`deep_water_speed`); pesca disponible |
| Caldera (activa) | Intransitable | No | El clima de Ceniza Volcánica golpea dentro del radio de la caldera + 800 px |

### Aplicación de la intransitabilidad

`TerrainManager.is_impassable_for(world_pos, civ_id, amphibious)` es la barrera en tiempo de ejecución. Todas las órdenes de movimiento de unidades resuelven el destino final a través de `TerrainManager.nearest_passable` antes de asignar un objetivo al agente de navegación. Si una posición solicitada está dentro de una zona intransitable, la unidad se redirige a la casilla alcanzable más cercana mediante una búsqueda radial de 30 anillos (24 px por anillo). El argumento `amphibious` proviene de la propia unidad (`UnitBase.is_amphibious()`), de modo que el agua se abre por unidad y no por civilización: a una milicia atlante se le niega el mar, a su Invocador de Mareas no.

El recorte del NavMesh (`NavMeshBuilder.build`) lo respalda a nivel de malla: las zonas de malpaís, risco y caldera se recortan de las mallas horneadas (`zone_obstructions`), de modo que los caminos las rodean; una cuarta malla (capa 8) deja el malpaís transitable para las civilizaciones que lo atraviesan. En los mapas de Islas el polígono de navegación se sustituye por polígonos de tierra por isla, de modo que la malla horneada nunca se extiende sobre el océano. Las unidades anfibias caminan por la malla de la capa 4, que abarca tierra y agua.

---

## Unidades navales

Las unidades navales extienden `ShipBase`, que extiende `UnitBase`. El terreno oceánico es transitable para todos los barcos.

### Muelle

| Propiedad | Valor |
|---|---|
| Coste | 150 Madera |
| PV | 1.800 |
| Tiempo de construcción | 45 s |
| Límite de cola de entrenamiento | 5 |
| Restricción de emplazamiento | Debe ser adyacente al agua (solo emplazamiento costero) |
| Tecla HUD | D |

El Muelle es el único edificio de producción de unidades navales. Los Barcos Pesqueros entregan automáticamente los recursos de pesca en el Muelle amigo más cercano.

### Plantilla de unidades navales

| Unidad | Edad | Coste | PV | Ataque | Alcance | Rol |
|---|---|---|---|---|---|---|
| **Barco Pesquero** | Oscura | 75M | — | — | — | Recolecta FOOD_FISH de los nodos oceánicos; devuelve la comida al Muelle; puede construir Trampas para Peces |
| **Barco de Transporte** | Feudal | 125M | — | — | — | Transporta hasta 8 unidades terrestres (aldeanos incluidos); los barcos y los barcos pesqueros no pueden embarcar; descarga en tierra firme |
| **Galera de Guerra** | Feudal | 75M + 35O | 120 | 6 | 5.5 | Combate naval a distancia |

## Unidades de asedio

Se producen en el **Taller de Asedio** (Edad del Castillo, 200 Madera).

| Unidad | Edad | Coste | PV | Ataque | Alcance | Notas |
|---|---|---|---|---|---|---|
| **Ariete** | Castillo | 160M | 180 | 40 (x3 contra edificios) | Cuerpo a cuerpo | Solo ataca automáticamente edificios; 0.2x de daño contra unidades |
| **Manganela** | Castillo | 160M + 135O | 90 | 35 | 7 | AoE de 72 px de salpicadura; alcance mínimo (35 % del máximo) |
| **Trabuquete** | Imperial | 200M + 200O | 70 | 200 | 12 | AoE de 48 px de salpicadura; debe desplegarse (3 s) antes de disparar; se repliega automáticamente con órdenes de movimiento; alcance mínimo (40 % del máximo) |

---

## Árbol tecnológico

32 tecnologías repartidas en 8 edificios de investigación (Herrería, Universidad, Templo, Cuartel, Establo, Campamento Maderero, Campamento Minero, Molino). Las tecnologías otorgan bonificaciones permanentes de estadísticas a unidades/edificios. Cada edificio de investigación ejecuta una tecnología activa más una cola de espera — hasta 5 tecnologías en curso por edificio, pagadas al encolar y reembolsadas íntegramente al cancelar.

### Herrería (13 tecnologías)

| Tecnología | Edad | Coste | Tiempo | Efecto |
|---|---|---|---|---|
| **Telar** | Oscura | 50c | 25s | PV del Aldeano ×1.15 |
| **Forja** | Feudal | 75c | 40s | Ataque de las unidades ×1.15 |
| **Armadura de Escamas** | Feudal | 100c+50o | 40s | Armadura cuerpo a cuerpo de las unidades +1 |
| **Armadura Acolchada** | Feudal | 100c | 35s | Armadura perforante del Arquero +1 |
| **Flechado** | Feudal | 100o | 35s | Ataque del Arquero ×1.20 |
| **Maestro Carpintero Naval** | Feudal | 200m+60o | 40s | PV de los barcos ×1.15, coste −15% |
| **Carreta Canaria** (`carreta_canaria`) | Feudal | 150c+75m | 40s | Capacidad de carga del Aldeano +25% (las granjas depositan al instante, no afectadas) |
| **Fundición de Hierro** | Castillo | 150o | 55s | Ataque de las unidades ×1.20 (requiere Forja) |
| **Carretón Isleño** (`carreton_isleno`) | Castillo | 200c+125m | 55s | Capacidad de carga del Aldeano +25% adicional (requiere Carreta Canaria) |
| **Armadura de Mallas** | Castillo | 200c+100o | 45s | Armadura cuerpo a cuerpo de las unidades +1 (requiere Armadura de Escamas) |
| **Flecha Bodkin** | Castillo | 100c+150o | 35s | Ataque del Arquero ×1.20, alcance ×1.10 (requiere Flechado) |
| **Alto Horno** | Imperial | 275c+225o | 50s | Ataque de las unidades ×1.15 |
| **Armadura de Placas** | Imperial | 300c+200o | 60s | Armadura cuerpo a cuerpo de las unidades +1 (requiere Armadura de Mallas) |

### Universidad (3 tecnologías)

Edificio de la Edad del Castillo (200 madera). Investiga mejoras militares avanzadas.

| Tecnología | Edad | Coste | Tiempo | Efecto |
|---|---|---|---|---|
| **Ingeniería de Asedio** | Castillo | 200o | 60s | Daño contra edificios ×1.20 |
| **Balística** | Castillo | 175o | 50s | Velocidad de ataque del Arquero ×1.20 (requiere Flechado) |
| **Química** | Imperial | 300o | 70s | Ataque del Arquero ×1.15 (requiere Balística) |

### Templo (3 tecnologías)

Edificio de la Edad del Castillo (175 madera). Investiga mejoras de moral y PV. El Templo es también el hospital de campaña — las unidades guarnecidas (capacidad 5) curan 4 PV/s, los héroes a la mitad — y entrena a la sacerdotisa-sanadora **Harimaguada** (85 Comida + 25 Oro, Edad del Castillo): siempre mujer, nunca lucha, sana aliados a 5 PV/s a distancia de contacto y hace triaje automático de los heridos cercanos mientras está inactiva.

| Tecnología | Edad | Coste | Tiempo | Efecto |
|---|---|---|---|---|
| **Fervor** | Castillo | 150o | 50s | Velocidad de movimiento de las unidades ×1.10 |
| **Santidad** | Castillo | 100c | 40s | PV del Espadachín ×1.15 |
| **Expiación** | Imperial | 150c+100o | 55s | PV de la caballería ×1.20 (requiere Santidad) |

### Líneas económicas de los campamentos (9 tecnologías)

Cada campamento de entrega investiga su propia línea de tres pasos — una tecnología por edad desde Feudal, con requisitos encadenados. Cada paso multiplica la velocidad de recolección del aldeano para ese recurso por 1.15 y su cesta de carga por 1.10 (claves de efecto `villager_<res>_gather_rate` / `villager_<res>_carry`, acumuladas sobre las carretas de la Herrería).

| Edificio (recurso) | Feudal | Castillo | Imperial |
|---|---|---|---|
| **Campamento Maderero** (madera) | Hacha de doble filo — 100c+50m, 25s | Sierra de arco — 150c+100m, 40s | Sierra de dos hombres — 300c+200m, 60s |
| **Campamento Minero** (oro + piedra) | Picos reforzados — 100c+75m, 25s | Minería de pozo — 175c+100m, 40s | Galerías profundas — 300c+150m, 60s |
| **Molino** (comida) | Collera de tiro — 75c+75m, 25s | Arado pesado — 125c+125m, 40s | Rotación de cultivos — 250c+250m, 60s |

### Tecnologías de mejora de unidad (4)

Se investigan en el edificio que entrena la unidad. Transforman inmediatamente todas las unidades existentes de ese tipo (PV escalados proporcionalmente), y el edificio pasa a entrenar la nueva unidad en adelante.

| Tecnología | Edificio | Edad | Coste | Tiempo | Transforma |
|---|---|---|---|---|---|
| **Hombre de Armas** | Cuartel | Feudal | 100c+40o | 45s | Milicia → Hombre de Armas |
| **Espadachín** | Cuartel | Castillo | 200c+60o | 45s | Hombre de Armas → Espadachín |
| **Explorador Pesado** | Establo | Feudal | 150c+75o | 45s | Explorador → Explorador Pesado |
| **Caballero** | Establo | Castillo | 200c+100o | 45s | Explorador Pesado → Caballero |

### Concesiones tecnológicas instantáneas por civilización

**Castellanos**: Reciben una tecnología de Herrería gratuita cada vez que avanzan de Edad. El juego concede automáticamente la tecnología de Herrería más antigua sin investigar disponible en la nueva Edad (respetando los requisitos). Ejemplo: avanzar a Feudal concede Telar o Forja gratis.

---

## Sistema de clima

Eventos de clima procedurales afectan al juego con modificadores de estadísticas y efectos visuales. Activación/desactivación y frecuencia configurables en la sala.

### Tipos de clima

| Clima | Restricción de mapa | Duración (pico) | Efectos |
|---|---|---|---|
| **Calima** (polvo sahariano) | Todos los mapas | 70-130s | Visión −40%, recolección −20% (madera/comida), velocidad de movimiento −15% |
| **Tormenta Atlántica** | Todos los mapas | 40-90s | Velocidad naval −30%, pesca −50%, deriva de proyectiles (30 px de viento cruzado) |
| **Niebla Marina** | Solo mapas costeros | 60-120s | Visión costera −60%, ocultación de unidades dentro de la zona costera (intensidad ≥0.5) — se rompe a corta distancia (180 px, 90 px para los Atlantes) o al atacar (3 s) |
| **Vientos Alisios** | Todos los mapas | 100-160s | Velocidad naval ±20% (alineación con el viento), deriva de proyectiles (40 px a favor del viento) |
| **Ceniza Volcánica** | Costa Volcánica | 40-80s | Visión −50%, recolección −30%, drenaje de PV de edificios (2/s), alrededor de las calderas (radio de la caldera + 800 px) |

### Fases del clima

Cada evento de clima tiene 3 fases:
1. **Entrada** (10 s): intensidad 0.0 → 1.0
2. **Pico** (duración indicada arriba): intensidad = 1.0
3. **Salida** (10 s): intensidad 1.0 → 0.0
4. **Despejado** (60-120 s): sin clima, intensidad = 0.0

### Ajustes de frecuencia del clima

- **Desactivado**: Sin eventos de clima
- **Normal**: Duración del despeje 60-120 s (línea base)
- **Frecuente**: Duración del despeje ×0.6 (36-72 s)
- **Extremo**: Duración del despeje ×0.3 (18-36 s)

### Efectos visuales

`WeatherOverlay` renderiza efectos en espacio de pantalla:
- **Lluvia** (Tormenta Atlántica): partículas que caen
- **Polvo** (Calima): partículas horizontales
- **Ceniza** (Ceniza Volcánica): partículas grises que caen
- **Viento** (Vientos Alisios): partículas horizontales
- **Viñeta de niebla** (Niebla Marina): oscurecimiento de los bordes de la pantalla

---

## Condiciones de victoria

Hay tres modos de victoria implementados, seleccionables en la sala:

- **Conquista**: Un jugador queda fuera cuando tiene cero unidades y cero edificios de producción; gana el último bando mutuamente aliado en pie.
- **Regicidio**: Cada jugador empieza con un Héroe. La muerte del héroe elimina a ese jugador al instante (sin reaparición en este modo).
- **Maravilla**: Construye una Maravilla (Era Imperial, cuesta 2500 madera + 2500 comida + 2500 piedra + 5000 oro) y defiéndela durante `WONDER_COUNTDOWN_SEC` (240 s = 4 minutos). Destruir la Maravilla cancela su cuenta atrás; la partida continúa.

**Eliminación y espectador**: la eliminación emite `EventBus.player_eliminated`. Si el jugador local es eliminado (o se rinde) mientras quedan bandos hostiles, la partida sigue — el panel de derrota ofrece "Ver mapa" y el jugador observa con las órdenes bloqueadas (`GameWorld.local_player_defeated`); el fin de partida definitivo reconstruye el panel. Equipos: `GameManager.are_allied` es el único punto de paso para la comprobación de victoria.

---

## Configuración de partida (Sala)

Los jugadores configuran una escaramuza antes de empezar:

| Opción | Valores |
|---|---|
| Tamaño del mapa | Pequeño / Mediano / Grande |
| Tipo de mapa | Llanura / Estándar / Costa Volcánica / Costa Desértica / Islas |
| Recursos iniciales | Escasos / Normales / Abundantes / Combate Total (todo a 9999) / Tutorial (solo 320 de madera) |
| Civilización del jugador | Elección entre 8 civilizaciones (Guanches, Canarii, Mahos, Francos, Britanos, Castellanos, Atlantes, Fenicios) |
| Número de rivales | 1-3 oponentes de IA (multijugador: hasta 4 jugadores en total, asientos restantes Abierto / IA / Cerrado) |
| Civilizaciones rivales | Elección de civilización para cada IA |
| Equipos | Jugadores y rivales asignables a los equipos 1-4 (`MatchConfig.player_teams`) |
| Edad inicial | Oscura / Feudal / Castillo / Imperial |
| Condición de victoria | Conquista / Regicidio / Maravilla |
| Clima activado | Sí / No |
| Frecuencia del clima | Desactivado / Normal / Frecuente / Extremo |
| Género del héroe | Aleatorio / Masculino / Femenino |

---

## Hitos

| Hito | Descripción | Estado |
|---|---|---|
| M1 | Mapa jugable con aldeanos recolectando recursos | ✅ Hecho |
| M2 | Centro Urbano, Cuartel, murallas, ejército básico, niebla de guerra | ✅ Hecho |
| M3 | Progresión de edades (4 edades), árbol tecnológico (8 tecnologías), nuevas unidades (Arquero, Piquero) | ✅ Hecho |
| M4 | Juego naval (Muelle, barcos, mapa de Islas, asalto naval de la IA) | ✅ Hecho |
| M5 | **Un jugador listo para producción**: 8 civilizaciones con unidades únicas/héroes, sistema de clima, guardado/carga, 3 condiciones de victoria, pulido y corrección de errores | ✅ Hecho |
| M6 | Terreno personalizado (malpaís, duna, risco, laurisilva) con bonificaciones de travesía por civilización y efectos de juego (visión/madera en laurisilva, ventaja de risco, agua poco profunda) | ✅ Hecho |
| M7 | Multijugador: sesiones LAN/Internet con autoridad en el host, sala unificada, replicación de estado, robustez, chat, equipos, reconexión, guardado/reanudación, prototipo de transporte de Steam | ✅ Hecho |
| M8 | Modo campaña: *Las Llamas de Tamarán* — prólogo tutorial + 4 misiones guionizadas | ✅ Hecho |
| M9 | Repeticiones y kit de creador: grabación de partidas, reproducción con línea de tiempo, modo cinemático, exportación de vídeo/clips | ✅ Hecho |
| M10 | Determinismo lockstep (movimiento fuera de la física de Godot), prueba con AppID de Steam en vivo, pase de balance | 📋 Planificado |

### Totales de contenido actuales

Verificados contra `project/resources/` y `project/scenes/` (2026-09-06):

- 8 civilizaciones (`resources/civilizations/*.tres`)
- 26 tipos de unidad jugables (25 regulares — 8 de ellas únicas de civilización — más la clase de héroe) y 16 héroes con nombre (2 por civilización, `resources/units/hero_*.tres`); 2 tipos de animal
- 20 tipos de edificio (`resources/buildings/*.tres`)
- 32 tecnologías (`resources/technologies/*.tres`; TechManager carga el directorio)
- 5 tipos de mapa, 3 tamaños, 4 modos de recursos, 3 condiciones de victoria, 5 tipos de clima, 99 ranuras de guardado
- Campaña: prólogo tutorial + 4 misiones (`CampaignData.MISSIONS`)
