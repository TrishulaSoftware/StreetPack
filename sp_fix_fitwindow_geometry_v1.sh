#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-streetpack_dock.py}"
[[ -f "$TARGET" ]] || { echo "ERR: target not found: $TARGET" >&2; exit 2; }

STAMP="$(date -u +%Y%m%d_%H%M%S_%3NZ 2>/dev/null || date -u +%Y%m%d_%H%M%SZ)"
BAK="${TARGET}.bak.${STAMP}"
cp -a -- "$TARGET" "$BAK"

TMP="${TARGET}.tmp.${STAMP}"

awk '
function indent_of(s){ match(s, /^[ \t]*/); return substr(s, RSTART, RLENGTH) }

BEGIN { in_fit=0; inserted_guard=0 }

{
  line=$0

  # 1) Fix the after() callback: _sp_fit_window(self) -> _sp_fit_window(self.winfo_toplevel())
  if (line ~ /\.after\(/ && line ~ /_sp_fit_window\(self\)/) {
    gsub(/_sp_fit_window\(self\)/, "_sp_fit_window(self.winfo_toplevel())", line)
  }

  # 2) Make _sp_fit_window robust even if someone calls it with a widget
  if (!in_fit && line ~ /^[ \t]*def[ \t]+_sp_fit_window[ \t]*\(/) {
    in_fit=1
    inserted_guard=0
    print line

    # Peek next line to learn indentation (and avoid double-inserting)
    if (getline nxt) {
      ind = indent_of(nxt)
      if (nxt !~ /winfo_toplevel\(\)/) {
        print ind "win = win.winfo_toplevel() if hasattr(win, \"winfo_toplevel\") else win"
        inserted_guard=1
      }
      print nxt
      next
    }
    next
  }

  # Exit function block when indentation returns to 0 and it’s not a continuation
  if (in_fit) {
    if (line ~ /^def[ \t]+/ || line ~ /^[^ \t]/) {
      in_fit=0
    }
  }

  print line
}
' "$TARGET" > "$TMP"

mv -f -- "$TMP" "$TARGET"

echo "OK: fixed _sp_fit_window to use toplevel"
echo "Backup: $BAK"
