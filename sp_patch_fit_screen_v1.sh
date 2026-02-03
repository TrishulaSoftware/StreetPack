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

# If already patched, exit clean.
if grep -q "def fit_to_screen(root" "$TARGET"; then
  echo "OK: fit_to_screen() already present. Backup at: $BAK"
  exit 0
fi

TMP="${TARGET}.tmp.${STAMP}"

awk '
BEGIN{
  inserted_func=0;
  inserted_call=0;
  saw_nonimport=0;
}
function emit_func(){
  print "";
  print "def fit_to_screen(root, reserve_w=80, reserve_h=120, min_w=980, min_h=640):";
  print "    root.update_idletasks()";
  print "    sw = root.winfo_screenwidth()";
  print "    sh = root.winfo_screenheight()";
  print "";
  print "    w = max(sw - reserve_w, min_w)";
  print "    h = max(sh - reserve_h, min_h)";
  print "";
  print "    x = max((sw - w) // 2, 0)";
  print "    y = max((sh - h) // 2, 0)";
  print "";
  print "    root.geometry(f\"{w}x{h}+{x}+{y}\")";
  print "";
  print "    # Some Linux WMs benefit from a zoom attempt (works on most WMs)";
  print "    try:";
  print "        root.wm_attributes(\"-zoomed\", True)";
  print "    except Exception:";
  print "        pass";
  print "";
  print "    root.update_idletasks()";
  print "";
}

{
  line=$0;

  # Detect end of import block: after we hit first non-import/non-blank/non-comment
  if (!saw_nonimport) {
    if (line ~ /^[[:space:]]*(import[[:space:]]|from[[:space:]].*[[:space:]]import[[:space:]])/ ||
        line ~ /^[[:space:]]*$/ ||
        line ~ /^[[:space:]]*#/ ) {
      print line;
      next;
    } else {
      # First real code line after imports -> insert function before it (once)
      if (!inserted_func) {
        emit_func();
        inserted_func=1;
      }
      saw_nonimport=1;
      print line;
      next;
    }
  }

  print line;

  # Insert call right after root = Tk(...) line (handles tk.Tk() or Tk())
  if (!inserted_call && line ~ /^[[:space:]]*root[[:space:]]*=[[:space:]]*(tk\.)?Tk[[:space:]]*\(/) {
    print "fit_to_screen(root)";
    inserted_call=1;
  }
}
END{
  if (!inserted_func) {
    # File had only imports/comments (unlikely) -> append function anyway
    emit_func();
  }
}
' "$TARGET" > "$TMP"

mv -f -- "$TMP" "$TARGET"

echo "OK: patched $TARGET"
echo "Backup: $BAK"
