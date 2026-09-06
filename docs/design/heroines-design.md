# Heroines of Calima: Flames of the Atlantic

## General Concept

Each civilization will have **2 heroes**: one male (already implemented) and one female (new). At match start, one of the two is selected **randomly** (50/50). Both have unique abilities that reflect their civilization's identity, but with different tactical approaches.

---

## Design of the 8 Heroines

### 1. **GUANCHES** — Dácil, Queen of the Valley 👑

**Existing male hero**: Bencomo (Mencey Charge - attack buff)

**Ability**: **"Mountain Voice" (Voz de la Montaña)**
- **Type**: Defensive area buff
- **Effect**: All allied units within 300px gain +2 melee armor and +50% healing rate for 12 seconds
- **Cooldown**: 60 seconds
- **Tactics**: Defensive - holds the line in prolonged engagements
- **Lore**: Dácil was a legendary Guanche princess. Her ability represents the resilience of the Guanche people

**Base stats**: Same as Bencomo (heavy infantry)

---

### 2. **CANARII** — Guayarmina, Guardian of Tara 🏹

**Existing male hero**: Doramas (Challenge - forced taunt)

**Ability**: **"Fate's Arrow" (Flecha del Destino)**
- **Type**: Long-range targeted attack
- **Effect**: Fires an unstoppable arrow dealing 80 direct damage (ignores armor) to a selected target up to 600px away. If it kills the target, the cooldown is halved (30s instead of 60s)
- **Cooldown**: 60 seconds (30s on kill)
- **Tactics**: Offensive - eliminates priority targets (enemy heroes, siege units)
- **Lore**: Guayarmina was a warrior princess of Gran Canaria known for her marksmanship

