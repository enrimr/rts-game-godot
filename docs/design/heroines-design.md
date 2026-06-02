# Heroínas de Calima: Flames of the Atlantic

## Concepto General

Cada civilización tendrá **2 héroes**: uno masculino (ya implementado) y uno femenino (nuevo). Al iniciar una partida, se selecciona **aleatoriamente** uno de los dos (50/50). Ambos tienen habilidades únicas que reflejan la identidad de su civilización, pero con enfoques tácticos diferentes.

---

## Diseño de las 8 Heroínas

### 1. **GUANCHES** — Dácil, Reina del Valle 👑

**Héroe masculino existente**: Bencomo (Mencey Charge - buff de ataque)

**Habilidad**: **"Voz de la Montaña" (Mountain Voice)**
- **Tipo**: Buff defensivo de área
- **Efecto**: Todas las unidades aliadas en 300px reciben +2 armadura cuerpo a cuerpo y +50% velocidad de curación durante 12 segundos
- **Cooldown**: 60 segundos
- **Táctica**: Defensiva - sostiene líneas en combates prolongados
- **Lore**: Dácil era una princesa guanche legendaria. Su habilidad representa la resiliencia del pueblo guanche

**Stats base**: Igual que Bencomo (infantería pesada)

---

### 2. **CANARII** — Guayarmina, Guardiana de Tara 🏹

**Héroe masculino existente**: Doramas (Challenge - taunt forzado)

