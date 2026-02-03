#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-streetpack_dock.py}"

if [[ ! -f "$TARGET" ]]; then
  echo "ERR: target not found: $TARGET" >&2
  exit 2
fi

STAMP="$(date -u +%Y%m%d_%H%M%S_%3NZ 2>/dev/null || date -u +%Y%m%d_%H%M%SZ)"
BAK="${TARGET}.bak.${STAMP}"
cp -a -- "$TARGET" "$BAK"

TMP="${TARGET}.tmp.${STAMP}"

awk '
function ltrim(s){ sub(/^[ \t]+/, "", s); return s }
function indent_of(s){ match(s, /^[ \t]*/); return substr(s, RSTART, RLENGTH) }

BEGIN { fixed=0 }

{
  line=$0

  # Match: root = Tk(...) or root = tk.Tk(...) with ANY indentation
  if (!fixed && line ~ /^[ \t]*root[ \t]*=[ \t]*(tk\.)?Tk[ \t]*\(/) {
    ind = indent_of(line)
    print line

    # Look ahead one line to see if fit_to_screen(root...) is immediately next
    if (getline nxt) {
      if (nxt ~ /^[ \t]*fit_to_screen[ \t]*\([ \t]*root/) {
        # Reprint with the SAME indent as root line
        print ind ltrim(nxt)
        fixed=1
        next
      } else {
        # Not present immediately after root line -> keep file as-is
        print nxt
        next
      }
    } else {
      # EOF after root line
      fixed=1
      next
    }
  }

  print line
}
END{
  if (fixed==1) {
    # ok
  }
}
' "$TARGET" > "$TMP"

mv -f -- "$TMP" "$TARGET"

echo "OK: repaired indent after root = Tk(...)"
echo "Backup: $BAK"
