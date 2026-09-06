# Game Design Document — Calima: Flames of the Atlantic

## Vision

A real-time strategy game inspired by Age of Empires II, set in the Atlantic archipelago of the Canary Islands across the 15th and 16th centuries. The player commands one of eight civilizations — from ancient seafarers and native islanders to European conquerors — across volcanic islands, ocean straits, and desert coasts.

The shipped scope covers single-player skirmish against up to 3 AI rivals (with teams), a four-mission campaign with a tutorial prologue (*The Flames of Tamarán*), LAN/Internet multiplayer for up to 4 players (host-authoritative, with reconnection and save/resume), and a replay system with video export.

---

## Setting

The Canary Islands (Islas Canarias) sit in the eastern Atlantic, 100 km off the coast of northwest Africa. They were the first Atlantic archipelago to be contested between European powers and indigenous populations, making them a natural crossroads for the age of exploration.

The game draws from three historical and mythological layers:

- **Ancient** — Phoenician and Carthaginian expeditions documented the islands centuries before the medieval conquest. The Atlantis myth, placed by Greek writers near the Pillars of Hercules, gives license for one fantastical civilization.
- **Native** — Three distinct native civilizations (Guanches, Canarii, Mahos) inhabited different islands, each with unique terrain advantages and cultures.
- **European** — Three invading powers (Francos, Britanos, Castellanos) arrived at different moments with different motivations: colonization, piracy, and conquest.

---

## Core Loop

1. Gather resources (Food, Wood, Gold, Stone)
2. Build a base and train an army
3. Research technologies to upgrade units
4. Advance through the Ages
5. Defeat the enemy

---

## Resources

| Resource | Sources | Primary use |
|---|---|---|
| **Food** | Farms, hunting, fishing (ocean), foraging, herded livestock (a Presa Canario dog, trained at the Mill, leads animals to the nearest own drop-off — enemy sheep convert on the way) | Unit training |
| **Food (Fish)** | Ocean fish nodes (`FOOD_FISH`); gathered by Fishing Boats | Unit training — same stockpile as Food |
| **Wood** | Trees, Laurisilva forest | Buildings, ships, archers |
| **Gold** | Gold mines, trade, hero abilities | Military upgrades, mercenaries |
| **Stone** | Quarries, volcanic deposits near calderas | Castles, towers, walls |

`FOOD_FISH` is a distinct `ResourceNode.ResourceType` enum value. Fish nodes spawn in the ocean between the two islands on Islands-type maps. Fishing Boats are the only unit that can gather from them.

---

## Age Progression

| Age | Name | Unlocks |
|---|---|---|
| 0 | **Dark Age** | Town Center, Houses, basic economy |
| 1 | **Feudal Age** | Barracks, Archery Range, Blacksmith, Stable (HeavyScout), Market (Fenicios: from Dark Age) |
| 2 | **Castle Age** | Castle, University, Siege Workshop, Stable (Knight), additional Town Center (buildable), unique units, advanced tech |
| 3 | **Imperial Age** | Full tech tree, elite unique units |

Advancing requires spending Food and Gold at the Town Center. Each civ may have bonuses that alter advancement cost or speed.

---

## Civilizations

Eight civilizations across three historical layers. See `civilizations_en.md` / `civilizations_es.md` for full details.

| Layer | Civilization | Identity |
|---|---|---|
| Ancient | **Atlantes** | Naval masters, coastal builders, fog of war (+50 % vision along their shores, harder to spot in Sea Fog), amphibious Tidecaller that walks into the sea |
| Ancient | **Fenicios** | Commerce, mercenaries, trade routes |
| Native | **Guanches** | Volcanic terrain, durable infantry, stone fortresses |
| Native | **Canarii** | Economy, balanced archers, elevated terrain bonus |
| Native | **Mahos** | Speed, desert terrain, minimal wood dependency |
| Invader | **Francos** | Fast advancement, organized cavalry, early pressure |
| Invader | **Britanos** | Naval power, long-range archers, raiding economy |
| Invader | **Castellanos** | Superior late-game technology, heavy infantry, towers |

