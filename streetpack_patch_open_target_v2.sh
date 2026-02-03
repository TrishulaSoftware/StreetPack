#!/usr/bin/env bash
set -euo pipefail

DOCK="$HOME/Trishula-Infra_Linux/StreetPack/streetpack_dock.py"
STAMP="$(date -u +%Y%m%d_%H%M%S_Z)"

[ -f "$DOCK" ] || { echo "[ERR] missing: $DOCK"; exit 1; }

cp -a "$DOCK" "$DOCK.bak.$STAMP"
echo "[ok] backup: $DOCK.bak.$STAMP"

python3 - <<'PY'
import os, re, sys
from pathlib import Path

dock = Path(os.path.expanduser("~/Trishula-Infra_Linux/StreetPack/streetpack_dock.py"))
txt  = dock.read_text(encoding="utf-8", errors="replace")

def ensure_import(name: str):
    global txt
    if re.search(rf'^\s*import\s+{re.escape(name)}\b', txt, flags=re.M):
        return
    m = re.search(r'^(import .+|from .+ import .+)\s*$', txt, flags=re.M)
    if m:
        ins = m.end()
        txt = txt[:ins] + f"\nimport {name}\n" + txt[ins:]
    else:
        txt = f"import {name}\n" + txt

ensure_import("subprocess")
ensure_import("os")

# ----------------- helper: open target -----------------
MARK = "SP_OPEN_TARGET_V2_BEGIN"
if MARK not in txt:
    helper = r'''
# SP_OPEN_TARGET_V2_BEGIN
def sp_open_path(path: str) -> None:
    if not path:
        return
    p = os.path.expanduser(path)
    try:
        if os.path.isfile(p):
            p = os.path.dirname(p) or p
        elif os.path.isdir(p):
            pass
        else:
            parent = os.path.dirname(p)
            p = parent if parent and os.path.isdir(parent) else ""
    except Exception:
        p = ""
    if not p:
        return
    try:
        subprocess.Popen(["xdg-open", p])
    except Exception:
        pass

def sp_open_target_from_root(root) -> None:
    try:
        ent = getattr(root, "_sp_entry_target", None)
        p = ent.get().strip() if ent is not None else ""
    except Exception:
        p = ""
    sp_open_path(p)
# SP_OPEN_TARGET_V2_END
'''
    # insert near other SP blocks if possible, else before main
    m = re.search(r'^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', txt, flags=re.M)
    ins = m.start() if m else len(txt)
    txt = txt[:ins] + helper + "\n" + txt[ins:]

lines = txt.splitlines(True)

def find_entry_var(prefer_word: str):
    # finds var = tk.Entry(...) or ttk.Entry(...)
    for i, line in enumerate(lines):
        m = re.match(r'^\s*([A-Za-z_]\w*)\s*=\s*(?:ttk\.)?Entry\s*\(', line)
        if m:
            var = m.group(1)
            if prefer_word.lower() in var.lower():
                return var, i
    # fallback: any Entry
    for i, line in enumerate(lines):
        m = re.match(r'^\s*([A-Za-z_]\w*)\s*=\s*(?:ttk\.)?Entry\s*\(', line)
        if m:
            return m.group(1), i
    return None, None

def after_multiline_call(start_i: int) -> int:
    # returns index of last line of a multiline (...) statement starting at start_i
    cnt = lines[start_i].count("(") - lines[start_i].count(")")
    j = start_i
    while cnt > 0 and j + 1 < len(lines):
        j += 1
        cnt += lines[j].count("(") - lines[j].count(")")
    return j

# Bind root._sp_entry_target to the "target" Entry if possible
target_var, target_i = find_entry_var("target")
if target_var and target_i is not None:
    end_i = after_multiline_call(target_i)
    window = "".join(lines[target_i:end_i+5])
    if "_sp_entry_target" not in window:
        indent = re.match(r'^(\s*)', lines[target_i]).group(1)
        lines.insert(end_i+1, f"{indent}root._sp_entry_target = {target_var}\n")
        print("[ok] wired root._sp_entry_target ->", target_var)
else:
    print("[warn] could not locate Target Entry var; Open Target may not bind")

