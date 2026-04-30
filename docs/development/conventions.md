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

## Resource Naming

- Resource files: `snake_case.tres` (e.g., `villager.tres`)
- Resource scripts: `snake_case_resource.gd` (e.g., `unit_resource.gd`)

## Git

- Branch naming: `feat/short-description`, `fix/short-description`
- Commit messages: imperative mood, ≤72 chars subject
- One logical change per commit