---

## Heroes

Each civilization has a **hero pair** — one male and one female named hero (16 total), selected in the lobby (`MatchConfig.hero_gender`: Random / Male / Female). Heroes are unique — they spawn once at game start and carry a special ability. See `civilizations_en.md` and `heroines-design.md` for each hero's name and ability.

Hero rules:
- Spawn near the Town Center at match start
- Cannot be trained; if killed, the hero respawns at the Town Center after 120 s (`HERO_RESPAWN_TIME`) — except in Regicide, where hero death is immediate defeat
- Stats equivalent to a Castle Age unique unit
- One special ability with a 45–120 s cooldown (audited: `tests/unit/test_hero_abilities.gd` casts all 16)

---

## Map Types

| Map | Description | Strategic focus |
|---|---|---|
| **Plains** | Flat land, no special terrain | Beginner-friendly |
| **Standard** | Land map with varied terrain | General play |
| **Volcanic Coast** | Coastal land with impassable caldera at center | Two land corridors, Guanches advantaged |
| **Desert Coast** | Arid Lanzarote-style map, ocean to the west | Wood-scarce, Mahos advantaged |
| **Islands** | Two islands separated by ocean | Naval required; Dock, Fishing Boats, Transport Ships, War Galleys essential |

---

## Terrain Tiles

| Tile | Movement | Buildable | Special effect |
|---|---|---|---|
| Grass | Normal | Yes | — |
| Sand / Dune | -20% infantry (heavy) | Yes | Mahos immune to penalty |
| Malpaís (volcanic rock) | Impassable (carved out of the navmesh) | No | Guanches traverse it via the layer-8 malpaís mesh |
| Lava-cooled black sand | Normal | No | Coastal/decorative |
| Laurisilva (dense forest) | -35% | No | High wood yield (dense 260-wood forests), vision −30% under the canopy |
| Risco (cliff edge) | No passage | No | Ranged units within 48 px of the cliff edge: +2 attack range |
| Shallow water (ocean ≤120 px from coast) | Land units blocked; amphibious full speed | No | Only the Atlantes Tidecaller wades — the rest of their army stays dry |
| Ocean | Land units blocked | No | Ships and amphibious units; the Tidecaller swims at 60% speed (`deep_water_speed`); fishing available |
| Caldera (active) | Impassable | No | Volcanic Ash weather strikes within caldera radius + 800 px |

### Impassability enforcement

`TerrainManager.is_impassable_for(world_pos, civ_id, amphibious)` is the runtime gate. All unit movement orders resolve the final destination through `TerrainManager.nearest_passable` before assigning a nav agent target. If a requested position is inside an impassable zone the unit is redirected to the nearest reachable tile via a 30-ring radial search (24 px per ring). The `amphibious` argument comes from the unit itself (`UnitBase.is_amphibious()`), so water is opened per unit and not per civilization: an Atlantes militia is refused the sea, its Tidecaller is not.

NavMesh carving (`NavMeshBuilder.build`) backs this up at the mesh level: malpaís, risco, and caldera zones are carved out of the baked meshes (`zone_obstructions`), so paths route around them; a fourth mesh (layer 8) leaves malpaís walkable for traversal civs. On Islands maps the nav polygon is replaced with per-island land polygons so the baked mesh never extends over ocean. Amphibious units walk the layer-4 mesh that spans land and water.

---

## Naval Units

Naval units extend `ShipBase`, which extends `UnitBase`. Ocean terrain is passable for all ships.

### Dock

| Property | Value |
|---|---|
| Cost | 150 Wood |
| HP | 1,800 |
| Build time | 45 s |
| Train queue cap | 5 |
| Placement constraint | Must be adjacent to water (coastal placement only) |
| HUD key | D |

The Dock is the sole production building for naval units. Fishing Boats automatically drop off fish resources at the nearest friendly Dock.

### Naval unit roster

