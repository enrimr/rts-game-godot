# Getting Started

## Prerequisites

- [Godot 4.3+](https://godotengine.org/download) (standard build, no Mono required)
- Git

## Setup

```bash
git clone https://github.com/your-username/age-of-empires-clone-godot.git
cd age-of-empires-clone-godot
```

Open Godot → **Import** → select `project/project.godot`.

## Project Structure

```
project/          # Godot project root (open this in the editor)
  assets/         # Art, audio, fonts
  scenes/         # .tscn files
  scripts/        # .gd files
  resources/      # .tres / .res data files
tests/            # GUT test suites
docs/             # Architecture and design docs
```

## Running Tests

Install the [GUT (Godot Unit Test)](https://github.com/bitwes/Gut) addon, then run tests from the GUT panel in the editor.

## Coding Conventions

- GDScript only (no C# for now)
- `snake_case` for variables and functions, `PascalCase` for classes and nodes
- All signals defined in `EventBus` — no direct node coupling across systems
- `@export` all tuneable values so designers can tweak without code changes
- Type-hint every function parameter and return value
