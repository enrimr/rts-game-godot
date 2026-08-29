# Map Generation

> **Source files:** `project/scripts/map/map_generator.gd` ·
> `terrain_painter.gd` · `terrain_detail.gd` · `map_materials.gd` ·
> `entity_placer.gd` · `resource_visuals.gd` · `nav_mesh_builder.gd` ·
> `project/scripts/core/terrain_manager.gd`
>
> **Keep in sync:** update this document whenever any of those files changes.

---

## Module layout

`MapGenerator` only sequences the pipeline (~150 lines). The work lives in
`RefCounted` modules it owns, each wired through an explicit `setup(...)` call so
there is no back-reference to the generator:

| Module | Responsibility |
|---|---|
| `MapMaterials` | Shared shader materials (terrain per type, deep/shallow water, lava) + the terrain colour table and `STAIN_TILE` grid |
| `TerrainDetail` | Tile-dithered ground decals and per-biome detail variants (grass/dune/malpaís/risco/laurisilva/caldera) |
| `TerrainPainter` | Backgrounds, per-map-type zone layouts, zone visuals, shorelines, island polygons; owns `MapMaterials` + `TerrainDetail` |
| `EntityPlacer` | Occupancy grid (spatial hash) and every spawn: TC ring, starting units, animals, resources, laurisilva forests, fish, islets |
| `ResourceVisuals` | Static art library for resource nodes (also used by `SaveManager` when restoring a save and by `ResourceNode` for stumps) |
| `NavMeshBuilder` | Land/ocean `NavigationPolygon` carving, zone obstacles, ocean boundary walls |

All modules receive the **same** `RandomNumberGenerator` instance, so a given
seed always produces the same map regardless of how the code is split.
`project/tools/check_map_gen.tscn` prints a deterministic census (TC positions,
zone checksum, per-type resource counts/amounts, animals, nav polygon counts, RNG
state) and is the regression gate for changes here — capture it before a change,
diff it after.

Two more headless harnesses cover the Islands map specifically:

