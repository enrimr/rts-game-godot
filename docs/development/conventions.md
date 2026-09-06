# Coding Conventions

## GDScript Style

- Type-hint everything: `func foo(x: int) -> String:`
- Use `class_name` for every base class and resource
- Prefer `@export` over hardcoded constants for designer-tweakable values
- Use `const` for true constants (magic numbers that will never change)
- Document non-obvious behaviour with a single-line comment above the relevant line

## Scene Organization

- One `.tscn` per logical entity (unit, building, UI panel)
- Root node name matches the file name in PascalCase
- Attach the main script directly to the root node

## Signal Discipline

- Cross-system events go through `EventBus`
- Local events (within a scene tree subtree) may use direct `connect()`
- Never call methods across system boundaries — emit a signal instead

## Simulation Discipline

- Every simulation-mutating intent (player AND AI) is a serializable `GameCommand` submitted through `CommandBus.submit()` — UI feedback stays at the submission site
- Simulation randomness draws from the `MatchRng` autoload; the global `randf()`/`randi()` are reserved for local-only audio/visual noise
- UI never hardcodes prices: buttons resolve costs from the same `.tres` data the simulation charges

## Resource Naming

- Resource files: `snake_case.tres` (e.g., `villager.tres`)
- Resource scripts: `snake_case_resource.gd` (e.g., `unit_resource.gd`)

## Git

- Branch naming: `feat/short-description`, `fix/short-description`
- Commit messages: imperative mood, ≤72 chars subject
- One logical change per commit
- Release tags only via `scripts/release_tag.sh` (bumps the version the multiplayer handshake checks)
