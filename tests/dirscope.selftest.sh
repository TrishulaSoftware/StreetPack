#!/usr/bin/env bash
set -euo pipefail

echo "[dirscope] selftest"
dirscope --selftest

echo "[dirscope] json sanity (no receipt)"
ROOT="$(mktemp -d)"
trap 'rm -rf "$ROOT"' EXIT
mkdir -p "$ROOT/a"
printf 'hello\n' > "$ROOT/a/file.txt"

dirscope "$ROOT" --json --no-receipt > "$ROOT/out.json"

python3 - <<'PY' "$ROOT/out.json"
import json, sys
p = sys.argv[1]
obj = json.load(open(p, "r", encoding="utf-8"))
# minimal schema checks (tight + stable)
assert obj["tool"]["name"] == "dirscope"
assert obj["scan"]["symlink_policy"] == "no-follow"
assert "counts" in obj and "files" in obj["counts"]
assert obj["counts"]["files"] >= 1
print("PASS: json schema ok")
PY

echo "[dirscope] receipt proof (isolated XDG_DATA_HOME)"
XDG_TMP="$(mktemp -d)"
trap 'rm -rf "$XDG_TMP"' EXIT
XDG_DATA_HOME="$XDG_TMP" dirscope "$ROOT" --json > /dev/null

RDIR="$XDG_TMP/streetpack/receipts/dirscope"
test -d "$RDIR"
test "$(ls -1 "$RDIR" | wc -l)" -ge 1
echo "PASS: receipt created in $RDIR"
