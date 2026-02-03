#!/usr/bin/env bash
set -euo pipefail

DOCK="$HOME/Trishula-Infra_Linux/StreetPack/streetpack_dock.py"
BIN="$HOME/.local/bin"
STAMP="$(date -u +%Y%m%d_%H%M%S_Z)"

[ -f "$DOCK" ] || { echo "[ERR] missing: $DOCK"; exit 1; }

cp -a "$DOCK" "$DOCK.bak.$STAMP"
echo "[ok] backup: $DOCK.bak.$STAMP"

python3 - <<'PY'
import os, re, sys
from pathlib import Path

dock = Path(os.path.expanduser("~/Trishula-Infra_Linux/StreetPack/streetpack_dock.py"))
txt = dock.read_text(encoding="utf-8", errors="replace")

MARKER = "SP_OPEN_TARGET_BTN_V1_BEGIN"
if MARKER in txt:
    print("[ok] Open Target patch already present; no-op")
    sys.exit(0)

# Ensure subprocess import exists (used for xdg-open)
if re.search(r'^\s*import\s+subprocess\b', txt, flags=re.M) is None:
    m = re.search(r'^\s*import\s+.*$', txt, flags=re.M)
    if m:
        ins = m.end()
        txt = txt[:ins] + "\nimport subprocess\n" + txt[ins:]
    else:
        txt = "import subprocess\n" + txt

helper = r'''
# SP_OPEN_TARGET_BTN_V1_BEGIN
def sp_open_target_from_root(root):
    """
    Opens the current Target (dir if dir, parent if file, parent-if-missing) in the file manager.
    Safe no-op if Target is blank or unusable.
    """
    try:
        ent = getattr(root, "_sp_entry_target", None)
        p = (ent.get().strip() if ent is not None else "")
    except Exception:
        p = ""

    if not p:
        return

    p = os.path.expanduser(p)
    open_p = p

    try:
        if os.path.isfile(p):
            open_p = os.path.dirname(p) or p
        elif os.path.isdir(p):
            open_p = p
        else:
            parent = os.path.dirname(p)
            open_p = parent if parent and os.path.isdir(parent) else ""
    except Exception:
        open_p = ""

    if not open_p:
        return

    try:
        subprocess.Popen(["xdg-open", open_p])
    except Exception:
        pass
# SP_OPEN_TARGET_BTN_V1_END
'''

# Insert helper near other SP blocks if possible
insert_pos = None
for pat in (r'#\s*SP_CONTEXT_MENU_V1_END\s*\n', r'#\s*SP_COLD_BOOT_END\s*\n'):
    m = re.search(pat, txt)
    if m:
        insert_pos = m.end()
        break
if insert_pos is None:
    m = re.search(r'^\s*if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:\s*$', txt, flags=re.M)
    insert_pos = m.start() if m else len(txt)

txt = txt[:insert_pos] + helper + "\n" + txt[insert_pos:]

lines = txt.splitlines(True)

def insert_after_target_entry(lines):
    # Find the Target Entry widget (expects variable name entry_target)
    for i, line in enumerate(lines):
        if "entry_target" in line and "tk.Entry" in line and "=" in line:
            # insert after the call (handle multi-line)
            indent = re.match(r'^(\s*)', line).group(1)
            cnt = line.count("(") - line.count(")")
            j = i
            while cnt > 0 and j + 1 < len(lines):
                j += 1
                cnt += lines[j].count("(") - lines[j].count(")")
            # avoid duplicate
            window = "".join(lines[i:j+4])
            if "_sp_entry_target" not in window:
                lines.insert(j+1, f"{indent}root._sp_entry_target = entry_target\n")
                print("[ok] wired root._sp_entry_target")
            return True
    print("[warn] could not locate entry_target = tk.Entry(...); Open Target may not bind")
    return False

def insert_open_target_button(lines):
    # Find Browse button variable and grid call
    m = None
    btn = None
    for i, line in enumerate(lines):
        if "tk.Button" in line and ("text=\"Browse\"" in line or "text='Browse'" in line):
            m = re.match(r'^\s*(\w+)\s*=\s*tk\.Button', line)
            if m:
                btn = m.group(1)
            else:
                btn = "btn_browse"
            break

    if btn is None:
        print("[warn] could not locate Browse button; skipping Open Target button injection")
        return False

    # locate its grid call
    grid_i = None
    for i, line in enumerate(lines):
        if re.search(r'^\s*' + re.escape(btn) + r'\.grid\s*\(', line):
            grid_i = i
            break

    if grid_i is None:
        print("[warn] could not locate Browse .grid(...); skipping Open Target button injection")
        return False

    indent = re.match(r'^(\s*)', lines[grid_i]).group(1)

    wire = f'''
{indent}# SP_OPEN_TARGET_BTN_WIRE_V1_BEGIN
{indent}try:
{indent}    btn_open_target = tk.Button(root, text="Open Target", command=lambda: sp_open_target_from_root(root))
{indent}    _gi = {btn}.grid_info()
{indent}    _row = int(_gi.get("row") or 0)
{indent}    _col = int(_gi.get("column") or 0) + 1
{indent}    btn_open_target.grid(
{indent}        row=_row,
{indent}        column=_col,
{indent}        padx=_gi.get("padx", 6),
{indent}        pady=_gi.get("pady", 6),
{indent}        sticky=_gi.get("sticky", "w"),
{indent}    )
{indent}except Exception:
{indent}    pass
{indent}# SP_OPEN_TARGET_BTN_WIRE_V1_END
'''
    # avoid duplicate
    if "SP_OPEN_TARGET_BTN_WIRE_V1_BEGIN" in "".join(lines[max(0, grid_i-5):grid_i+30]):
        print("[ok] Open Target button wire already present; no-op")
        return True

    lines.insert(grid_i+1, wire)
    print("[ok] injected Open Target button next to Browse")
    return True

ok1 = insert_after_target_entry(lines)
ok2 = insert_open_target_button(lines)

new_txt = "".join(lines)
Path(dock).write_text(new_txt, encoding="utf-8")
print("[ok] patched:", dock)
PY

mkdir -p "$BIN"

# Ensure streetpack launcher exists
if [ ! -f "$BIN/streetpack" ]; then
  cat > "$BIN/streetpack" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
python3 "$HOME/Trishula-Infra_Linux/StreetPack/streetpack_dock.py" >/tmp/streetpack_dock.out 2>&1 & disown
echo "StreetPack Dock log: /tmp/streetpack_dock.out"
EOF
  chmod 755 "$BIN/streetpack"
  echo "[ok] installed: $BIN/streetpack"
else
  echo "[ok] launcher already present: $BIN/streetpack"
fi

echo
echo "[next] launch UI:"
echo "  export PATH=\"$HOME/.local/bin:\$PATH\""
echo "  streetpack"
