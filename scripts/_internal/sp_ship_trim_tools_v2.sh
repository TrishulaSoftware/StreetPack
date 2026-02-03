#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-streetpack_dock.py}"
[[ -f "$TARGET" ]] || { echo "ERR: target not found: $TARGET" >&2; exit 2; }

STAMP="$(date -u +%Y%m%d_%H%M%S_%3NZ 2>/dev/null || date -u +%Y%m%d_%H%M%SZ)"
BAK="${TARGET}.bak.${STAMP}"
cp -a -- "$TARGET" "$BAK"

python3 - "$TARGET" <<'PY'
import re, sys, pathlib

p = pathlib.Path(sys.argv[1])
src = p.read_text(encoding="utf-8", errors="replace")
txt = src

# 1) Trim tool list (ship-default)
tools = [
  "safedel","diffwatch","dirscope","hashscan","runshield","permcheck","secretsniff",
  "logtail+","netpulse","procwatch","pathdoctor","bulkrename-safe","dedupe-lite","packreceipt"
]
tools_line = 'TOOLS=[' + ",".join(f'"{t}"' for t in tools) + ']'
txt, n_tools = re.subn(
  r'^TOOLS=\[.*\]\s*$',
  '# SP_SHIP_TOOLS_CANON_V1: trimmed tool list for release; stubs can be hidden automatically\n' + tools_line,
  txt,
  flags=re.M
)

# 2) Add stub-detector helper (best-effort) if missing
stub_helper = """# SP_HIDE_STUB_TOOLS_V1_BEGIN
def sp_tool_is_stub(name: str) -> bool:
  \"\"\"Best-effort: hide placeholder tools that still contain 'mvp_stub' in their wrapper script.\"\"\"
  try:
    import os, shutil
    exe = shutil.which(name)
    if not exe:
      cand = os.path.expanduser("~/.local/bin/" + name)
      exe = cand if os.path.isfile(cand) else ""
    if not exe:
      return False
    with open(exe, "rb") as f:
      head = f.read(16384).lower()
    return (b"mvp_stub" in head) or (b"mvp stub" in head)
  except Exception:
    return False
# SP_HIDE_STUB_TOOLS_V1_END
"""
if "SP_HIDE_STUB_TOOLS_V1_BEGIN" not in txt:
  txt, n_stub = re.subn(
    r'^\s*# SP_SYSTEMTOOLS_V1_END\s*$',
    stub_helper + "\n# SP_SYSTEMTOOLS_V1_END",
    txt,
    count=1,
    flags=re.M
  )
else:
  n_stub = 0

# 3) Ensure _tool_values hides stubs unless SP_SHOW_STUBS=1
stub_filter = (
'    # SP_SHIP_HIDE_STUBS_V1_BEGIN\n'
'    try:\n'
'      import os as _sp_os\n'
'      if (_sp_os.environ.get("SP_SHOW_STUBS","").strip() == ""):\n'
'        out = [t for t in out if not sp_tool_is_stub(t)]\n'
'    except Exception:\n'
'      pass\n'
'    # SP_SHIP_HIDE_STUBS_V1_END\n\n'
)

# replace existing block (any indentation)
txt = re.sub(
  r'(?ms)^\s*# SP_SHIP_HIDE_STUBS_V1_BEGIN.*?^\s*# SP_SHIP_HIDE_STUBS_V1_END\s*\n',
  stub_filter,
  txt
)

# if still missing, insert after danger filter
if "SP_SHIP_HIDE_STUBS_V1_BEGIN" not in txt:
  txt, n_ins = re.subn(
    r'(?ms)(\n\s*# hide danger unless enabled.*?\n\s*except Exception:\n\s*  pass\n\n)(\s*# filter)',
    r'\1' + stub_filter + r'\2',
    txt,
    count=1
  )
else:
  n_ins = 1

