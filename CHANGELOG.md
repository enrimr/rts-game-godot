# Changelog

All notable changes to **Calima: Flames of the Atlantic** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Civilization bonuses wired for real
- The four bonuses advertised in-game but never implemented now work: Fenicios build their Market from the Dark Age and their ships cost 15% less; Guanches train Pikemen from the Dark Age; Canarii houses double as drop-off points; Mahos building wood discount (×0.70) is now actually charged — button price, AI price sheet and the placement command all agree.
- New: caldera claim — a Mining Camp raised within a caldera's shadow trickles stone to its owner (Volcanic Coast).
- New: Mahos dune sight — vision ×1.40 while a Mahos unit stands on dune terrain (mirrors the Atlantes coastal vision).
 - 2026-09-02 → 2026-09-06

Everything since the `v0.9.8-beta` tag, grouped by theme.

### Replays & creator kit
- **Every match records itself** as a compressed snapshot stream (`user://replays/`, faithful by construction — no re-simulation), watchable from the new main-menu **Replays** browser
- **Replay playback v2**: seekable timeline (backward seeks reboot and fast-forward), pause, playback speeds, reveal-map toggle, and a "watch replay" button on the game-over screen
- **Creator kit**: cinematic mode (**C**, UI-free, optional floating minimap), centred title card, and background **video export** at a smooth 30 FPS — of the whole match or an **A/B-marked clip**; the replay bar never enters exported footage
- Replays take no orders: the action menu, hotkeys and right-click order paths are all locked during playback

### Campaign — *The Flames of Tamarán*
- Four scripted Canarii missions against the Atlante invasion (fixed-seed deterministic worlds, side objectives, scripted attack waves, conquest/survive/regicide victory kinds) plus a tutorial prologue that now opens the same war
- Mission briefings, story outros, difficulty ramp (per-mission AI caps), chain unlocking, persistent progress; mission 1 teaches the Mill and the herding game
- Sixteen unique hero sprites — every hero recognizable from its lore (Don Quijote rides Rocinante)

### Pastoral economy
- **Mill** (Dark Age food drop-off) trains the **Presa Canario** herding dog: fetch an animal, lead it home, get paid food for the net approach; enemy sheep convert on the way; guard-dog bite when idle, never abandons a trip on its own
- **Harimaguada** priestess-healer trained at the Temple (always female, by lore): follow-and-mend healing plus idle auto-triage; the Temple doubles as a field hospital (garrisoned units heal, heroes at half rate) and now looks like an **almogarén** — an open dry-stone Canarian shrine
- Wild sheep flocks graze the open map — contested targets both the player's and the AI's dogs race for; the flock wears its owner's colour (team collars)
- The AI plays the same game: builds a Mill, raises dogs, herds unclaimed animals and slaughters its own sheep when food runs short

### Camp economy technologies (tech tree grows to 32)
- Nine AoE2-style economy techs, one per age from Feudal, researched at the camps themselves: Lumber Camp — *Double-Bit Axe → Bow Saw → Two-Man Saw* (wood); Mining Camp — *Reinforced Picks → Shaft Mining → Deep Galleries* (gold + stone); Mill — *Horse Collar → Heavy Plow → Crop Rotation* (food). Each step: +15% gather rate and +10% carry for that resource
- Full tech-tree audit with real fixes, research **queueing** (up to 5 in flight per building, paid at enqueue, fully refunded on cancel) and an AoE2-style glyph for every technology

### Unit visual styles
- New 3-way **Unit style** setting, switchable live: **Classic** (the flat default), **Enhanced** (reversible ink outline + volume shading + extra procedural animation), and **Redesigned** (lore-driven from-scratch rigs for every unit with a full animation state machine)

### Spectator mode & notifications
- Surrendering — or losing everything — while hostile sides remain no longer ends the match: the defeat panel offers **View map** and you keep watching the live battle with orders locked; the definitive result arrives when the war actually ends
- Notification toasts now carry **shortcut action buttons**: jump to the event, place a House one click after a pop-cap warning, locate the hero when he's in danger

