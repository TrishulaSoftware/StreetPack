#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "[smoke_all] bash -n (scripts only)..."
# top-level scripts
[ -f "$ROOT/install_all.sh" ] && bash -n "$ROOT/install_all.sh"
[ -f "$ROOT/uninstall_all.sh" ] && bash -n "$ROOT/uninstall_all.sh"

# per-repo tool + tests
for repo in "$ROOT"/repos/*; do
  [ -d "$repo" ] || continue
  tool="$(basename "$repo")"
  if [ -f "$repo/$tool" ]; then
    bash -n "$repo/$tool"
  fi
  for sh in "$repo"/tests/*.sh; do
    [ -f "$sh" ] && bash -n "$sh"
  done
done

echo "[smoke_all] per-repo smoke tests..."
for repo in "$ROOT"/repos/*; do
  [ -d "$repo/tests" ] || continue
  (cd "$repo/tests" && bash ./smoke.sh)
done

echo "[smoke_all] PASS"