| Unit | Age | Cost | HP | Attack | Range | Role |
|---|---|---|---|---|---|---|
| **Fishing Boat** | Dark | 75W | — | — | — | Gathers FOOD_FISH from ocean nodes; returns food to Dock; can build Fish Traps |
| **Transport Ship** | Feudal | 125W | — | — | — | Carries up to 8 land units (villagers included); ships and fishing boats may not board; unloads on dry land |
| **War Galley** | Feudal | 75W + 35G | 120 | 6 | 5.5 | Ranged naval combat |

## Siege Units

Produced at the **Siege Workshop** (Castle Age, 200 Wood).

| Unit | Age | Cost | HP | Attack | Range | Notes |
|---|---|---|---|---|---|---|
| **Battering Ram** | Castle | 160W | 180 | 40 (x3 vs buildings) | Melee | Auto-attacks buildings only; 0.2x damage vs units |
| **Mangonel** | Castle | 160W + 135G | 90 | 35 | 7 | AoE 72 px splash; minimum range (35 % of max) |
| **Trebuchet** | Imperial | 200W + 200G | 70 | 200 | 12 | AoE 48 px splash; must deploy (3 s) before firing; auto-undeploys on move orders; minimum range (40 % of max) |

---

## Technology Tree

32 technologies across 8 research buildings (Blacksmith, University, Temple, Barracks, Stable, Lumber Camp, Mining Camp, Mill). Technologies provide permanent stat bonuses to units/buildings. Each research building runs one active tech plus a waiting queue — up to 5 techs in flight per building, paid at enqueue and fully refunded on cancel.

### Blacksmith (13 technologies)

| Tech | Age | Cost | Time | Effect |
|---|---|---|---|---|
| **Loom** | Dark | 50f | 25s | Villager HP ×1.15 |
| **Forging** | Feudal | 75f | 40s | Unit attack ×1.15 |
| **Scale Barding** | Feudal | 100f+50g | 40s | Unit melee armour +1 |
| **Padded Archer Armour** | Feudal | 100f | 35s | Archer pierce armour +1 |
| **Fletching** | Feudal | 100g | 35s | Archer attack ×1.20 |
| **Shipwright** | Feudal | 200w+60g | 40s | Ship HP ×1.15, cost −15% |
| **Canarian Cart** (`carreta_canaria`) | Feudal | 150f+75w | 40s | Villager carry capacity +25% (farms deposit instantly, unaffected) |
| **Iron Casting** | Castle | 150g | 55s | Unit attack ×1.20 (requires Forging) |
| **Island Handcart** (`carreton_isleno`) | Castle | 200f+125w | 55s | Villager carry capacity +25% again (requires Canarian Cart) |
| **Chain Barding** | Castle | 200f+100g | 45s | Unit melee armour +1 (requires Scale Barding) |
| **Bodkin Arrow** | Castle | 100f+150g | 35s | Archer attack ×1.20, range ×1.10 (requires Fletching) |
| **Blast Furnace** | Imperial | 275f+225g | 50s | Unit attack ×1.15 |
| **Plate Barding** | Imperial | 300f+200g | 60s | Unit melee armour +1 (requires Chain Barding) |

### University (3 technologies)

Castle Age building (200 wood). Researches advanced military upgrades.

| Tech | Age | Cost | Time | Effect |
|---|---|---|---|---|
| **Siege Engineering** | Castle | 200g | 60s | Damage vs buildings ×1.20 |
| **Ballistics** | Castle | 175g | 50s | Archer attack speed ×1.20 (requires Fletching) |
| **Chemistry** | Imperial | 300g | 70s | Archer attack ×1.15 (requires Ballistics) |

### Temple (3 technologies)

Castle Age building (175 wood). Researches morale and HP buffs. The Temple is also the field hospital — garrisoned units (capacity 5) heal 4 HP/s, heroes at half rate — and trains the **Harimaguada** priestess-healer (85 Food + 25 Gold, Castle Age): always female, never fights, mends allies at 5 HP/s in touch range and auto-triages nearby wounded while idle.

| Tech | Age | Cost | Time | Effect |
|---|---|---|---|---|
| **Fervor** | Castle | 150g | 50s | Unit move speed ×1.10 |
| **Sanctity** | Castle | 100f | 40s | Swordsman HP ×1.15 |
| **Atonement** | Imperial | 150f+100g | 55s | Cavalry HP ×1.20 (requires Sanctity) |