### AI overhaul
- **The AI builds with real villagers** — instant enemy buildings are gone; a builder walks to every site (docks included, fish traps raised by fishing boats) and abandoned sites are re-crewed
- **Idle acquisition**: idle combat units (player and AI alike) now hunt hostiles within sight (~240 px) by their stance rules instead of waiting to be touched
- **AI-vs-AI wars actually happen**, including naval ones — galleys burn known enemy docks and fish traps, transports sail with smaller armies
- **Mop-up**: with nothing left to siege, the AI hunts the last sighted survivors instead of idling

### Under the hood
- **Savegame schema v2**: in-flight research, garrisons, unit stances and the live weather state machine survive the round-trip; newer schemas refused with a reason, older ones load with defaults
- **Wire hardening**: the host re-validates every client placement and strips wire-borne commands of local-only privileges
- HUD decomposition continued: the command grid (`HudActionMenu`), tutorial driver (`HudTutorial`) and action tables (`HudActionDefs`) extracted; every button price now comes from the same `.tres` data the simulation charges
- Per-civilization synthesized voice "languages", order-acknowledgment voices and multi-take combat sounds; audio synthesis reference documented
- Land units can no longer wade into the sea (step veto at both off-mesh movement paths, CI chaos probe); animals included
- Main menu v2 (centred logo, gold play button), AoE2-style players/score overlay on the minimap, farmers stay on their farm, hero miniatures show the actual hero

---

## [0.9.8-beta] - 2026-09-02 - Teams, Steam Social & Performance

### Added
- **Teams and alliances** (2v2, 2v1, ...) across skirmish and multiplayer: shared vision, team victory, ally-aware auto-attack, team pickers in both lobbies, persisted in saves
- **Allied AI teamwork**: AI teammates send assist squads when you are raided and announce their offensives with a ping
- **Shift-queued waypoints and patrol**
- **Mercenary hiring finished** at the Market — every civ, localized, with unit miniatures and cooldown badges; Fenicios pay 25% less
- **Multiplayer save/resume**: the host saves the roster and per-player fog; the resume lobby reserves the original seats and the match can start with absent players (their seat holds through the rejoin grace)
- **Version handshake**: the host refuses clients from a different build with a reasoned dialog; releases tagged via `scripts/release_tag.sh` only
- **Display settings and remappable camera keys**; optional FPS counter
- **Steam polish**: roster avatars, rich presence, allied minimap pings (Alt+click)
- **Formant-synthesized unit selection voices** (AoE-style barks), baked on a worker thread
- **Stronger team colours on every unit** — cloth repainted to the owner's colour with shading preserved

### Fixed
- Hero-ability audit: all 16 heroes' abilities verified, five real bugs fixed (instant-ability cooldowns, Mercenary Pact crash, Boarding dash, team awareness, Calima cloud parenting)
- Steam-ID rejoin authentication and a command-pipe rate limit

### Performance
- Incremental fog-of-war reveal (stationary armies stop paying per tick)
- Physics catch-up capped at 2 steps/frame — 200v200 battles from 7.5 to 30 fps
- Per-resource RVO obstacles dropped; chase repath hysteresis; minimap draw rewrite; perf gates joined the test suite

---

## [0.9.6-beta / 0.9.7-beta] - 2026-08-31 - Internet & Steam Multiplayer

### Added
- **Internet hosting via UPnP** from the lobby (automatic port mapping, public address in the header); LAN vs Internet split in the main menu
- **Steam transport prototype** (GodotSteam GDExtension): public lobbies, friend invites (with an in-game picker when the overlay is unavailable), Valve relay networking — on the test AppID
- **Mid-match reconnection**: a dropped player's seat is reserved (90 s grace), the rejoining client gets its old player id and a full state resync
- **Multiplayer chat**: lobby panel and in-game overlay (Enter), colour-coded, with system lines; in-lobby rename (pinned to the Steam persona on Steam sessions)
- Siege boulder visuals with client echo — the Mangonel finally throws a visible stone

### Fixed
- Client-side placement validated against the client's own stockpile (clients could only place houses)
- Client HUD showed no actions on its own buildings (was gated on player 0)

---

## [0.9.1-beta → 0.9.5-beta] - 2026-08-27 → 2026-08-31 - Command Pattern, Combat Controls & LAN Multiplayer

