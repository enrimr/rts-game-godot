# Game Design Document — Calima Kingdoms: Flames of the Atlantic

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
| 1 | **Feudal Age** | Barracks, Archery Range, Blacksmith |
| 2 | **Castle Age** | Castle, unique units, advanced tech |
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
| **Single Island** | Land surrounded by ocean | Central control, no naval escape |
| **Archipelago** | 2–3 islands, naval routes between them | Fleet required for expansion |
| **Volcanic Coast** | Coastal land with impassable caldera at center | Two land corridors, Guanches advantaged |
| **Desert Coast** | Arid Lanzarote-style map, ocean to the west | Wood-scarce, Mahos advantaged |

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
| **Fishing Boat** | Dark | 75W | — | — | — | Gathers FOOD_FISH from ocean nodes; returns food to Dock |
| **Transport Ship** | Feudal | 125W | — | — | — | Ocean movement only; no combat (garrison system, future milestone) |
| **War Galley** | Feudal | 75W + 35G | 120 | 6 | 5.5 | Ranged naval combat |

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
| Starting Resources | Scarce / Normal / Abundant |
| Civilization | Choose from 8 civs |
| Starting Age | Dark / Feudal / Castle / Imperial |

---

## Milestones

| Milestone | Description | Status |
|---|---|---|
| M1 | Playable map with villagers gathering resources | Done |
| M2 | Town Center, Barracks, walls, basic military | Done |
| M3 | Full tech tree for one civilization | In progress |
| M4 | AI opponent | Done |
| M5 | All 8 civilizations with unique content | Planned |
| M6 | Hero units for each civilization | Planned |
| M7 | Custom terrain tiles (malpaís, dune, risco, laurisilva) | Planned |
| M8 | All 4 map types with generators | Planned |
| M9 | Multiplayer (LAN) | Planned |
