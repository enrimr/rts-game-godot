# Setup Instructions

1. Install [Godot 4.6+](https://godotengine.org/download) (standard build, no C#).
2. Clone the repository and open `project/project.godot` in Godot (**Import**).
3. Wait for the first import to complete, then press **F5** to play.

Run the test suite headlessly from the repo root:

```bash
GODOT=/path/to/godot ./run_tests.sh
```

Full developer onboarding (project structure, harness catalog, conventions, sub-agent workflow, release tagging): **[docs/development/getting-started.md](docs/development/getting-started.md)**.

## Troubleshooting

- **Missing translations or class errors after pulling**: close Godot, optionally delete `project/.godot/global_script_class_cache.cfg`, reopen the project and let it reimport. Translations can also be reimported individually (FileSystem dock → right-click `assets/translations/translations.csv` → Reimport).
- **New `class_name` not recognized headlessly**: run `$GODOT --headless --path project --import` once.
