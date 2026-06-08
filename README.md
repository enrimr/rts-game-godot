# Calima: Flames of the Atlantic

A historically-inspired real-time strategy game set in the Canary Islands and Atlantic trade routes, built with [Godot 4](https://godotengine.org). Experience the clash of indigenous Atlantic civilizations with European colonial powers through fast-paced skirmish battles.

Created by **Enrique Ismael Mendoza Robaina** ([@enrimr](https://github.com/enrimr)).

---

## Status

**Production-ready** — Core gameplay loop complete with 8 playable civilizations, 28 unit types, 21 technologies, and full AI opponent. Recent work focused on polish and bug fixes.

---

## Key Features

### Civilizations
8 unique factions with distinct playstyles:
- **Guanches** (Tenerife) — Fortress infantry, stone building bonus, malpaís traversal
- **Canarii** (Gran Canaria) — Superior food economy, cheap archer rushes
- **Mahos** (Fuerteventura) — Fast expansion, light cavalry raids, dune traversal
- **Franks** (Norman Conquerors) — Rapid age advancement, powerful cavalry
- **Britons** (English Privateers) — Long-range archers, naval dominance
- **Castellanos** (Castilian Conquistadors) — Free Blacksmith tech/age, balanced army
- **Atlantes** (Mythical Sea People) — Amphibious warfare, ship attack speed
- **Fenicios** (Phoenician Traders) — Naval economy, ramming war galleys

Each civilization includes:
- 1 unique hero unit with special ability
- 1 unique military unit with distinctive mechanics
- Civilization-specific stat bonuses
- Historical flavor and strategic identity

### Gameplay Systems
- **4 Ages**: Dark → Feudal → Castle → Imperial
- **4 Resources**: Food, Wood, Gold, Stone
- **28 Unit Types**: Villagers, infantry, cavalry, archers, siege, naval
- **22 Building Types**: Economy, military production, research, defense
- **21 Technologies**: Weapon/armour upgrades, unit improvements, economic bonuses
- **3 Victory Conditions**: Conquest (elimination), Regicide (kill enemy hero), Wonder (build + hold)
- **5 Map Types**: Plains, Standard, Volcanic Coast, Desert Coast, Islands
- **Dynamic Weather**: Calima dust storms, Atlantic storms, sea fog, trade winds, volcanic ash (affects vision, movement, combat)

### Combat & Strategy
- **Ranged Combat**: Attack-ground, cover fire, minimum range mechanics
- **Siege Warfare**: Deploy/undeploy trebuchets, AoE splash damage
- **Naval Gameplay**: Fishing boats, war galleys, troop transports, amphibious assaults
- **Hero Abilities**: 16 legendary heroes (one male + one female per civilization), each with a unique power; gender selectable in the lobby
- **Unit Special Abilities**: Hit-and-run cavalry, ambush shots, lance charges, salvo fire

### Visual Presentation
- **Readable procedural art**: Hand-built vector figures for every unit, building and animal (no external textures)
- **Random unit gender**: Every human unit is randomly male or female (cosmetic); distinct heroine sprites
- **Team-colour identification**: Buildings carry their owner's colour on roofs, flags, banners and sails
- **Living world**: Animated water with coastal foam, pulsing caldera lava, walking animals, ground shadows, ambient lighting

### Technical Highlights
- **Procedural Map Generation**: Random terrain, resources, starting positions
- **Fog of War**: 3-state visibility system (unexplored/explored/visible)
- **AI Opponent**: Economic management, military production, naval operations, age advancement, aggression escalation
- **Save/Load System**: 99 save slots with complete game state serialization
- **Weather System**: Procedural events with real-time stat modifiers and visual effects
- **Spatial Audio**: Distance-based sound attenuation for combat and building
- **Optimized Performance**: Area2D range detection, cached physics queries, outward spiral spawn positioning

---

## Screenshots

*(Coming soon — procedural weather effects, naval battles, siege warfare, hero abilities)*

---

## Getting Started

### Prerequisites

- [Godot 4.3](https://godotengine.org/download) or later (standard build, no C# required)
- Git

### Installation

```bash
git clone https://github.com/enrimr/age-of-empires-clone-godot.git
cd age-of-empires-clone-godot
```

Open **Godot → Import** and select `project/project.godot`.

Press **F5** (or the play button) to launch the game.

### Controls

See **[GAMEPLAY.md](GAMEPLAY.md)** for complete controls, unit stats, building costs, and strategy tips.

**Quick reference:**
- **Left-click**: Select units/buildings
- **Right-click**: Move / Attack / Gather
- **Ctrl + 1-9**: Create control groups
- **1-9**: Recall control groups
- **A**: Attack-move
- **S**: Stop
- **H**: Hold position
- **P**: Patrol
- **Delete**: Delete selected units/buildings
- **Space**: Jump to alert location
- **Escape**: Pause menu

---

## Architecture

### Project Structure

```
project/          ← Open this folder in Godot (contains project.godot)
  assets/         ← Art, audio, fonts, shaders
  scenes/         ← .tscn scene files
  scripts/
    core/         ← Autoloads: GameManager, EventBus, ResourceManager, etc.
    units/        ← UnitBase + 28 unit classes
    buildings/    ← BuildingBase + 22 building classes
    economy/      ← ResourceNode, drop-off logic
    map/          ← MapGenerator, FogOfWar, TerrainManager
    combat/       ← Projectiles, damage calculation
    ai/           ← AIPlayer coordinator + 4 specialist modules
    ui/           ← HUD, minimap, menus
  resources/      ← .tres data files (units, buildings, techs, civs)
tests/            ← GUT unit and integration tests
docs/             ← Architecture and design documentation
```

### Design Principles

- **EventBus pattern**: All cross-system communication via signals
- **Data-driven**: Stats live in `Resource` files, not hardcoded
- **Type safety**: Full type hints on all functions
- **Autoload singletons**: 14 global managers for game systems
- **Performance-first**: Area2D range detection, cached queries, spiral spawning

Full architecture notes: [CLAUDE.md](CLAUDE.md) · [docs/architecture/overview.md](docs/architecture/overview.md)

---

## Testing

Uses [GUT](https://github.com/bitwes/Gut) addon for unit and integration tests.

Install GUT, then open the GUT panel inside Godot and click **Run All**.

Tests live in `tests/unit/` and `tests/integration/`.

---

## Roadmap

| Milestone | Description | Status |
|---|---|---|
| M1 | Villagers gather resources, basic map | ✅ Done |
| M2 | Town Center, Barracks, military, fog of war | ✅ Done |
| M3 | Age progression, new units (Archer, Pikeman) | ✅ Done |
| M4 | Naval gameplay, tech tree, 8 civs, weather system | ✅ Done |
| M5 | All unique units/heroes polished, balance pass | ✅ Done |
| M6 | Custom terrain tiles (malpaís, dune, risco, laurisilva) | 🚧 In progress |
| M7 | Multiplayer (LAN) | 📋 Planned |
| M8 | Campaign mode with story missions | 📋 Planned |

---

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Development Workflow

The project uses 5 specialized sub-agents for development:
1. `developer` — Implements features and fixes bugs
2. `code-reviewer` — Reviews changes before merging
3. `tester` — Writes/updates GUT tests
4. `docs-keeper` — Keeps documentation synchronized
5. `performance-checker` — Profiles and optimizes hot paths

See [CLAUDE.md](CLAUDE.md) for sub-agent details.

---

## License

[CC BY-NC 4.0](LICENSE) — Free to use and modify with attribution, no commercial use.

Copyright © 2026 Enrique Ismael Mendoza Robaina.

---

## Acknowledgments

Inspired by Age of Empires II and the rich history of the Canary Islands.

Built with [Godot Engine](https://godotengine.org) — open source game engine.

Testing powered by [GUT](https://github.com/bitwes/Gut) — Godot Unit Testing framework.

---

## Links

- [Gameplay Guide](GAMEPLAY.md) — Complete how-to-play with unit stats and costs
- [Architecture Documentation](docs/architecture/overview.md) — System design and patterns
- [Civilization Reference](docs/design/civilizations_en.md) — All 8 civs with bonuses and unique units
- [Developer Guide](CLAUDE.md) — Codebase structure and conventions
