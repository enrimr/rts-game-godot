# Map Generation

> **Source files:** `project/scripts/map/map_generator.gd` · `project/scripts/core/terrain_manager.gd`
>
> **Keep in sync:** update this document whenever either file changes.

---

## Overview

Map generation runs synchronously at match start before any unit is spawned.
It is triggered by a single static call:

```gdscript
MapGenerator.generate(parent, units_layer, rng)  # returns { tc_positions: Array[Vector2] }
```

The return value is a dictionary with one key — `tc_positions` — an array of
world-space coordinates, one per player (index 0 = human player, 1…N = AI rivals).

The whole pipeline runs inside `MapGenerator._run()` and follows a fixed order:

```
1. Terrain background & zones
2. Town-center positions (TC ring)
3. Navigation mesh update
4. Animals
5. Player resources (per-TC)
6. Neutral resources
7. Nav obstacles bake
8. Minimap texture bake
```

---

## Map types

Selected in the lobby via `MatchConfig.map_type` (`MatchConfig.MapType` enum).

| Type | Enum | Description |
|---|---|---|
| Plains | `PLAINS` | Flat green grass, no terrain zones — simplest map |
| Standard | `STANDARD` | Grass base with scattered terrain zones |
| Volcanic Coast | `VOLCANIC_COAST` | Central caldera + malpais bands |
| Desert Coast | `DESERT_COAST` | Full dune base with grass oases near TCs |
| Islands | `ISLANDS` | One land island per player surrounded by ocean |

---

## Map sizes

Set via `MatchConfig.map_size`. Determines `_map_half` (world half-extent in pixels).

| Size | `_map_half` |
|---|---|
| Small | 1200 px |
| Medium | 1800 px |
| Large | 2600 px |

All distances in the generator are expressed as fractions of `_map_half` so they
scale automatically.

---

## TC placement

For every map type except Islands, town centers are placed with `_place_tc_ring()`:

- N positions are distributed evenly around a circle of radius `_map_half * 0.48`.
- The ring starts at a random angle so no player has a fixed compass advantage.
- Each TC receives a random jitter of ±7 % of `_map_half` in both axes.
- For 2 players this reproduces the classic face-to-face layout; for 3 a triangle; for 4 a square.

On Islands maps each TC is placed near the centre of its own island (±60 px random offset).

---

## Terrain zones

`TerrainManager` stores terrain as a list of circular zones:

```gdscript
{ center: Vector2, radius: float, type: TerrainType }
```

Zones are evaluated in **reverse insertion order** — the last zone added wins.
This means specific overrides (e.g. grass oases) should be added after the base zone.

### Terrain types

| Type | Passable | Effect |
|---|---|---|
| `GRASS` | Yes | No penalty (default) |
| `LAURISILVA` | Yes | Speed × 0.65; contains trees |
| `DUNE` | Yes | Speed × 0.80; Mahos immune |
| `MALPAIS` | No* | Impassable; Guanches immune |
| `RISCO` | No | Impassable; range bonus nearby |
| `OCEAN` | No* | Ships only; Atlantes slowed but not blocked |
| `CALDERA` | No | Impassable |

*Civ immunity overrides passability — see `TerrainManager.get_speed_mult()`.

### Zone counts per map type

**Standard:**
- 3 laurisilva patches (radius 6–14 % of map half)
- 2 malpais blobs (8–18 %)
- 2 dune patches (7–15 %)
- 4 risco clusters (3–7 %)

**Volcanic Coast:**
- 1 central caldera (radius 16 %)
- 4 malpais rings around caldera (6–12 %, distributed at 90° intervals)
- 4 risco clusters (3–7 %)
- 2 laurisilva patches on northern half (8–15 %)

**Desert Coast:**
- 1 full-map dune zone (base layer)
- 2 grass oases near player starting positions (18 %)
- 3 risco ridges on east edge (4–9 %)

**Islands (per island):**
- 1–2 laurisilva patches near centre (12–22 % of island radius)
- 1 malpais or risco on the coastal edge (8–15 %)

---

## Visual painting

After zones are registered in `TerrainManager`, `_flush_terrain_zones_visual()` iterates them
and creates Polygon2D scene-tree nodes for each:

| Zone type | Nodes created |
|---|---|
| Laurisilva | 1 base circle + 3 batched canopy Polygon2D (10–16 trees per zone) |
| Risco | 1 base circle + 2 batched rock Polygon2D (light/dark shard groups) |
| Malpais | 1 base circle + 1 batched fragment Polygon2D |
| Caldera | 2 base circles (outer red + inner black) + 3–5 Line2D lava cracks |
| Other | 1 circle Polygon2D |

All terrain nodes use `z_index` between −9 and −6 so they render below units and buildings.

