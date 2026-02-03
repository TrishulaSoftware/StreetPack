#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-streetpack_dock.py}"

# Tunables (override by env if you want)
RESERVE_W="${RESERVE_W:-140}"
RESERVE_H="${RESERVE_H:-220}"   # GNOME top bar + dock often needs more
MIN_W="${MIN_W:-740}"
MIN_H="${MIN_H:-520}"

if [[ ! -f "$TARGET" ]]; then
  echo "ERR: target not found: $TARGET" >&2
  exit 2
fi

STAMP="$(date -u +%Y%m%d_%H%M%S_%3NZ 2>/dev/null || date -u +%Y%m%d_%H%M%SZ)"
BAK="${TARGET}.bak.${STAMP}"
cp -a -- "$TARGET" "$BAK"

TMP="${TARGET}.tmp.${STAMP}"

awk -v rw="$RESERVE_W" -v rh="$RESERVE_H" -v mw="$MIN_W" -v mh="$MIN_H" '
function has(s, pat){ return (s ~ pat) }

{
  line=$0

  # 1) Lower the defaults in the function signature if present
  if (has(line, /^def[ \t]+fit_to_screen\(/)) {
    gsub(/reserve_w=[0-9]+/, "reserve_w=" rw, line)
    gsub(/reserve_h=[0-9]+/, "reserve_h=" rh, line)
    gsub(/min_w=[0-9]+/, "min_w=" mw, line)
    gsub(/min_h=[0-9]+/, "min_h=" mh, line)
    print line
    next
  }

  # 2) Fix/update the call (keep indentation)
  if (has(line, /^[ \t]*fit_to_screen[ \t]*\([ \t]*root/)) {
    match(line, /^[ \t]*/)
    ind = substr(line, RSTART, RLENGTH)

    # If it is a bare call fit_to_screen(root) -> replace with explicit params
    if (has(line, /^[ \t]*fit_to_screen[ \t]*\([ \t]*root[ \t]*\)[ \t]*$/)) {
      print ind "fit_to_screen(root, reserve_w=" rw ", reserve_h=" rh ", min_w=" mw ", min_h=" mh ")"
      next
    }

    # Otherwise, update existing numeric params if they exist
    gsub(/reserve_w=[0-9]+/, "reserve_w=" rw, line)
    gsub(/reserve_h=[0-9]+/, "reserve_h=" rh, line)
    gsub(/min_w=[0-9]+/, "min_w=" mw, line)
    gsub(/min_h=[0-9]+/, "min_h=" mh, line)
    print line
    next
  }

  print line
}
' "$TARGET" > "$TMP"

mv -f -- "$TMP" "$TARGET"

echo "OK: tuned fit_to_screen defaults + call"
echo "Backup: $BAK"
echo "Using: reserve_w=$RESERVE_W reserve_h=$RESERVE_H min_w=$MIN_W min_h=$MIN_H"
