#!/usr/bin/env bash
set -euo pipefail
T="${1:-streetpack_dock.py}"
[[ -f "$T" ]] || { echo "ERR: missing $T" >&2; exit 2; }

STAMP="$(date -u +%Y%m%d_%H%M%S_%3NZ 2>/dev/null || date -u +%Y%m%d_%H%M%SZ)"
BAK="${T}.bak.${STAMP}"
cp -a -- "$T" "$BAK"

python3 - "$T" <<'PY'
from pathlib import Path
import re, sys

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")

if "SP_START_CLEAN_TABS_V1" in s:
    print("OK: SP_START_CLEAN_TABS_V1 already present")
    sys.exit(0)

# 1) add helper block near bottom (before __main__)
main_re = re.search(r'(?m)^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:', s)
if not main_re:
    raise SystemExit("ERR: can't find if __name__ == '__main__' block")

helper = r'''
# SP_START_CLEAN_TABS_V1  (ship-default: receipts/outputs lists start empty; files remain on disk)
def _sp_widget_clear(w):
    # Listbox
    try:
        w.delete(0, "end")
        return
    except Exception:
        pass
    # Treeview
    try:
        for iid in w.get_children():
            w.delete(iid)
    except Exception:
        pass

def _sp_start_clean_tabs(app):
    # runs after UI builds; clears any auto-populated items from the list widgets
    for attr in ("_rcpt_list", "_out_list"):
        w = getattr(app, attr, None)
        if w is not None:
            _sp_widget_clear(w)
'''
s = s[:main_re.start()] + helper + "\n" + s[main_re.start():]

# 2) schedule clear right after bindings (prefer after out_list right-click bind)
m = re.search(r'(?m)^(?P<ind>\s*)self\._out_list\.bind\(".*Button-3.*"\s*,.*\)\s*$', s)
if not m:
    # fallback: after rcpt right-click bind
    m = re.search(r'(?m)^(?P<ind>\s*)self\._rcpt_list\.bind\(".*Button-3.*"\s*,.*\)\s*$', s)

if not m:
    raise SystemExit("ERR: can't find list bind() lines for _out_list/_rcpt_list to hook into")

ind = m.group("ind")
inject = f'{ind}# SP_START_CLEAN_TABS_V1: clear receipts/outputs lists on launch (ship-default)\n{ind}self.after(0, lambda: _sp_start_clean_tabs(self))\n'

# insert after the matched line
line_end = s.find("\n", m.end())
if line_end == -1:
    line_end = len(s)
else:
    line_end += 1
s = s[:line_end] + inject + s[line_end:]

p.write_text(s, encoding="utf-8")
print("OK: SP_START_CLEAN_TABS_V1 installed")
PY

echo "OK: patched $T"
echo "Backup: $BAK"
