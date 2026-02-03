#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
FAIL=0

echo "[smoke_all] bash -n on all tools..."
while IFS= read -r -d '' f; do
  if ! bash -n "$f" >/dev/null 2>&1; then
    echo "[FAIL] bash -n: $f"
    FAIL=1
  fi
done < <(find "$HERE/repos" -maxdepth 2 -type f -name "*" -perm -111 -print0)

echo "[smoke_all] per-repo smoke tests..."
for d in "$HERE"/repos/*; do
  [[ -d "$d" ]] || continue
  if [[ -x "$d/tests/smoke.sh" ]]; then
    echo "[smoke] $(basename "$d")"
    if ! (cd "$d" && ./tests/smoke.sh); then
      echo "[FAIL] tests: $d"
      FAIL=1
    fi
  fi
done

if [[ "$FAIL" -ne 0 ]]; then
  echo "[smoke_all] FAIL"
  exit 1
fi
echo "[smoke_all] PASS"