Trees are batched: all canopy polygons of the same colour group inside one zone are
concatenated into a single `Polygon2D` (sub-polygons separated by a degenerate bridge edge).
This keeps the scene-tree node count low regardless of tree density.

---

## Resource spawning

### Per-player resources (land maps)

Called once per TC with an angle offset so deposits face outward.
Forest zones use **tight packing** (`FOREST_NODE_RADIUS = 13 px`) with random size variants.

| Resource | Count | Distance from TC |
|---|---|---|
| Gold deposit | 5 nodes | 320–480 px |
| Stone deposit | 5 nodes | 360–530 px |
| Forest zones | 8 zones (size variant chosen randomly) | 160–500 px |
| Hunting food | 2 deposits of 3 nodes | 160–300 px |

### Forest size variants

Applied to player, neutral, and scattered forests. Tight packing removes large gaps that block units.

| Variant | Tree count | Zone radius |
|---|---|---|
| Small | 12–18 | 50 px |
| Medium | 22–30 | 75 px |
| Large | 35–45 | 105 px |

### Per-player resources (Islands)

Distances are clamped to 65 % of island radius to keep deposits on land.

| Resource | Count |
|---|---|
| Gold deposit | 4 nodes |
| Stone deposit | 4 nodes |
| Forest zones | 6–8 zones (size variant randomly chosen) |
| Hunting food | 1 deposit of 3 nodes |

### Neutral resources (land maps)

Placed around map centre regardless of TC positions.

| Resource | Count | Distance from centre |
|---|---|---|
| Gold deposits | 2 × 6 nodes | 400–700 px |
| Stone deposits | 2 × 5 nodes | 450–720 px |
| Forest zones | 7 zones (size variant randomly chosen) | 250–700 px |

### Scattered resources (land maps)

`_spawn_scattered_resources()` runs after neutral resources on all non-Islands maps.
Deposits are placed at **random positions across the full map**, with a 500 px minimum distance from any TC.
This ensures the mid-map and map edges are not empty.

| Resource | Groups placed | Nodes per group |
|---|---|---|
| Gold deposits | ~3 × res_mult | 4–7 |
| Stone deposits | ~2 × res_mult | 4–6 |
| Forest zones | ~6 × res_mult | size variant randomly chosen |

### Islands-only resources

- **Fish banks** (`FOOD_FISH`): ~8 × player_count × 0.75 nodes scattered in ocean around the map centre, between 0.5× and 2× island radius.
- **Resource islets**: 3–4 small procedural land polygons in open ocean. Each islet carries one random template from: `[Gold]`, `[Wood+Stone]`, `[Stone]`, `[Wood]`, `[Gold+Stone]`.

---

## Placement collision system

All objects (TCs, units, animals, resource nodes) are registered in a spatial hash before placement.
A candidate position is accepted only if its required clearance radius does not overlap any
already-registered object.

### Clearance radii

| Object | Radius |
|---|---|
| Town center | 130 px |
| Unit | 22 px |
| Animal | 28 px |
| Wood node | 22 px |
| Other resource | 30 px |

### Spatial hash

Objects are indexed into a grid of 140 px cells (`SPATIAL_CELL`).
Collision checks scan only the 3×3 neighbourhood of cells around the candidate point,
making each check O(1) amortised instead of O(n).

`_find_free_arc()` and `_find_free_near()` attempt up to `MAX_PLACE_TRIES` (30) random
positions before giving up. Forest zones use `count × 12` attempts.

---

## Navigation meshes

Two `NavigationRegion2D` nodes live in the scene:

| Node | Navigation layer | Used by |
|---|---|---|
| `NavigationRegion2D` | Layer 1 | Land units |
| `OceanNavigationRegion2D` | Layer 2 | Ships |

On Islands maps both meshes are rebuilt from the procedural land polygons:

- **Land mesh** — one CCW outline per island polygon; `make_polygons_from_outlines()` carves the walkable area.
- **Ocean mesh** — one CCW full-map square outline with each island polygon reversed (CW) as a hole, so ships navigate everywhere except land.

On other map types only the land mesh is used (ships are not trained on non-ocean maps).

After mesh creation, four thin `StaticBody2D` walls are placed just outside the map boundary on the ocean layer so ships cannot sail out of bounds.

Impassable terrain zones (Malpais, Risco, Caldera) are carved from the land nav mesh via
`NavigationObstacle2D` nodes sized to the zone radius.

---

## Minimap texture

`TerrainManager.bake_minimap_texture(map_half, 256)` samples a 256×256 grid.
For each pixel it evaluates terrain type using flat `PackedFloat32Array` zone data
(no Dictionary lookup) and uses `distance_squared` to avoid square-root calls.
The result is stored in `TerrainManager.minimap_texture` as an `ImageTexture`.