### Architecture
- **Command pattern**: every simulation-mutating order — player AND AI — is a serializable `GameCommand` through the `CommandBus`, tick-stamped into a match log (the foundation replays and multiplayer are built on)
- **MatchRng**: a single seeded RNG stream for all simulation randomness; deterministic decision layer (identical command logs across runs at a fixed seed)
- God-object split: `game_world.gd` into six world controllers (setup/victory/camera/selection/commands/placement), `map_generator.gd` into six pipeline modules, HUD into self-wiring components
- Unified `.tres`-backed building cost table — player and AI pay the same prices (the old hand-written table let the player build some buildings for free)

### Combat & controls
- **AoE2 combat stances** (Aggressive / Defensive with leash / Stand Ground / No Attack), **group formations** (Line / Box / Spread / Rings) and **building garrison** (TC 10, towers 5, one extra arrow per occupant; villagers via Garrison button or the Town Bell)
- Canonical combat state machine in `UnitBase` — all 16 leaf units migrated onto override hooks
- Watch Towers shoot visible arrows; progressive fire/smoke on damaged buildings; universal building health bars (building damage used to be invisible)
- Double-click selects every building of a type (shared rally + training); per-unit-type queue badges; stance/formation glyphs with persistent active states; confirmation before demolishing >5 buildings; Backspace aliases Delete on macOS

### Multiplayer (phases 1–2)
- **LAN multiplayer**: host-authoritative ENet session, unified lobby with player seats (Open/AI/Closed), per-player name/colour/civ, kick, host-edited settings with live client summary
- **Host→client state replication** at 15 Hz with interpolated puppet mirror worlds; queues, research, market, weather and projectiles mirrored; delta stream with keyframes under the ENet MTU
- **Robustness**: disconnects and surrenders become resignations, host-left dialog, replicated pause

### Fixed
- RVO avoidance retuned (fast units were speed-capped; crowds gridlocked); buildings' RVO obstacles removed (they sealed corridors the navmesh had opened)
- Impassable terrain carved into the navmesh — paths route around lava instead of freezing on the rim
- Fog-of-war grid sized to the actual map (large-map margins were permanently unfogged)
- Diagonal building placements no longer collapse the navmesh bake (half-pixel nudge + fallback ladder)

---

## [0.9.0-beta] - 2026-08-26 - Isometric View & Civilization Identity

The first tagged beta: the isometric refactor merged after a month of UI/UX groundwork.

### Added
- **Isometric presentation**: camera-level projection (`IsoProjection`), upright billboarded entities with depth sorting (`IsoBillboard`), building massings
- **Per-civilization visual identity**: architecture styles (`CivStyle`), unit dress (headgear/sashes), per-civ ship hulls and sails (`ShipDress`)
- **Contextual cursors** (the tabona pointer + context glyphs, macOS-safe baking)
- **Control groups** (Ctrl/Cmd+1–9) with clickable HUD chips; SPACE jumps to the last attack alert; idle-villager/military cycle buttons with count badges; persistent hero widget in Regicide; camera follow
- **Localization pass**: EN/ES for unit/building names, lobby, HUD; rich cost tooltips replacing the cost strip
- Hero energy aura; heroes spawn in front of the TC via spawn spiral

---

## [0.6.0] - 2026-06-08 - Visual Overhaul

### Summary
A full art pass: every unit, building, animal and the terrain were redesigned from cryptic colored polygons into clearly readable figures, and all human units now have a random visual gender. No gameplay rules changed — this release is purely visual quality, identification and polish.

### Added
- **Random visual gender for all human units** — every human unit (villager, infantry, cavalry, archers, unique units) is randomly male or female (50/50) when created, shown via long hair framing the head. Persisted across save/load. Ships, siege engines and animals are unaffected.
- **Distinct heroine sprites** — female heroes now read as women: long hair, a golden circlet (they are queens/leaders) and a flared gown, while keeping their weapon and shield.
- **Team-colour building accents** — buildings carry team-coloured detail (roofs, flags, banners, awnings, domes, sails) so each building's owner is identifiable at a glance.
- **Ground shadows** under every unit and building, seating them on the terrain.
- **Animated water shader** (layered swell, ripples, foam) for oceans and coasts.
- **Terrain detail shader** (grain + tonal variation) so terrain isn't flat colour.
- **Animated lava** (pulsing ember glow) on malpaís veins and caldera cracks/pools.
- **Coastal oceans** with sandy, variable-width beaches and foam on Volcanic Coast and Desert Coast maps.
- **Ambient lighting + vignette** per map type for atmosphere.
- **Walking gait for animals** — deer and sheep legs swing in a trot while moving.

