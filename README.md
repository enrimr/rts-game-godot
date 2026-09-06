# Calima: Flames of the Atlantic

A real-time strategy game in the spirit of Age of Empires II, set in the Canary Islands at the crossroads of native kingdoms, ancient seafarers and European invaders. Built entirely with [Godot 4](https://godotengine.org) and GDScript — every sprite, sound and voice in the game is generated procedurally, with zero external art or audio assets.

Created by **Enrique Ismael Mendoza Robaina** ([@enrimr](https://github.com/enrimr)).

Current version: **0.9.8-beta** (see [CHANGELOG.md](CHANGELOG.md)).

---

## Key Features

### Content
- **8 civilizations** across three historical layers (native islanders, ancient seafarers, European invaders), each with unique bonuses, a unique military unit and two named heroes
- **26 unit types** — villagers, a priestess-healer, a herding dog, three infantry lines, cavalry, siege engines (with a deploy/undeploy trebuchet), ships, and 8 civilization-unique units
- **16 named heroes** (one male + one female per civilization), each with a distinct active ability; hero gender selectable in the lobby
- **20 building types** — economy, military production, research, defense, and the Wonder
- **32 technologies** — Blacksmith weapon/armour lines, University siege science, Temple rites, four unit upgrades, and three-step economy lines at the Lumber Camp, Mining Camp and Mill
- **Campaign**: *The Flames of Tamarán* — a tutorial prologue plus four scripted missions of the Canarii resistance against the Atlante invasion
- **3 victory conditions**: Conquest, Regicide (protect your hero), Wonder (build and hold)
- **5 procedural map types** (Plains, Standard, Volcanic Coast, Desert Coast, Islands) in three sizes, with 4 starting-resource modes

### Systems
- **Dynamic weather** — 5 event types (Calima dust, Atlantic Storm, Sea Fog, Trade Winds, Volcanic Ash) with real stat effects, a forecast warning, per-civilization resistances and sea-fog cloaking
- **Terrain that matters** — malpaís lava fields, dunes, cliff vantage points, laurisilva forests and calderas, each with movement/vision/combat effects and per-civ traversal bonuses
- **AoE2-style combat controls** — stances, group formations, attack-move, patrol, shift-queued waypoints, control groups, garrison with building volleys, town bell
- **Naval and amphibious warfare** — fishing economy, war galleys, troop transports, and the Atlantes Tidecaller that wades into the sea
- **Full AI opponents** — economy (including herding dogs and livestock), construction with real builder villagers, fog-honest military targeting, naval assaults, allied-AI teamwork, and three difficulty levels
- **Save/Load** — 99 slots, complete game state including in-flight research, garrisons and live weather
- **Fog of war** — three states with AoE2-style building memory on map and minimap

### Multiplayer
- **LAN and Internet** (UPnP) multiplayer for up to 4 players, host-authoritative with client mirror worlds interpolated at 15 Hz
- **Teams and alliances** (2v2, 2v1, ...) across skirmish and multiplayer, with allied AI teammates
- Unified lobby with per-player colours, civs and teams, open/AI/closed seats, chat, kick, and a version handshake
- **Mid-match reconnection** (reserved seats + full resync) and **multiplayer save/resume** with the original players
- **Steam transport prototype** (lobbies, invites, Valve relay — test AppID)

### Replays & creator kit
- Every match records itself (`user://replays/`); watch from the **Replays** menu with a seekable timeline, pause, playback speeds and a reveal-map toggle
- **Cinematic mode** (UI-free), optional floating minimap, and **video export** — render a whole replay or an A/B-marked clip to a 30 FPS video in the background
- **Spectator mode** — defeated or surrendered while others still fight? "View map" keeps you watching the live battle (orders locked)

### Presentation
- 100 % procedural vector art with three selectable unit styles — **Classic**, **Enhanced** (ink outline + shading + extra animation) and **Redesigned** (lore-driven rigs) — switchable live in settings
- Team colours on units and buildings, per-civ architecture and ship dress, hero auras, progressive fire/smoke on damaged buildings
- Fully synthesized audio: per-civilization gibberish voice "languages" (formant synthesis), spatial sound effects and procedural music
- English and Spanish localization

---

## Civilizations

| Civilization | Layer | Identity |
|---|---|---|
| **Guanches** (Tenerife) | Native | Stone buildings +20% HP, malpaís traversal, early spearmen — Menceyes Guard |
| **Canarii** (Gran Canaria) | Native | +15% food gathering, cheap archers — Ravine Archer (cliff range bonus) |
| **Mahos** (Lanzarote/Fuerteventura) | Native | −30% building wood cost, fast light cavalry, dune traversal — Sand Raider |
| **Francos** (Norman conquerors) | Invader | −15% age-advance cost, +15% cavalry HP — Chevalier Normand |
| **Britanos** (English privateers) | Invader | Archer range +1 per age, faster warships — Longbowman |
| **Castellanos** (Castilian crown) | Invader | Free Blacksmith tech per age, tough swordsmen — Conquistador |
| **Atlantes** (the drowned empire) | Ancient | Coastal vision +50%, sea-fog stealth, faster ships — amphibious Tidecaller |
| **Fenicios** (Phoenician traders) | Ancient | Market from the Dark Age, mercenary hiring — ramming Trireme |

Full details: [docs/design/civilizations_en.md](docs/design/civilizations_en.md) · [player's guide](docs/guide_en.md).

---

## Screenshots

Unit-style galleries (captured by the review harnesses) live in the repo:

- [Redesigned unit rigs](docs/design/unit-redesign-gallery/a_2_redesigned_grid.png) — and [in motion](docs/design/unit-redesign-gallery/a_6_redesigned_attack.png)
- [Enhanced style](docs/design/unit-enhanced-gallery/enhanced_grid.png) vs [Classic](docs/design/unit-enhanced-gallery/classic_grid.png)

---

## Getting Started

### Play

- [Godot 4.6](https://godotengine.org/download) or later (standard build, no C#)

```bash
git clone https://github.com/enrimr/age-of-empires-clone-godot.git
cd age-of-empires-clone-godot
```

Open **Godot → Import** and select `project/project.godot`, then press **F5**.

### Learn to play

- **[GAMEPLAY.md](GAMEPLAY.md)** — controls and hotkeys quick reference
- **[Player's Guide (EN)](docs/guide_en.md)** / **[Guía del Jugador (ES)](docs/guide_es.md)** — the full manual: civilizations, economy, tech tree, combat, multiplayer, replays, campaign

### Run the tests

```bash
GODOT=/path/to/godot ./run_tests.sh                # whole GUT suite (unit + integration)
GODOT=/path/to/godot ./run_tests.sh res://tests/unit/test_world_query.gd   # one script
```

Standalone headless/renderer harnesses live under `project/tools/` — the full catalog is in [docs/testing/harnesses.md](docs/testing/harnesses.md).

---

## Architecture

```
project/          ← Open this in Godot (contains project.godot)
  assets/         ← Fonts, shaders, translations (art & audio are procedural)
  scenes/         ← .tscn scene files
  scripts/
    core/         ← Autoload singletons (GameManager, EventBus, CommandBus, ...)
    units/        ← UnitBase + 26 unit classes
    buildings/    ← BuildingBase + building classes
    game/         ← GameWorld scene root + world controllers + GameCommand layer
    campaign/     ← CampaignData, CampaignManager, MissionDirector
    map/          ← Map generation pipeline, FogOfWar, terrain
    ai/           ← AIPlayer coordinator + economy/construction/military/naval modules
    multiplayer/  ← NetworkSession, StateReplicator, ReplayFile
    ui/           ← HUD components, menus, minimap, lobby
  resources/      ← .tres data (units, buildings, technologies, civilizations)
  tests/          ← GUT unit and integration tests
docs/             ← Architecture, design and player documentation
```

### Design principles

- **Command pattern** — every simulation-mutating order (player and AI) is a serializable `GameCommand` through `CommandBus`; the tick-stamped log is the backbone of replays and multiplayer
- **EventBus pattern** — all cross-system communication via signals
- **Data-driven** — stats live in `Resource` files, never hardcoded; UI buttons read prices from the same data the simulation charges
- **Host-authoritative multiplayer** — clients puppet interpolated mirror worlds; the wire never gains privileges
- **Deterministic simulation randomness** — one seeded `MatchRng` stream per match
- **Type safety** — full type hints on all functions

Full notes: [docs/architecture/overview.md](docs/architecture/overview.md) · [docs/architecture/systems.md](docs/architecture/systems.md) · [CLAUDE.md](CLAUDE.md)

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and [docs/development/getting-started.md](docs/development/getting-started.md). The project is developed with 5 specialized AI sub-agents (developer, code-reviewer, tester, docs-keeper, performance-checker) — see [CLAUDE.md](CLAUDE.md).

Releases are tagged only via `scripts/release_tag.sh` (it bumps the project version — which the multiplayer handshake checks — commits, tags and pushes in one step).

---

## License

[CC BY-NC 4.0](LICENSE) — Free to use and modify with attribution, no commercial use.

Copyright © 2026 Enrique Ismael Mendoza Robaina.

---

## Acknowledgments

Inspired by Age of Empires II and the history of the Canary Islands.

Built with [Godot Engine](https://godotengine.org). Testing powered by [GUT](https://github.com/bitwes/Gut). Steam networking via [GodotSteam](https://godotsteam.com).

---

## Links

- [Gameplay quick reference](GAMEPLAY.md) — controls and hotkeys
- [Player's Guide](docs/guide_en.md) / [Guía del Jugador](docs/guide_es.md) — the full manual
- [Architecture overview](docs/architecture/overview.md) · [System design details](docs/architecture/systems.md)
- [Game design document](docs/design/game-design-document.md)
- [Civilization reference](docs/design/civilizations_en.md)
- [Harness catalog](docs/testing/harnesses.md)
- [Developer guide](CLAUDE.md)
