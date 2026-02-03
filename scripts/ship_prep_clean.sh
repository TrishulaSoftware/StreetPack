#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

echo "== Deleting repo junk =="
find . -maxdepth 5 \( -name '*.egg-info' -o -name dist -o -name build -o -name '__pycache__' -o -name '.pytest_cache' -o -name '.mypy_cache' -o -name '.ruff_cache' \) -print -exec rm -rf -- {} +
find . -maxdepth 8 -type f \( -name '*.pyc' -o -name '*.pyo' \) -print -delete

echo "== Deleting runtime artifacts =="
SPHOME="$HOME/.local/share/streetpack"
rm -rf -- "$SPHOME/receipts" "$SPHOME/outputs" "$SPHOME/logs" "$SPHOME/tmp" "$SPHOME/cache" 2>/dev/null || true

echo "DONE"