### Changed
- **All unit sprites redesigned** into recognisable figures: villager (straw-hat peasant with a pick), militia/man-at-arms/long swordsman (helmeted swordsmen with shields), pikeman (pike), scout/heavy scout/knight and unique cavalry (riders on horseback), archers (drawing a bow), the 8 civ-unique units, and the siege engines and ships (with hull detail, oars, sails).
- **All building sprites upgraded** with stonework shading, ashlar lines, crenellations and thematic detail (forge glow, market stalls, temple/university domes, etc.).
- **Animal sprites redesigned** — deer (with antlers) and sheep (woolly), converted from flat rectangles to figures.
- **Unit & animal orientation** now follows the navigation destination, so units and animals face the way they travel (including on diagonal and near-vertical paths).
- **Terrain boundaries softened** — zone edges fade into neighbours following the zone's real outline, and coastlines are rounded with naturally varying beach/foam width.

### Fixed
- **Jerky unit movement** — enabled 2D physics interpolation (render ran faster than the 60 Hz physics step with interpolation off, so sprites snapped between ticks). Movement is now smooth.

---

## [0.5.1] - 2026-06-02 - Heroines

*(Folded in from the former `HEROINES_CHANGELOG.md`.)*

### Added
- **8 female heroes** — one per civilization, doubling the hero roster to **16** (8 male + 8 female), each with a unique ability and its own `.tres` stats:

| Civilization | Heroine | Ability | Role |
|---|---|---|---|
| Guanches | Dácil | Mountain Voice | Defensive buffer |
| Canarii | Guayarmina | Fate's Arrow | Sniper assassin |
| Mahos | Tibiabin | Sandstorm | Area denial |
| Francos | Catalina de Béthencourt | Honor Duel | Hero hunter |
| Britanos | Grace O'Malley | Boarding Action | Initiator |
| Castellanos | Dulcinea del Toboso | Call to Arms | Force multiplier |
| Atlantes | Cleito | Rising Tide | Hybrid support |
| Fenicios | Elissa | Mercenary Pact | Economic conversion |

- **Hero gender selection** in the lobby (Random / Male / Female) with dynamic hero info display
- Bilingual lore documentation (`docs/lore/heroes-and-heroines.md`, `docs/design/heroines-design.md`) and EN/ES translations

---

## [0.5.0] - 2026-06-01 - Production-Ready Milestone

### Summary
All core features implemented: 8 playable civilizations, the full unit roster and tech tree of the time, a complete AI opponent, save/load, dynamic weather, and 3 victory conditions. Work focused on polish and bug fixes to reach production-ready status.

### Added
- **Cover Fire command** for archers and siege units (move into range then attack-ground)
- **Flying arrow projectiles** with visual arc animation
- **Procedural body animation** for all units (walk, attack, work)
- **Polygon2D silhouettes** for all units and buildings (replaces ColorRect placeholders)
- **Tall stone tower visual** for Watch Tower
- **Archery Range** building (Feudal Age, trains Archer)
- **Attack-ground command** for ranged and siege units
- **Outward spiral spawn positioning** using physics queries to prevent unit overlap
- **Technology tree** across Blacksmith, University, Temple, unit upgrades and Castellanos instant grants
- **8 Hero units** with unique abilities (Menceyes Charge, Challenge, Ambush, Forced Diplomacy, Plunder, Knight Errant Charge, Calima, Trade Route)
- **8 Unique units** with special mechanics (Menceyes Guard, Ravine Archer, Sand Raider, Chevalier Normand, Longbowman, Conquistador, Tidecaller, Trireme)
- **Dynamic weather system** with 5 procedural event types (Calima, Atlantic Storm, Sea Fog, Trade Winds, Volcanic Ash)
- **Weather overlay** with visual effects (rain, dust, ash, wind, fog vignette)
- **Market building** with dynamic exchange rates (per-player, per-resource) and mercenary hiring
- **Naval gameplay** on Islands maps (Dock, Fishing Boat, Transport Ship, War Galley, Fish Trap)
- **AI naval assault** with transport ship boarding and amphibious landing
- **3 victory conditions** (Conquest, Regicide, Wonder)
- **Save/Load system** with 99 JSON slots and metadata UI
- **Population cap system** (5 per House, starts at 15)
- **Spatial audio** with distance attenuation
- **Control groups** (Ctrl+1-9 to save, 1-9 to recall)
- **Camera follow** for selected unit groups
- **Minimap** with right-click move orders and resource/unit/building icons

