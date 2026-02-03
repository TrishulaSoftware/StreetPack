#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
for d in "$HERE"/repos/*; do
  [[ -d "$d" ]] || continue
  if [[ -x "$d/install.sh" ]]; then
    echo "[install_all] $(basename "$d")"
    (cd "$d" && ./install.sh)
  fi
done
echo "[install_all] done"