# ----------------- optional: context menus (only if none exists) -----------------
have_any_menu = ("SP_CONTEXT_MENU_V1_BEGIN" in "".join(lines)) or ("SP_CONTEXT_MENU_V2_BEGIN" in "".join(lines))
if not have_any_menu:
    menu_block = r'''
# SP_CONTEXT_MENU_V2_BEGIN
def sp_attach_context_menus(root, entry_target=None, entry_args=None, entry_out=None, text_output=None):
    def _clip_set(s: str):
        try:
            root.clipboard_clear()
            root.clipboard_append(s)
            root.update()
        except Exception:
            pass

    def _entry_menu(w, is_target=False):
        menu = tk.Menu(root, tearoff=0)
        menu.add_command(label="Cut",  command=lambda: w.event_generate("<<Cut>>"))
        menu.add_command(label="Copy", command=lambda: w.event_generate("<<Copy>>"))
        menu.add_command(label="Paste",command=lambda: w.event_generate("<<Paste>>"))
        menu.add_separator()
        menu.add_command(label="Select All", command=lambda: (w.select_range(0, "end"), w.icursor("end")))
        menu.add_command(label="Clear", command=lambda: (w.delete(0, "end")))
        if is_target:
            menu.add_separator()
            menu.add_command(label="Copy Target Path", command=lambda: _clip_set(w.get().strip()))
            menu.add_command(label="Open Target", command=lambda: sp_open_target_from_root(root))
        return menu

    def _text_menu(w):
        menu = tk.Menu(root, tearoff=0)
        menu.add_command(label="Cut",  command=lambda: w.event_generate("<<Cut>>"))
        menu.add_command(label="Copy", command=lambda: w.event_generate("<<Copy>>"))
        menu.add_command(label="Paste",command=lambda: w.event_generate("<<Paste>>"))
        menu.add_separator()
        menu.add_command(label="Select All", command=lambda: (w.tag_add("sel", "1.0", "end-1c")))
        menu.add_command(label="Clear", command=lambda: (w.delete("1.0", "end")))
        return menu

    def _bind_menu(w, menu_factory, is_target=False):
        if w is None:
            return
        menu = menu_factory(w) if not is_target else menu_factory(w, True)
        def popup(e):
            try:
                menu.tk_popup(e.x_root, e.y_root)
            finally:
                try: menu.grab_release()
                except Exception: pass
        try:
            w.bind("<Button-3>", popup)
            w.bind("<Control-Button-1>", popup)
        except Exception:
            pass

    _bind_menu(entry_target, _entry_menu, is_target=True)
    _bind_menu(entry_args,   _entry_menu)
    _bind_menu(entry_out,    _entry_menu)
    _bind_menu(text_output,  _text_menu)
# SP_CONTEXT_MENU_V2_END
'''
    # insert before main
    whole = "".join(lines)
    m = re.search(r'^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', whole, flags=re.M)
    ins = m.start() if m else len(whole)
    whole = whole[:ins] + menu_block + "\n" + whole[ins:]
    lines = whole.splitlines(True)
    print("[ok] installed context menus (v2)")
else:
    print("[ok] existing context menu block found; leaving it alone (no double menus)")

# ----------------- Open Target button UNDER Browse -----------------
whole = "".join(lines)

# find Browse button var (tk.Button or ttk.Button)
mb = re.search(r'^\s*([A-Za-z_]\w*)\s*=\s*(?:ttk\.)?Button\s*\(.*?text\s*=\s*[\'"]Browse[\'"].*?\)\s*$',
               whole, flags=re.M|re.S)
browse_var = mb.group(1) if mb else None

if browse_var:
    # find its .grid(...) line
    gi = None
    grid_pat = re.compile(r'^\s*' + re.escape(browse_var) + r'\.grid\s*\(', flags=re.M)
    mgrid = grid_pat.search(whole)
    if mgrid:
        # insert right after the .grid(...) statement block
        lns = whole.splitlines(True)
        # map char index -> line index
        char = mgrid.start()
        acc = 0
        grid_i = 0
        for idx, line in enumerate(lns):
            if acc + len(line) > char:
                grid_i = idx
                break
            acc += len(line)

        # find end of multiline grid call
        cnt = lns[grid_i].count("(") - lns[grid_i].count(")")
        j = grid_i
        while cnt > 0 and j + 1 < len(lns):
            j += 1
            cnt += lns[j].count("(") - lns[j].count(")")

        # avoid reinject
        window = "".join(lns[grid_i:j+30])
        if "SP_OPEN_TARGET_BTN_UNDER_BROWSE_V2_BEGIN" not in window:
            indent = re.match(r'^(\s*)', lns[grid_i]).group(1)
            wire = f'''
{indent}# SP_OPEN_TARGET_BTN_UNDER_BROWSE_V2_BEGIN
{indent}try:
{indent}    btn_open_target = tk.Button(root, text="Open Target", command=lambda: sp_open_target_from_root(root))
{indent}    _gi = {browse_var}.grid_info()
{indent}    _row = int(_gi.get("row") or 0)
{indent}    _col = int(_gi.get("column") or 0)
{indent}    btn_open_target.grid(
{indent}        row=_row+1,
{indent}        column=_col,
{indent}        padx=_gi.get("padx", 6),
{indent}        pady=_gi.get("pady", 6),
{indent}        sticky=_gi.get("sticky", "w"),
{indent}    )
{indent}except Exception:
{indent}    pass
{indent}# SP_OPEN_TARGET_BTN_UNDER_BROWSE_V2_END
'''
            lns.insert(j+1, wire)
            whole = "".join(lns)
            print("[ok] injected Open Target button under Browse")
        else:
            print("[ok] Open Target-under-Browse already present; no-op")
    else:
        print("[warn] found Browse button var but no .grid() call; skipping button injection")
else:
    print("[warn] could not find Browse button creation; skipping button injection")

dock.write_text(whole, encoding="utf-8")
print("[ok] wrote:", dock)
PY

echo "[next] relaunch:"
echo "  export PATH=\"$HOME/.local/bin:\$PATH\""
echo "  streetpack"
