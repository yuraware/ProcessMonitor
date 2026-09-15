#!/usr/bin/env bash
#
# Formats and lints the Swift sources.
#
#   scripts/lint.sh          check only (CI mode); exits non-zero on violations
#   scripts/lint.sh --fix    apply swiftformat and swiftlint autocorrections
#
# Requires: brew install swiftformat swiftlint
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FIX=0
[[ "${1:-}" == "--fix" ]] && FIX=1

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: $1 is not installed. Run: brew install $1" >&2
    exit 1
  fi
}
need swiftformat
need swiftlint

cd "$ROOT"
if [[ $FIX -eq 1 ]]; then
  swiftformat .
  swiftlint --fix --quiet
  swiftlint --quiet
else
  swiftformat --lint .
  swiftlint --strict --quiet
fi