# 4) Ship-default: do NOT auto-refresh receipts/outputs when building tabs
txt = re.sub(r'\n\s*self\._receipts_refresh\(\)\s*\n', '\n    # (ship-default) list stays empty until Refresh is clicked\n', txt, count=1)
txt = re.sub(r'\n\s*self\._outputs_refresh\(\)\s*\n',  '\n    # (ship-default) list stays empty until Refresh is clicked\n', txt, count=1)
txt = re.sub(r'\n\s*# SP_START_CLEAN_TABS_V1:.*\n\s*self\.after\(0, lambda: _sp_start_clean_tabs\(self\)\)\s*\n', '\n', txt, count=1)

# 5) Receipts/Outputs click + right-click reliability:
#    - store ABSOLUTE paths in listbox
#    - remove references to missing _sp_open_selected
txt = txt.replace("_sp_open_selected(", "_sp_open_from_widget(")
txt = txt.replace('self._rcpt_list.insert("end", f.name)', 'self._rcpt_list.insert("end", str(f))')
txt = txt.replace('self._out_list.insert("end", f.name)',  'self._out_list.insert("end", str(f))')

# 6) Normalize listbox bindings (single click, double click, enter, right-click)
def fix_binds(block_name, var):
  pat = rf'(?ms)(\s*try: self\.{var}\.delete\(0, \'end\'\)\n\s*except Exception: pass\n\n)(\s*self\.{var}\.bind.*?self\.{var}\.bind\("<Button-3>".*?\n)'
  rep = (
    r'\1'
    f'    self.{var}.bind("<ButtonRelease-1>", lambda e: _sp_open_from_widget(e, self.{var}))\n'
    f'    self.{var}.bind("<Double-Button-1>",  lambda e: _sp_open_from_widget(e, self.{var}))\n'
    f'    self.{var}.bind("<Return>",           lambda e: _sp_open_from_widget(e, self.{var}))\n'
    f'    self.{var}.bind("<Button-3>",         lambda e: _sp_popup_path_menu(e, self.{var}))\n'
  )
  return re.sub(pat, rep, txt, count=1)

# apply bind fixes (best-effort; only if patterns match)
txt2, nrb = re.subn(
  r'(?ms)(\s*try: self\._rcpt_list\.delete\(0, \'end\'\)\n\s*except Exception: pass\n\n)(\s*self\._rcpt_list\.bind.*?self\._rcpt_list\.bind\("<Button-3>".*?\n)',
  r'\1'
  '    self._rcpt_list.bind("<ButtonRelease-1>", lambda e: _sp_open_from_widget(e, self._rcpt_list))\n'
  '    self._rcpt_list.bind("<Double-Button-1>",  lambda e: _sp_open_from_widget(e, self._rcpt_list))\n'
  '    self._rcpt_list.bind("<Return>",           lambda e: _sp_open_from_widget(e, self._rcpt_list))\n'
  '    self._rcpt_list.bind("<Button-3>",         lambda e: _sp_popup_path_menu(e, self._rcpt_list))\n',
  txt,
  count=1
)
txt3, nob = re.subn(
  r'(?ms)(\s*try: self\._out_list\.delete\(0, \'end\'\)\n\s*except Exception: pass\n\n)(\s*self\._out_list\.bind.*?self\._out_list\.bind\("<Button-3>".*?\n)',
  r'\1'
  '    self._out_list.bind("<ButtonRelease-1>", lambda e: _sp_open_from_widget(e, self._out_list))\n'
  '    self._out_list.bind("<Double-Button-1>",   lambda e: _sp_open_from_widget(e, self._out_list))\n'
  '    self._out_list.bind("<Return>",            lambda e: _sp_open_from_widget(e, self._out_list))\n'
  '    self._out_list.bind("<Button-3>",          lambda e: _sp_popup_path_menu(e, self._out_list))\n',
  txt2,
  count=1
)
txt = txt3

p.write_text(txt, encoding="utf-8")
print("OK: ship trim + stub-hide + receipts/outputs click fixes installed")
PY

echo "OK: patched $TARGET"
echo "Backup: $BAK"

python3 -m py_compile "$TARGET" >/dev/null && echo "OK: py_compile passed"
