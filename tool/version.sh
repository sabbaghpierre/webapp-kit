#!/usr/bin/env bash
# tool/version.sh [new-version] — the single entry point for versioning.
# Without args: prints current version. With an arg: writes VERSION and
# stamps the pubspec.yaml literal (Dart forbids anything but a literal
# version: field), then shows the diff. CI fails any build where the
# two disagree, so this stays the one place versions change.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$ROOT/VERSION"
PUBSPEC="$ROOT/tui/pubspec.yaml"

current="$(cat "$VERSION_FILE" 2>/dev/null || echo dev)"
if (($# == 0)); then
  printf '%s\n' "$current"
  exit 0
fi

NEW="$1"
if [[ ! "$NEW" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "tool/version.sh: version must look like 0.0.1, got '$NEW'" >&2
  exit 1
fi

printf '%s\n' "$NEW" >"$VERSION_FILE"
if [[ -f "$PUBSPEC" ]]; then
  sed -i "s/^version: .*/version: $NEW/" "$PUBSPEC"
fi
if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$ROOT" diff -- VERSION tui/pubspec.yaml || true
else
  echo "VERSION=$NEW (pubspec stamped)"
fi