| Harness | Checks |
|---|---|
| `project/tools/check_islands_layout.tscn` | Island polygons don't overlap, keep a channel ≥ 120 px and stay inside the boundary; both nav meshes are non-empty; a ship spawning at the dock sits on the ocean mesh and can sail to a rival island. Env: `CALIMA_RIVALS`, `CALIMA_MAP_SIZE`, `CALIMA_SEED` |
| `project/tools/check_nav_islands.tscn` | The runtime navmesh rebake (`WorldPlacement`) neither opens a land route across open sea nor wipes the ocean mesh. Env: `CALIMA_MAP`, `CALIMA_SEED` |

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
1. Town-center positions (TC ring) + footprint registration
2. Terrain background & zones            (TerrainPainter)
3. Animals                               (EntityPlacer)
4. Player resources (per-TC)             (EntityPlacer)
5. Neutral + scattered resources         (EntityPlacer)
6. Laurisilva forests                    (EntityPlacer)
7. Navigation meshes, obstacles, walls   (NavMeshBuilder)
8. Minimap texture bake                  (TerrainManager)
```

Town centers are placed and registered *first* so the occupancy grid rejects any
later spawn that would land on a starting base.

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

For every map type except Islands, town centers are placed with `EntityPlacer.place_tc_ring()`:

- N positions are distributed evenly around a circle of radius `_map_half * 0.48`.
- The ring starts at a random angle so no player has a fixed compass advantage.
- Each TC receives a random jitter of ±7 % of `_map_half` in both axes.
- For 2 players this reproduces the classic face-to-face layout; for 3 a triangle; for 4 a square.

On Islands maps each TC is placed near the centre of its own island (±60 px random offset).

### Island ring layout

`MapGenerator._island_layout(player_count)` solves the island radius and the ring
distance instead of taking a fixed share of the map. Islands used to be sized at
`_map_half * 0.30` for 3+ players, which on a small 4-player map made neighbours
overlap: they merged into a single land mass *and* broke the ocean nav mesh.

The solver pushes the ring as far out as the boundary allows (that buys the
largest radius) and then sizes the radius so the worst case still fits:

```
ring   = map_half - ISLAND_SHORE_MARGIN - ISLAND_CENTER_JITTER - radius * ISLAND_BLOB_MAX
2 * ring * sin(PI / n) >= 2 * radius * ISLAND_BLOB_MAX + 2 * ISLAND_CENTER_JITTER + ISLAND_CHANNEL
```

| Constant | Value | Meaning |
|---|---|---|
| `ISLAND_BLOB_MAX` | 1.22 | Worst-case radial factor of `TerrainPainter.make_island_poly()` — a "radius r" island actually bulges to `r * 1.22` |
| `ISLAND_CHANNEL` | 200 px | Open water kept between neighbouring islands (the transport lane) |
| `ISLAND_SHORE_MARGIN` | 80 px | Open water kept between an island and the map boundary the ocean mesh is cut to |
| `ISLAND_CENTER_JITTER` | 20 px | Random offset applied to each island centre |

The radius is clamped to `[map_half * 0.16, map_half * 0.38]` (0.30 for 3+
players) so a duel map keeps its generous island and a crowded map still gets
real land rather than token islets. Above the lobby's 4-player cap the floor
takes over from the channel constraint; islands shrink but never touch.

Resource islets (`EntityPlacer.spawn_resource_islets()`) obey the same rule with
`ISLET_CHANNEL` (160 px): a candidate outside `map_half - islet_extent -
ISLET_CHANNEL`, or too close to an existing land polygon, is **rejected** instead
of clamped back inside — clamping is what used to push islets into the islands.

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

After zones are registered in `TerrainManager`, `TerrainPainter.flush_zone_visuals()` iterates them
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

`EntityPlacer.spawn_scattered_resources()` runs after neutral resources on all non-Islands maps.
Deposits are placed at **random positions across the full map**, with a 500 px minimum distance from any TC.
This ensures the mid-map and map edges are not empty.

| Resource | Groups placed | Nodes per group |
|---|---|---|
| Gold deposits | ~3 × res_mult | 4–7 |
| Stone deposits | ~2 × res_mult | 4–6 |
| Forest zones | ~6 × res_mult | size variant randomly chosen |

After the random scatter, an **edge pass** places 8 evenly-distributed groups around the map perimeter (75–95 % of `_map_half`), alternating forest → gold → forest → stone. This fills corners and edges that the random scatter might miss.

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

`EntityPlacer._find_free_arc()` and `_find_free_near()` attempt up to `MAX_PLACE_TRIES` (30) random
positions before giving up. Forest zones use `count × 12` attempts.

---

## Navigation meshes

Carved by `NavMeshBuilder.build(parent, map_half, land_polys)`. Two
`NavigationRegion2D` nodes live in the scene:

| Node | Navigation layer | Used by |
|---|---|---|
| `NavigationRegion2D` | Layer 1 | Land units |
| `OceanNavigationRegion2D` | Layer 2 | Ships |

On Islands maps both meshes are rebuilt from the procedural land polygons by
`NavMeshBuilder._bake()`, which feeds a `NavigationMeshSourceGeometryData2D` to
`NavigationServer2D.bake_from_source_geometry_data()`:

- **Land mesh** — the island polygons as *traversable* outlines, no obstructions.
- **Ocean mesh** — the full-map square as the traversable outline and every island polygon as an *obstruction*, so ships navigate everywhere except land.

The baker replaces the earlier `NavigationPolygon.make_polygons_from_outlines()`
call, which is deprecated **and** fails its convex partition whenever two source
outlines touch or overlap: two islands close together produced an ocean mesh with
zero polygons, which froze every ship on the map (a unit whose start position is
off-mesh never receives a path). The baked meshes keep no source outlines, so the
census and the harnesses report *polygon* counts instead. `_bake()` keeps the
scene's `agent_radius`/`cell_size` and, if a bake ever comes back empty, leaves
the existing mesh in place and pushes a warning rather than blanking the region.

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
