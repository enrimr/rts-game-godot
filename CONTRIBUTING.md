# Contributing

## Workflow

1. Fork the repository and create a feature branch from `main` (`feat/short-description` or `fix/short-description`)
2. Make your changes following the [coding conventions](docs/development/conventions.md) and the architecture rules in [CLAUDE.md](CLAUDE.md) (EventBus signals, CommandBus for simulation mutations, `.tres`-driven stats, MatchRng for simulation randomness)
3. Run the test suite before opening a PR: `GODOT=/path/to/godot ./run_tests.sh` (runs both `tests/unit` and `tests/integration`; check the `Scripts` count — GUT skips unparseable scripts silently). If your change touches a gated system (map generation, navigation, multiplayer, sea containment, performance), run the relevant harness from [docs/testing/harnesses.md](docs/testing/harnesses.md) too
4. Keep documentation in sync — `docs/` and `CLAUDE.md` must describe the code as it is (all technical docs in English)
5. Open a PR with a clear description of what changed and why

Releases are tagged only via `scripts/release_tag.sh` (maintainers).

## Reporting Bugs

Use the GitHub issue tracker. Include the Godot version, OS, steps to reproduce, and — for multiplayer issues — whether you were host or client.
