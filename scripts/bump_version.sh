#!/usr/bin/env bash
# Bump the release version in lockstep across every per-platform core.json and
# gateware.json, and print the new version to stdout.
#
# Usage: bump_version.sh <patch|minor|major>
#
# The three sibling cores (drizzt.SMS / drizzt.GG / drizzt.SG-1000) release
# together, so their versions are kept identical; gateware.json carries the same
# number for the gateman manifest. The current version is read from the first
# pkg/pocket/Cores/*/core.json (they are all in sync).
set -euo pipefail

BUMP="${1:?usage: bump_version.sh <patch|minor|major>}"
case "$BUMP" in
  patch | minor | major) ;;
  *) echo "bump_version.sh: unknown bump type '$BUMP' (want patch|minor|major)" >&2; exit 1 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

set -- "$PROJECT_DIR"/pkg/pocket/Cores/*/core.json
CURRENT="$(jq -r '.core.metadata.version' "$1")"
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"

case "$BUMP" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
esac

NEW="${MAJOR}.${MINOR}.${PATCH}"
DATE="$(date -u +%Y-%m-%d)"

for f in "$PROJECT_DIR"/pkg/pocket/Cores/*/core.json; do
  jq --arg v "$NEW" --arg d "$DATE" \
    '.core.metadata.version = $v | .core.metadata.date_release = $d' \
    "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done

GATEWARE="$PROJECT_DIR/gateware.json"
if [ -f "$GATEWARE" ]; then
  jq --arg v "$NEW" '.version = $v' "$GATEWARE" > "$GATEWARE.tmp" && mv "$GATEWARE.tmp" "$GATEWARE"
fi

echo "Bumped $CURRENT -> $NEW" >&2
echo "$NEW"
