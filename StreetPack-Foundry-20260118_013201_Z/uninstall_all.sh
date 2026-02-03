#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
for d in "$HERE"/repos/*; do
  [[ -d "$d" ]] || continue
  if [[ -x "$d/uninstall.sh" ]]; then
    echo "[uninstall_all] $(basename "$d")"
    (cd "$d" && ./uninstall.sh)
  fi
done
echo "[uninstall_all] done"
