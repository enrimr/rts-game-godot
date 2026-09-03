#!/usr/bin/env bash
set -euo pipefail

# Release tagging with the version bump the NETWORK HANDSHAKE depends on:
# NetworkSession compares project.godot's application/config/version between
# host and client and refuses mismatches, so the tag and that setting must
# always move together. This script is the only supported way to tag.
#
# Usage:
#   scripts/release_tag.sh                # bump patch: v0.9.8-beta -> v0.9.9-beta
#   scripts/release_tag.sh 1.0.0          # explicit version (v prefix optional)
#   scripts/release_tag.sh --dry-run      # show what would happen, touch nothing
#   scripts/release_tag.sh --skip-tests   # tag without running the GUT suite
# Flags and version can be combined in any order.

GAME_REPO="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_GODOT="$GAME_REPO/project/project.godot"
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"

DRY_RUN=0
SKIP_TESTS=0
NEW_VERSION=""
for arg in "$@"; do
    case "$arg" in
        --dry-run)    DRY_RUN=1 ;;
        --skip-tests) SKIP_TESTS=1 ;;
        *)            NEW_VERSION="${arg#v}" ;;
    esac
done

cd "$GAME_REPO"

# ── Preconditions ─────────────────────────────────────────────────────────────
if [[ -n "$(git status --porcelain)" ]]; then
    echo "ERROR: working tree not clean — commit or stash first." >&2
    exit 1
fi
if [[ "$(git rev-parse --abbrev-ref HEAD)" != "main" ]]; then
    echo "ERROR: releases are tagged from main." >&2
    exit 1
fi

LAST_TAG="$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")"

# ── Version: explicit arg, or bump the patch keeping the suffix ──────────────
if [[ -z "$NEW_VERSION" ]]; then
    base="${LAST_TAG#v}"                       # 0.9.8-beta
    suffix=""
    core="$base"
    if [[ "$base" == *-* ]]; then
        suffix="-${base#*-}"                   # -beta
        core="${base%%-*}"                     # 0.9.8
    fi
    IFS=. read -r major minor patch <<< "$core"
    NEW_VERSION="${major}.${minor}.$((patch + 1))${suffix}"
fi
NEW_TAG="v${NEW_VERSION}"

if git rev-parse "$NEW_TAG" >/dev/null 2>&1; then
    echo "ERROR: tag $NEW_TAG already exists." >&2
    exit 1
fi

echo "==> Last tag:    $LAST_TAG"
echo "==> New release: $NEW_TAG"
echo "==> Commits since $LAST_TAG:"
git log --oneline "$LAST_TAG"..HEAD | sed 's/^/      /'

if [[ "$DRY_RUN" == "1" ]]; then
    echo "==> DRY RUN — would set config/version=\"$NEW_VERSION\", commit, tag $NEW_TAG and push."
    exit 0
fi

# ── Tests ─────────────────────────────────────────────────────────────────────
if [[ "$SKIP_TESTS" == "0" ]]; then
    echo "==> Running the GUT suite..."
    GODOT="$GODOT" ./run_tests.sh > /tmp/release_tag_tests.log 2>&1 \
        || { echo "ERROR: tests failed — see /tmp/release_tag_tests.log" >&2; exit 1; }
    grep -E "All tests passed" /tmp/release_tag_tests.log >/dev/null \
        || { echo "ERROR: could not confirm a green suite — see /tmp/release_tag_tests.log" >&2; exit 1; }
    # GUT silently skips unparseable test scripts and still reports success:
    # the reported script count must match the files on disk.
    expected=$(find project/tests/unit -name 'test_*.gd' | wc -l | tr -d ' ')
    reported=$(grep -E '^Scripts[[:space:]]+[0-9]+' /tmp/release_tag_tests.log | awk '{print $2}')
    if [[ "$expected" != "$reported" ]]; then
        echo "ERROR: GUT ran $reported of $expected test scripts — a parse error is being skipped silently." >&2
        exit 1
    fi
    echo "    Suite green ($reported/$expected scripts)."
fi

# ── Version bump (the handshake source of truth) ─────────────────────────────
if grep -q '^config/version=' "$PROJECT_GODOT"; then
    sed -i '' "s|^config/version=.*|config/version=\"$NEW_VERSION\"|" "$PROJECT_GODOT"
else
    echo "ERROR: config/version missing from project.godot — the network handshake needs it." >&2
    exit 1
fi
echo "==> project.godot -> config/version=\"$NEW_VERSION\""

git add "$PROJECT_GODOT"
git commit -m "chore: release $NEW_TAG — bump handshake version"
git tag -a "$NEW_TAG" -m "$NEW_TAG"
git push origin main --follow-tags
echo "==> Done: $NEW_TAG tagged and pushed (handshake version in sync)."
