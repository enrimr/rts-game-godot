# Changelog

All notable changes to **Calima: Flames of the Atlantic** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

## [0.5.0] - 2026-06-01 - Production-Ready Milestone

### Summary
All core features implemented. 8 playable civilizations, 28 unit types, 21 technologies, full AI opponent, complete save/load system, dynamic weather, and 3 victory conditions. Recent work focused on polish and bug fixes to achieve production-ready status.

### Added
- **Cover Fire command** for archers and siege units (move into range then attack-ground)
- **Flying arrow projectiles** with visual arc animation
- **Procedural body animation** for all units (walk, attack, work)
- **Polygon2D silhouettes** for all units and buildings (replaces ColorRect placeholders)
- **Tall stone tower visual** for Watch Tower
- **Archery Range** building (Feudal Age, trains Archer)
- **Attack-ground command** for ranged and siege units
- **Outward spiral spawn positioning** using physics queries to prevent unit overlap
- **21 technologies** across Blacksmith (9), University (3), Temple (3), Unit Upgrades (4), Castellanos instant grants (2)
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
- **Godot 4.3** project setup
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

## [Unreleased]

### Planned Features
- **Multiplayer (LAN)** — M7 milestone
- **Custom terrain tiles** — malpaís, dune, risco, laurisilva (M6)
- **Campaign mode** — story missions (M8)
- **Tutorial mode** — complete interactive tutorial
- **Mercenary system** — full UI integration
- **Advanced AI** — difficulty levels, personality traits
- **More unique unit abilities** — complete all civ-specific mechanics
- **Sound effects** — complete audio coverage for all actions
- **Music system** — dynamic soundtrack per age/situation
- **Localization** — Spanish, English, French translations

---

## Version History Summary

| Version | Date | Description |
|---|---|---|
| 0.5.0 | 2026-06-01 | Production-ready: 8 civs, 21 techs, weather, save/load, polish |
| 0.4.0 | 2026-05-15 | Naval gameplay, weather system, market, research buildings |
| 0.3.0 | 2026-04-20 | Age progression, cavalry, siege, tech research |
| 0.2.0 | 2026-03-10 | Military units, combat, fog of war, AI opponent |
| 0.1.0 | 2026-02-01 | Foundation: villagers, resources, map generation |