### Camp economy lines (9 technologies)

Each drop-off camp researches its own three-step line — one tech per age from Feudal, chained prerequisites. Every step multiplies that resource's villager gather rate by 1.15 and its carry basket by 1.10 (effect keys `villager_<res>_gather_rate` / `villager_<res>_carry`, stacked on the Blacksmith carts).

| Building (resource) | Feudal | Castle | Imperial |
|---|---|---|---|
| **Lumber Camp** (wood) | Double-Bit Axe — 100f+50w, 25s | Bow Saw — 150f+100w, 40s | Two-Man Saw — 300f+200w, 60s |
| **Mining Camp** (gold + stone) | Reinforced Picks — 100f+75w, 25s | Shaft Mining — 175f+100w, 40s | Deep Galleries — 300f+150w, 60s |
| **Mill** (food) | Horse Collar — 75f+75w, 25s | Heavy Plow — 125f+125w, 40s | Crop Rotation — 250f+250w, 60s |

### Unit Upgrade Technologies (4)

Researched at the building that trains the unit. Transforms all existing units of that type immediately (HP scaled proportionally), and the building trains the new unit going forward.

| Tech | Building | Age | Cost | Time | Transforms |
|---|---|---|---|---|---|
| **Man-at-Arms** | Barracks | Feudal | 100f+40g | 45s | Militia → Man-at-Arms |
| **Long Swordsman** | Barracks | Castle | 200f+60g | 45s | Man-at-Arms → Long Swordsman |
| **Heavy Scout** | Stable | Feudal | 150f+75g | 45s | Scout → Heavy Scout |
| **Knight** | Stable | Castle | 200f+100g | 45s | Heavy Scout → Knight |

### Civilization Instant Tech Grants

**Castellanos**: Receive one free Blacksmith technology each time they advance an Age. The game automatically grants the oldest unresearched Blacksmith tech available at the new Age (respecting prerequisites). Example: advancing to Feudal grants Loom or Forging for free.

---

## Weather System

Procedural weather events affect gameplay with stat modifiers and visual effects. Enabled/disabled and frequency configurable in lobby.

### Weather Types

| Weather | Map Restriction | Duration (peak) | Effects |
|---|---|---|---|
| **Calima** (Saharan dust) | All maps | 70-130s | Vision −40%, gather −20% (wood/food), move speed −15% |
| **Atlantic Storm** | All maps | 40-90s | Naval speed −30%, fishing −50%, projectile drift (30 px cross-wind) |
| **Sea Fog** | Coastal maps only | 60-120s | Coastal vision −60%, unit cloaking when in coastal zone (intensity ≥0.5) — broken at close range (180 px, 90 px for Atlantes) or by attacking (3 s) |
| **Trade Winds** | All maps | 100-160s | Naval speed ±20% (alignment with wind), projectile drift (40 px with wind) |
| **Volcanic Ash** | Volcanic Coast | 40-80s | Vision −50%, gather −30%, building HP drain (2/s), around calderas (caldera radius + 800 px) |

### Weather Phases

Each weather event has 3 phases:
1. **Ramp-in** (10 s): intensity 0.0 → 1.0
2. **Peak** (duration above): intensity = 1.0
3. **Ramp-out** (10 s): intensity 1.0 → 0.0
4. **Clear** (60-120 s): no weather, intensity = 0.0

### Weather Frequency Settings

- **Off**: No weather events
- **Normal**: Clear duration 60-120 s (baseline)
- **Frequent**: Clear duration ×0.6 (36-72 s)
- **Extreme**: Clear duration ×0.3 (18-36 s)

### Visual Effects

`WeatherOverlay` renders screen-space effects:
- **Rain** (Atlantic Storm): falling particles
- **Dust** (Calima): horizontal particles
- **Ash** (Volcanic Ash): falling grey particles
- **Wind** (Trade Winds): horizontal particles
- **Fog vignette** (Sea Fog): screen-edge darkening

