# Calima Kingdoms: Flames of the Atlantic

An Age of Empires II inspired real-time strategy game built with [Godot 4](https://godotengine.org).  
Created by **Enrique Ismael Mendoza Robaina** ([@enrimr](https://github.com/enrimr)).

## Status

Active development — core gameplay loop playable. See [GAMEPLAY.md](GAMEPLAY.md) for controls and a full how-to-play guide.

## What works right now

- Procedural map generation (resources, animals, two teams)
- Fog of war with three states: unexplored / explored / visible
- Villagers gather Food, Wood, Gold and return to drop-off buildings
- Build House, Barracks, Lumber Camp, Mining Camp, Farm, Wall, Gate
- Train Militia from the Barracks (Dark Age)
- **Age progression** Dark → Feudal → Castle → Imperial
  - Feudal unlocks Archer in the Barracks
  - Castle unlocks Pikeman in the Barracks
- Sheep conversion (nearest unit claims them)
- Scout unit for each team at game start
- AI opponent: gathers resources, builds a Barracks, trains and attacks, advances Ages, escalates aggression when threatened
- Minimap with right-click to move selected units
- Camera follow selected unit group
- Population cap (Houses expand it)
- Game-over screen with return-to-menu button

## Getting Started

### Prerequisites

- [Godot 4.3](https://godotengine.org/download) or later (standard build, no C# required)
- Git

### Running the game

```bash
git clone https://github.com/enrimr/rts-game-godot.git
cd rts-game-godot
```

Open **Godot → Import** and select `project/project.godot`.

Press **F5** (or the play button) to run.

### Running tests

Install the [GUT addon](https://github.com/bitwes/Gut), then open the GUT panel inside the Godot editor and click **Run All**.

## How to play

See **[GAMEPLAY.md](GAMEPLAY.md)** for a complete guide: controls, unit roster, building costs, Age advancement costs, and tips.

## Project Structure

```
project/          ← Open this folder in Godot (contains project.godot)
  assets/         ← Art, audio, fonts, shaders
  scenes/         ← .tscn scene files
  scripts/
    core/         ← Singletons: GameManager, EventBus, ResourceManager,
    │               SelectionManager, PopulationManager, AgeManager
    units/        ← UnitBase, Villager, Militia, Archer, Pikeman, Scout, Sheep
    buildings/    ← BuildingBase, TownCenter, Barracks, House, …
    economy/      ← ResourceNode, drop-off logic
    map/          ← MapGenerator, FogOfWar
    ai/           ← AIPlayer state machine
    ui/           ← HUDManager, ResourceDisplay, UnitPortrait, Minimap
  resources/      ← .tres data files (UnitResource, BuildingResource, …)
tests/            ← GUT unit and integration tests
docs/             ← Architecture and design documentation
```

Full architecture notes: [CLAUDE.md](CLAUDE.md) · [docs/architecture/overview.md](docs/architecture/overview.md)

## Roadmap

| Milestone | Description | Status |
|---|---|---|
| M1 | Villagers gather resources, basic map | Done |
| M2 | Town Center, Barracks, military, fog of war | Done |
| M3 | Age progression, new units (Archer, Pikeman) | Done |
| M4 | Full tech tree for one civilization | Planned |
| M5 | Five civilizations with unique content | Planned |
| M6 | Multiplayer (LAN) | Planned |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[CC BY-NC 4.0](LICENSE) — free to use and modify with attribution, no commercial use.  
Copyright © 2026 Enrique Ismael Mendoza Robaina.
