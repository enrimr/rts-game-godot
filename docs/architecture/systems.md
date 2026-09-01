# System Design Details

## Command Pattern (player orders)

Every simulation-mutating player intent is a `GameCommand`
(`scripts/game/commands/game_command.gd`) submitted through the `CommandBus`
autoload (`scripts/core/command_bus.gd`) — input/UI code decides *what* the
player meant, the command *does* it. Commands carry only serializable data:
entity IDs from the `EntityRegistry` autoload (`scripts/core/entity_registry.gd`),
positions and type strings, never node pointers. `CommandBus.submit()`
tick-stamps each command into the match log and executes it; the log is the
foundation replays build on and the exact payload a LAN lockstep session will
exchange (`save_log()` writes it as JSON lines, `command_from_dict()` rebuilds
any entry).

The nine command classes live in `scripts/game/commands/`:

| Class | kind | Verbs / payload |
|---|---|---|
| `UnitPointCommand` | `unit_point` | move / attack_move (formation ring fan-out) / attack_ground; unit IDs + point |
| `UnitTargetCommand` | `unit_target` | attack / gather (restores depleted farms & fish traps, routes fishing boats to their dock; optional `drop_id` pins the drop-off, used by the AI) / build / drop_off / board (walk-then-board poll) / board_instant (the AI's distance-free garrison) / set_drop_off; unit IDs + target ID |
| `UnitActionCommand` | `unit_action` | stop / delete / hero_ability / trebuchet_toggle / scout_explore(_stop); unit IDs |
| `TransportCommand` | `transport` | unload_all / unload_one(index) / move_unload(pos); transport ID |
| `ProductionCommand` | `production` | train(unit_id — empty = the TC's no-arg signature) / cancel_train(index) / research(tech_id) / cancel_research (full refund); building ID |
| `BuildingActionCommand` | `building_action` | set_rally(pos) / gate_lock / delete (routes through take_damage); building ID |
| `MarketCommand` | `market` | buy / sell / hire (spawns the Fenicios mercenary at the rally point); building ID + item |
| `PlaceBuildingCommand` | `place_building` | building type + positions (a wall drag is ONE command with the whole run) + rotation + builder IDs; pays per site, stops when the stockpile runs out. `instant` completes construction immediately (the AI); `EXTRA_SCENES` maps the AI-only `town_center_ai`; `last_placed` hands the created nodes back to the submission site (runtime only, never serialized). Costs resolve at execute time from `WorldPlacement.building_costs` — the single .tres-backed table player and AI both pay (the old hand-written player table missed university/market/temple, so the player built them for free) — and are never part of the payload, so a remote command cannot name its own price |
| `AdvanceAgeCommand` | `advance_age` | player only |

Ownership is validated at execute time (`GameCommand._own_entities` keeps only
entities whose `player_id` matches the command's), so a hostile or replayed
payload cannot order another player's units. Deeper validation (costs, rosters,
queue caps) lives where it always did — `order_train`, `AgeManager`,
`TechManager`, `Market` — so the commands stay thin.

`EntityRegistry` assigns sequential IDs: `CommandBus.start_match(world)` (the
last line of `GameWorld._ready`) rescans the world in tree order and the
`unit_spawned` / `building_placed` signals register everything created after
that, so identical simulations hand out identical IDs. `id_of()` lazily
registers stragglers no signal covers.

**The AI submits through the bus too**, with its own `player_id`: villager
production queued at its Town Center (`ProductionCommand` — the SAME queue,
cost and train time the player pays; the AI used to spawn villagers
instantly, which unbalanced the early game), gather assignments with pinned
drop-offs,
training, research, age advance, batched attack orders (one command per
target), naval patrol moves, transport loading (`board_instant`) and all
building placement (`PlaceBuildingCommand` with `instant` + `costs_override`;
the rebuilt TC uses `EXTRA_SCENES["town_center_ai"]` and reads its node back
from `last_placed`). AI decision-making, cooldowns and built-count bookkeeping
stay in the AI modules — only mutations cross the bus.

**MatchRng** (autoload, `scripts/core/match_rng.gd`) is the single seeded
stream for all simulation randomness — unit spawn jitter, gender roll, animal
wander, scout waypoints, transport unload angles, hero summon offsets, the
whole weather state machine and projectile drift, and every AI position
search. `GameWorld._ready` seeds it with the match seed (same one the save
stores), and `SaveManager` persists the mid-match generator state (as a String
— the state is 64-bit and JSON numbers are doubles), so a loaded game
continues the exact draw sequence. Audio noise buffers keep using the global
RNG on purpose: local-only, never feeds back into state.

**Decision timers tick on physics frames.** `AIPlayer`, `WeatherManager`,
`AgeManager` and `TechManager` accumulate `_physics_process` deltas (a fixed
step = a deterministic tick count), and the simulation `SceneTreeTimer`s (AI
TC-rebuild retries, the board poll) use `process_in_physics`. Measured with
`tools/check_sim_fingerprint.tscn` (fixed seed, exact physics-tick window,
canonical census + full command log): over a 60 sim-second window two runs
produce **identical command logs** — the whole decision layer replays — while
entity positions diverge, because movement rides Godot physics + RVO
avoidance. That position drift is the remaining non-determinism: it leaks
into draw counts (wander/jitter draw at arrival times) and eventually into
position-dependent decisions.

What does **not** go through the bus: selection, control groups, camera, HUD
state, the placement ghost, `show_path` (debug visual) and all click feedback
(flashes, order sounds) — local-only concerns that must not replay or cross
the network. Remaining work before lockstep/replays, in dependency order:
deterministic movement (fixed-step, physics-free unit motion — the big one),
production-building/arrow/`unit_base` `_process` logic onto physics ticks,
the async navmesh rebake's completion frame, fog visibility timing, and
execute-side placement validation.

Migrating cover fire surfaced a real bug, now fixed: `_order_attack_ground_all`
used to emit `minimap_move_order`, whose handler synchronously issued
`_order_move_all` — the move overrode the just-issued attack-ground order, so
cover fire cancelled itself.

Gated by `tests/unit/test_command_bus.gd` (registry determinism, serialization
round-trips for all ten kinds, ownership filtering, log stamping, formation
determinism, replayed-entry equivalence), `tests/unit/test_match_rng.gd`
(seed-replay property) and `tools/check_command_bus.tscn` (a real match driven
exclusively through the bus: move + train + place, then a wait that asserts
the rival AI's commands land in the same log, all entries rebuildable).

## Multiplayer (host-authoritative)

`NetworkSession` (autoload, `scripts/multiplayer/network_session.gd`) runs a
host-authoritative session over ENet, designed LAN-first but Internet-capable
(the transport is identical; Internet later adds UPnP connectivity and the
phase-2 interpolation buffer absorbs latency).

- **The host is the single simulation authority.** On a client,
  `CommandBus.submit` redirects every command over the wire instead of
  executing; the host receives it, REPLACES its `player_id` with the sender's
  assigned player (identity comes from the connection, never the payload — a
  hostile client cannot order another player's units), and runs it through
  `CommandBus.submit_remote`.
- **Match start**: the host freezes a `snapshot_config()` of MatchConfig plus
  a shared seed (`MatchConfig.forced_seed`, read by `GameWorld._ready` ahead
  of the CALIMA_SEED env) and broadcasts it; every machine loads game_world
  with identical settings, so map generation and `EntityRegistry` hand out
  IDENTICAL entity IDs on all sides — command payloads reference entities by
  those IDs across the wire.
- **Mixed rivals**: the start config carries a `humans` list
  (`NetworkSession.match_human_ids`, default `[0]` offline). `WorldSetup`
  spawns every rival's starting assets (TC, villagers, scout, hero) but
  creates the `AIPlayer` brain only on the simulation authority
  (`not is_client()`) and only for non-human rivals
  (`not is_human_player(rival_id)`) — a client-side brain would submit
  through the redirected CommandBus stamped with the client's identity.
- **Lobby** (`LanLobby`, `scripts/ui/lan_lobby.gd` → `LobbyScreen` with
  `lan_mode = true`): the entry card only picks a name and hosts/joins; once
  the session is up it swaps to the SAME `LobbyScreen` the skirmish uses.
  In `lan_mode` the rival count/civ rows are replaced by a players panel:
  the host row, then one row per lobby seat — a connected human (colour
  swatch, name, civ, host-only Kick) or a host-configurable slot
  (Open / AI with civ dropdown / Closed, `NetworkSession.lobby_slots`).
  `open_seats_left()` refuses connections when no open slot remains. Every
  human picks their own colour (host validates — taken colours rejected and
  greyed) and civilization (`request_civ`, validated against the civ .tres)
  via the right-hand civ grid; both live in the host-authoritative roster and
  replicate via `roster_changed`. The host edits the match settings in place
  and `broadcast_lobby()` pushes them (config snapshot + slots) so clients
  render a live read-only summary. On start the host derives
  `rival_civ_ids` = human civs (roster order) + AI-slot civs, sets
  `rival_count`, and the colour picks install `PlayerColors` overrides on
  every machine.
- **Phase 2 (shipped, first cut)**: `StateReplicator`
  (`scripts/multiplayer/state_replicator.gd`, added by `GameWorld` when
  online). The host samples the simulation every 4 physics ticks (15 Hz)
  and streams unit position/state/HP and building HP/state by entity id
  (unreliable-ordered RPC via `NetworkSession.send_state`); spawns,
  removals and the match outcome go reliable (`send_events`). A client
  puppets its mirror world — physics processing OFF (no local simulation,
  no local damage; `_process` stays on for animation/depth) — and
  interpolates between snapshots, deriving `velocity`/`current_state` so
  walk/attack animations read. Host-spawned entities materialize from
  spawn records (scene/script/unit_data/civ/gender) and adopt the host's
  id via `EntityRegistry.register_as`. Stockpiles/population/ages ride the
  snapshot into the managers' `apply_remote` (emit-on-change → client HUD
  live). The `local_player_id` sweep landed with it: command submit sites,
  selection filters, fog perspective, minimap, alerts and the game-over
  title all follow `NetworkSession.local_player_id` (0 offline), and
  victory is decided only by the authority.
- **Phase 2 polish (shipped)**: building rows carry extras — production
  queue + train timer (puppets mirror them and never advance training
  locally; `train_queue_changed` re-emits on composition change), active
  research (`TechManager.apply_remote_research`/`clear_remote_research`)
  and market offsets; researched-tech lists and resource-node amounts ride
  a slow ~1 Hz channel; weather replicates verbatim
  (`WeatherManager.apply_remote`, client state machine gated off — the
  MatchRng streams diverge once the host consumes AI draws); arrows echo
  as visual-only projectiles (`EventBus.projectile_spawned` → client
  spawns `Arrow` with `echo = true`); `take_damage` is a no-op on puppets;
  game-speed buttons hidden on clients.
- **Robustness (shipped)**: a client dropping or surrendering mid-match
  becomes a resignation (`NetworkSession.player_resigned` →
  `WorldVictory.handle_resignation`, any victory mode — the match ends when
  nobody is left to fight); a vanished host raises `connection_lost` on
  clients (dialog → menu); the host's pause replicates
  (`NetworkSession.notify_pause` → client freezes with a banner) while a
  client's ESC menu never pauses the authoritative sim. The stream is
  delta-based: unreliable deltas carry only changed rows, a reliable
  keyframe every 15th snapshot heals losses, meta ships on change, and
  oversized deltas (>1300 B) route reliably — nothing exceeds the ENet MTU.
  Gate: `tools/check_net_robustness.tscn` (CALIMA_ROB_CASE =
  drop | resign | hostleft, two processes).
- **Chat (shipped)**: `NetworkSession.send_chat` → host validates the
  sender and rebroadcasts `chat_received` (120-char cap, trimmed). The LAN
  lobby shows a colour-coded log + input under the players panel; in match
  the `HudChat` component (online only) opens with Enter, swallows keys
  while typing (hotkeys listen in `_unhandled_input`), and fades lines
  above the command bar.
- **Siege echo (shipped)**: `SiegeFx.launch_boulder` is the shared arcing
  stone (host visual + client echo; the Mangonel finally shows a projectile
  — damage timing untouched); the fx stream carries a kind (arrow|boulder).
- **Internet hosting (shipped, UPnP)**: the lobby's "Internet…" button runs
  `NetworkSession.setup_internet` on a thread (UPnP discover → UDP port
  mapping → external address). Success swaps the header address for
  "Internet: <ip> (port)"; failure instructs manual port forwarding. The
  mapping is removed on leave. Clients join by typing the public IP.
- **Steam transport (prototype, AppID 480)**: GodotSteam 4.22 GDExtension
  vendored (`addons/godotsteam`, macOS/win64/linux64). `ensure_steam()`
  boots the API lazily; `host_steam()` = public lobby tagged
  `game=calima_fota` + native `SteamMultiplayerPeer.host_with_lobby`;
  clients browse tag-filtered lobbies or accept friend invites
  (`join_requested` → `connect_to_lobby`). Everything above
  `multiplayer_peer` (seats, commands, replication, chat) is untouched.
  Missing Steam client degrades to a notice; `steam_appid.txt` (480) must
  ship next to exported executables; swap the real AppID in
  `NetworkSession.STEAM_APP_ID` once Steamworks registration lands.
- **Reconnection (shipped)**: a dropped human's seat is reserved for
  `rejoin_grace_sec` (90 s; env `CALIMA_REJOIN_GRACE`) — "disconnected,
  holding their seat" in chat, match keeps running; grace expiry becomes
  the old resignation. A mid-match connection is parked until its profile
  claims a vacant seat (roster-name match, or the single vacancy), gets its
  OLD player id back, the frozen match config (`in_progress` flag) and —
  once its seed-identical world boots (`notify_resync_ready`) — a one-shot
  full resync (`StateReplicator.full_resync_to`): removals of dead initial
  entities, spawn records for everything born since, full keyframe. The
  connection-lost dialog offers "Reconectar" (`rejoin_last`: last IP or
  Steam lobby). Gate: `tools/check_net_rejoin.tscn` (three processes).
- **Menu split**: "Multijugador LAN" vs "Multijugador Internet"
  (`LanLobby.internet_mode` — Steam-only card); Steam sessions pin roster
  names to the Steam persona (rename hidden + `_apply_rename` refuses).
- **Teams (shipped)**: `MatchConfig.player_teams` + `GameManager.are_allied`
  choke point (auto-acquisition, WorldQuery, towers, gates, fog shared
  vision, team victory in conquest/regicide/resignation, HUD winner-side).
  Team pickers in both lobbies (`request_team` over the wire, AI-slot
  teams); persisted in saves.
- **Waypoints + patrol (shipped)**: Shift+right-click queues movement legs
  (`UnitBase._waypoints`, command-layer clearing), Patrol [R] bounces
  attack-move legs between two points; both ride `UnitPointCommand`
  (`queued` flag / `patrol` verb).
- **Steam social (shipped)**: roster carries steam ids → real avatars in
  the players panel; rich presence set/cleared with the session; Alt+click
  minimap pings (host-validated, ally-filtered display, SPACE-ring memory).
- **Allied AI (shipped)**: an AI team-mate sends assist squads when an ally
  is raided (attack-move, team ping, ally-only toast; 30 s cooldown, spare
  army required) and announces its offensives with a target ping
  (`ally_message` on the bus, replicated; gate `tools/check_ally_ai.tscn`).
- **Mercenaries finished**: every civ hires at the Market (age-gated,
  localized labels/tooltips, unit miniatures, cooldown badges); Fenicios
  pay 25% less (`Market.get_mercenary_cost`).
- **Hero abilities audited**: `tests/unit/test_hero_abilities.gd` casts all
  16; fixed instant-ability cooldown skip (+fizzle/kill-refund flags), the
  Mercenary Pact crash, the mouse-dependent Boarding dash, missing team
  awareness and the Calima cloud parenting.
- **Phase 2 still pending**: live Steam-lobby manual test. Migration to lockstep stays open: the command wire format is
  shared, only the return channel changes — it requires the
  simulation-determinism milestone (movement off Godot physics).

Gated by `tests/unit/test_network_session.gd` (config snapshot round-trip,
JSON-serializable, offline defaults, open-seat accounting, civ-pick
validation, humans-list install/reset) and the two-process
`tools/check_net_smoke.tscn`: a real client joins a real host, picks a civ,
receives the config (seed + assigned player 1 + civs + humans), boots the
mirror world (asserting it runs ZERO AI brains and that mirror entities are
puppets), sends a move command for its scout by entity ID, and the host —
running a mixed human + AI-slot match — asserts the AI brain exists only for
the AI rival, the command arrived stamped as player 1, and the scout
physically moved in its simulation; the client then asserts the movement
came BACK through the replication stream and its own mirror scout moved.

## Economy System

Resources: Food, Wood, Gold, Stone (matching AoE2 exactly).

Villagers gather from `ResourceNode` objects on the map. Each villager carries up to 10 units and returns to a drop-off building. `ResourceManager` is the single source of truth for stockpiles.

## Combat System

All damage flows through `unit.take_damage(amount, source)`. Armor reduces incoming damage. Range is checked via `attack_range` on `UnitResource`. Combat uses the AoE2 damage formula:

```
damage = max(1, attacker.attack - target.armor_melee)
```

**Melee attackers never park out of reach.** Two systemic bugs made whole
armies look unable to damage buildings: (1) `NavigationAgent2D` declares
arrival `target_desired_distance` (24 px) short of the approach point, so a
short-reach unit could freeze 3 px outside its strike range forever — the
chase branch now closes that last gap on a straight line WITHOUT avoidance
(RVO crushes a push toward a wall flanked by parked allies; the building's
collision is the real stop); (2) a blocked building-attacker used to exhaust
`MAX_STUCK_RETRIES` and go permanently idle — it now walks `APPROACH_STEPS`
(alternating ±45°…180° around the footprint, held until a strike lands or the
steps run out) before giving up, so crowds spread around the building instead
of quitting on the jammed face.

**Watch towers auto-attack with visible arrows.** `WatchTower._physics_process`
picks the nearest enemy in the `"units"` group within `ATTACK_RANGE` (220 px)
and launches the Archer's `Arrow` (damage and `unit_attacked` applied on
impact) from the tower top. That group is load-bearing and joined by
`UnitBase._ready` — no scene declares it, so before that line it was empty and
tower targeting, the Menceyes Guard aura and several hero abilities that scan
it silently did nothing. Arrow spawns call `reset_physics_interpolation()` or
the spawn teleport ghosts across the screen for a frame.

**Combat stances (AoE2).** Every unit carries `UnitBase.Stance`
(AGGRESSIVE default / DEFENSIVE / STAND_GROUND / PASSIVE), set through the
`UnitActionCommand` `stance_*` verbs. Stances govern AUTONOMOUS behaviour
only — an explicit attack order always chases. All four auto-acquisition
paths (range Area2D, retaliation, guard response, post-kill rescan) funnel
through `_auto_engage`, which the stance can veto and which marks the
engagement as auto: PASSIVE never engages; STAND_GROUND strikes in reach but
breaks off instead of chasing; DEFENSIVE chases up to `DEFENSIVE_LEASH`
(200 px) from its anchor — the latest ordered position — then walks home and
refuses new fights until it is back inside the leash.

**Formations.** `UnitPointCommand` carries the formation each group move was
issued with (`line` / `box` / `spread` / `rings`; the HUD buttons only set
WorldCommands' local choice for the NEXT move). Line/box/spread are rank-
ordered grids facing the approach direction — melee front, ranged (attack
range > 2 tiles) behind, unarmed next, siege rear — computed deterministically
by the same static helpers the tests exercise.

**Garrison.** `BuildingBase` owns the garrison API (`garrison_capacity`,
`can_garrison_unit`, `garrison_unit`, `ungarrison_all`): land units only —
never ships or siege — and only into COMPLETE buildings; occupants are hidden
and paused, ejected via the spawn spiral, and DIE if the building is destroyed
(the AoE2 rule). WatchTower holds 5, the player's TC 10. Right-clicking an own
TC/tower garrisons MILITARY only (`WorldCommands.garrisons_by_right_click` —
Villager inherits `is_combat_unit() == true`, so without the explicit
exclusion villagers entered buildings they were sent to repair). Villagers
shelter through two explicit controls: the Garrison button on their panel
(a pending map-click action — click one of your buildings) and the Town Bell
on the TC (one ring shelters every villager in its nearest TC/tower with
room via the pure `bell_assignments` — overflow spills to the next building;
ringing while anyone is sheltered ejects every garrison). The shared building
volley (`_ranged_attack_arrows()`) adds one arrow per occupant — the TC only
shoots while garrisoned.

**Damaged buildings burn progressively** (`BuildingDamageFx`, attached by
`BuildingBase` and `TownCenterBuilding`): smoke from the FIRST point of damage, flame tongues
join below 50 %, heavy fire and dark smoke below 25 %; repairs walk the stages
back down, and construction sites/rubble never burn (only `COMPLETE` state).
Purely visual — CPUParticles2D in the upright billboard space, render-side
randomness, never MatchRng. Reviewed via `tools/check_damage_fx.tscn`
(real-renderer screenshot of the four stages plus a tower firing).

## Pathfinding

Uses Godot's built-in `NavigationAgent2D` on each unit. Navigation regions are updated when buildings are placed or destroyed.

**RVO avoidance is tuned programmatically** (`UnitBase._tune_avoidance`, one
source — the scenes stay at engine defaults, which are wrong for an RTS):
`max_speed` = the unit's `move_speed` × 1.6 (the default 100 CLAMPS the
avoidance-safe velocity — the 180 px/s Scout moved at 55 % of design speed),
`neighbor_distance` 80 px (default 500 made armies brake for units half a map
away — the molasses jams), `max_neighbors` 7, `time_horizon_agents` 0.7, and
the agent radius mirrors the physics footprint (`_collision_radius`, capsule/
circle/rect aware). `avoidance_priority` is dynamic: 0.7 while moving, 0.4
idle — parked units yield to marching ones instead of both bowing to each
other. Gated by `tests/unit/test_avoidance_tuning.gd`.

**Buildings have NO RVO avoidance obstacle.** They used to carry one at
collision + 16 px per side — larger than the navmesh carve margin (6 px +
agent radius) — so two grid-adjacent buildings sealed the very corridor the
mesh had opened between them: the path threaded the gap, the physics gap fit
the unit, and the RVO solver returned a safe velocity of exactly ZERO forever
(the frozen-villager playtest bug). The navmesh is the single static
authority; physics collision is the hard backstop. Resource nodes keep their
small RVO obstacle: its margin (±20) sits INSIDE their mesh carve (±24.5), so
it smooths steering without ever contradicting the path.

Three `NavigationRegion2D` nodes live in `game_world.tscn`, distinguished by their
`navigation_layers` bit; every agent picks exactly one of them:

| Region | Layer | Agents | Surface |
|---|---|---|---|
| `NavigationRegion2D` | 1 | Land units | Land only (ocean excluded on Islands maps) |
| `OceanNavigationRegion2D` | 2 | Ships | Ocean only (islands are obstructions) |
| `AmphibiousNavigationRegion2D` | 4 (`NavMeshBuilder.AMPHIBIOUS_LAYER`) | Amphibious land units (Tidecaller) | The whole board, land and water alike |

The amphibious mesh exists because a unit cannot simply be given layers 1 **and**
2: both meshes are baked with an `agent_radius` of 10 px, so each one stops ~10 px
short of the shoreline and the two never share an edge. An agent on both layers
would still be trapped on its island. One continuous mesh is the only way across.

`WorldPlacement._do_nav_rebake()` rebakes the land **and** amphibious regions after
every building placement or demolition (`_rebake_region()`, one async bake per
region, with the callback bound to its region). Without the second bake a
Tidecaller would path straight through buildings the land mesh already routes
around.

## Amphibious Movement

Water permission is a **unit** capability, not a civ flag:

```gdscript
# UnitBase — land units stay on land no matter which civ owns them
func is_amphibious() -> bool:
	return false
```

`ShipBase` returns `true`. `Tidecaller` returns
`TerrainManager.civ_can_traverse_ocean(civ_id)`, so a future amphibious unit only
needs `can_traverse_ocean = true` in its civilization resource. The flag is passed
straight into the terrain queries (`get_speed_mult`, `is_impassable_for`,
`nearest_passable`) through `UnitBase._safe_destination()` and `_nav_velocity()`.

Two consequences that used to be bugs:

- An Atlantes **land** unit is refused a water destination. Previously permission
  came from the civ, so any Atlantes unit could be sent to sea, land on the
  ocean-free land mesh, and freeze (an off-mesh `target_position` makes
  `is_navigation_finished()` return true immediately).
- `TransportShip._disembark_position()` deliberately asks for a *land* tile even
  for an amphibious passenger, so troops land on the beach instead of being
  dropped into the surf off the land mesh.

Speeds in the water come from civ data rather than a hardcoded constant:
`TerrainManager.deep_water_speed(civ_id)` reads `stat_multipliers.deep_water_speed`
and falls back to `DEEP_WATER_SPEED` (0.60). Shallow water (ocean within
`SHALLOW_WATER_DEPTH` of the coast) is waded at full speed. Gated by
`tests/unit/test_shallow_water.gd` and the `tools/check_amphibious.tscn` harness.

## Terrain Impassability

`TerrainManager` (autoload) is the single authority on whether a world position is passable for a given actor.

**Key API:**

| Method | Signature | Description |
|---|---|---|
| `is_impassable_for` | `(world_pos: Vector2, civ_id: String, amphibious: bool = false) -> bool` | Returns `true` if the tile at `world_pos` is impassable for the given civilization; ocean is passable only for amphibious actors |
| `nearest_passable` | `(world_pos: Vector2, civ_id: String, amphibious: bool = false) -> Vector2` | Radial search (30 rings × 24 px step) returning the closest passable position |
| `get_speed_mult` | `(world_pos: Vector2, civ_id: String, amphibious: bool = false) -> float` | Terrain speed multiplier; `0.0` means blocked. Amphibious actors get `1.0` in shallow water and `deep_water_speed(civ_id)` beyond it |
| `deep_water_speed` | `(civ_id: String) -> float` | `stat_multipliers.deep_water_speed` from the civ resource, default `DEEP_WATER_SPEED` (0.60) |
| `civ_can_traverse_ocean` | `(civ_id: String) -> bool` | The `can_traverse_ocean` civ flag — the gate for amphibious *land* units |
| `nearest_ocean` | `(world_pos: Vector2) -> Vector2` | Spiral search returning the closest ocean tile — used to guarantee ship spawns land in water |
| `distance_to_coast` | `(world_pos: Vector2) -> float` | Distance to the nearest land/ocean boundary, `INF` on a landlocked map |
| `bake_minimap_texture` | `() -> ImageTexture` | Generates a 256×256 terrain texture used by the minimap renderer |

`distance_to_coast` is analytic — the closest point on every land outline segment
and on every OCEAN zone circle — and memoized per `COAST_CACHE_CELL` (24 px)
grid cell, evaluated at the **cell centre** so the answer never depends on which
query filled the cell first. The cache is dropped by `reset()`, `add_zone()` and
`set_land_polys()`; those three are therefore the only legal ways to mutate
terrain. The previous implementation was an outward ring search costing ~1.8 ms
per call: sea fog asks for the coastal distance once per unit and building
several times a second, which by itself exceeded the whole frame budget and made
the game crawl whenever Sea Fog rolled in. `_point_in_any_land` also
bounding-box rejects (`_land_bounds`) before running the polygon test.
Gated by `tests/unit/test_coast_distance.gd`.

**Integration points:**

- `UnitBase` carries a `civ_id: String = ""` property. Its `_safe_destination(destination: Vector2) -> Vector2` helper calls `TerrainManager.nearest_passable(destination, civ_id, is_amphibious())` before any nav agent assignment.
- `ShipBase` overrides `_safe_destination` to snap to `nearest_ocean` instead: ships
  are amphibious, so `nearest_passable` considers land passable and would leave a
  nav target on the shore — off the ocean navmesh, where the agent reports
  "navigation finished" immediately and the ship never moves.
- All unit `order_move` implementations (`Militia`, `Archer`, `Pikeman`, `Scout`, `HeavyScout`, `Knight`) and `Villager._start_move_to` call `_safe_destination` before setting `nav_agent.target_position`.
- `Animal` nodes call `TerrainManager.nearest_passable(pos, "")` in `order_move`, `_pick_wander_target`, and `_start_flee` so fauna never path onto water or other impassable terrain.

## NavMesh Carving

`NavMeshBuilder.build(parent, map_half, land_polys)` runs at map generation time
(called from `MapGenerator._run`):

- **Carves impassable terrain zones into the meshes** (`zone_obstructions`):
  risco and caldera always, malpaís on every mesh except the layer-8 one.
  This is what makes paths route AROUND lava: the old approach parented
  `NavigationObstacle2D` nodes (RVO-only — they never touched the baked
  mesh), so paths crossed the zones and units ground to a halt against the
  rim where the speed multiplier hits 0. The runtime rebake in WorldPlacement
  re-injects the same zone obstructions, or the first building placed would
  erase the carve.
- Bakes the land mesh (layer 1) on every map type: the board (or the islands)
  minus all impassable zones.
- Bakes the malpaís-traversal mesh (layer 8, `MALPAIS_LAYER`): identical to
  land but with malpaís left walkable. Land units of a civ with
  `can_traverse_malpais` switch to this layer in `UnitBase._ready`, so the
  Guanches bonus survives the carving.
- Bakes the amphibious mesh (layer 4) as the full playable square minus the
  impassable zones — its point is spanning land AND water, never split by the
  shoreline agent-radius insets.
- On **Islands** maps the land/malpaís meshes use the per-island land polygons
  as the walkable surface, and the ocean mesh is baked as the board minus
  those islands.

This means ships navigate their own layer, amphibious units navigate the
continuous layer, traversal civs cross malpaís on layer 8, and plain land
units are blocked by the land mesh boundaries. Gated by
`tools/check_volcanic_nav.tscn`: a militia ordered to the far side of a
caldera on a Volcanic Coast map must arrive AND never enter the zone.

### The half-pixel bake nudge

Every bake — the generation-time one in `NavMeshBuilder._bake` and the debounced
runtime rebake in `WorldPlacement._rebake_region` — inflates the region's agent
radius by `NavMeshBuilder.RADIUS_NUDGE` (0.5 px).

The reason is a hard failure mode of Godot's 2D navmesh baker. Player buildings
snap to a 16 px grid and carve with a 6 px margin
(`BuildingBase._nav_bake_half_extents`), so two buildings placed *diagonally* can
leave a 20 px carved gap on both axes — and once each footprint is inflated by the
10 px agent radius, the two holes meet at exactly one point. The convex partition
fails on that pinch and returns an **empty polygon for the whole board**, not just
that corner: `NavigationPolygon polygon convex partition failed`. The rebake then
keeps the previous (uncarved) mesh, so the failure shows up as buildings that
units path straight through plus an error every debounce tick.

Baking half a pixel wider makes the two holes overlap by 1 px, Clipper merges
them, and the partition succeeds. In fuzzing (1500 dense grid-snapped layouts)
the nominal radius failed on 5.5 % of them and the nudged radius on none.
`NavMeshBuilder.RADIUS_FALLBACKS` supplies three further sub-pixel offsets, tried
in order when a bake still comes back empty; `WorldPlacement._on_nav_bake_done`
walks that ladder and only then keeps the previous mesh, warning once per region
instead of re-requesting the bake forever on identical geometry.

Gated by `tests/unit/test_nav_bake_nudge.gd` (the minimised two-footprint case)
and `tools/check_nav_bake_diag.tscn` (two real houses placed diagonally in a live
match; fails on pre-nudge code).

## Fog of War

`FogOfWar` (`scripts/map/fog_of_war.gd`) keeps one byte grid for the human player,
sized at `_ready()` from `MatchConfig.get_map_half()` plus `GRID_MARGIN` (200 px)
at `CELL_SIZE` = 50 px per cell — 56×56 on SMALL, 80×80 on MEDIUM, 112×112 on
LARGE (`grid_w`/`grid_h`/`map_origin`). It used to be a fixed 80×80 rect over
±2000 px, which left a 600 px ring of a LARGE map permanently unfogged: islands
at the margins showed on the minimap without ever being scouted. Three states per
cell: `STATE_UNEXPLORED` / `STATE_EXPLORED` / `STATE_VISIBLE`. Every
`UPDATE_INTERVAL` (0.12 s) `_tick()` demotes VISIBLE → EXPLORED, re-reveals from the
player's units and buildings, repaints only the dirty cells into the shroud texture,
and then applies entity visibility.

Reveal radius per watcher is `line_of_sight × 64 px` multiplied by three factors:

| Factor | Source | Notes |
|---|---|---|
| Weather | `WeatherManager.get_vision_multiplier(pos, 0)` | Calima / Sea Fog / Volcanic Ash, already scaled by civ weather affinity |
| Terrain | `TerrainManager.get_vision_mult(pos)` | Laurisilva canopy −30%; buildings skip it (laurisilva is not buildable) |
| Coast | `FogOfWar._coastal_vision_mult(pos)` | Civ `coastal_vision` multiplier, applied only inside `WeatherManager.COASTAL_ZONE_DEPTH` (400 px) of a shore |

`_coastal_vision_mult` is the only reader of the `coastal_vision` civ multiplier:
the Atlantes carry 1.50, so their units and buildings see 50 % further along any
shore — the same band sea fog operates in — and exactly 1.0 inland. The
`is_equal_approx(mult, 1.0)` fast path keeps the coast query out of the hot loop
for the other seven civs. Gated by `tests/unit/test_coastal_vision.gd`.

Visibility of entities is applied in `_apply_visibility()`: enemy units need a
VISIBLE cell and must not be fog-cloaked (see the sea-fog cloak rules under
[Weather System](#weather-system)), enemy buildings and resource nodes stay drawn
once their cell is EXPLORED (AoE2-style memory).

## Tech Tree System

Technologies are defined as `TechnologyResource` `.tres` files under `resources/technologies/`. Seventeen technologies are currently implemented:

| Technology | Researched at | Effect |
|---|---|---|
| `loom` | Barracks | Villager HP / armor |
| `fletching` | Barracks | Archer attack / range |
| `scale_barding` | Barracks | Cavalry armor |
| `bodkin_arrow` | Barracks | Archer attack |
| `chain_barding` | Barracks | Cavalry armor |
| `blast_furnace` | Barracks | Infantry attack |
| `plate_barding` | Barracks | Cavalry armor |
| `shipwright` | Barracks | Ship speed / cost |
| `forging` | Blacksmith | Melee attack |
| `padded_archer_armor` | Blacksmith | Archer pierce armor |
| `iron_casting` | Blacksmith | Melee attack |
| `siege_engineering` | University | Siege weapon effectiveness |
| `ballistics` | University | Projectile accuracy |
| `chemistry` | University | Projectile attack bonus |
| `sanctity` | Temple | Monk HP |
| `fervor` | Temple | Monk move speed |
| `atonement` | Temple | Monks can convert buildings |

`TechManager` (autoload) owns the research queue and applies effects when research completes. `CivBonusManager` (autoload) stores per-player multipliers derived from civilization bonuses and applied techs.

When a `TechnologyResource` has non-empty `upgrade_from_unit_id` and `upgrade_to_unit_id` fields, `TechManager` treats it as a unit upgrade: on completion it immediately replaces all live units of type `upgrade_from_unit_id` with instances of `upgrade_to_unit_id` (HP scaled proportionally), and the source building switches its training queue to produce the new type going forward. Upgrade techs are researched at the same building that trains the unit (Barracks for infantry upgrades, Stable for cavalry upgrades).

## AI System

`AIPlayer` (`scripts/ai/ai_player.gd`, `extends Node`) is the coordinator. It owns `BUILDING_SCENES` and `VILLAGER_SCENE` constants, wires `EventBus` signals, and runs on a 2-second `TICK_INTERVAL` tick (plus a 3-second `THREAT_CHECK_INTERVAL` scan). All substantive logic is delegated to four `RefCounted` modules that are instantiated in `_ready()` via `ModuleClass.new()` then `.setup(self)`. Each module holds a typed back-reference `var _ai: AIPlayer` and accesses sibling modules through `_ai._module.method()`.

| Module | Class | File | Responsibilities |
|---|---|---|---|
| `_construction` | `AIConstruction` | `scripts/ai/ai_construction.gd` | Building placement; placement-failure cooldowns (`_build_fail_counts`, `_build_cooldowns`); population-house management; loads all building costs at startup via `BuildingResource.get_cost_dict()` |
| `_economy` | `AIEconomy` | `scripts/ai/ai_economy.gd` | Villager spawning and idle-villager assignment; per-age resource-type target fractions; age-advance trigger; `find_nearest_resource` / `find_nearest_drop_off` helpers |
| `_military` | `AIMilitary` | `scripts/ai/ai_military.gd` | `AggressionLevel` enum (PASSIVE / ALERTED / AGGRESSIVE) with decay timer; Barracks, Stable, and SiegeWorkshop training; tech research priority queue (`_TECH_PRIORITY`); multi-target attack dispatch; control-zone threat detection and base defense |
| `_naval` | `AINaval` | `scripts/ai/ai_naval.gd` | Naval unit training; galley patrol and HP-based retreat (`GALLEY_RETREAT_HP_RATIO = 0.30`); transport boarding and `order_move_then_unload` assault sequence; fish-trap construction; idle land-unit attack once units have crossed to the enemy island |

`AIPlayer` also contains TC-loss handling: on `EventBus.building_destroyed`, if the destroyed building is the AI's Town Center, a 0.5 s deferred call to `_attempt_tc_rebuild` finds the safest villager (maximally distant from the enemy center-of-mass) and places a new TC. If the AI has no units and no buildings it emits `EventBus.player_eliminated`.

On **Islands** maps (`MatchConfig.map_type == ISLANDS`) the `_run_tick` call also invokes all four naval methods; land-only maps skip the naval module entirely.

## UI / HUD System

The HUD is a `CanvasLayer` scene at `scenes/ui/hud/hud.tscn`, instanced as a child of `GameWorld` in `scenes/game/game_world.tscn`. The root node carries `hud_manager.gd`, which retains the core in-game UI (action menu, selection panel, timer bars, tutorial) and **composes** a set of focused child components, each a plain `Node` added in `_ready`:

| Component (`class_name`) | File | Responsibility |
|---|---|---|
| `HudResourceBar` | `scripts/ui/hud/hud_resource_bar.gd` | Top-bar resource counters + gatherer counts, population label (at-cap flash), age label; self-wires to EventBus |
| `HudWeather` | `scripts/ui/hud/hud_weather.gd` | Weather announcement banner + countdown pill; self-wires to `WeatherManager` |
| `HudMatchStats` | `scripts/ui/hud/hud_match_stats.gd` | Match clock, per-player/rival stat counters, timeline snapshots, game-over + charts overlays |
| `HudMenus` | `scripts/ui/hud/hud_menus.gd` | Pause menu, settings, save-slot picker, surrender (tutorial/dpad hooks injected as callables) |
| `HudControls` | `scripts/ui/hud/hud_controls.gd` | Game-speed buttons, camera dpad + panning, idle-villager/idle-military cycle buttons |
| `HudStyle` | `scripts/ui/hud/hud_style.gd` | Shared `StyleBoxFlat` panel/button factory |

The components self-wire to their own signals; `hud_manager` does not relay events to them. The split was incremental and behaviour-preserving — `hud_manager.gd` went from ~3300 to ~1900 lines. A headless load harness lives at `project/tools/check_hud.gd` (`godot --headless -s tools/check_hud.gd`).

**EventBus wiring** (`hud_manager._ready` connects the core panels; components connect their own):

| Signal | Handler | Effect |
|---|---|---|
| `EventBus.resource_changed` | `_on_resource_changed` | Updates the matching `ResourceDisplay` for the local player |
| `EventBus.unit_selected` | `_on_unit_selected` | Rebuilds the unit portraits grid and detail panel |
| `EventBus.age_advance_complete` | `_on_age_advance_complete` | Updates the age label for the local player |
| `EventBus.market_rate_changed` | `_on_market_rate_changed` | Refreshes the Market action panel with live rates if the changed market is currently selected |
| `GameManager.game_started` | `_on_game_started` | Resets game speed and refreshes age/resources (the clock is started by `HudMatchStats`) |
| `GameManager.game_paused` | `toggle_pause` | Shows/hides the full-screen pause overlay |
| `GameManager.game_over` | `HudMatchStats._on_game_over` | Stops the clock and builds the end-of-match summary + charts |

**Component breakdown**:

- **TopBar** (`PanelContainer`, anchored top): four `ResourceDisplay` nodes (Food, Wood, Gold, Stone), a population `Label`, an age `Label`, and a game-clock `Label`.
- **ResourceDisplay** (`class_name ResourceDisplay extends HBoxContainer`): two `Label` children — `IconLabel` for the resource name and `AmountLabel` for the count. Updated via `set_amount(value: int)`.
- **BottomBar** (`PanelContainer`, anchored bottom): a selection panel and a minimap panel.
  - **UnitPortraitsGrid** (`GridContainer`, 10 columns, max 40 portraits): populated dynamically by `HudManager.update_selection`. Each cell is a `UnitPortrait` instance.
  - **UnitDetailPanel**: shows the first selected unit's display name and HP bar.
  - **ActionButtonsGrid**: `GridContainer` with `ACTION_COLS = 5` columns and `ACTION_ROWS = 2` rows (10 slots per page). When the active action list exceeds 10 entries, the last two slots on the bottom row become ◀/▶ pagination buttons. `_render_action_page()` rebuilds the grid for the current `_action_page`.
  - **MinimapPanel**: hosts `MinimapRenderer` (`scripts/ui/minimap.gd`). Rendering is split across two child layers so the widget is not rebuilt every frame: **ContentLayer** (terrain texture, fog cells, resources, buildings, units — the expensive entity iteration) redraws on a decoupled tick every `CONTENT_REDRAW_INTERVAL` (0.2 s), while **OverlayLayer** (camera viewport rect, event flashes, border) is marked dirty only when the camera view actually changes or a flash is animating; an idle minimap issues no draw calls. Enemy buildings seen at least once are remembered at their last known position (`_known_enemy_buildings`, updated on the content tick) and drawn dimmed while their fog cell is EXPLORED — even if destroyed under fog, AoE2-style; a ghost is only forgotten when the player re-observes the spot and the building is gone.
- **PauseOverlay** (`ColorRect`, full-screen, 50 % black): visible only when the game is paused.

**UnitPortrait** (`class_name UnitPortrait extends PanelContainer`): built entirely in code (`_ready`). Displays a 6-character name abbreviation and a color-coded HP bar (green > 50 %, yellow > 25 %, red ≤ 25 %). Created and discarded each time the selection changes; no scene file.

**Building selection behaviour**:

- When a building with `state != BuildingState.COMPLETE` is selected, the HUD shows only the Destroy action button regardless of building type.
- When construction completes, `EventBus.building_construction_complete` fires `_on_building_construction_complete`, which re-calls `_on_building_selected` on the same building if it is still selected, replacing the Destroy-only panel with the building's full action set.
- Buildings that implement `is_respawning_hero()` (or are an instance of `TownCenterBuildable`) are treated as Town Centers: the HUD shows the Town Center action set and wires the training queue.

**Player filtering**: `HudManager.local_player_id` (default `0`) gates all resource and age callbacks so that only data belonging to the local player is displayed.

## Naval Units

All naval units extend `ShipBase` (`scripts/units/ship_base.gd`), which itself extends `UnitBase`. `ShipBase` returns `true` from `is_amphibious()`, which is what makes ocean terrain passable for every ship regardless of the owning player's civilization. It used to force `civ_id = "atlantes"` for that same purpose; the hull now inherits the owner's civilization instead (`CivStyle.civ_id_for_player`), which is what the naval dress pass paints.

### Naval civ identity

`ShipDress` (`scripts/utils/ship_dress.gd`) is the naval counterpart of `UnitDress`:
a ship has no head to hang headgear on, so the hull planking carries the civ
material and the sail carries the civ colour, both read from `CivStyle.NAVAL`
(`hull` / `deck` / `sail` / `accent` / `motif`).

- Recolours the `Hull`, `HullShadow`, `Deck`, `Cabin`, `Ram`, gunwale/plank/bulwark/bench and `OarBlade*` polygons; retints an existing `SailStripe` or adds a `CivSailBand` when the sail is plain.
- Adds a prow ornament for the two civs whose identity *is* the sea: the Atlantes bronze dorsal fin plus a bronze waterline stripe (`motif: "fin"`), and the Fenicios painted eye (`motif: "eye"`). Other civs get a short cutwater (`"beak"`) or nothing.
- Applied deferred from `ShipBase._ready`, guarded by `META_APPLIED`, so it is idempotent and so HUD icons (`IconBaker` waits four frames) show the dressed hull.
- Civ-unique hulls opt out by stamping `META_APPLIED` in their own `_ready` — the Trireme already carries Fenicios art.

Reviewed with `tools/check_ship_gallery.tscn` (one civ per row, `CALIMA_CIVS` narrows
the grid); gated by `tests/unit/test_ship_dress.gd`.

### Unit classes

| Unit | Script | Age | Cost | Notes |
|---|---|---|---|---|
| Fishing Boat | `scripts/units/fishing_boat.gd` | Dark | 75W | Gathers `FOOD_FISH` from ocean nodes; returns food to nearest friendly Dock |
| Transport Ship | `scripts/units/transport_ship.gd` | Feudal | 125W | No combat; capacity 8; boards military units (Militia, Archer, Pikeman, Scout, Hero) — Villagers cannot board; unloads units at nearest passable shore position via `TerrainManager.nearest_passable` |
| War Galley | `scripts/units/war_galley.gd` | Feudal | 75W + 35G | Ranged naval combat: 6 attack, 5.5 range, 120 HP |

### Dock building

`scripts/buildings/dock.gd` / `scenes/buildings/dock.tscn` / `resources/buildings/dock.tres`

- Cost: 150 Wood — HP: 1,800 — Build time: 45 s
- Placement is validated by `_is_coastal()` in `game_world.gd`; the building can only be placed on land tiles directly adjacent to water.
- Trains the three naval units above with a queue cap of 5.
- HUD hotkey: **D** in the build menu.

Fishing boats automatically return food to the nearest friendly Dock. Right-clicking a Dock while carrying fish triggers the drop-off.

`Dock.water_access_point()` is the dock's berth: the first hull-clear open-water
position off its seaward side (`WATER_CLEARANCE` = 56 px, direction averaged from
16 ocean probes), falling back to `TerrainManager.nearest_ocean`. It is resolved
once and cached — neither the dock nor the coastline moves, and returning boats ask
for it every physics frame. Everything that navigates *to* a dock must aim at the
berth rather than at the dock node: the dock's own origin sits on the shoreline,
normally on land and always off the ocean navmesh, so a boat sent there stalled with
a full hold forever. `FishingBoat._drop_off_position()` returns the berth (or the
drop-off node's origin for buildings without the method) and the `DROP_OFF_RANGE`
check measures against whichever of the two is nearer. New ships spawn at the berth
too, spiralled aside by `_free_water_near` so a training queue doesn't stack on one
pixel. Gated by `tests/unit/test_dock_ship_spawn.gd` and
`tests/unit/test_fishing_boat_drop_off.gd`.

Fishing boats can also construct a **Fish Trap** on ocean tiles. Fish Traps are ocean buildings that regenerate food over time, providing a passive food source that does not require the boat to travel to a resource node.

Map boundary walls (invisible `NavigationObstacle2D` nodes along the map edges) prevent ships from sailing outside the playable area.

## Production Buildings

### TownCenterBuildable

`scripts/buildings/town_center_buildable.gd` (`class_name TownCenterBuildable`) extends `BuildingBase`. Requires Castle Age (age 2). Cost: 275 Wood (defined in `resources/buildings/town_center.tres`; 2400 HP). Scene: `scenes/buildings/town_center.tscn` (80×80 collision).

The building goes through the standard `BuildingBase` construction state machine while villagers build it. Once `state == COMPLETE` it activates two subsystems:

**Villager training** — queue cap 5 (`MAX_QUEUE`), cost 50 food (`VILLAGER_COSTS`). Public API mirrors the Stable/Barracks pattern:

| Method | Description |
|---|---|
| `order_train() -> bool` | Enqueues a villager; deducts food; emits `EventBus.train_queue_changed` |
| `order_cancel_train(index: int)` | Refunds food; removes entry; emits `EventBus.train_queue_changed` |
| `get_queue() -> Array` | Returns a duplicate of the current training queue |
| `get_max_queue() -> int` | Returns `MAX_QUEUE` (5) |
| `get_train_progress() -> float` | Fraction 0–1 of current training progress |

**Hero respawn** — listens to `EventBus.hero_died`. If the signal fires for the same `player_id`, the TC starts a 120-second (`HERO_RESPAWN_TIME`) countdown and re-spawns the hero on expiry via `_do_respawn_hero`. The respawn logic is designed so only one TC handles a given death event (the main TC connects first in scene order).

| Method | Description |
|---|---|
| `is_respawning_hero() -> bool` | `true` while a hero respawn countdown is active |
| `get_hero_respawn_fraction() -> float` | Progress 0–1 of the respawn timer |
| `get_hero_respawn_remaining() -> int` | Seconds remaining, ceiled |

**Drop-off** — a `DropOffBuilding` child node named `DropOff` is included in the scene. On `_ready`, `player_id` is propagated to it via `call_deferred("_sync_drop_off_player_id")` so villagers can return resources to this TC.

**HUD integration** — `HudManager._on_building_selected` detects `is_respawning_hero()` or `building is TownCenterBuildable` and renders the standard Town Center action panel (train villager, age-advance, hero-respawn bar). HUD build key: **Y** (`min_age: 2`).

### Stable

`scripts/buildings/stable.gd` (`class_name Stable`) extends `BuildingBase`. Trains cavalry units with a queue cap of 5 (`MAX_QUEUE`). Available units are gated by `AgeManager.get_age(player_id)` and civ-gated via the unit's civilization field:

| Unit ID | Class | Age requirement | Cost source | Civ restriction |
|---|---|---|---|---|
| `heavy_scout` | `HeavyScout` | Feudal (1) | `resources/units/heavy_scout_data.tres` | All |
| `knight` | `Knight` | Castle (2) | `resources/units/knight_data.tres` | All |
| `sand_raider` | `SandRaider` | Feudal (1) | `resources/units/sand_raider_data.tres` | Mahos only |
| `chevalier_normand` | `ChevalierNormand` | Castle (2) | `resources/units/chevalier_normand_data.tres` | Franks only |

Training cost is read from `UnitResource` fields (`cost_food`, `cost_wood`, `cost_gold`) and modified by `CivBonusManager.get_unit_cost_multiplier`. Resources are refunded on `order_cancel_train`. The `EventBus.train_queue_changed` signal is emitted after every queue mutation. On spawn, `PopulationManager.add_unit` is called and `EventBus.unit_spawned` is emitted.

### Research-only buildings

`Blacksmith`, `University`, and `Temple` extend `BuildingBase` and add no new API beyond the base class. They exist as production-building nodes so that `TechManager` can gate technology research by building type.

### Market

`scripts/buildings/market.gd` (`class_name Market`) extends `BuildingBase`.

Exchange rates are **dynamic per player per resource** (all operations require `BuildingState.COMPLETE`). Base rates are `BASE_SELL_RATE = 15` (resources per 1 gold) and `BASE_BUY_RATE = 20` (resources per 1 gold spent). Each lot traded degrades the relevant rate by `DEGRADE_PER_LOT = 3` steps, bounded by `MAX_SELL_RATE = 30` and `MIN_BUY_RATE = 5`. Rates recover 1 step every `RECOVERY_INTERVAL = 30` seconds via `_process`. State is tracked in per-player, per-resource offset dictionaries (`_sell_offsets`, `_buy_offsets`, `_recovery_timers`).

| Method | Direction | Description |
|---|---|---|
| `get_sell_rate(pid, resource) -> int` | query | Current sell rate (resources per 1 gold); increases with use |
| `get_buy_rate(pid, resource) -> int` | query | Current buy rate (resources per 1 gold spent); decreases with use |
| `sell_resource(player_id, resource)` | resource → gold | Single-unit sell at current sell rate; degrades rate |
| `buy_resource(player_id, resource)` | gold → resource | Single-unit buy at current buy rate; degrades rate |
| `sell_lot(player_id, resource)` | 100 resource → gold | Bulk sell: 100 / current sell rate gold received; degrades rate; emits `EventBus.market_rate_changed` |
| `buy_lot(player_id, resource)` | 5 gold → resource | Bulk buy: 5 × current buy rate resources received; degrades rate; emits `EventBus.market_rate_changed` |

## Cavalry Units

`HeavyScout` (`scripts/units/heavy_scout.gd`) and `Knight` (`scripts/units/knight.gd`) both extend `UnitBase`. Their movement and attack FSM pattern matches `Militia`: `MOVING` / `ATTACKING` states, `order_move` / `order_attack` entry points, avoidance via `NavigationAgent2D.velocity_computed`. Stats are defined entirely in their respective `UnitResource` `.tres` files.

## Siege Units

Three siege unit classes extend `UnitBase` and are produced by `SiegeWorkshop`.

### SiegeWorkshop

`scripts/buildings/siege_workshop.gd` (`class_name SiegeWorkshop`) extends `BuildingBase`. Requires Castle Age (age 2). Queue cap 5 (`MAX_QUEUE`). Units available are gated by `AgeManager.get_age(player_id)`:

| Unit ID | Class | Age requirement | Cost |
|---|---|---|---|
| `battering_ram` | `BatteringRam` | Castle (2) | 160W |
| `mangonel` | `Mangonel` | Castle (2) | 160W + 135G |
| `trebuchet` | `Trebuchet` | Imperial (3) | 200W + 200G |

Training cost is read from `UnitResource` fields and resources are refunded on `order_cancel_train`. `EventBus.train_queue_changed` is emitted after every queue mutation.

### BatteringRam

`class_name BatteringRam`. Melee siege unit. Overrides `_on_enemy_entered_range` to skip auto-attack if the entering body does not have a `building_data` property — rams never chase units. `_get_effective_attack_vs` multiplies base attack by 3.0 against buildings (further scaled by `CivBonusManager.get_siege_attack_bonus`) and by 0.2 against units.

### Mangonel and AoE splash

`class_name Mangonel`. Ranged siege unit with `SPLASH_RADIUS = 72.0` px. On each attack tick, `_fire_at(target_pos)` creates a `PhysicsShapeQueryParameters2D` with a `CircleShape2D` of that radius, calls `PhysicsDirectSpaceState2D.intersect_shape(query, 32)` at the impact point, and applies damage to every resulting collider that belongs to an enemy. Armor is subtracted per-target with a floor of 1.

Minimum range: `MIN_RANGE_RATIO = 0.35`. During `_handle_attacking`, if `dist < reach * MIN_RANGE_RATIO` the unit actively moves away from the target by 120 px. During `_handle_movement` the transition to `ATTACKING` only triggers when the target is inside `[reach * MIN_RANGE_RATIO, reach]`.

### Trebuchet — deploy/undeploy mechanic

`class_name Trebuchet`. Same AoE splash implementation as Mangonel but with `SPLASH_RADIUS = 48.0` px and `MIN_RANGE_RATIO = 0.40`.

Trebuchet adds a two-state deploy system on top of the base FSM:

| Bool flag | Meaning |
|---|---|
| `is_deployed` | Unit is unpacked and can fire |
| `_deploying` | Transition to deployed in progress |
| `_undeploying` | Transition to packed in progress |

`DEPLOY_TIME = 3.0` seconds. While either `_deploying` or `_undeploying` is true, `_physics_process` routes to `_handle_deploy_animation(delta)` instead of the normal FSM. On completion of undeploying, if an `attack_target` is still valid the unit resumes movement toward it automatically.

`order_move` and `order_attack` both call `_start_undeploy()` if `is_deployed` is true before issuing a nav target, ensuring the trebuchet never moves while packed. `_handle_movement` calls `_start_deploy()` when the target enters the valid firing band, replacing the direct `ATTACKING` state transition used by other ranged units.

## CivBonusManager — Extended API

Two query methods were added to `CivBonusManager`:

| Method | Signature | Description |
|---|---|---|
| `get_archer_armor_pierce_bonus` | `(player_id: int) -> float` | Returns additive pierce-armor bonus for archers; backed by `archer_armor_pierce` key in `_ADDITIVE_KEYS` |
| `get_unit_move_speed_multiplier` | `(player_id: int) -> float` | Returns the `unit_move_speed` multiplier applied to every unit's nav velocity |

`get_attack_speed_multiplier` handles `unit_id == "archer"` by returning the `archer_attack_speed` multiplier. `SandRaider` calls `CivBonusManager.get_attack_speed_multiplier(player_id, unit_data.id)` to scale its attack timer.

`get_unit_hp_multiplier`: `"sand_raider"` is included in the cavalry HP branch alongside `"scout"`, `"heavy_scout"`, and `"knight"`, so the `cavalry_hp` multiplier (e.g. Franks +15%) applies to Sand Raiders.

`get_unit_speed_multiplier`: `"sand_raider"` is included in the `scout_speed` branch, so the Mahos `scout_speed` bonus (+25%) applies to their unique unit.

`_ADDITIVE_KEYS` now includes `"archer_armor_pierce"` (alongside the existing `"unit_armor_melee"`). Additive keys accumulate flat points rather than multiplying.

`UnitBase._nav_velocity` multiplies movement speed by `CivBonusManager.get_unit_move_speed_multiplier(player_id)`. `Archer` attack speed is scaled by `CivBonusManager.get_attack_speed_multiplier(player_id, "archer")`.

## Age Advancement

Ages: Dark (0) → Feudal (1) → Castle (2) → Imperial (3). Advancing costs resources and takes time. Certain units, buildings, and technologies are locked behind age requirements.

## Weather System

`WeatherManager` (autoload, `scripts/core/weather_manager.gd`) drives a global procedural weather cycle. Weather affects all players equally and is controlled by two `MatchConfig` settings: `weather_enabled: bool` and `weather_frequency: int` (0=Off, 1=Normal, 2=Frequent, 3=Extreme). Both are exposed in the lobby as a single "Weather" option row.

### Weather types

| ID | `WeatherType` | Effect summary |
|---|---|---|
| `calima` | `CALIMA` | Saharan dust haze — land speed −15%, gather rate (food/wood) −20%, vision −40% |
| `atlantic_storm` | `ATLANTIC_STORM` | Rain & wind — naval speed −30%, fish gather −50%; projectile drift (crosswind) |
| `sea_fog` | `SEA_FOG` | Coastal fog (≤400 px from coast) — vision −60%, enemy units cloaked when intensity ≥ 0.5 (see the cloak rules below) |
| `trade_winds` | `TRADE_WINDS` | NE→SW wind — naval speed ±20% depending on heading; projectile drift along wind |
| `volcanic_ash` | `VOLCANIC_ASH` | Caldera zones (caldera radius + 800 px) — gather −30%, vision −50%, buildings drain 2 HP/s |

### Sea-fog cloak rules

`WeatherManager.is_unit_cloaked_by_weather(world_pos)` only answers the question
"is this position inside an active fog bank?". Two things break the cloak, and
`FogOfWar._apply_visibility` (the only caller with access to both sides) applies
them through `_breaks_fog_cloak`:

1. **Proximity.** An enemy within `WeatherManager.fog_spot_range(owner_id)` of any
   own unit or finished own building is visible anyway. The base range is
   `FOG_SPOT_RANGE` = 180 px, scaled by the owner civ's `fog_stealth` multiplier —
   the Atlantes ship 0.5, so they have to be found at 90 px.
2. **Attacking.** `UnitBase.is_revealed_by_combat()` stays true for
   `COMBAT_REVEAL_TIME` (3 s) after the unit's last strike (`_last_strike_msec`,
   stamped by the canonical machine in `_handle_attacking`). Firing gives your
   position away.

Without those rules the cloak hid *every* enemy inside the 400 px coastal band
regardless of line of sight — and on an Islands map the entire playable area is
inside that band, so whole armies became invisible while standing next to your
own units. Gated by `tests/unit/test_fog_cloak_reveal.gd`.

Map-type restrictions: `SEA_FOG` only spawns on ISLANDS / VOLCANIC_COAST / DESERT_COAST; `VOLCANIC_ASH` only on VOLCANIC_COAST (the only map type that generates calderas). `_in_volcanic_zone` checks the `TerrainManager` CALDERA zones; a map with no caldera (legacy save mid-event) falls back to whole-map coverage so an active event is never a no-op.

### Phase state machine

```
CLEAR ──(timer)──► RAMP_IN (10 s) ──► PEAK (variable) ──► RAMP_OUT (10 s) ──► CLEAR
```

`intensity` is a 0..1 float that smoothly ramps in/out. All stat-modifier calls multiply by `intensity` so effects fade gracefully.

### Stat-modifier query API

| Method | Consumers |
|---|---|
| `get_move_speed_multiplier(world_pos)` | `UnitBase._nav_velocity` |
| `get_naval_speed_multiplier(move_dir)` | `ShipBase._nav_velocity` |
| `get_gather_rate_multiplier(resource, world_pos)` | `Villager` gather loop |
| `get_vision_multiplier(world_pos)` | `FogOfWar._reveal_from_units/buildings` |
| `get_projectile_drift() → Vector2` | `Trebuchet._spawn_projectile`, `Mangonel._fire_at` |
| `is_unit_cloaked_by_weather(world_pos) → bool` | `FogOfWar._apply_visibility` |
| `fog_spot_range(player_id) → float` | `FogOfWar._breaks_fog_cloak` |
| `get_building_damage_rate(world_pos) → float` | `BuildingBase._process` |

`COASTAL_ZONE_DEPTH` (400 px) is public on purpose: besides bounding the sea-fog
effects it is also the band `FogOfWar._coastal_vision_mult` uses for the Atlantes
`coastal_vision` bonus, so "the coast" means one distance everywhere in the game.

### Visual overlay

`WeatherOverlay` (`scripts/ui/weather_overlay.gd`) is a `Node2D` child of `GameWorld` (z_index 15). It draws entirely in screen/viewport coordinates using `draw_set_transform_matrix(get_canvas_transform().affine_inverse())` at the start of `_draw()`, so the effect is camera-independent. Each weather type has dedicated particle arrays updated in `_process` and drawn in `_draw`:

| Weather | Visual |
|---|---|
| ATLANTIC_STORM | Falling rain lines (`_rain_particles`, 60) |
| TRADE_WINDS | Horizontal streak lines (`_wind_particles`, 30) |
| CALIMA | Drifting dust circles (`_dust_particles`, 80) |
| VOLCANIC_ASH | Falling ash circles (`_ash_particles`, 60) |
| SEA_FOG | Concentric vignette rects at screen edges |

All weather types also blend a full-screen color overlay that fades in/out with intensity.

### HUD notification

`GameWorld` listens to `WeatherManager.weather_changed` and `WeatherManager.weather_cleared` and calls `HudManager.show_weather(weather_id)` / `HudManager.hide_weather()`. The HUD creates a transient `Label` with the weather name that fades in over 0.8 s and fades out over 1.5 s.

### Conquest victory condition

Conquest mode (the default) no longer ends on Town Center destruction alone. A player is defeated only when they have **zero units AND zero buildings** remaining. When the AI's TC is destroyed, `AIPlayer` attempts to rebuild it using the safest available villager; if it has no villagers, no buildings, and no units it emits `EventBus.player_eliminated` and the match checks for an overall winner.