**Habilidad**: **"Flecha del Destino" (Fate's Arrow)**
- **Tipo**: Ataque dirigido de largo alcance
- **Efecto**: Dispara una flecha imparable que hace 80 de daño directo (ignora armadura) a un objetivo seleccionado hasta 600px de distancia. Si mata al objetivo, el cooldown se reduce a la mitad (30s en lugar de 60s)
- **Cooldown**: 60 segundos (30s si mata)
- **Táctica**: Ofensiva - elimina objetivos prioritarios (héroes enemigos, siege units)
- **Lore**: Guayarmina era una princesa guerrera de Gran Canaria conocida por su puntería

**Stats base**: Arquera (menor HP que Doramas, mayor rango)
- HP: 180 (vs 280 de Doramas)
- Attack: 15
- Range: 320px
- Speed: 110 (más rápida)

---

### 3. **MAHOS** — Tibiabin, Jinete de las Dunas 🐪

**Héroe masculino existente**: Guadarfía (Ambush - invisibilidad)

**Habilidad**: **"Tormenta de Arena" (Sandstorm)**
- **Tipo**: Área de denegación (AoE DoT)
- **Efecto**: Crea una tormenta de arena de 200px de radio en su posición actual durante 10 segundos. Enemigos dentro reciben 3 daño/segundo y tienen -40% velocidad de movimiento y -50% precisión de proyectiles
- **Cooldown**: 70 segundos
- **Táctica**: Control de zona - bloquea rutas, ralentiza ataques enemigos
- **Lore**: Tibiabin era una reina majorera. Su habilidad evoca las tormentas del desierto

**Stats base**: Caballería ligera (como Guadarfía)

---

### 4. **FRANKS** — Catalina de Béthencourt, Condesa Conquistadora ⚔️

**Héroe masculino existente**: Jean de Béthencourt (Forced Diplomacy - conversión temporal)

**Habilidad**: **"Duelo de Honor" (Honor Duel)**
- **Tipo**: Buff de combate 1v1
- **Efecto**: Desafía a un héroe o unidad única enemiga dentro de 250px. Durante 15 segundos, ambos reciben +100% daño contra el otro, pero -50% daño contra otras unidades. Si Catalina mata al objetivo, recupera el 50% de su HP máximo
- **Cooldown**: 80 segundos
- **Táctica**: Cazadora de héroes - elimina al líder enemigo
- **Lore**: Catalina representa el código de honor de los caballeros normandos

**Stats base**: Caballería pesada (infantry con mount visual)
- HP: 320
- Attack: 22
- Speed: 95

---

### 5. **BRITONS** — Grace O'Malley, Reina Pirata 🏴‍☠️

**Héroe masculino existente**: Francis Drake (Plunder - bonus gold en kills)

**Habilidad**: **"Abordaje" (Boarding Action)**
- **Tipo**: Dash + stun
- **Efecto**: Se lanza 200px en línea recta hacia un punto seleccionado. Todas las unidades enemigas en la trayectoria reciben 30 de daño y quedan aturdidas durante 2 segundos. Si impacta un edificio, lo daña por 100
- **Cooldown**: 50 segundos
- **Táctica**: Iniciadora - rompe formaciones enemigas, interrumpe siege
- **Lore**: Grace O'Malley era una pirata irlandesa legendaria que rivalizó con Drake

**Stats base**: Infantry con bonus naval
- HP: 260
- Attack: 18
- Speed: 105
- Bonus: +50% daño vs edificios

---

### 6. **CASTELLANOS** — Dulcinea, Dama de la Estrategia 📜

**Héroe masculino existente**: Don Quijote (Knight Errant Charge - carga en línea)

**Habilidad**: **"Llamada a las Armas" (Call to Arms)**
- **Tipo**: Summon + buff
- **Efecto**: Invoca instantáneamente 3 Militia temporales en su posición durante 40 segundos. Estos Militia tienen +20% HP y ataque. Cuando expiran o mueren, no cuentan como bajas para el jugador
- **Cooldown**: 90 segundos
- **Táctica**: Utilidad - refuerza defensas desesperadas o añade masa a ataques
- **Lore**: Dulcinea representa la inspiración idealizada de Don Quijote convertida en líder real

**Stats base**: Soporte (infantry con menos daño pero más HP)
- HP: 300
- Attack: 12
- Speed: 90

---

### 7. **ATLANTES** — Cleito, Maestra de las Mareas 🌊

**Héroe masculino existente**: Artaxerax (Calima - niebla artificial)

**Habilidad**: **"Marea Creciente" (Rising Tide)**
- **Tipo**: Curación de área + movimiento
- **Efecto**: Crea una ola de agua que se expande desde su posición a 250px de radio durante 3 segundos. Unidades aliadas tocadas por la ola se curan 60 HP y reciben +30% velocidad de movimiento durante 8 segundos. Unidades enemigas reciben 20 de daño y -20% velocidad durante 4 segundos
- **Cooldown**: 65 segundos
- **Táctica**: Híbrido - cura + reposicionamiento táctico
- **Lore**: Cleito era la esposa mortal de Poseidón en la leyenda de la Atlántida

**Stats base**: Infantry anfibio
- HP: 240
- Attack: 16
- Speed: 100 (120 en agua)

---

### 8. **FENICIOS** — Elissa, Fundadora de Cartago 🏛️

**Héroe masculino existente**: Hannón (Trade Route - pasivo de oro)

**Habilidad**: **"Pacto Mercenario" (Mercenary Pact)**
- **Tipo**: Conversión económica
- **Efecto**: Gasta 400 de oro para convertir instantáneamente una unidad enemiga no-heroica dentro de 200px de forma **permanente**. La unidad convertida pasa a ser del jugador y mantiene toda su veteranía/upgrades. No funciona en héroes ni edificios
- **Cooldown**: 120 segundos
- **Requisito**: Requiere 400 gold en reserva
- **Táctica**: Swing táctico - roba unidades caras (Knights, Trebuchets, unique units)
- **Lore**: Elissa (Dido) fundó Cartago y era conocida por su astucia diplomática y comercial

**Stats base**: Infantry económica (débil en combate)
- HP: 220
- Attack: 10
- Speed: 85
- Bonus pasivo: +10% velocidad de recolección de oro para villagers en 400px

---

## Implementación Técnica

### 1. **Nueva Estructura de Hero Maps** (game_world.gd)

```gdscript
const HERO_MALE_MAP: Dictionary = {
    "guanches":    "res://resources/units/hero_bencomo.tres",
    "canarii":     "res://resources/units/hero_doramas.tres",
    # ... resto existente
}

const HERO_FEMALE_MAP: Dictionary = {
    "guanches":    "res://resources/units/hero_dacil.tres",
    "canarii":     "res://resources/units/hero_guayarmina.tres",
    "mahos":       "res://resources/units/hero_tibiabin.tres",
    "franks":      "res://resources/units/hero_catalina.tres",
    "britons":     "res://resources/units/hero_grace.tres",
    "castellanos": "res://resources/units/hero_dulcinea.tres",
    "atlantes":    "res://resources/units/hero_cleito.tres",
    "fenicios":    "res://resources/units/hero_elissa.tres",
}
```

### 2. **Selección Aleatoria al Spawn**

```gdscript
func _spawn_hero(player_id: int, civ_id: String, pos: Vector2) -> Node:
    var use_female: bool = randi() % 2 == 0  # 50/50
    var hero_map: Dictionary = HERO_FEMALE_MAP if use_female else HERO_MALE_MAP
    var data_path: String = hero_map.get(civ_id, "")
    # ... resto del código existente
```

### 3. **Nuevas Habilidades en HeroUnit.gd**

```gdscript
enum Ability {
    # ... existentes ...
    # Heroínas
    MOUNTAIN_VOICE,        # Dácil - Guanches
    FATES_ARROW,           # Guayarmina - Canarii
    SANDSTORM,             # Tibiabin - Mahos
    HONOR_DUEL,            # Catalina - Franks
    BOARDING_ACTION,       # Grace - Britons
    CALL_TO_ARMS,          # Dulcinea - Castellanos
    RISING_TIDE,           # Cleito - Atlantes
    MERCENARY_PACT,        # Elissa - Fenicios
}
```

### 4. **Archivos a Crear**

**Resources** (8 archivos `.tres`):
- `project/resources/units/hero_dacil.tres`
- `project/resources/units/hero_guayarmina.tres`
- `project/resources/units/hero_tibiabin.tres`
- `project/resources/units/hero_catalina.tres`
- `project/resources/units/hero_grace.tres`
- `project/resources/units/hero_dulcinea.tres`
- `project/resources/units/hero_cleito.tres`
- `project/resources/units/hero_elissa.tres`

**Scripts** (ninguno - reusan `hero_unit.gd`):
- Todas las heroínas comparten el script `HeroUnit`
- Las habilidades se implementan en métodos específicos en `hero_unit.gd`

### 5. **Balance Considerations**

| Héroe/Heroína | Rol | Fuerza | Debilidad |
|---|---|---|---|
| Bencomo vs Dácil | Offense vs Defense | Bencomo mejor en push agresivos | Dácil mejor en defensas de base |
| Doramas vs Guayarmina | Tank vs Sniper | Doramas soporta línea frontal | Guayarmina es glass cannon |
| Guadarfía vs Tibiabin | Stealth vs Control | Guadarfía gank individual | Tibiabin control de grupo |
| Béthencourt vs Catalina | Utility vs Duelist | Jean convierte unidades | Catalina mata héroes |
| Drake vs Grace | Economic vs Combat | Drake genera oro pasivo | Grace aporta iniciación |
| Quijote vs Dulcinea | Dive vs Summon | Quijote divide backline | Dulcinea refuerza frontline |
| Artaxerax vs Cleito | Stealth vs Healing | Artaxerax esconde army | Cleito sustenta peleas |
| Hannón vs Elissa | Passive vs Active | Hannón oro gratis long-game | Elissa swing táctico instant |

---

## Ejemplos de Uso Táctico

### Dácil (Guanches)
**Situación**: Enemigo hace push con 10 Militia + 2 Archers contra tu base.
**Respuesta**: Activa "Mountain Voice" → tus 5 Villagers + 3 Militia defienden efectivamente con +2 armor.

### Guayarmina (Canarii)
**Situación**: Enemigo tiene Trebuchet asediando tu TC a 500px.
**Respuesta**: "Fate's Arrow" → mata el Trebuchet ignorando su armor → cooldown reducido a 30s.

### Tibiabin (Mahos)
**Situación**: Enemigo hace rush de Knights por un paso estrecho.
**Respuesta**: "Sandstorm" en el cuello de botella → Knights ralentizados → tus Pikemen los alcanzan.

### Catalina (Franks)
**Situación**: Partida en modo Regicide - necesitas matar al héroe enemigo.
**Respuesta**: "Honor Duel" al héroe enemigo → ambos hacen x2 daño → ganas el 1v1 → curas 50%.

### Grace (Britons)
**Situación**: Enemigo tiene grupo de Archers detrás de Militia.
**Respuesta**: "Boarding Action" atraviesa la línea → stunnea Archers → tus Militia los alcanzan.

### Dulcinea (Castellanos)
**Situación**: Enemigo hace rush temprano con 8 Militia - solo tienes 2 Villagers y el TC.
**Respuesta**: "Call to Arms" → 3 Militia temporales aparecen → defiendes hasta que lleguen refuerzos.

### Cleito (Atlantes)
**Situación**: Tu army de 12 unidades está a 30% HP después de una batalla - enemigo contraataca.
**Respuesta**: "Rising Tide" → cura 60 HP a todas + speed boost → te retiras mientras curas.

### Elissa (Fenicios)
**Situación**: Enemigo tiene un Knight veterano (caro, upgraded) avanzando.
**Respuesta**: "Mercenary Pact" → gastas 400g → el Knight ahora es tuyo permanentemente.

---

## Visual Design (Placeholder)

Todas las heroínas usan el mismo sistema de Polygon2D que los héroes masculinos:
- **Color distintivo**: Tono ligeramente más claro o diferente hue vs su contraparte masculina
- **Hero ring**: Mismo anillo dorado (código existente)
- **Tamaño**: Mismo que el héroe masculino de su civ
- **Animación**: Reusan el body rotation procedural de `unit_base.gd`

---

## Testing Checklist

- [ ] Las 8 heroínas se seleccionan aleatoriamente (verificar 50/50 en 100 partidas)
- [ ] Cada habilidad funciona correctamente en isolation
- [ ] Habilidades no causan crashes si el héroe muere mid-cast
- [ ] Modo Regicide funciona con heroínas (muerte = derrota)
- [ ] Cooldowns se muestran correctamente en UI
- [ ] Efectos visuales de habilidades son visibles
- [ ] Audio feedback para cada habilidad (evento EventBus)
- [ ] SaveManager serializa/deserializa heroínas correctamente
- [ ] AI no crashea cuando enemigo tiene heroína

---

## Roadmap de Implementación

### Phase 1: Infrastructure (1-2 horas)
1. Añadir `HERO_FEMALE_MAP` a `game_world.gd`
2. Modificar `_spawn_hero()` para selección aleatoria
3. Añadir nuevos `Ability` enums a `hero_unit.gd`
4. Extender `ABILITY_MAP` con nuevos IDs

### Phase 2: Resources (2-3 horas)
5. Crear 8 archivos `.tres` con stats base
6. Configurar `hero_ability_id` para cada heroína

### Phase 3: Abilities Implementation (6-8 horas)
7. Implementar cada habilidad en `hero_unit.gd`:
   - `_use_mountain_voice()`
   - `_use_fates_arrow(target: Node)`
   - `_use_sandstorm()`
   - `_use_honor_duel(target: Node)`
   - `_use_boarding_action(direction: Vector2)`
   - `_use_call_to_arms()`
   - `_use_rising_tide()`
   - `_use_mercenary_pact(target: Node)`

### Phase 4: UI Integration (1-2 horas)
8. Añadir tooltips para nuevas habilidades
9. Actualizar `hud_manager.gd` para mostrar habilidades de heroínas

### Phase 5: Testing & Balance (3-4 horas)
10. Playtest cada heroína en combate real
11. Ajustar cooldowns/números si es necesario
12. Verificar interacciones con weather/techs

---

## Estimación Total: **13-19 horas de desarrollo**

**Prioridad**: Alta - añade variedad estratégica y rejugabilidad significativa.

**Impacto en AAA Score**: +0.5 puntos (de 7.5 a 8.0) - demuestra profundidad de contenido y diseño de personajes.
