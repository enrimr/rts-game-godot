# Calima: Flames of the Atlantic — CLAUDE.md

## Project Overview

An Age of Empires II inspired 2D real-time strategy game built in **Godot 4** with GDScript.

- **Engine**: Godot 4.6+
- **Language**: GDScript (no C#)
- **Genre**: 2D real-time strategy (top-down isometric-style)
- **Scope**: Single-player skirmish vs AI + campaign, 8 civilizations, LAN/Internet multiplayer (host-authoritative), replays

## Repository Layout

```
project/          ← Open this in Godot editor (contains project.godot)
  assets/         ← Art, audio, fonts, shaders
  scenes/         ← .tscn scene files
  scripts/        ← .gd source files
    core/         ← Singletons: GameManager, EventBus, ResourceManager, SelectionManager, CivBonusManager, TechManager
    units/        ← UnitBase, Villager, military unit classes
    buildings/    ← BuildingBase and specific building scripts
    economy/      ← ResourceNode, drop-off logic
    map/          ← MapGenerator + its modules (TerrainPainter, EntityPlacer,
                    NavMeshBuilder, MapMaterials, TerrainDetail, ResourceVisuals),
                    FogOfWar, PlacementGrid, terrain overlays
    combat/       ← Projectiles, damage calculation
    ai/           ← AIPlayer coordinator + AIConstruction, AIEconomy, AIMilitary, AINaval modules
    research/     ← TechTree, ResearchQueue
    ui/           ← HUD, menus, minimap
    multiplayer/  ← NetworkSession, StateReplicator, ReplayFile
    utils/        ← Shared helpers
  resources/      ← .tres/.res data files (CivilizationResource, UnitResource, etc.)
tests/            ← GUT unit and integration tests
docs/             ← Architecture and design documentation
```

## Core Architecture Principles

1. **EventBus pattern** — cross-system communication happens exclusively through signals on `EventBus` (autoload). Never call methods across system boundaries directly.
2. **Data-driven resources** — all tuneable values live in `Resource` subclasses under `resources/`. Scripts read from resources; they do not hardcode stats.
3. **Autoloads (singletons)**: `GameManager`, `EventBus`, `EntityRegistry`, `CommandBus`, `MatchRng`, `NetworkSession`, `ResourceManager`, `SelectionManager`, `CivBonusManager`, `TechManager`, `WeatherManager`, `AgeManager`, `AudioManager`, `TerrainManager`, `PopulationManager`, `SaveManager`, `GameSettings`, `MatchConfig`, `CampaignManager` — access these by name anywhere.
4. **Type hints everywhere** — every GDScript function must declare parameter types and return type.
5. **Area2D for range detection** — attack ranges use Area2D nodes that monitor for enemies entering/leaving range, avoiding per-frame physics queries.
6. **Outward spiral spawn positioning** — units spawn at free positions found via outward spiral physics query, preventing overlap.
8. **Collision layers** — layer 1 = world (buildings, scenery, boundary walls); layer 2 = units (all CharacterBody2D units/animals/ships). Units use `collision_layer=2, collision_mask=1`: they physically collide only with the world — RVO avoidance (not physics) separates units from each other, preventing group jams. Detection Area2Ds (attack range, gate, sheep conversion) and unit-seeking physics queries must include bit 2 in their mask. Locked by `test_collision_layers.gd`.
7. **Grid-snap placement** — the player's building/wall placement snaps to a 16 px grid via `PlacementGrid` (`scripts/map/placement_grid.gd`, pure/testable); units still move continuously. Hold **Alt** for free placement. AI placement is unchanged.
9. **Command pattern** — every simulation-mutating intent, player AND AI, is a `GameCommand` (serializable: EntityRegistry IDs + positions, never node pointers) submitted through `CommandBus.submit()`, which tick-stamps it into the match log (replay/LAN foundation) and executes it. UI feedback and selection stay at the submission site; AI decision-making stays in the AI modules, only its mutations cross the bus.
10. **MatchRng for simulation randomness** — anything random that affects game state (spawn jitter, animal wander, weather, projectile drift, AI position searches) draws from the `MatchRng` autoload, seeded once per match with the map seed. The global `randf()`/`randi()` are reserved for local-only audio/visual noise.

## Key Files

| File | Purpose |
|---|---|
| **Core Systems** ||
| `project/scripts/core/game_manager.gd` | Global game state, pause, game-over, victory conditions (Conquest/Regicide/Wonder) |
| `project/scripts/core/event_bus.gd` | All cross-system signals |
| `project/scripts/core/resource_manager.gd` | Per-player food/wood/gold/stone stockpiles, spatial resource cache |
| `project/scripts/core/selection_manager.gd` | Unit selection, control groups |
| `project/scripts/core/age_manager.gd` | Per-player Age tracking, age advance timer, cost multipliers |
| `project/scripts/core/civ_bonus_manager.gd` | Per-player multipliers for unit stats, gather rates, age-up costs, move speed, attack speed; archer range bonuses per age; per-civ weather resistance; per-resource carry baskets (`villager_<res>_carry`, stacked on `villager_carry_capacity`) |
| `project/scripts/core/tech_manager.gd` | Research per building (one active + AoE2-style queue, `MAX_RESEARCH_QUEUE` 5 in flight per building, paid at enqueue, promoted automatically), applies technology effects, 32 technologies total; start/finish/cancel emit research_state_changed (HUD queue slot), cancel_research and cancel_queued_research refund in full; a destroyed lab refunds its whole queue; `collect_state`/`restore_state` persist in-flight research across save/load (re-armed WITHOUT re-charging — keyed by the building's index in the saved array), `reset_match_state` drops stale cross-match research at match start without refund (called by `WorldSetup`) |
| `project/scripts/core/weather_manager.gd` | Procedural weather state machine (Calima, Atlantic Storm, Sea Fog, Trade Winds, Volcanic Ash); stat-modifier query API; `collect_state`/`apply_saved_state` persist the live state machine across save/load (phase, timers, wind — a forecast in progress re-warns on restore) |
| `project/scripts/core/population_manager.gd` | Per-player population current/cap tracking |
| `project/scripts/core/save_manager.gd` | Complete game save/load system, JSON-based, 99 save slots; `SCHEMA_VERSION` 2 read-enforced (saves NEWER than the build are refused with a reason, older ones load with defaults for new keys); v2 persists in-flight research (active + queues, keyed by building index in the saved array, re-armed without re-charging), garrisons (occupants nested under their building/transport record, restored back INSIDE), unit stances and the weather state machine; multiplayer saves add a roster sheet (`multiplayer` key: names/Steam IDs/civs/colours/teams per seat) and per-player explored fog (`fog_by_player`, gathered from clients via `NetworkSession.collect_client_fogs` — `save_game` is a coroutine, await it); `resume_sheet`/`resume_fog_b64` feed the resume lobby and resync, `cancel_pending` backs out of an abandoned resume |
| `project/scripts/core/match_config.gd` | Lobby settings (map size, resources, civs, victory mode, weather frequency) |
| `project/scripts/core/terrain_manager.gd` | Terrain type detection, coastal zone queries, terrain gameplay effects (laurisilva vision mult, risco vantage, shallow water); `get_speed_mult`/`is_impassable_for`/`nearest_passable` take an `amphibious` flag (ocean is opened by the unit, never by the civ), `deep_water_speed(civ_id)` reads the civ's `deep_water_speed` multiplier (default 0.60); `distance_to_coast` is analytic + memoized per 24 px cell (the weather/fog hot path — invalidate via `reset`/`add_zone`/`set_land_polys` only) |
| `project/scripts/core/audio_manager.gd` | Spatial audio playback, distance attenuation; ALL sfx/music are procedurally baked at startup (zero audio assets). Voices are formant-synthesized gibberish (glottal sawtooth → 3 two-pole vowel resonators + noise consonants): each CIV speaks its own deterministic "language" (`VOICE_CIV_POOLS` syllables + `VOICE_CIV_PITCH` accent) across class prosodies (`VOICE_KINDS`: selections ask, `ack_move`/`ack_attack` order confirmations affirm), per gender. `play_voice(id, female, civ_id)` resolves civ→gender→default with anti-repeat; siege stays mechanical. The ~460-clip cast bakes in parallel via `WorkerThreadPool.add_group_task` (skipped entirely in headless — `ensure_voices_ready()` bakes synchronously for tools/tests). Combat/gather sounds carry several takes via `_register_multi` (pool round-robin rotates them). Audition via `tools/check_voice_gallery.tscn` (env `CALIMA_CIVS`); full synthesis reference in `docs/architecture/audio_synthesis.md` |
| `project/scripts/core/game_settings.gd` | Difficulty, master volume, persisted settings; `unit_style` enum (`UnitStyle` CLASSIC 0 / ENHANCED 1 / REDESIGNED 2, default CLASSIC) with `unit_style_changed` signal for the live re-dress; legacy `enhanced_units` bool kept as an alias (maps to ENHANCED, old configs migrate on load) and `enhanced_units_changed` still fires; env overrides `CALIMA_UNIT_STYLE=0|1|2` (takes precedence) and `CALIMA_ENHANCED_UNITS=1` for tooling/perf runs |
| `project/scripts/core/command_bus.gd` | `CommandBus` autoload — single entry point for player intents: tick-stamped command log (replay/LAN foundation), `submit`/`command_from_dict`/`save_log`; bound per match via `start_match(world)` |
| `project/scripts/core/entity_registry.gd` | `EntityRegistry` autoload — stable per-match numeric IDs for units/buildings/resource nodes (tree-order rescan + spawn-signal registration), `id_of`/`resolve` |
| `project/scripts/core/match_rng.gd` | `MatchRng` autoload — the single seeded RNG stream for all simulation randomness; seeded per match by `GameWorld._ready`, mid-match state persisted by `SaveManager` (as String — 64-bit vs JSON doubles), global `randf()` reserved for local audio/visual noise |
| `project/scripts/multiplayer/network_session.gd` | `NetworkSession` autoload — host-authoritative LAN/Internet session over ENet: host/join/leave, peer→player map, lobby handshake (`snapshot_config`/`apply_config` + shared `MatchConfig.forced_seed` → identical worlds and entity IDs on every machine), client→host command pipe (`CommandBus.submit` redirects on clients; the host stamps the SENDER's player_id — the wire never decides identity — and brands the command `remote_origin` in `_rx_command`: privileged local-only verbs refuse wire-borne commands — AI `instant` placement, `EXTRA_SCENES`, `board_instant` — and every remote placement is re-validated host-side via `WorldPlacement.placement_legal`). Lobby roster (names/colours/civs) is host-authoritative; `lobby_slots` (Open/AI/Closed) + `open_seats_left()` gate joins; `start_match` derives `rival_civ_ids` (human civs then AI slots) and ships a `humans` list → `match_human_ids`/`is_human_player`. Human rivals get starting assets but no AI brain; AI-slot brains run ONLY on the host (`WorldSetup` gate). Version guard: `_tx_profile` carries `game_version()` (from `project.godot` `application/config/version`) and the host refuses mismatched builds with a reasoned dialog (`join_refused`). Tag releases ONLY with `scripts/release_tag.sh` — it bumps that setting, commits, tags and pushes in one step (auto-increments the patch keeping the suffix; `--dry-run`, `--skip-tests`, or an explicit version arg). Resume: `begin_resume(slot)` freezes the lobby onto a multiplayer save (seats reserved in `_vacant_seats`, claimed via the rejoin matcher; picks locked), `_start_resumed_match` ships the saved config with `resumed: true` — the match may start with absent players (their seat runs the rejoin grace) |
| `project/scripts/multiplayer/state_replicator.gd` | `StateReplicator` — phase-2 replication node (GameWorld adds it when online): host samples the sim at 15 Hz and streams unit pos/state/HP + building HP/state by entity id (spawns/removals/game-over reliable); the sampler streams only sim entities — nodes without a `health` property are skipped, because tower/archer arrows fly INSIDE the unit/building layers and used to crash the snapshot (null→float cast) and mint junk entity ids/spawn records (locked by `test_state_replicator_snapshot.gd`); clients puppet their mirror world (physics off, `_process` on) and interpolate, adopting host ids via `EntityRegistry.register_as`; stockpiles/pop/ages land through the managers' `apply_remote`. Resumed matches: the client boots the map but ZERO entities (`GameWorld._clear_generated_entities` — a restored host world shares no spawn baseline with a fresh one; only the scene TC survives, id 1 on both ends via the rescan) and `full_resync_to` ships everything as spawn records (kind `"r"` recreates resource nodes programmatically) plus that seat's saved fog (`"fog"`, zstd) |
| **Campaign** ||
| `project/scripts/campaign/campaign_data.gd` | `CampaignData` — the four Canarii missions as a const table: fixed seed + MatchConfig fields, victory kind (`conquest`/`regicide`/`survive`), side objectives (`train`/`build`/`destroy`/`herd` — herd counts `EventBus.animal_herded` dog trips completed home; mission 1 teaches Mill + herding), scripted waves |
| `project/scripts/campaign/campaign_manager.gd` | `CampaignManager` autoload — progress (user://campaign.cfg, chain-unlock), `launch_mission` writes the whole MatchConfig + `campaign_mission`; skirmish/MP starts reset the flag |
| `project/scripts/campaign/mission_director.gd` | `MissionDirector` — mounted by GameWorld when `campaign_mission >= 0` (single-player only): EventBus-driven objective checkmarks (HUD panel top-left), scripted wave spawns at the enemy TC (attack-move, no AI brain), survive countdown → `declare_winner(0)`, completion → CampaignManager |
| `project/scripts/ui/campaign_screen.gd` | `CampaignScreen` — mission selector (locked/playable/completed) + briefing panel; opened from the main menu Campaña button |
| **Unit Classes** ||
| `project/scripts/units/unit_base.gd` | Base class for all units; canonical combat state machine (order_move/order_attack, chase, strike, target re-scan) with ~16 override hooks (`_strike_damage`, `_combat_reposition`, `_combat_side_tick`, `_after_strike`, …) — leaf units override hooks, never copy the machine; Area2D range detection, attack-move, stuck detection, body animation; RVO tuned in _tune_avoidance (max_speed from move_speed ×1.6 — the engine default 100 capped fast units; neighbor_distance 80, dynamic avoidance_priority: movers 0.7, idle 0.4 so crowds part); AoE2 combat stances (`Stance` enum + `set_stance`; every auto-acquisition funnels through `_auto_engage` so PASSIVE vetoes, STAND_GROUND never chases and DEFENSIVE chases up to `DEFENSIVE_LEASH` from its anchor — explicit orders always chase); idle acquisition (`_tick_idle_acquire`: IDLE combat units sweep `ACQUIRE_RADIUS` 240 px every 0.6 s and hunt the nearest hostile unit on their own — they used to engage only what physically touched their attack-range Area2D, so idle armies stood beside enemy villagers forever; STAND_GROUND only takes what it can already strike, and the post-kill re-scan chains onto survivors within the same radius); `is_amphibious()` decides water permission per unit (false here — the ship/Tidecaller overrides open the sea) and feeds every `TerrainManager` query; `_step_enters_sea()` (`COAST_GUARD_DIST` 64 px gate via memoized `distance_to_coast`) vetoes any step that would ENTER ocean at the two off-mesh movement paths — RVO safe_velocity in `_on_velocity_computed` and the combat last-gap closer in `_handle_attacking` — so land units can never wade into the sea |
| `project/scripts/units/villager.gd` | Gathering and building logic, work/walk animation differentiation |
| `project/scripts/units/healer_unit.gd` | Harimaguada — Canarii-lore priestess-healer trained at the Temple (85F/25G, Castle Age); ALWAYS female (`is_female = true` before `super._ready()`); never fights (attack 0, PASSIVE, `_auto_engage` no-op); follow-and-mend machine (`order_heal`, 5 HP/s at 42 px) plus idle triage auto-scan (most wounded ally within 260 px); custom `_animate_body` (walk sway, nursing lean) |
| `project/scripts/units/presa_canario.gd` | Presa Canario — herding dog trained at the Mill (30F/10G, Dark Age); guard dog when pressed (attack 3, 30 HP, DEFENSIVE default) but herding is sacred: `_auto_engage` is vetoed mid-trip, only an explicit attack order drops the flock (releasing the animal and paying the approach so far); fetch-and-lead machine (`order_herd`: FETCH the animal, take it in tow via `Animal.start_following`, LEAD it to the nearest own drop-off and release) — sheep convert on contact and land OWNED, wild game's wander origin moves to the release point; shepherd's yield: each trip pays 1 food / `HERD_FOOD_PX` (40 px) of NET approach toward home (circles pay nothing) and completion emits `EventBus.animal_herded`; quadruped plinth/shadow + trot `_animate_body`; "select_dog" growl-bark voice |
| `project/scripts/units/hero_unit.gd` | Hero units — 16 named heroes (2 per civ, `hero_*.tres`), each with a unique ability (extends Militia) |
| `project/scripts/units/militia.gd` | Dark Age infantry |
| `project/scripts/units/man_at_arms.gd` | Feudal Age infantry upgrade |
| `project/scripts/units/long_swordsman.gd` | Castle Age infantry upgrade |
| `project/scripts/units/pikeman.gd` | Castle Age anti-cavalry spearman (+12 vs cavalry via `attack_bonuses`; Guanches train it from the Dark Age) |
| `project/scripts/units/archer.gd` | Feudal Age ranged infantry, attack-ground, cover fire |
| `project/scripts/units/scout.gd` | Dark Age exploration cavalry, auto-explore ability |
| `project/scripts/units/heavy_scout.gd` | Feudal Age cavalry upgrade |
| `project/scripts/units/knight.gd` | Castle Age heavy cavalry |
| `project/scripts/units/battering_ram.gd` | Castle Age melee siege; ×3 vs buildings, 0.2× vs units |
| `project/scripts/units/mangonel.gd` | Castle Age AoE siege; 72 px splash, minimum range |
| `project/scripts/units/trebuchet.gd` | Imperial Age long-range siege; 48 px splash, deploy/undeploy mechanic |
| `project/scripts/units/fishing_boat.gd` | Naval food gatherer |
| `project/scripts/units/transport_ship.gd` | Naval troop transport, `CAPACITY` 8 land units (villagers may board); `_disembark_position()` always lands passengers on dry ground, even amphibious ones |
| `project/scripts/units/war_galley.gd` | Feudal Age combat ship |
| **Unique Units (8 civs)** ||
| `project/scripts/units/menceyes_guard.gd` | Guanches infantry: Rage Aura at HP < 50% |
| `project/scripts/units/ravine_archer.gd` | Canarii archer: Ambush Shot (×2 first shot when stationary) |
| `project/scripts/units/sand_raider.gd` | Mahos cavalry: Hit & Run (retreat after attack) |
| `project/scripts/units/chevalier_normand.gd` | Franks cavalry: Lance Charge (×2.5 after 80 px movement) |
| `project/scripts/units/longbowman.gd` | Britons archer: Armour Piercing (+4 vs cavalry, +3 vs spearmen — lives in its .tres `attack_bonuses`, applied by the shared counter-triangle path) |
| `project/scripts/units/conquistador.gd` | Castellanos infantry: Salvo Fire (3 rapid shots, 12 s CD) |
| `project/scripts/units/tidecaller.gd` | Atlantes amphibious: Tidal Pulse (2 splash damage); the only land unit with `is_amphibious()` true (gated on the civ's `can_traverse_ocean`), rides navigation layer 4 |
| `project/scripts/units/trireme.gd` | Fenicios ship: Ram (×2 vs ships, 40 px knockback) |
| **Building Classes** ||
| `project/scripts/buildings/building_base.gd` | Base class for all buildings; outward spiral spawn positioning, rally points; garrison API (`garrison_capacity`/`garrison_unit`/`ungarrison_all` — land units only, occupants die with the building) and the shared ranged-volley machinery (`_ranged_attack_arrows()` > 0 enables it; towers always fire, the TC only while garrisoned, each occupant adds an arrow) |
| `project/scripts/buildings/building_damage_fx.gd` | `BuildingDamageFx` — progressive fire/smoke on damaged buildings (smoke from the FIRST point of damage, flames <50%, heavy fire <25%; repair walks it back; construction/rubble never burn); attached by BuildingBase and TownCenterBuilding, purely visual (render-side RNG) |
| `project/scripts/buildings/town_center.gd` | Main TC: trains villagers, hero respawn, drop-off |
| `project/scripts/buildings/town_center_buildable.gd` | Castle Age player-built TC (275 wood) |
| `project/scripts/buildings/barracks.gd` | Trains infantry (Militia/Archer/Man-at-Arms/Pikeman/Long Swordsman/unique units) |
| `project/scripts/buildings/archery_range.gd` | Feudal Age: trains Archer |
| `project/scripts/buildings/stable.gd` | Trains cavalry (Scout/Heavy Scout/Knight/unique cavalry) |
| `project/scripts/buildings/siege_workshop.gd` | Castle Age: trains siege (BatteringRam/Mangonel/Trebuchet) |
| `project/scripts/buildings/dock.gd` | Naval: trains ships (FishingBoat/TransportShip/WarGalley/Trireme); spawns them in open water off its seaward side, spiralling around ships already there; `water_access_point()` is the cached berth every ship must navigate to instead of the dock's on-land origin |
| `project/scripts/buildings/blacksmith.gd` | Research weapon/armour upgrades (9 techs) |
| `project/scripts/buildings/university.gd` | Castle Age: research advanced techs (Ballistics/Chemistry/Siege Engineering) |
| `project/scripts/buildings/temple.gd` | Castle Age almogarén (open dry-stone Canarian shrine — massing recipe `_temple()` + scene facade, review via `tools/check_temple_look.tscn`): research morale/HP buffs (Fervor/Sanctity/Atonement), field hospital (garrisoned units heal 4 HP/s, heroes at HALF rate so Regicide never stalls), trains Harimaguada (queue cap 5) |
| `project/scripts/buildings/market.gd` | Resource trading with dynamic rates, mercenary hiring |
| `project/scripts/buildings/wonder.gd` | Imperial Age: Wonder victory condition |
| `project/scripts/buildings/watch_tower.gd` | Defensive tower: fires visible arrows at the nearest enemy in the "units" group (the group UnitBase._ready joins — load-bearing for tower targeting, the Menceyes aura and several hero abilities); garrisons 5, each occupant adds an arrow to the volley (machinery lives in BuildingBase) |
| `project/scripts/buildings/wall_segment.gd` | Defensive wall |
| `project/scripts/buildings/gate.gd` | Wall gate (opens for allies) |
| `project/scripts/buildings/house.gd` | +5 population cap |
| `project/scripts/buildings/farm.gd` | Renewable food source |
| `project/scripts/buildings/fish_trap.gd` | Naval renewable food source |
| `project/scripts/buildings/lumber_camp.gd` | Wood drop-off; researches the wood economy line (Double-Bit Axe → Bow Saw → Two-Man Saw) |
| `project/scripts/buildings/mining_camp.gd` | Gold/stone drop-off; researches the mining economy line (Reinforced Picks → Shaft Mining → Deep Galleries) |
| `project/scripts/buildings/mill.gd` | `Mill` — food drop-off (100W/600HP, Dark Age, `DropOffBuilding` child like the camps) + trains the Presa Canario herding dog (queue cap 5) + researches the food economy line (Horse Collar → Heavy Plow → Crop Rotation); HUD build key M, train key P; camp/mill massing recipes reviewed via `tools/check_camps_look.tscn` |
| **Game World (scene root + controllers)** ||
| `project/scripts/game/game_world.gd` | Scene root and thin dispatcher (~385 lines): scene node refs, shared match state (`drop_off`, `_selected_units`, `_ai_town_centers`, `_fog`, saved-game fields), `_ready` wiring, `_process`/`_unhandled_input` routing into the controllers below, and the stable external surface (`jump_camera_to`, `get_zoom`/`set_zoom`, `_start_placement`, `live_selection()` — the prune-on-read barrier every controller must use instead of `_selected_units`, …) |
| `project/scripts/game/world_setup.gd` | `WorldSetup` — match bootstrap: civs, player/AI town centers, hero spawn, tutorial spawns, ambient lighting, AI debug overlay |
| `project/scripts/game/world_victory.gd` | `WorldVictory` — victory/defeat/elimination checks, Wonder countdown, game-over flow; resignation → spectate: `handle_resignation` accepts the local player too — with hostile sides still standing the match plays on (defeat panel via `EventBus.player_eliminated`, orders locked by `GameWorld.local_player_defeated`, camera/selection stay live), otherwise the remaining side wins after `RESIGN_END_DELAY`; the end-of-game freeze stops building `_physics_process` and the AI brains too (they used to keep spawning live units into a "frozen" battlefield) |
| `project/scripts/game/world_camera.gd` | `WorldCamera` — pan/zoom/edge-scroll, camera follow, alert ring + SPACE jump |
| `project/scripts/game/world_selection.gd` | `WorldSelection` — click/drag/double-click selection, control-group hotkeys |
| `project/scripts/game/world_commands.gd` | `WorldCommands` — the player's intent layer: right-click resolution (incl. garrisoning military into own TC/towers), target pickers (visible-facade building hit-test), pending actions, HUD action router, dogs-ONLY selections herd a right-clicked animal (`_selection_all_dogs`) while any other selection slaughters it, current formation choice (`_formation`, local UI state — each move command carries it; picking a formation immediately reforms the selection in place around its centroid via `_reform_selection`); every simulation mutation is packaged as a `GameCommand` and submitted through `CommandBus`, UI feedback (flashes, sounds) stays here |
| `project/scripts/game/commands/game_command.gd` | `GameCommand` — command-pattern base: serializable payload (`to_dict`/`read`), execute-time ownership validation (`_own_entities`), `remote_origin` flag (set only by `NetworkSession._rx_command`, never serialized — wire-borne commands lose local privileges); 9 leaf commands in the same dir (`UnitPointCommand` move/attack-move/attack-ground + formation, `UnitTargetCommand` attack/gather (`drop_id`)/build/drop-off/board/board_instant/set_drop_off/heal/herd (herd: only dogs answer, any animal targetable), `UnitActionCommand`, `TransportCommand`, `ProductionCommand`, `BuildingActionCommand`, `MarketCommand` incl. mercenary spawn, `PlaceBuildingCommand` incl. wall runs + `last_placed` (`instant` is a privileged tools/tests-only flag now — AI buildings are villager-built), `AdvanceAgeCommand`); the AI queues its villagers at its TC via `ProductionCommand` — same cost and train time as the player |
| `project/scripts/game/world_placement.gd` | `WorldPlacement` — building placement ghost/grid-snap, wall drag, coastal/ocean checks, navmesh rebake; `building_costs()` is the single .tres-backed cost table player and AI both pay; static `placement_legal`/`placement_shape_size` re-run the ghost's rules host-side (terrain class — land / coastal dock / fully-ocean fish trap — + physics overlap; shape sizes read once per type from the scene's collision rect) for every wire-borne placement |
| **Map Generation (pipeline + modules)** ||
| `project/scripts/map/map_generator.gd` | `MapGenerator` — thin pipeline (~150 lines): reads `MatchConfig`, sequences painter → placer → nav builder per map type, returns `{tc_positions}`. Owns the shared `RandomNumberGenerator`, the land-polygon array and `_island_layout()` (solves island radius + ring distance so islands never overlap at any player count / map size) |
| `project/scripts/map/map_materials.gd` | `MapMaterials` — lazily cached shader materials (terrain per type, deep/shallow water, lava), terrain colour table, `STAIN_TILE` grid |
| `project/scripts/map/terrain_detail.gd` | `TerrainDetail` — tile-dithered ground decals and per-biome detail variants (grass/dune/malpaís/risco/laurisilva/caldera) |
| `project/scripts/map/terrain_painter.gd` | `TerrainPainter` — backgrounds, per-map-type zone layouts, zone visuals, shorelines, island polygons; owns `MapMaterials` + `TerrainDetail` |
| `project/scripts/map/entity_placer.gd` | `EntityPlacer` — spatial-hash occupancy grid (`SPATIAL_CELL = 140`) plus every spawn: TC ring, starting units, animals, player/neutral/scattered resources, laurisilva forests, fish, resource islets; wild sheep flocks (2 + map_half/900 clusters of 2–4, always >520 px from every TC — contested herding targets) draw from their own seeded RNG stream so downstream placement census is untouched |
| `project/scripts/map/resource_visuals.gd` | `ResourceVisuals` — static resource-node art library; also used by `SaveManager` on load and by `ResourceNode` for tree stumps |
| `project/scripts/map/nav_mesh_builder.gd` | `NavMeshBuilder` — bakes the four `NavigationPolygon` meshes via `NavigationServer2D.bake_from_source_geometry_data`: layer 1 land, layer 2 ocean, layer 4 `AMPHIBIOUS_LAYER` (spans land+water), layer 8 `MALPAIS_LAYER` (malpaís left walkable — traversal civs' land units switch to it in `UnitBase._ready`). Impassable zones (risco/caldera always, malpaís except layer 8) are CARVED via `zone_obstructions` so paths route around them (the old RVO-only `NavigationObstacle2D`s let paths cross the lava and units froze on the rim); the runtime rebake re-injects them. Also ocean boundary walls and the shared bake helpers — `RADIUS_NUDGE` (+0.5 px) and the `RADIUS_FALLBACKS` ladder |
| **AI Systems** ||
| `project/scripts/ai/world_query.gd` | `WorldQuery` — read-only query service over the unit/building layers (own/enemy/all, of_type/in_state/nearest_to); the AI queries it instead of walking the scene tree. Fog-honest sighting layer: `refresh_sightings` (throttled flat-array sweep, ~1.7/s per AI; LOS from the entity's .tres × 64 px, FogOfWar's scale) feeds `sighted_enemy_units` (targetable only while seen NOW) and `known_enemy_buildings` (seen now OR remembered at last position — AoE2 semantics). Exposed lazily as `AIPlayer.world` |
| `project/scripts/ai/ai_player.gd` | AI coordinator: EventBus wiring, TC rebuild, elimination logic; owns the `world: WorldQuery` getter |
| `project/scripts/ai/ai_economy.gd` | Villager spawning/assignment, resource targets per age, age-advance trigger; pastoral economy: `manage_dogs` (up to `MAX_AI_DOGS` 2 Presa Canarios trained at a complete Mill, idle dogs sent at the nearest unclaimed animal via the CommandBus "herd" verb) + `manage_flock` (single-in-flight slaughter of an own sheep near the TC while the food-gatherer share is under target) |
| `project/scripts/ai/ai_construction.gd` | Building placement, placement-failure cooldowns, population-house management; builds a Mill early (food drop-off by the TC) and Watch Towers from the Feudal Age (`tower_target_for_age`: 1 Feudal, 2 Castle+); every placement is raised by a real villager over the same construction time the player pays (`_place` picks the nearest free villager, `manage_unfinished` re-crews sites whose builder died — the old instant completion was an AI-only cheat) |
| `project/scripts/ai/ai_military.gd` | Military training, research priority, combat targeting, base defense, aggression escalation; targeting is fog-honest (`sighted_enemy_units`/`known_enemy_buildings` — the primary enemy TC stays map knowledge so the AI still leaves home) |
| `project/scripts/ai/ai_naval.gd` | Naval training, galley patrol/retreat, transport assault (from 2 land military — the old bar of 3 parked the transport for the opening ten minutes of an island AI-vs-AI war), fish-trap construction; galleys hunt sighted enemy ships first and otherwise burn the enemy's KNOWN waterline (`_find_coastal_target`: docks/fish traps) — without that, two AIs on separate islands coexisted forever; the dock is villager-built on the shore and fish traps are raised by the fishing boat over time (no instant construction); AI-vs-AI hostility measured by `tools/check_ai_vs_ai.tscn` (env CALIMA_MAP/WIPE_AT/SURVIVORS/TICKS — wipes the player and times the first cross-AI attack command and casualty) |
| **UI Systems** ||
| `project/scripts/ui/hud_manager.gd` | CanvasLayer coordinator (~940 lines, was a 2,300-line god object): selection info panel (name/HP/status/portraits/stat chips), train-queue + research-slot row, detail-panel progress bars (age/hero/research), composition of every HUD child component. The command grid lives in `HudActionMenu`, the tutorial in `HudTutorial`, action tables in `HudActionDefs` |
| `project/scripts/ui/hud/hud_action_defs.gd` | `HudActionDefs` — static action tables (unit/build/stance/gate/mercenary layouts, glyph + hotkey maps) and pure builders: `train_action` (cost from the unit's .tres), `build_action` (cost from `WorldPlacement.building_costs`), `tech_action` (localized name/desc) — NO hardcoded prices anywhere, a rebalance can't make a button lie (`test_hud_panels.gd` audits every button against the data) |
| `project/scripts/ui/hud/hud_action_menu.gd` | `HudActionMenu` — the command grid: button rendering + paging, press routing into the HUD signals, pending map-click actions, stance/formation highlights, hotkeys, and every per-selection layout; ONE `_populate_production` panel serves all train/research buildings via their `get_available_units()` + TechManager (replaced eight near-identical populate functions); reaches back through `_hud` like the world controllers reach GameWorld; in a REPLAY `populate()` refuses every action (info panel yes, buttons/hotkeys no — recorded history takes no orders; `GameWorld._orders_locked` blocks the right-click/minimap/placement paths for both replays and defeated spectators) |
| `project/scripts/ui/hud/hud_tutorial.gd` | `HudTutorial` — tutorial lesson driver: owns the TutorialOverlay, per-step gameplay-signal listeners, build/villager gates (`gates_active`/`step`/`unlocked_build_ids`); lesson resource top-ups are EMITTED via `EventBus.tutorial_grant_resources` and applied by game_world — the HUD never mutates a stockpile |
| `project/scripts/ui/hud/hud_resource_bar.gd` | `HudResourceBar` — top-bar resource counters + gatherer counts, population label, age label (self-wires to EventBus) |
| `project/scripts/ui/hud/hud_weather.gd` | `HudWeather` — weather announcement banner + countdown pill (self-wires to WeatherManager) |
| `project/scripts/ui/hud/hud_match_stats.gd` | `HudMatchStats` — match clock, per-player/rival stat counters, timeline snapshots, game-over + charts overlays; the result panel also appears on local elimination while the match plays on (spectate: hint line, no replay button, rebuilt when the definitive game_over lands) |
| `project/scripts/ui/hud/hud_menus.gd` | `HudMenus` — in-game pause menu, settings panel, save-slot picker, surrender flow |
| `project/scripts/ui/hud/hud_controls.gd` | `HudControls` — game-speed buttons, camera dpad (with panning), idle-villager/idle-military cycle buttons, locate-hero button (selects + centres camera; greyed while respawning) |
| `project/scripts/ui/hud/hud_style.gd` | `HudStyle` — shared StyleBoxFlat panel/button factory, bold font + text outline helpers |
| `project/scripts/ui/hud/hud_hero_widget.gd` | `HudHeroWidget` — persistent hero portrait + HP card in Regicide matches (click centers camera) |
| `project/scripts/ui/hud/hud_control_groups.gd` | `HudControlGroups` — clickable chips for assigned control groups (dominant-type miniature + count) |
| `project/scripts/ui/hud/hud_chat.gd` | `HudChat` — in-match multiplayer chat (online only): Enter opens/sends, Escape closes, focused input swallows hotkeys, colour-coded lines fade above the command bar; lobby chat lives in `LobbyScreen._build_chat_panel`, transport in `NetworkSession.send_chat`/`chat_received` |
| `project/scripts/ui/ui_icons.gd` | `UiIcons` — procedural glyph library (37+ command/resource/stat glyphs plus per-technology glyphs via `tech_glyph(tech_id)`, baked once, cost-row builders) |
| `project/scripts/ui/action_button.gd` | `ActionButton` — uniform square command button: glyph/entity miniature, hotkey badge, queue badge, category accent |
| `project/scripts/ui/cursor_manager.gd` | `CursorManager` — contextual mouse cursors (tabona/naife pointer + context glyph); pure resolve_context mapping |
| `project/scripts/ui/train_queue_slot.gd` | `TrainQueueSlot` — training queue slot with entity miniature, progress veil, cancel |
| `project/scripts/utils/icon_baker.gd` | `IconBaker` — runtime-baked entity miniatures (civ-styled) for buttons/portraits/queue |
| `project/scripts/utils/iso_projection.gd` | `IsoProjection` — camera-level isometric math (world/screen, zoom composition) |
| `project/scripts/utils/iso_billboard.gd` | `IsoBillboard` — upright entities on the projected ground, depth sort, z constants |
| `project/scripts/utils/civ_style.gd` | `CivStyle` — per-civ visual identity (wall/roof silhouette/trim/headgear, plus the `NAVAL` hull/deck/sail/accent/motif palettes) |
| `project/scripts/utils/unit_dress.gd` | `UnitDress` — per-civ headgear/sash decoration of shared unit rigs |
| `project/scripts/utils/team_dress.gd` | `TeamDress` — AoE2-style team colours on unit rigs: cloth (tunic/hood/cap/sleeves/legs, knight caparison+plume) is repainted to the OWNER's colour keeping each polygon's brightness (shading survives); steel (saturation gate), leather/skin/wood and natural brown horses (hue-band gate on horse nodes) never change. Applied from `UnitBase._apply_team_dress`; review via `tools/check_team_colors.tscn` screenshots; contract locked by `test_team_dress.gd` |
| `project/scripts/utils/unit_enhancer.gd` | `UnitEnhancer` — OPTIONAL enhanced unit look (`GameSettings.enhanced_units`, settings toggle, default off): fully reversible layer applied by `UnitBase` as the LAST paint step and stripped live on toggle. Ink outline (grown dark polygon copies as CHILDREN at relative z -1 — they merge into one contour behind the figure and follow Head/Tool pivots), volume shading (per-polygon vertical `vertex_colors` gradient baked from the current colour — `Polygon2D.color` is NEVER touched, so the TeamDress contract holds), and `animate_extras` post-step over `_animate_body` (idle breathing, walk lean + squash&stretch, attack anticipation snap; only rigs with a Head — ships/siege get outline+shading only). Everything added/shaded is meta-marked for `strip`; contract locked by `test_unit_enhancer.gd`, review via `tools/check_enhanced_units.tscn` |
| `project/scripts/utils/unit_redesign.gd` | `UnitRedesign` — the third unit style (`GameSettings.UnitStyle.REDESIGNED`): lore-driven from-scratch Polygon2D rigs for every unit (villager m/f tamarco+multi-tool, Militia→Long Swordsman gear progression, banot pikeman, archer with working bow draw, Harimaguada white gown, cavalry with decoupled horse/rider gallop, Presa Canario brindle trot, siege with rolling wheels/pendulum log/snapping arms + trebuchet pack/deploy poses, side-profile ships in the `CivStyle.NAVAL` palette with rowing oars, all 8 civ-unique units, heroes = base rig + circlet/cape/+12%). `apply()` builds a `RedesignBody` sibling and HIDES the classic Body (never freed); `strip()` restores it exactly; both idempotent. When active, `UnitBase._process` calls `UnitRedesign.animate()` INSTEAD of `_animate_body` — full state-machine animation (2-phase walk cycle with arm counter-swing/bounce/lean, wind-up→snap→recover strikes per weapon kind slash/thrust/bow/gun/heal/tool, chop/mine/forage/build villager work, idle breathing + weight shift). Team colour painted directly from `PlayerColors` at build (hue/sat owner, brightness modelling); units without a rig yet keep the classic look. Contract locked by `test_unit_redesign.gd`, review via `tools/check_redesigned_units.tscn` |
| `project/scripts/utils/ship_dress.gd` | `ShipDress` — per-civ hull/deck/sail repaint + prow ornament of the shared hulls (Atlantes bronze fin, Fenicios eye); civ-unique hulls stamp `META_APPLIED` to opt out |
| `project/scripts/utils/entity_names.gd` | `EntityNames` — localized unit/building/technology display names (`tech_name`/`tech_description`, keys `TECH_<ID>`/`TECH_<ID>_DESC`) with fallback |
| `project/scripts/utils/alert_ring.gd` | `AlertRing` — ring buffer of attack-alert positions for the SPACE jump |
| `project/scripts/utils/hero_aura.gd` | `HeroAura` — animated Dragon Ball-style golden flame aura behind the hero (3 additive layers, upright billboard space, inserted before Body so the figure reads on top); replaced the static gold ground ring |
| `project/scripts/utils/visual_fx.gd` | `VisualFx` — ground shadows, selection plinths, nameplate visibility |
| `project/scripts/ui/resource_display.gd` | HBoxContainer showing one resource icon + amount |
| `project/scripts/ui/unit_portrait.gd` | PanelContainer showing unit name + HP bar in selection grid |
| `project/scripts/ui/weather_overlay.gd` | Screen-space visual effects (rain, dust, ash, fog) driven by WeatherManager |
| **Resources** ||
| `project/resources/units/unit_resource.gd` | Unit stat definition (Resource) |
| `project/resources/buildings/building_resource.gd` | Building stat definition |
| `project/resources/technologies/technology_resource.gd` | Tech effects |
| `project/resources/civilizations/civilization_resource.gd` | Civ bonuses |

## Coding Conventions

- `snake_case` for variables, functions, file names
- `PascalCase` for class names (`class_name`), node names, scene root names
- Use `@export` for all designer-tunable values
- Use `const` for true constants
- One `class_name` per base script; leaf classes may omit it
- Signals: defined in `EventBus` for cross-system; direct `connect()` within a scene subtree only
- No comments explaining *what* code does — only *why* for non-obvious constraints

## Resources (AoE2 style)

- **Food** — farms, hunt, fish, berries
- **Wood** — trees
- **Gold** — gold mines
- **Stone** — stone quarries

## Age Progression

`GameManager.Age` enum: `DARK=0`, `FEUDAL=1`, `CASTLE=2`, `IMPERIAL=3`

## Testing

Uses the [GUT](https://github.com/bitwes/Gut) addon (vendored at
`project/addons/gut`). Tests live in `project/tests/unit/` and
`project/tests/integration/` (inside the Godot project so they resolve via
`res://`). Run them headlessly with `./run_tests.sh` (the whole suite — the
default now runs BOTH test dirs; it used to silently run only tests/unit, and
the CI script-count guard counts both) or
`./run_tests.sh res://tests/unit/test_world_query.gd` (one script); set the
`GODOT` env var to the engine binary. Also runnable from the GUT panel in the
editor. There are also standalone headless harnesses under `project/tools/`
(`check_*.gd`) for things GUT can't easily reach (HUD scene load, WorldQuery,
PlacementGrid).

**The complete harness catalog — all 56 `check_*` tools with purpose and env
vars — lives in `docs/testing/harnesses.md`** (generated from each harness's
header comment; regenerate with `python3 docs/testing/regen_harness_catalog.py`
after adding or changing one). The block below is only the curated CI-gate
subset. Screenshot galleries from design reviews are archived under
`docs/design/` (unit-redesign-gallery, unit-enhanced-gallery).

`project/tools/check_map_gen.tscn` is the map-generation regression gate: it
prints a deterministic census (TC positions, zone checksum, per-type resource
counts/amounts/position checksum, animals, nav polygons/obstacles, RNG state,
scene node counts) for every map type at a fixed seed. Capture it before
touching map generation and diff it after — the numbers must not move unless
the change is meant to alter the map.

```sh
$GODOT --headless --path project res://tools/check_map_gen.tscn   # env: CALIMA_SEED, CALIMA_MAPS, CALIMA_RIVALS
# Islands: no overlapping islands, both nav meshes usable, ships can sail out of their dock
CALIMA_RIVALS=3 CALIMA_MAP_SIZE=0 $GODOT --headless --path project res://tools/check_islands_layout.tscn
# Islands: the runtime navmesh rebake keeps land carved and the ocean sailable
$GODOT --headless --path project res://tools/check_nav_islands.tscn   # env: CALIMA_MAP
# Two diagonally placed buildings must not empty the navmesh (the bake-nudge gate)
$GODOT --headless --path project res://tools/check_nav_bake_diag.tscn   # env: CALIMA_MAP, CALIMA_SEED
# Command pattern: a real match driven through CommandBus (move/train/place + rebuildable log)
$GODOT --headless --path project res://tools/check_command_bus.tscn   # env: CALIMA_SEED
# Determinism probe: run twice, diff — identical command logs, positions still diverge (physics)
$GODOT --headless --path project res://tools/check_sim_fingerprint.tscn   # env: CALIMA_SEED, CALIMA_MAP, CALIMA_TICKS
# Volcanic Coast: a unit ordered across a caldera must route AROUND it and arrive
$GODOT --headless --path project res://tools/check_volcanic_nav.tscn   # env: CALIMA_SEED
# Multiplayer smoke: run BOTH (host first, backgrounded) — client joins, sends a command, host executes it
CALIMA_NET_ROLE=host   $GODOT --headless --path project res://tools/check_net_smoke.tscn &
CALIMA_NET_ROLE=client $GODOT --headless --path project res://tools/check_net_smoke.tscn   # env: CALIMA_NET_PORT
# Resume gate, two phases (host backgrounded first in each): phase 1 saves an online
# match (roster sheet + client fog), phase 2 re-hosts it — the client reclaims its
# seat, boots an EMPTY mirror, receives the full resync + its explored fog, and a
# command round-trips. Uses save slot 89 (deleted on success).
CALIMA_RESUME_ROLE=host_save     $GODOT --headless --path project res://tools/check_net_resume.tscn &
CALIMA_RESUME_ROLE=client_save   $GODOT --headless --path project res://tools/check_net_resume.tscn
CALIMA_RESUME_ROLE=host_resume   $GODOT --headless --path project res://tools/check_net_resume.tscn &
CALIMA_RESUME_ROLE=client_resume $GODOT --headless --path project res://tools/check_net_resume.tscn   # env: CALIMA_NET_PORT
# Amphibious: the Tidecaller swims off the beach, land units are refused water, passengers disembark dry
$GODOT --headless --path project res://tools/check_amphibious.tscn
# Sea-containment chaos probe (also a CI gate, CALIMA_TICKS=2400 there): boots a real
# Islands match, shoves land units at the ocean every way a live game does, audits
# every land unit every sampled tick — no land unit may ever stand on OCEAN terrain
$GODOT --headless --path project res://tools/check_sea_containment.tscn   # env: CALIMA_SEED, CALIMA_MAP, CALIMA_TICKS, CALIMA_RIVALS
# Naval civ identity (real renderer, not headless): every hull dressed for every civ
CALIMA_SHOT_DIR=/tmp/calima-ships $GODOT --path project --resolution 1600x900 \
  res://tools/check_ship_gallery.tscn   # env: CALIMA_CIVS=atlantes,fenicios
# Damage fire/smoke stages + watch-tower arrows (real renderer): screenshot review
CALIMA_SHOT_DIR=/tmp/calima-fx $GODOT --path project --resolution 1400x900 \
  res://tools/check_damage_fx.tscn
# Team colours on unit rigs (real renderer): unit-type columns x player-colour rows,
# full grid + two close-ups — cloth must follow the row, materials must not
CALIMA_SHOT_DIR=/tmp/calima-teams $GODOT --path project --resolution 1500x900 \
  res://tools/check_team_colors.tscn
# Enhanced unit look (real renderer): the same unit grid shot classic, then re-shot
# after flipping GameSettings.enhanced_units live (outline/shading/extra animation
# must appear, strip must restore the classic rig)
CALIMA_SHOT_DIR=/tmp/calima-enhanced $GODOT --path project --resolution 1500x900 \
  res://tools/check_enhanced_units.tscn
# Redesigned unit style (real renderer): per-batch grid shot classic, re-shot after
# switching GameSettings.unit_style to REDESIGNED live, plus close-ups and frozen
# walk/attack/gather poses (CALIMA_BATCH=a..f: a infantry+villager, b cavalry+healer+dog,
# c siege, d ships, e civ-uniques, f heroes)
CALIMA_SHOT_DIR=/tmp/calima-redesign CALIMA_BATCH=a $GODOT --path project \
  --resolution 1500x900 res://tools/check_redesigned_units.tscn
# Building/unit look reviews (real renderer, screenshots): the Temple almogarén in a
# lineup, the Lumber/Mining Camp + Mill yards, and the Harimaguada priestess rig
CALIMA_SHOT_DIR=/tmp/calima-temple $GODOT --path project res://tools/check_temple_look.tscn
CALIMA_SHOT_DIR=/tmp/calima-camps  $GODOT --path project res://tools/check_camps_look.tscn
CALIMA_SHOT_DIR=/tmp/calima-hari   $GODOT --path project res://tools/check_harimaguada_look.tscn
# Selection voices: exports every baked formant voice to WAV (listen with afplay) + census
CALIMA_SHOT_DIR=/tmp/calima-voices $GODOT --headless --path project res://tools/check_voice_gallery.tscn
# Frame-time probe (real renderer): boots a fixed-seed match, prints avg process/physics
# ms per frame + nav/physics population counters — run on two builds for perf A/Bs.
# env: CALIMA_PERF_LABEL/RIVALS/MAP_SIZE/MAP/RESOURCES, CALIMA_PERF_ARMY (units per side,
# clashing armies), CALIMA_PERF_DEVELOP (game-seconds at 4x before measuring), _WINDOW,
# CALIMA_PERF_DISABLE=fog,minimap,hud,weather,units,world,interp,areas,rvo,
#   unit_physics,rvo_lite,no_velcb,phys30,steps4,steps2,hide_units,hide_world
#   (cost attribution), CALIMA_FOG_STATS=1 (per-phase fog tick timings).
# Vsync is disabled by the probe; trust the "wall ms/frame + ticks/frame" line
# (the TIME_PROCESS monitor is unreliable, and fps overstates when the sim dilates).
$GODOT --path project --resolution 1280x720 res://tools/check_perf_probe.tscn
# Replay browser panel (real renderer): seeds fake replay headers (one with a
# long roster — must ellipsize, never push the buttons out) and screenshots it
CALIMA_SHOT_DIR=/tmp/calima-replays $GODOT --path project --resolution 1600x900 \
  res://tools/check_replays_panel.tscn
# HUD action panels (real renderer): selects camps/mill/temple/barracks/TC in
# the real HUD and screenshots each button layout (headless twin: the
# tests/unit/test_hud_panels.gd contract, which also audits button prices)
CALIMA_SHOT_DIR=/tmp/calima-camp-research $GODOT --path project --resolution 1500x900 \
  res://tools/check_camp_research.tscn
# Campaign gate (headless): mission 1 boots deterministically, the director
# mounts, the first scripted wave spawns, victory records progress (progress
# file is backed up/restored). UI review: check_campaign_screen.tscn (renderer).
$GODOT --headless --path project res://tools/check_campaign.tscn
# AI pastoral behaviour probe (headless): a real match at 8x — the AI must build
# a Mill, train a Presa Canario and issue at least one herd command via CommandBus
$GODOT --headless --path project res://tools/check_ai_pastoral.tscn   # env: CALIMA_SEED, CALIMA_TICKS, CALIMA_FULL
# Simulation budget gate (headless, suite-friendly): 100v100 battle must hold
# >= 30 ticks/s wall (healthy: 60; CI overrides the floor to 20 via
# CALIMA_PERF_MIN_TICKS). Catches sim-side regressions (RVO population,
# per-tick chase repaths). Perf PROPERTIES (incremental fog, repath hysteresis,
# avoidance dispatch reconnect) are locked machine-independently in
# tests/unit/test_perf_properties.gd as part of the normal GUT suite.
$GODOT --headless --path project res://tools/check_perf_gate.tscn
```

Note: GUT silently *skips* a test script that fails to parse while still
reporting "all passed" — always check the `Scripts` count in the summary and run
`$GODOT --headless --path project --import` after adding a new `class_name`.

## Current Status

**Production-ready** — All core features implemented. Recent work focused on polish and bug fixes.

### Implemented Features

**Core Gameplay:**
- 4 Ages (Dark → Feudal → Castle → Imperial) with age-advance costs and timers
- 4 resources (Food, Wood, Gold, Stone) with villager gathering, drop-off buildings, and farms
- Population cap system (5 per House, starts at 15)
- 3 victory conditions: Conquest (eliminate all enemies), Regicide (kill enemy hero), Wonder (build + hold for timer)
- Fog of War with 3 states: unexplored / explored / visible
- Save/Load system (99 JSON slots with metadata UI; schema v2 also persists in-flight research, garrisons, unit stances and the live weather state — newer schemas refused, older ones load with defaults)
- Procedural map generation with 5 map types (Plains, Standard, Volcanic Coast, Desert Coast, Islands)
- 4 resource modes (Scarce, Normal, Abundant, Full Combat)

**Units (26 playable types — 25 regular incl. 8 civ-uniques, plus the hero class — and 2 animal types):**
- Villagers (gather, build, repair)
- Support: Harimaguada healer (Temple, Castle Age, always female, auto-triage), Presa Canario herding dog (Mill, Dark Age, leads animals to the nearest own drop-off — enemy sheep convert on the way; each trip pays food for the net approach; guard-dog bite when idle, never abandons a trip on its own)
- Infantry: Militia → Man-at-Arms → Long Swordsman, Pikeman, Archer
- Cavalry: Scout → Heavy Scout → Knight
- Siege: Battering Ram, Mangonel, Trebuchet (deploy mechanic)
- Naval: Fishing Boat, Transport Ship (capacity 8), War Galley
- Animals: Sheep (convertible), generic Animal; wild sheep flocks graze the open map away from every TC — contested herding targets both the player's and the AI's dogs race for
- 16 named Heroes (2 per civ, lobby gender pick) with unique abilities
- 8 Unique units (one per civ) with special mechanics

**Buildings (20 types):**
- Economy: Town Center, House, Lumber Camp (researches the wood line), Mining Camp (researches the gold/stone line), Mill (food drop-off + trains Presa Canario + researches the food line), Farm, Fish Trap
- Military: Barracks, Archery Range, Stable, Siege Workshop, Dock
- Research: Blacksmith, University, Temple (also field hospital: garrisoned units heal 4 HP/s, heroes half rate; trains Harimaguada), Market
- Defense: Wall Segment, Gate, Watch Tower
- Special: Wonder (victory condition)

**Technologies (32 total):**
- Blacksmith (13): Loom, Forging, Iron Casting, Blast Furnace, Scale/Chain/Plate Barding, Padded Archer Armour, Fletching, Bodkin Arrow, Shipwright, Canarian Cart / Island Handcart (villager carry capacity +25% each, farms unaffected)
- University (3): Ballistics, Chemistry, Siege Engineering
- Temple (3): Fervor, Sanctity, Atonement
- Camp economy (9, AoE2-style — one per age from Feudal, chained prerequisites; each step: that resource's gather rate ×1.15 and its carry basket ×1.10 via `villager_<res>_gather_rate` / `villager_<res>_carry`): Lumber Camp — Double-Bit Axe → Bow Saw → Two-Man Saw (wood); Mining Camp — Reinforced Picks → Shaft Mining → Deep Galleries (gold+stone); Mill — Horse Collar → Heavy Plow → Crop Rotation (food)
- Unit Upgrades (4): Man-at-Arms, Long Swordsman, Heavy Scout, Knight
- Instant civ bonus: Castellanos free Blacksmith tech per age
- Research queue: up to 5 techs in flight per building (active + queued), paid at enqueue, full refund on cancel, promoted automatically

**Civilizations (8 total):**
- Guanches: Stone building HP bonus, Pikemen from the Dark Age, infantry-focused, malpaís traversal
- Canarii: Food gather bonus, cheap archers, houses double as drop-off points, no heavy cavalry
- Mahos: Cheaper timber (building wood cost ×0.70 — applied at button/AI/command alike via `CivBonusManager.get_building_costs`), fast cavalry, dune traversal, vision ×1.40 while standing on dunes (`dune_vision`, read by `FogOfWar._dune_vision_mult`)
- Franks: Cheaper age advance, cavalry HP bonus, farms built ×1.20 faster (`farm_build_speed`, read in `Villager._handle_building`)
- Britons: Archer range +1/age, warship attack speed bonus
- Castellanos: Free Blacksmith tech/age, defensive volleys reach ×1.10 (`tower_range`, read in `BuildingBase._attack_range`), balanced roster
- Atlantes: Ship attack speed bonus, distinct sea-stone/bronze fleet (`CivStyle.NAVAL`), amphibious unique unit (Tidecaller wades shallows at full speed, swims deep water at `deep_water_speed` 0.60), harder to spot in Sea Fog (`fog_stealth` 0.5), +50 % vision within 400 px of a shore (`coastal_vision` 1.50, read by `FogOfWar._coastal_vision_mult`)
- Fenicios: Market from the Dark Age, ship cost ×0.85, trireme passive gold, mercenary discount, ramming naval unique unit

**Weather System:**
- 5 procedural weather types (Calima, Atlantic Storm, Sea Fog, Trade Winds, Volcanic Ash)
- Stat modifiers: vision, movement speed, gather rate, projectile drift, building damage
- Per-civ weather affinity: `CivilizationResource.weather_affinity` ({weather_id: resistance 0..1}) scales penalties per civilization (e.g. Guanches immune to Calima, Atlantes ignore the Atlantic Storm naval penalty); weather query methods take an optional `player_id`. Full matrix: Guanches (calima 0.0, volcanic_ash 0.5), Mahos (calima 0.5), Atlantes (atlantic_storm 0.0, sea_fog 0.5), Fenicios (atlantic_storm 0.5), Britons (atlantic_storm 0.5), Canarii (sea_fog 0.5, trade_winds 0.5), Castellanos (calima 0.5); Franks are the neutral continental baseline (no affinity)
- Volcanic Ash is spatial: only rolls on Volcanic Coast maps and only affects positions within a caldera's radius + 800 px (`WeatherManager._in_volcanic_zone` queries `TerrainManager` CALDERA zones; calderaless maps fall back to whole-map coverage)
- Weather-based cloaking (Sea Fog coastal stealth): the cloak breaks within `WeatherManager.fog_spot_range(owner)` of an own unit/building (180 px, ×`fog_stealth` — Atlantes 90 px) and for `UnitBase.COMBAT_REVEAL_TIME` after the hidden unit strikes; `FogOfWar._breaks_fog_cloak` owns both rules
- Weather forecast: a `forecast` phase warns the player `FORECAST_TIME` seconds before an event ramps in (`WeatherManager.weather_incoming` signal → `HudWeather` banner); weather stays inactive (no penalties) during the warning
- Visual effects overlay (rain, dust, ash, fog vignette)
- Lobby-configurable frequency (Off/Normal/Frequent/Extreme)

**Combat:**
- Melee and ranged damage calculation with armour types (melee/pierce); counter triangle via `UnitResource.attack_bonuses` read in `UnitBase._strike_damage` (COMBAT_CLASSES map: pikeman +12 vs cavalry, cavalry +4/scout +3 vs archers, archers +3 vs spearmen, longbowman keeps its +4 vs cavalry as data) — arrows inherit it because archers charge them with `_strike_damage`; the AI counters what it SIGHTS (`_counter_bias` shifts the barracks mix)
- Projectile system with flight time and drift (weather-affected)
- Area-of-effect splash damage (Mangonel 72 px, Trebuchet 48 px)
- Attack-ground command for ranged/siege units
- Cover Fire button (move into range then attack)
- AoE2 combat stances: Aggressive / Defensive (leash + return) / Stand Ground / No Attack
- Group formations: Line (melee front, ranged behind), Box, Spread, Rings — selectable per military selection; picking one immediately reforms the selection in place around its centroid (AoE2 behaviour)
- Garrison: land units shelter in the TC (10) and Watch Towers (5); each occupant adds an arrow to the building's volley (the TC only shoots while garrisoned); occupants die if the building falls. Right-click garrisons military ONLY (a villager's right-click on an own building is always build/repair); villagers use their Garrison button (map-click pending action) or the TC's Town Bell (nearest-with-room assignment, second ring ejects everyone)
- Minimum range mechanic (siege)
- Auto-attack range detection via Area2D nodes (no per-frame queries)
- Healing: Harimaguada follow-and-mend (5 HP/s touch range, idle auto-triage) + Temple garrison ward (4 HP/s, heroes half rate)
- Sea containment: `UnitBase._step_enters_sea` vetoes any step entering ocean at the two off-mesh movement paths (RVO safe_velocity, combat gap-closer) — land units never wade into the sea (`check_sea_containment` CI gate); animals carry the same veto in `animal.gd` (wild flocks graze near coasts)

**AI:**
- Economic AI: villager spawning/assignment, resource balancing, age advancement; pastoral economy (builds a Mill, trains up to 2 herding dogs, races the player for unclaimed/wild animals, slaughters one own sheep at a time when food is wanted)
- Construction AI: building placement with cooldowns, population management, Mill early + Watch Towers from Feudal; buildings are raised by real villagers with the player's construction time (docks included; fish traps by fishing boat) and abandoned sites get re-crewed
- Military AI: training queues, research priorities, aggression escalation; fog-honest targeting via the WorldQuery sighting layer (units targetable only while seen, buildings remembered once scouted, primary enemy TC stays map knowledge); mop-up mode — with no enemy buildings left to siege, the minimum-army gate drops to 1 and any standing military hunts the last sighted units
- Naval AI: ship training, galley patrols (enemy ships first, then known enemy docks/fish traps), transport assaults from 2 land military, fish-trap construction
- Defensive AI: base defense, TC rebuild, idle unit redeployment

**UI/UX:**
- HUD: resource display, population counter, age indicator, unit selection grid (40 max)
- Notification toasts with shortcut action buttons (`NotificationDisplay.push` accepts an `{icon, tooltip, callback}` action): attack/loss/built/destroyed toasts jump the camera to the spot (whole toast clickable + visible button), pop-cap offers one-click house placement, hero-low-HP locates the hero; the toast zone anchors above the REAL command-bar height at runtime (review via `tools/check_notifications.tscn`)
- Minimap with right-click move orders, resource/unit/building icons; enemy buildings remembered at last known position under fog (AoE2-style), forgotten only when re-scouted and gone
- Weather banner and countdown pill
- In-game pause menu (Resume, Settings, Surrender, Exit)
- Game-over screen with victory/defeat message; surrendering (or losing everything) while hostile sides remain shows the defeat panel but the match plays on — "Ver mapa" spectates the live battle (orders locked), the final result rebuilds the panel
- Match lobby with civ selection, map type, resource mode, victory mode, weather settings
- LAN lobby reuses the SAME lobby screen (`LobbyScreen.lan_mode`): live players panel (host + per-seat rows: joined human with colour/name/civ/kick, or host-configured Open/AI/Closed slot), per-player name+colour+civ picks, host-edited settings with live read-only summary on clients
- Tooltips for all buttons (buildings, units, technologies)
- Camera follow selected units
- Control groups: Ctrl/Cmd+1..9 assign, 1..9 recall, clickable HUD chips (double-click centers camera); SPACE jumps to the last attack alert (5-entry ring, clickable attack toasts)

**Polish:**
- Procedural body animation for all units (walk, attack, work)
- Flying arrow projectiles (visual only)
- Readable Polygon2D figures for all units/buildings/animals (redesigned from placeholder silhouettes — villagers, soldiers, riders, archers, ships, siege, civ-unique units, deer/sheep)
- Random visual gender for all human units (50/50, long hair for female); persisted across save/load; cosmetic only — except the Harimaguada, always female by lore
- Lore-true landmark visuals: the Temple is an almogarén (open dry-stone Canarian shrine), the Lumber Camp a logging yard, the Mining Camp a timber-framed dig, the Mill a stone tower with canvas sails (`check_temple_look` / `check_camps_look` harnesses)
- Distinct heroine sprites (long hair, golden circlet, gown); hero gender selectable in the lobby (Random/Male/Female)
- Team-colour building accents (roofs, flags, banners, awnings, domes, sails) via the `Team*`-node accent system in `building_base.gd`, plus player colour stripes
- Ground shadows under units and buildings
- Animated water shader (swell + coastal foam), terrain detail shader, animated caldera lava, ambient lighting + vignette
- Smooth terrain-zone blending and rounded sandy coastlines
- Animal walking gait (deer/sheep legs trot); unit & animal orientation follows travel direction
- 2D physics interpolation enabled (smooth movement at high render framerates)
- Tall stone tower visual for Watch Tower
- Selection indicators (green circle for player, yellow for allies)
- Hero energy aura (animated Dragon Ball-style golden flame, `HeroAura`; reviewed via `tools/check_hero_aura.tscn` screenshots) + locate-hero HUD button next to the idle-unit buttons
- Rally point markers for production buildings
- Health bars for units/buildings (hidden when full HP); BuildingBase creates the building bar at runtime — most building scenes ship without a HealthBar node, and before this nothing ever showed building HP (damage LOOKED like it wasn't applied)
- Progressive damage fire/smoke on buildings (smoke from the FIRST point of damage, flames <50%, heavy fire <25%; repair clears it)
- Sound effects: select, attack, build, gather, hit (with spatial attenuation)
- 3-way "Unit style" video setting (Classic / Enhanced / Redesigned, default Classic, cycled live from both settings panels): ENHANCED is the reversible `UnitEnhancer` layer (ink contour, vertical volume shading, extra procedural animation — idle breathing, walk lean/bounce, attack snap); REDESIGNED swaps in the lore-driven from-scratch `UnitRedesign` rigs (tamarco villagers, magado warrior line, banot pikeman, working bow draws, decoupled horse/rider gallop, brindle Presa trot, pendulum ram log / snapping mangonel arm / pack-deploy trebuchet beam, side-profile lateen/cog/galley hulls with rowing oars, all 8 civ-uniques, circlet-and-cape heroes) with its own full state-machine animation

### Recent Bug Fixes (Production-Ready Milestone)

1. Cover Fire: register as pending action, move into range before firing
2. Spawn positioning: outward spiral physics query prevents unit overlap
3. Minimap: fixed revealing entire resource clusters at once
4. Weather HUD: fixed banner/pill centering at non-1920 resolutions
5. Villager: fixed `_animate_body` signature mismatch
6. Town Center: fixed initial graphic, arrow projectile rendering
7. WarGalley: fixed HP check using wrong property names
8. Conquest victory: fixed missing DEAD/DESTROYED node checks
9. Conquest defeat: fixed never triggering for human player
10. Regicide: fixed per-mode victory condition logic
11. Market: fixed page reset on cooldown refresh
12. Volcanic Ash: fixed building damage application
13. Nav mesh: skip obstacles for terrain player civ can traverse
14. Release script: resolve game repo path correctly

### Known Limitations (Planned for Future Milestones)

- Multiplayer: phases 1–2 shipped (LAN host-authoritative session + unified lobby + client→host command pipe + host→client state replication at 15 Hz with puppet mirror worlds and interpolation via `StateReplicator`); queue/research/market/weather/arrow+boulder mirroring, robustness (drop/surrender→resignation, host-left dialog, replicated pause, delta+keyframe stream under the ENet MTU), chat (lobby+in-game, system lines), in-lobby rename Internet hosting via UPnP, and a Steam transport prototype (GodotSteam GDExtension, lobbies+invites+Valve relay on test AppID 480), mid-match reconnection (reserved seats + full resync, `check_net_rejoin` gate), multiplayer save/resume (host saves roster + per-player fog, resume lobby reserves the original seats, absent players may join mid-match; `check_net_resume` gate) and a version-check handshake shipped; LAN/Internet split menu entries; pending: live Steam test
- Lockstep simulation still open: requires deterministic, physics-free unit movement (command wire format is already shared)
- Balance tuning from real playtesting pending

## Sub-agents

Five specialized agents live in `.claude/agents/`. Invoke them by name with `@agent-name` or via the Claude Code agent system.

| Agent | File | When to invoke |
|---|---|---|
| `developer` | `.claude/agents/developer.md` | Implementing features, fixing bugs, any coding task |
| `tester` | `.claude/agents/tester.md` | Writing GUT tests, expanding coverage, investigating test failures |
| `code-reviewer` | `.claude/agents/code-reviewer.md` | Before merging a branch, after a large refactor |
| `docs-keeper` | `.claude/agents/docs-keeper.md` | After any `.gd`/`.tscn`/`.tres` change to sync documentation |
| `performance-checker` | `.claude/agents/performance-checker.md` | When a system touches `_process`/`_physics_process`, after adding unit-heavy features, or when performance feels off |

### Recommended workflow

```
developer  →  code-reviewer  →  tester  →  docs-keeper
```

1. `developer` implements the feature
2. `code-reviewer` reviews the diff — blockers must be fixed before proceeding
3. `tester` writes or updates GUT tests for the changed code
4. `docs-keeper` updates `docs/` and `CLAUDE.md` to reflect the new state
