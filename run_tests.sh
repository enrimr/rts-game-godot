#!/usr/bin/env bash
# Run the GUT unit test suite headlessly.
#
# Usage:  ./run_tests.sh            # all tests in tests/unit
#         ./run_tests.sh res://tests/unit/test_world_query.gd   # a single script
#
# Requires Godot 4.x on PATH as `godot`, or set GODOT to the binary path, e.g.
#   GODOT="/Applications/Godot.app/Contents/MacOS/Godot" ./run_tests.sh
set -euo pipefail

GODOT="${GODOT:-godot}"
PROJECT_DIR="$(cd "$(dirname "$0")/project" && pwd)"
TARGET="${1:-res://tests/unit}"

cd "$PROJECT_DIR"

# -gselect runs a single script when TARGET points at a .gd file; otherwise
# -gdir runs every test in the directory. -gexit makes Godot return the GUT
# exit code (non-zero on failure) so CI can gate on it.
if [[ "$TARGET" == *.gd ]]; then
  exec "$GODOT" --headless -s addons/gut/gut_cmdln.gd -gselect="$TARGET" -gexit
else
  exec "$GODOT" --headless -s addons/gut/gut_cmdln.gd -gdir="$TARGET" -gexit
fi
