# Getting Started

## Prerequisites

- [Godot 4.6](https://godotengine.org/download) or later (standard build, no Mono/C# required)
- Git
- Python 3 (only for regenerating the harness catalog)

## Setup

```bash
git clone https://github.com/enrimr/age-of-empires-clone-godot.git
cd age-of-empires-clone-godot
```

Open Godot → **Import** → select `project/project.godot`, wait for the first import to finish, then press **F5** to run.

There are no external art or audio assets — everything is generated procedurally at startup (the first launch bakes ~460 voice clips on a worker thread).

## Project Structure

```
project/          # Godot project root (open this in the editor)
  assets/         # Fonts, shaders, translations (translations.csv)
  scenes/         # .tscn files
  scripts/        # .gd files (core/, units/, buildings/, game/, ai/, map/,
                  #            campaign/, multiplayer/, ui/, utils/)
  resources/      # .tres data files (units, buildings, technologies, civs)
  tests/          # GUT test suites (unit/ + integration/)
  tools/          # Standalone check_* harnesses (headless + renderer)
docs/             # Architecture, design, testing and player docs
scripts/          # Repo-level shell scripts (release_tag.sh)
```

## Running Tests

The [GUT](https://github.com/bitwes/Gut) addon is vendored at `project/addons/gut` — nothing to install.

```bash
GODOT=/path/to/godot ./run_tests.sh                                  # whole suite (unit + integration)
GODOT=/path/to/godot ./run_tests.sh res://tests/unit/test_herding.gd # one script
```

Notes:

- GUT silently **skips** a test script that fails to parse while still reporting "all passed" — always check the `Scripts` count in the summary, and run `$GODOT --headless --path project --import` after adding a new `class_name`.
- Standalone harnesses under `project/tools/` cover what GUT can't (scene loads, screenshots, multi-process networking, long simulations). The full catalog with env vars is **[docs/testing/harnesses.md](../testing/harnesses.md)**; the curated CI-gate subset is in [CLAUDE.md](../../CLAUDE.md) → Testing.

## Coding Conventions

See [conventions.md](conventions.md). The essentials:

- GDScript only (no C#); type-hint every parameter and return value
- `snake_case` for variables/functions/files, `PascalCase` for classes/nodes
- All cross-system signals go through `EventBus`; every simulation-mutating order goes through `CommandBus` as a `GameCommand`
- Stats live in `.tres` resources, never hardcoded; simulation randomness draws from `MatchRng`
- `@export` all designer-tunable values

## Sub-agent workflow

The project is developed with five specialized AI agents defined in `.claude/agents/` (see [CLAUDE.md](../../CLAUDE.md) → Sub-agents):

```
developer  →  code-reviewer  →  tester  →  docs-keeper
```

`performance-checker` joins whenever a change touches `_process`/`_physics_process` or unit-heavy features.

## Releases

Tag releases **only** with `scripts/release_tag.sh` — it bumps `application/config/version` in `project.godot` (which the multiplayer version handshake checks), commits, tags and pushes in one step. It auto-increments the patch keeping the suffix; supports `--dry-run`, `--skip-tests`, or an explicit version argument.