### Fixed
1. **Cover Fire**: register as pending action, move into range before firing
2. **Spawn positioning**: outward spiral physics query prevents unit overlap
3. **Minimap**: fixed revealing entire resource clusters at once (reduced reveal radius to 30% of unit sight range)
4. **Weather HUD**: fixed banner and pill not centered at non-1920 resolutions
5. **Villager**: fixed `_animate_body` signature mismatch (delta parameter)
6. **Town Center**: fixed initial graphic rendering
7. **WarGalley**: fixed HP check using wrong property names
8. **Conquest victory**: fixed missing DEAD/DESTROYED node checks in elimination logic
9. **Conquest defeat**: fixed never triggering for human player
10. **Regicide**: fixed per-mode victory condition logic
11. **Market**: fixed page reset on cooldown refresh (increased mercenary cooldown to 2 min)
12. **Volcanic Ash**: fixed building damage application
13. **Nav mesh obstacles**: skip for terrain player civ can traverse
14. **Release script**: resolve game repo path correctly before cd
15. **Minimap resource reveal**: fix showing all resources in group when only one cell explored

### Changed
- **Villager animation**: differentiate walk vs work animations
- **Unit animation**: all units now have procedural body animation (rotation during movement/attack)
- **Building visuals**: replaced flat ColorRect placeholders with Polygon2D silhouettes
- **Watch Tower**: redesigned with tall stone polygon silhouette
- **Arrow projectiles**: archers now shoot visible flying arrows
- **Weather frequency**: configurable in lobby (Off/Normal/Frequent/Extreme)
- **AI aggression**: escalates when threatened (PASSIVE → ALERTED → AGGRESSIVE)
- **AI base defense**: defends against enemies near any building, not just TC radius

### Performance
- **Area2D range detection**: attack ranges use Area2D monitoring, no per-frame physics queries
- **Cached physics queries**: spatial queries cached and reused where possible
- **Outward spiral spawning**: BuildingBase.find_spawn_pos() uses efficient ring search pattern

---

## [0.4.0] - 2026-05-15 - Naval & Weather Update

### Added
- **Naval gameplay** on Islands map type
- **Dock building** (150 wood, trains ships)
- **Fishing Boat** (gathers FOOD_FISH from ocean)
- **Transport Ship** (carries 10 military units)
- **War Galley** (ranged naval combat)
- **Fish Trap** (75 wood, passive food source in ocean)
- **Weather system** with procedural events
- **5 weather types**: Calima, Atlantic Storm, Sea Fog, Trade Winds, Volcanic Ash
- **Weather stat modifiers**: vision, movement, gather rate, projectile drift, building damage
- **Weather visual effects**: rain, dust, ash, wind, fog vignette
- **AI naval module** (AINaval): ship training, galley patrols, transport assaults
- **Market building** with resource trading
- **Blacksmith technologies** (Loom, Forging, Iron Casting, etc.)
- **University building** with advanced techs
- **Temple building** with morale buffs

### Changed
- **Map generation**: added Islands map type with ocean zones
- **Terrain system**: ocean tiles marked as impassable for land units
- **AI economy**: resource targets adjusted per age
- **AI construction**: added fish-trap construction logic

---

## [0.3.0] - 2026-04-20 - Age Progression & Military Expansion

