# Game Design Document — Calima: Flames of the Atlantic

## Vision

A real-time strategy game inspired by Age of Empires II, set in the Atlantic archipelago of the Canary Islands across the 15th and 16th centuries. The player commands one of eight civilizations — from ancient seafarers and native islanders to European conquerors — across volcanic islands, ocean straits, and desert coasts.

Single-player skirmish against AI is the initial scope. LAN multiplayer is planned for a later milestone.

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
| **Food** | Farms, hunting, fishing (ocean), foraging | Unit training |
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
| 1 | **Feudal Age** | Barracks, Archery Range, Blacksmith, Stable (HeavyScout), Market |
| 2 | **Castle Age** | Castle, University, Siege Workshop, Stable (Knight), additional Town Center (buildable), unique units, advanced tech |
| 3 | **Imperial Age** | Full tech tree, elite unique units |

Advancing requires spending Food and Gold at the Town Center. Each civ may have bonuses that alter advancement cost or speed.

---

## Civilizations

Eight civilizations across three historical layers. See `civilizations.md` for full details.

| Layer | Civilization | Identity |
|---|---|---|
| Ancient | **Atlantes** | Naval masters, coastal builders, fog of war |
| Ancient | **Fenicios** | Commerce, mercenaries, trade routes |
| Native | **Guanches** | Volcanic terrain, durable infantry, stone fortresses |
| Native | **Canarii** | Economy, balanced archers, elevated terrain bonus |
| Native | **Mahos** | Speed, desert terrain, minimal wood dependency |
| Invader | **Francos** | Fast advancement, organized cavalry, early pressure |
| Invader | **Britanos** | Naval power, long-range archers, raiding economy |
| Invader | **Castellanos** | Superior late-game technology, heavy infantry, towers |

---

## Heroes

Each civilization has one named hero unit. Heroes are unique — they spawn once at game start, cannot be retrained, and carry a special ability. See `civilizations.md` for each hero's name and ability.

Hero rules:
- Spawn near Town Center at Dark Age
- Cannot be trained or rebuilt if lost
- Stats equivalent to a Castle Age unique unit
- One special ability with 45–60s cooldown

---

## Map Types

| Map | Description | Strategic focus |
|---|---|---|
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
| Malpaís (volcanic rock) | -50% | No | Guanches immune; not buildable |
| Lava-cooled black sand | Normal | No | Coastal/decorative |
| Laurisilva (dense forest) | -30% | No | High wood yield, reduces vision |
| Risco (cliff edge) | No passage | No | Units on top: +2 attack range |
| Shallow water | -40% (land units) | No | Atlantes immune |
| Ocean | Land units blocked | No | Ships only; fishing available |
| Caldera (active) | Impassable | No | Control adjacent zone → +stone/min |

### Impassability enforcement

`TerrainManager.is_impassable_for(world_pos, civ_id)` is the runtime gate. All unit movement orders resolve the final destination through `TerrainManager.nearest_passable` before assigning a nav agent target. If a requested position is inside an impassable zone the unit is redirected to the nearest reachable tile via a 30-ring radial search (24 px per ring).

NavMesh carving (`MapGenerator._add_nav_obstacles`) backs this up at the mesh level: malpaís, risco, and caldera zones become `NavigationObstacle2D` nodes, and on Islands maps the nav polygon is replaced with per-island land polygons so the baked mesh never extends over ocean.

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
| **Transport Ship** | Feudal | 125W | — | — | — | Boards military units (Militia, Archer, Pikeman, Scout, Hero); Villagers blocked |
| **War Galley** | Feudal | 75W + 35G | 120 | 6 | 5.5 | Ranged naval combat |

## Siege Units

Produced at the **Siege Workshop** (Castle Age, 200 Wood).

| Unit | Age | Cost | HP | Attack | Range | Notes |
|---|---|---|---|---|---|---|
| **Battering Ram** | Castle | 160W | 180 | 40 (x3 vs buildings) | Melee | Auto-attacks buildings only; 0.2x damage vs units |
| **Mangonel** | Castle | 160W + 135G | 90 | 35 | 7 | AoE 72 px splash; minimum range (35 % of max) |
| **Trebuchet** | Imperial | 200W + 200G | 70 | 200 | 12 | AoE 48 px splash; must deploy (3 s) before firing; auto-undeploys on move orders; minimum range (40 % of max) |

---

## Win Conditions

- **Conquest**: destroy all enemy Town Centers and military production buildings
- **Wonder**: build a Wonder and defend it for 200 in-game years
- **Relics**: collect all map relics and hold them for 200 in-game years

---

## Match Configuration (Lobby)

Players configure a skirmish before starting:

| Option | Values |
|---|---|
| Map Size | Small / Medium / Large |
| Map Type | Standard / Volcanic Coast / Desert Coast / Islands |
| Starting Resources | Scarce / Normal / Abundant / Full Combat (all resources 9999) |
| Civilization | Choose from 8 civs |
| Starting Age | Dark / Feudal / Castle / Imperial |

---

## Milestones

| Milestone | Description | Status |
|---|---|---|
| M1 | Playable map with villagers gathering resources | Done |
| M2 | Town Center, Barracks, walls, basic military | Done |
| M3 | Full tech tree, naval gameplay, Islands map, 8 civilizations; Blacksmith / University / Temple / Market / Stable / Siege Workshop / TownCenterBuildable buildings; HeavyScout and Knight cavalry units; BatteringRam / Mangonel / Trebuchet siege units; 17 technologies; HUD action grid 5×2 with pagination | In progress |
| M4 | AI opponent with naval assault on Islands | Done |
| M5 | All 8 civilizations with unique content and hero units | Planned |
| M6 | Custom terrain tiles (malpaís, dune, risco, laurisilva) | Planned |
| M7 | All map types with generators | Planned |
| M8 | Multiplayer (LAN) | Planned |
