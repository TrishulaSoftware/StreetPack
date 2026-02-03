#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-streetpack_dock.py}"

# TUNABLES (override per run)
UI_MIN_W="${UI_MIN_W:-720}"
UI_MIN_H="${UI_MIN_H:-480}"
OUT_TXT_H="${OUT_TXT_H:-10}"   # was 18
NET_TXT_H="${NET_TXT_H:-12}"   # was 24

if [[ ! -f "$TARGET" ]]; then
  echo "ERR: target not found: $TARGET" >&2
  exit 2
fi

STAMP="$(date -u +%Y%m%d_%H%M%S_%3NZ 2>/dev/null || date -u +%Y%m%d_%H%M%SZ)"
BAK="${TARGET}.bak.${STAMP}"
cp -a -- "$TARGET" "$BAK"

TMP="${TARGET}.tmp.${STAMP}"

awk -v minw="$UI_MIN_W" -v minh="$UI_MIN_H" -v oh="$OUT_TXT_H" -v nh="$NET_TXT_H" '
{
  line=$0

  # 1) Remove/relax hardcoded master minimums (e.g., master.minsize(980, 640))
  if (line ~ /master\.minsize\(/) {
    gsub(/master\.minsize\([0-9]+[ \t]*,[ \t]*[0-9]+\)/, "master.minsize(" minw ", " minh ")", line)
  }

  # 2) STOP locking minsize to requested widget size (this is the real cutoff culprit)
  if (line ~ /r\.minsize\(r\.winfo_reqwidth\(\),[ \t]*r\.winfo_reqheight\(\)\)/) {
    gsub(/r\.minsize\(r\.winfo_reqwidth\(\),[ \t]*r\.winfo_reqheight\(\)\)/, "r.minsize(" minw ", " minh ")", line)
  }

  # 3) Lower default Text heights that inflate reqheight
  # output text (txt = tk.Text(root, ..., height=18, ...))
  if (line ~ /tk\.Text\(root,.*height=[0-9]+/) {
    gsub(/height=[0-9]+/, "height=" oh, line)
  }

  # net box (self._net_box = tk.Text(win, height=24, ...))
  if (line ~ /tk\.Text\(win,.*height=[0-9]+/) {
    gsub(/height=[0-9]+/, "height=" nh, line)
  }

  # 4) If fit_to_screen() signature still has big mins, tune those too
  if (line ~ /^def[ \t]+fit_to_screen\(/) {
    gsub(/min_w=[0-9]+/, "min_w=" minw, line)
    gsub(/min_h=[0-9]+/, "min_h=" minh, line)
  }

  print line
}
' "$TARGET" > "$TMP"

mv -f -- "$TMP" "$TARGET"

echo "OK: relaxed UI minimums + removed reqsize lock + reduced Text heights"
echo "Backup: $BAK"
echo "Now: UI_MIN_W=$UI_MIN_W UI_MIN_H=$UI_MIN_H OUT_TXT_H=$OUT_TXT_H NET_TXT_H=$NET_TXT_H"
