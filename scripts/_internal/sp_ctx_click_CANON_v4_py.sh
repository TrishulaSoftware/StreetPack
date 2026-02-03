#!/usr/bin/env bash
set -euo pipefail
TARGET="${1:-streetpack_dock.py}"
[[ -f "$TARGET" ]] || { echo "ERR: target not found: $TARGET" >&2; exit 2; }

STAMP="$(date -u +%Y%m%d_%H%M%S_%3NZ 2>/dev/null || date -u +%Y%m%d_%H%M%SZ)"
BAK="${TARGET}.bak.${STAMP}"
cp -a -- "$TARGET" "$BAK"

python3 - "$TARGET" <<'PY'
from pathlib import Path
import re, sys

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8", errors="replace")

# Remove any existing canon blocks (any version)
s = re.sub(r"(?ms)^# SP_CTX_HANDLERS_CANON_V.*?^# END SP_CTX_HANDLERS_CANON_V.*?$", "", s)

block = r'''# SP_CTX_HANDLERS_CANON_V4  (receipts/outputs: open in text editor; right-click menu; robust path resolve)
import os, shlex, subprocess, shutil
from pathlib import Path

def _sp__debug(msg):
    if os.environ.get("SP_DEBUG", "").strip():
        try: print(msg, flush=True)
        except Exception: pass

def _sp__share_root():
    xdg = os.environ.get("XDG_DATA_HOME")
    base = Path(xdg) if xdg else (Path.home() / ".local/share")
    return base / "streetpack"

def _sp__receipts_root(): return _sp__share_root() / "receipts"
def _sp__outputs_root():  return _sp__share_root() / "outputs"

def _sp__pick_editor_cmd():
    env = os.environ.get("SP_EDITOR", "").strip()
    if env:
        try: return shlex.split(env)
        except Exception: return [env]
    for c in ("gnome-text-editor","gedit","kate","mousepad","xed","code"):
        exe = shutil.which(c)
        if exe:
            if c == "code": return [exe, "--reuse-window"]
            return [exe]
    return None

def _sp__resolve(raw):
    if raw is None: return None
    s = str(raw).strip()
    if not s: return None
    s = s.split("|", 1)[0].strip()
    p = Path(s)

    if p.is_absolute() and p.exists():
        return p

    # direct under outputs/receipts
    for root in (_sp__outputs_root(), _sp__receipts_root()):
        cand = root / s
        if cand.exists():
            return cand

    # receipts/<tool>/<file> and outputs/<tool>/<file>
    rr, orr = _sp__receipts_root(), _sp__outputs_root()
    try:
        for cand in rr.glob("*/" + s):
            if cand.exists(): return cand
    except Exception: pass
    try:
        for cand in orr.glob("*/" + s):
            if cand.exists(): return cand
    except Exception: pass

    # shallow search fallback (limited)
    for root in (orr, rr):
        try:
            i = 0
            for cand in root.rglob(s):
                if cand.exists(): return cand
                i += 1
                if i > 50: break
        except Exception: pass

    cand = Path.cwd() / s
    if cand.exists(): return cand
    return None

def _sp_open_text_editor(pathlike):
    p = pathlike if isinstance(pathlike, Path) else _sp__resolve(pathlike)
    if not p or not p.exists():
        _sp__debug(f"[sp] open_text_editor: missing raw={pathlike!r} resolved={str(p) if p else None}")
        return
    cmd = _sp__pick_editor_cmd()
    if not cmd:
        _sp__debug("[sp] open_text_editor: no editor found; falling back to xdg-open")
        subprocess.Popen(["xdg-open", str(p)])
        return
    silent = (os.environ.get("SP_DEBUG", "").strip() == "")
    out = subprocess.DEVNULL if silent else None
    err = subprocess.DEVNULL if silent else None
    _sp__debug(f"[sp] open_text_editor: cmd={cmd!r} path={str(p)!r}")
    subprocess.Popen(cmd + [str(p)], stdout=out, stderr=err)

def _sp_reveal(pathlike):
    p = pathlike if isinstance(pathlike, Path) else _sp__resolve(pathlike)
    if not p or not p.exists():
        _sp__debug(f"[sp] reveal: missing raw={pathlike!r} resolved={str(p) if p else None}")
        return
    folder = str(p.parent)
    _sp__debug(f"[sp] reveal: folder={folder!r}")
    subprocess.Popen(["xdg-open", folder], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def _sp__sel_raw(widget):
    try:
        sel = widget.curselection()
        if not sel: return None
        return widget.get(sel[0])
    except Exception:
        return None

def _sp_open_from_widget(e, widget):
    raw = _sp__sel_raw(widget)
    _sp__debug(f"[sp] click: raw={raw!r}")
    if raw: _sp_open_text_editor(raw)

def _sp_popup_path_menu(e, widget):
    raw = _sp__sel_raw(widget)
    _sp__debug(f"[sp] menu: raw={raw!r}")
    if not raw: return
    import tkinter as _tk
    m = getattr(widget, "_sp_ctx_menu", None)
    if m is None:
        m = _tk.Menu(widget, tearoff=0)
        widget._sp_ctx_menu = m
    else:
        m.delete(0, "end")
    m.add_command(label="Open in Text Editor", command=lambda r=raw: _sp_open_text_editor(r))
    m.add_command(label="Open Folder",         command=lambda r=raw: _sp_reveal(r))
    m.add_separator()
    m.add_command(label="Copy Path",           command=lambda r=raw: (widget.clipboard_clear(), widget.clipboard_append(str(_sp__resolve(r) or r))))
    try:
        m.tk_popup(e.x_root, e.y_root)
    finally:
        try: m.grab_release()
        except Exception: pass
# END SP_CTX_HANDLERS_CANON_V4
'''

m = re.search(r"(?m)^class[ \t]+App\b", s)
if not m:
    raise SystemExit("ERR: could not find 'class App' to inject before")
s = s[:m.start()] + block + "\n\n" + s[m.start():]
p.write_text(s, encoding="utf-8")
print("OK: CANON_V4 injected")
PY

python3 -m py_compile "$TARGET" && echo "OK: syntax clean"
echo "Backup: $BAK"