**Base stats**: Archer (lower HP than Doramas, longer range)
- HP: 180 (vs Doramas' 280)
- Attack: 15
- Range: 320px
- Speed: 110 (faster)

---

### 3. **MAHOS** — Tibiabin, Rider of the Dunes 🐪

**Existing male hero**: Guadarfía (Ambush - invisibility)

**Ability**: **"Sandstorm" (Tormenta de Arena)**
- **Type**: Area denial (AoE DoT)
- **Effect**: Creates a 200px-radius sandstorm at her current position for 10 seconds. Enemies inside take 3 damage/second and suffer -40% movement speed and -50% projectile accuracy
- **Cooldown**: 70 seconds
- **Tactics**: Zone control - blocks routes, slows enemy assaults
- **Lore**: Tibiabin was a queen of Fuerteventura. Her ability evokes the desert storms

**Base stats**: Light cavalry (same as Guadarfía)

---

### 4. **FRANKS** — Catalina de Béthencourt, Conquering Countess ⚔️

**Existing male hero**: Jean de Béthencourt (Forced Diplomacy - temporary conversion)

**Ability**: **"Honor Duel" (Duelo de Honor)**
- **Type**: 1v1 combat buff
- **Effect**: Challenges an enemy hero or unique unit within 250px. For 15 seconds, both deal +100% damage against each other but -50% damage against other units. If Catalina kills the target, she recovers 50% of her max HP
- **Cooldown**: 80 seconds
- **Tactics**: Hero hunter - takes out the enemy leader
- **Lore**: Catalina embodies the code of honor of the Norman knights

**Base stats**: Heavy cavalry (infantry with visual mount)
- HP: 320
- Attack: 22
- Speed: 95

---

### 5. **BRITONS** — Grace O'Malley, Pirate Queen 🏴‍☠️

**Existing male hero**: Francis Drake (Plunder - bonus gold on kills)

**Ability**: **"Boarding Action" (Abordaje)**
- **Type**: Dash + stun
- **Effect**: Dashes 200px in a straight line toward a selected point. All enemy units in the path take 30 damage and are stunned for 2 seconds. If she hits a building, it takes 100 damage
- **Cooldown**: 50 seconds
- **Tactics**: Initiator - breaks enemy formations, interrupts siege
- **Lore**: Grace O'Malley was a legendary Irish pirate who rivaled Drake

**Base stats**: Infantry with naval bonus
- HP: 260
- Attack: 18
- Speed: 105
- Bonus: +50% damage vs buildings

---

### 6. **CASTELLANOS** — Dulcinea, Lady of Strategy 📜

**Existing male hero**: Don Quijote (Knight Errant Charge - line charge)

**Ability**: **"Call to Arms" (Llamada a las Armas)**
- **Type**: Summon + buff
- **Effect**: Instantly summons 3 temporary Militia at her position for 40 seconds. These Militia have +20% HP and attack. When they expire or die, they do not count as casualties for the player
- **Cooldown**: 90 seconds
- **Tactics**: Utility - reinforces desperate defenses or adds mass to attacks
- **Lore**: Dulcinea represents Don Quijote's idealized inspiration made a real leader

**Base stats**: Support (infantry with less damage but more HP)
- HP: 300
- Attack: 12
- Speed: 90

---

### 7. **ATLANTES** — Cleito, Mistress of the Tides 🌊

**Existing male hero**: Artaxerax (Calima - artificial fog)

**Ability**: **"Rising Tide" (Marea Creciente)**
- **Type**: Area healing + movement
- **Effect**: Creates a wave of water expanding from her position out to a 250px radius over 3 seconds. Allied units touched by the wave heal 60 HP and gain +30% movement speed for 8 seconds. Enemy units take 20 damage and -20% speed for 4 seconds
- **Cooldown**: 65 seconds
- **Tactics**: Hybrid - healing + tactical repositioning
- **Lore**: Cleito was Poseidon's mortal wife in the legend of Atlantis

**Base stats**: Amphibious infantry
- HP: 240
- Attack: 16
- Speed: 100 (120 in water)

---

### 8. **FENICIOS** — Elissa, Founder of Carthage 🏛️

**Existing male hero**: Hannón (Trade Route - passive gold)

**Ability**: **"Mercenary Pact" (Pacto Mercenario)**
- **Type**: Economic conversion
- **Effect**: Spends 400 gold to instantly and **permanently** convert a non-hero enemy unit within 200px. The converted unit becomes the player's and keeps all its veterancy/upgrades. Does not work on heroes or buildings
- **Cooldown**: 120 seconds
- **Requirement**: Requires 400 gold in reserve
- **Tactics**: Tactical swing - steals expensive units (Knights, Trebuchets, unique units)
- **Lore**: Elissa (Dido) founded Carthage and was known for her diplomatic and commercial cunning

**Base stats**: Economic infantry (weak in combat)
- HP: 220
- Attack: 10
- Speed: 85
- Passive bonus: +10% gold gathering speed for Villagers within 400px

---

## Technical Implementation

### 1. **New Hero Map Structure** (game_world.gd)

```gdscript
const HERO_MALE_MAP: Dictionary = {
    "guanches":    "res://resources/units/hero_bencomo.tres",
    "canarii":     "res://resources/units/hero_doramas.tres",
    # ... existing rest
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

### 2. **Random Selection at Spawn**

```gdscript
func _spawn_hero(player_id: int, civ_id: String, pos: Vector2) -> Node:
    var use_female: bool = randi() % 2 == 0  # 50/50
    var hero_map: Dictionary = HERO_FEMALE_MAP if use_female else HERO_MALE_MAP
    var data_path: String = hero_map.get(civ_id, "")
    # ... existing rest of the code
```

### 3. **New Abilities in HeroUnit.gd**

```gdscript
enum Ability {
    # ... existing ...
    # Heroines
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

### 4. **Files to Create**

**Resources** (8 `.tres` files):
- `project/resources/units/hero_dacil.tres`
- `project/resources/units/hero_guayarmina.tres`
- `project/resources/units/hero_tibiabin.tres`
- `project/resources/units/hero_catalina.tres`
- `project/resources/units/hero_grace.tres`
- `project/resources/units/hero_dulcinea.tres`
- `project/resources/units/hero_cleito.tres`
- `project/resources/units/hero_elissa.tres`

**Scripts** (none - they reuse `hero_unit.gd`):
- All heroines share the `HeroUnit` script
- Abilities are implemented as dedicated methods in `hero_unit.gd`

### 5. **Balance Considerations**

| Hero/Heroine | Role | Strength | Weakness |
|---|---|---|---|
| Bencomo vs Dácil | Offense vs Defense | Bencomo better at aggressive pushes | Dácil better at base defense |
| Doramas vs Guayarmina | Tank vs Sniper | Doramas holds the front line | Guayarmina is a glass cannon |
| Guadarfía vs Tibiabin | Stealth vs Control | Guadarfía single-target ganks | Tibiabin group control |
| Béthencourt vs Catalina | Utility vs Duelist | Jean converts units | Catalina kills heroes |
| Drake vs Grace | Economic vs Combat | Drake generates passive gold | Grace brings initiation |
| Quijote vs Dulcinea | Dive vs Summon | Quijote splits the backline | Dulcinea reinforces the frontline |
| Artaxerax vs Cleito | Stealth vs Healing | Artaxerax hides the army | Cleito sustains fights |
| Hannón vs Elissa | Passive vs Active | Hannón free gold long-game | Elissa instant tactical swing |

---

## Tactical Usage Examples

### Dácil (Guanches)
**Situation**: Enemy pushes your base with 10 Militia + 2 Archers.
**Response**: Activate "Mountain Voice" → your 5 Villagers + 3 Militia defend effectively with +2 armor.

### Guayarmina (Canarii)
**Situation**: An enemy Trebuchet is besieging your Town Center from 500px.
**Response**: "Fate's Arrow" → kills the Trebuchet ignoring its armor → cooldown reduced to 30s.

### Tibiabin (Mahos)
**Situation**: Enemy rushes Knights through a narrow pass.
**Response**: "Sandstorm" on the chokepoint → Knights slowed → your Pikemen catch them.

### Catalina (Franks)
**Situation**: Regicide match - you need to kill the enemy hero.
**Response**: "Honor Duel" on the enemy hero → both deal x2 damage → you win the 1v1 → you heal 50%.

### Grace (Britons)
**Situation**: Enemy has a group of Archers behind Militia.
**Response**: "Boarding Action" pierces the line → stuns the Archers → your Militia catch them.

### Dulcinea (Castellanos)
**Situation**: Enemy rushes early with 8 Militia - you only have 2 Villagers and the Town Center.
**Response**: "Call to Arms" → 3 temporary Militia appear → you hold out until reinforcements arrive.

### Cleito (Atlantes)
**Situation**: Your 12-unit army is at 30% HP after a battle - the enemy counterattacks.
**Response**: "Rising Tide" → heals 60 HP on everyone + speed boost → you retreat while healing.

### Elissa (Fenicios)
**Situation**: Enemy has a veteran Knight (expensive, upgraded) advancing.
**Response**: "Mercenary Pact" → you spend 400g → the Knight is now permanently yours.

---

## Visual Design (Placeholder)

All heroines use the same Polygon2D system as the male heroes:
- **Distinctive color**: Slightly lighter tone or different hue vs their male counterpart
- **Hero ring**: Same golden ring (existing code)
- **Size**: Same as their civ's male hero
- **Animation**: Reuse the procedural body rotation from `unit_base.gd`

---

## Testing Checklist

- [ ] All 8 heroines are selected randomly (verify 50/50 over 100 matches)
- [ ] Each ability works correctly in isolation
- [ ] Abilities do not cause crashes if the hero dies mid-cast
- [ ] Regicide mode works with heroines (death = defeat)
- [ ] Cooldowns are displayed correctly in the UI
- [ ] Ability visual effects are visible
- [ ] Audio feedback for each ability (EventBus event)
- [ ] SaveManager serializes/deserializes heroines correctly
- [ ] AI does not crash when the enemy has a heroine

---

## Implementation Roadmap

### Phase 1: Infrastructure (1-2 hours)
1. Add `HERO_FEMALE_MAP` to `game_world.gd`
2. Modify `_spawn_hero()` for random selection
3. Add new `Ability` enums to `hero_unit.gd`
4. Extend `ABILITY_MAP` with new IDs

### Phase 2: Resources (2-3 hours)
5. Create 8 `.tres` files with base stats
6. Configure `hero_ability_id` for each heroine

### Phase 3: Abilities Implementation (6-8 hours)
7. Implement each ability in `hero_unit.gd`:
   - `_use_mountain_voice()`
   - `_use_fates_arrow(target: Node)`
   - `_use_sandstorm()`
   - `_use_honor_duel(target: Node)`
   - `_use_boarding_action(direction: Vector2)`
   - `_use_call_to_arms()`
   - `_use_rising_tide()`
   - `_use_mercenary_pact(target: Node)`

### Phase 4: UI Integration (1-2 hours)
8. Add tooltips for the new abilities
9. Update `hud_manager.gd` to show heroine abilities

### Phase 5: Testing & Balance (3-4 hours)
10. Playtest each heroine in real combat
11. Adjust cooldowns/numbers if needed
12. Verify interactions with weather/techs

---

## Total Estimate: **13-19 hours of development**

**Priority**: High - adds significant strategic variety and replayability.

**Impact on AAA Score**: +0.5 points (from 7.5 to 8.0) - demonstrates content depth and character design.
