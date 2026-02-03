#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HOME/.local/bin"
mkdir -p "$BIN"
count=0
for repo in "$ROOT"/repos/*; do
  [ -d "$repo" ] || continue
  tool="$(basename "$repo")"
  src="$repo/$tool"
  if [ -f "$src" ]; then
    install -m 755 "$src" "$BIN/$tool"
    count=$((count+1))
  fi
done
echo "[install_all] installed=$count -> $BIN"
