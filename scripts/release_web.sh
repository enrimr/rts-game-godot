#!/usr/bin/env bash
set -euo pipefail

GODOT="/Applications/Godot.app/Contents/MacOS/Godot"
GAME_REPO="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$GAME_REPO/project"
BUILD_DIR="$GAME_REPO/builds/html"
RELEASE_REPO="/Users/enrique/development/projects/calima-kingdoms-web"

# ── 1. Export ─────────────────────────────────────────────────────────────────
echo "==> Exporting Web build..."
mkdir -p "$BUILD_DIR"
"$GODOT" --headless --path "$PROJECT_DIR" --export-release "Web" "$BUILD_DIR/index.html"
echo "    Build complete."

# ── 2. Copy to release repo ───────────────────────────────────────────────────
echo "==> Copying files to release repo..."
cp "$BUILD_DIR"/index.* "$RELEASE_REPO"/

# ── 3. Commit & push ─────────────────────────────────────────────────────────
echo "==> Committing..."
cd "$RELEASE_REPO"

# Derive version tag from latest game repo commit
GAME_HASH=$(git -C "$GAME_REPO" rev-parse --short HEAD)
GAME_DATE=$(date +%Y-%m-%d)
MSG="release: ${GAME_DATE} (${GAME_HASH})"

git add -A
if git diff --cached --quiet; then
    echo "    Nothing changed — build is identical to last release."
    exit 0
fi

git commit -m "$MSG"
git push origin HEAD
echo "==> Done. Pushed: $MSG"
