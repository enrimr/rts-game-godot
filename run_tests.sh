#!/usr/bin/env bash
# Run the GUT test suite headlessly (tests/unit AND tests/integration).
#
# Usage:  ./run_tests.sh            # the whole suite
#         ./run_tests.sh res://tests/unit/test_world_query.gd   # a single script
#
# Requires Godot 4.x on PATH as `godot`, or set GODOT to the binary path, e.g.
#   GODOT="/Applications/Godot.app/Contents/MacOS/Godot" ./run_tests.sh
set -euo pipefail

GODOT="${GODOT:-godot}"
PROJECT_DIR="$(cd "$(dirname "$0")/project" && pwd)"
TARGET="${1:-}"

cd "$PROJECT_DIR"

# -gselect runs a single script when TARGET points at a .gd file; otherwise
# -gdir runs every test in the directory. -gexit makes Godot return the GUT
# exit code (non-zero on failure) so CI can gate on it. The default runs BOTH
# test dirs — tests/integration used to be silently left out of every run.
if [[ "$TARGET" == *.gd ]]; then
  exec "$GODOT" --headless -s addons/gut/gut_cmdln.gd -gdir="$(dirname "$TARGET")" -gselect="$(basename "$TARGET")" -gexit
elif [[ -n "$TARGET" ]]; then
  exec "$GODOT" --headless -s addons/gut/gut_cmdln.gd -gdir="$TARGET" -gexit
else
  exec "$GODOT" --headless -s addons/gut/gut_cmdln.gd \
    -gdir=res://tests/unit -gdir=res://tests/integration -gexit
fi