### Added
- **4 Ages**: Dark → Feudal → Castle → Imperial
- **Age advancement system** with costs and timers
- **Archer unit** (Feudal Age, ranged infantry)
- **Pikeman unit** (Castle Age, anti-cavalry)
- **Man-at-Arms** (Feudal Age infantry upgrade)
- **Long Swordsman** (Castle Age infantry upgrade)
- **Scout unit** (exploration cavalry with auto-explore ability)
- **Heavy Scout** (Feudal Age cavalry upgrade)
- **Knight** (Castle Age heavy cavalry)
- **Stable building** (trains cavalry)
- **Siege Workshop** (Castle Age, trains siege units)
- **Battering Ram** (melee siege, ×3 vs buildings)
- **Mangonel** (AoE siege, 72 px splash, minimum range)
- **Trebuchet** (Imperial Age long-range siege, deploy/undeploy)
- **Technology research** at Barracks (8 techs)
- **AI age advancement** logic
- **AI military module** (training, research, combat)

### Changed
- **Unit training**: gated by Age requirements
- **Building availability**: Age-locked structures (Stable, Siege Workshop, University)
- **AI behavior**: adapts strategy per age

---

## [0.2.0] - 2026-03-10 - Military & Combat

### Added
- **Barracks building** (175 wood, trains infantry)
- **Militia unit** (Dark Age infantry)
- **Melee combat system** with damage calculation
- **Ranged combat system** with projectiles
- **Armour types** (melee/pierce)
- **Fog of War** with 3 states (unexplored/explored/visible)
- **Minimap** with unit/building/resource icons
- **AI opponent** with basic economy and military
- **AI construction module** (building placement)
- **AI economy module** (villager management)
- **Selection grid** showing up to 40 selected units
- **Health bars** for units and buildings
- **Town Center** as main base building

### Changed
- **Villagers**: can now build military structures
- **Resource gathering**: drop-off at Town Center, Lumber Camp, Mining Camp
- **Map generation**: added enemy starting position

---

## [0.1.0] - 2026-02-01 - Foundation

### Added
- **Godot 4** project setup
- **Villagers** with gathering (food, wood, gold)
- **Resource nodes** (trees, gold mines, berries, sheep)
- **Drop-off buildings** (Town Center, Lumber Camp, Mining Camp)
- **Farm** building (60 wood, renewable food)
- **House** building (25 wood, +5 population cap)
- **Wall & Gate** buildings (defense structures)
- **Procedural map generation** with random resources
- **Resource Manager** (per-player stockpiles)
- **Selection Manager** (unit selection, control groups)
- **EventBus** architecture for decoupled signals
- **Data-driven design** with Resource files
- **Navigation system** with NavigationAgent2D
- **Basic HUD** (resource display, population counter)
- **Match lobby** with map settings

### Infrastructure
- **GUT testing framework** integration
- **CI/CD pipeline** with GitHub Actions
- **Documentation** (CLAUDE.md, architecture docs)
- **Sub-agent system** (developer, tester, code-reviewer, docs-keeper, performance-checker)

---

## Roadmap (next)

- Live Steam-lobby test on a real AppID
- Lockstep simulation (requires deterministic, physics-free unit movement)
- Balance tuning from playtesting
- More campaign chapters

---

## Version History Summary

| Version | Date | Description |
|---|---|---|
| (unreleased) | 2026-09-06 | Replays & creator kit, campaign, pastoral economy, camp techs, unit styles, spectator, AI overhaul |
| 0.9.8-beta | 2026-09-02 | Teams & alliances, Steam social, mercenaries, hero audit, MP save/resume, performance |
| 0.9.6/0.9.7-beta | 2026-08-31 | Internet (UPnP) + Steam prototype, reconnection, chat |
| 0.9.1–0.9.5-beta | 2026-08-27→31 | Command pattern, stances/formations/garrison, LAN multiplayer phases 1–2 |
| 0.9.0-beta | 2026-08-26 | Isometric view, per-civ visual identity, control groups, localization |
| 0.6.0 | 2026-06-08 | Visual overhaul: readable figures, unit gender, living terrain |
| 0.5.1 | 2026-06-02 | Heroines: 16-hero roster, lobby gender pick |
| 0.5.0 | 2026-06-01 | Production-ready single-player: 8 civs, weather, save/load, polish |
| 0.4.0 | 2026-05-15 | Naval gameplay, weather system, market, research buildings |
| 0.3.0 | 2026-04-20 | Age progression, cavalry, siege, tech research |
| 0.2.0 | 2026-03-10 | Military units, combat, fog of war, AI opponent |
| 0.1.0 | 2026-02-01 | Foundation: villagers, resources, map generation |