---

## Victory Conditions

Three victory modes are implemented, selectable in the lobby:

- **Conquest**: A player is out when they have zero units and zero production buildings; the last mutually allied side standing wins.
- **Regicide**: Each player starts with a Hero. Hero death eliminates that player instantly (no respawn in this mode).
- **Wonder**: Build a Wonder (Imperial Age, costs 2500 wood + 2500 food + 2500 stone + 5000 gold) and defend it for `WONDER_COUNTDOWN_SEC` (240 s = 4 minutes). Destroying the Wonder cancels its countdown; the match continues.

**Elimination and spectating**: elimination emits `EventBus.player_eliminated`. If the local player is eliminated (or surrenders) while hostile sides remain, the match plays on — the defeat panel offers "View map" and the player spectates with orders locked (`GameWorld.local_player_defeated`); the definitive game-over rebuilds the panel. Teams: `GameManager.are_allied` is the single choke point for the win check.

---

## Match Configuration (Lobby)

Players configure a skirmish before starting:

| Option | Values |
|---|---|
| Map Size | Small / Medium / Large |
| Map Type | Plains / Standard / Volcanic Coast / Desert Coast / Islands |
| Starting Resources | Scarce / Normal / Abundant / Full Combat (all 9999) / Tutorial (320 wood only) |
| Player Civilization | Choose from 8 civs (Guanches, Canarii, Mahos, Franks, Britons, Castellanos, Atlantes, Fenicios) |
| Rival Count | 1-3 AI opponents (multiplayer: up to 4 players total, remaining seats Open / AI / Closed) |
| Rival Civilizations | Choose civ for each AI |
| Teams | Players and rivals assignable to teams 1-4 (`MatchConfig.player_teams`) |
| Starting Age | Dark / Feudal / Castle / Imperial |
| Victory Condition | Conquest / Regicide / Wonder |
| Weather Enabled | On / Off |
| Weather Frequency | Off / Normal / Frequent / Extreme |
| Hero Gender | Random / Male / Female |

---

## Milestones

| Milestone | Description | Status |
|---|---|---|
| M1 | Playable map with villagers gathering resources | ✅ Done |
| M2 | Town Center, Barracks, walls, basic military, fog of war | ✅ Done |
| M3 | Age progression (4 ages), tech tree (8 techs), new units (Archer, Pikeman) | ✅ Done |
| M4 | Naval gameplay (Dock, ships, Islands map, AI naval assault) | ✅ Done |
| M5 | **Production-ready single-player**: 8 civs with unique units/heroes, weather system, save/load, 3 victory conditions, polish & bug fixes | ✅ Done |
| M6 | Custom terrain (malpaís, dune, risco, laurisilva) with civ traversal bonuses and gameplay effects (laurisilva vision/wood, risco vantage, shallow water) | ✅ Done |
| M7 | Multiplayer: LAN/Internet host-authoritative sessions, unified lobby, state replication, robustness, chat, teams, reconnection, save/resume, Steam transport prototype | ✅ Done |
| M8 | Campaign mode: *The Flames of Tamarán* — tutorial prologue + 4 scripted missions | ✅ Done |
| M9 | Replays & creator kit: match recording, timeline playback, cinematic mode, video/clip export | ✅ Done |
| M10 | Lockstep determinism (movement off Godot physics), live Steam AppID test, balance pass | 📋 Planned |

### Current content totals

Verified against `project/resources/` and `project/scenes/` (2026-09-06):

- 8 civilizations (`resources/civilizations/*.tres`)
- 26 playable unit types (25 regular — 8 of them civ-unique — plus the hero class) and 16 named heroes (2 per civ, `resources/units/hero_*.tres`); 2 animal types
- 20 building types (`resources/buildings/*.tres`)
- 32 technologies (`resources/technologies/*.tres`; TechManager loads the directory)
- 5 map types, 3 sizes, 4 resource modes, 3 victory conditions, 5 weather types, 99 save slots
- Campaign: tutorial prologue + 4 missions (`CampaignData.MISSIONS`)
