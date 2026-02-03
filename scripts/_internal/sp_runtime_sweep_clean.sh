#!/usr/bin/env bash
set -euo pipefail
BASE="${XDG_DATA_HOME:-$HOME/.local/share}/streetpack"
STAMP="$(date -u +%Y%m%d_%H%M%S_%3NZ 2>/dev/null || date -u +%Y%m%d_%H%M%SZ)"
BK="$BASE/_ship_sweep_backup/$STAMP"
mkdir -p "$BK"

for d in receipts outputs logs out; do
  if [[ -d "$BASE/$d" ]]; then
    mv -n "$BASE/$d" "$BK/" || true
  fi
  mkdir -p "$BASE/$d"
done

echo "OK: swept runtime artifacts to: $BK"
