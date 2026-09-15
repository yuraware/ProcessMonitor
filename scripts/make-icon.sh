#!/usr/bin/env bash
# Regenerates Support/AppIcon.icns from scripts/make-icon.swift.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
swift "$ROOT/scripts/make-icon.swift" "$TMP/AppIcon.iconset"
iconutil -c icns "$TMP/AppIcon.iconset" -o "$ROOT/Support/AppIcon.icns"
echo "Wrote $ROOT/Support/AppIcon.icns"
