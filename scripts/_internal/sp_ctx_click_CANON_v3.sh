#!/usr/bin/env bash
set -euo pipefail
TARGET="${1:-streetpack_dock.py}"
[[ -f "$TARGET" ]] || { echo "ERR: target not found: $TARGET" >&2; exit 2; }

STAMP="$(date -u +%Y%m%d_%H%M%S_%3NZ 2>/dev/null || date -u +%Y%m%d_%H%M%SZ)"
BAK="${TARGET}.bak.${STAMP}"
cp -a -- "$TARGET" "$BAK"

TMP="${TARGET}.tmp.${STAMP}"

# 1) Remove any prior SP_CTX_HANDLERS_CANON blocks (any version), then prepend V3.
awk '
BEGIN{skip=0}
# drop older canon blocks
/^# SP_CTX_HANDLERS_CANON_V/ { skip=1; next }
skip==1 && /^# END SP_CTX_HANDLERS_CANON_V/ { skip=0; next }
skip==1 { next }
{ print }
' "$TARGET" > "$TMP.base"

HANDLERS="$(cat <<'PY'
# SP_CTX_HANDLERS_CANON_V3  (receipts/outputs: open in text editor; right-click menu; prints debug)
import os, shutil, subprocess, shlex, sys, re

def _sp_dbg(msg):
    try: print(msg, file=sys.stderr, flush=True)
    except Exception: pass

def _sp_cmd_exists(name: str) -> bool:
    return shutil.which(name) is not None

def _sp_extract_path_from_text(s):
    if s is None: return None
    raw = str(s).strip()
    if raw.startswith("file://"): raw = raw[7:]
    raw = os.path.expanduser(raw)

    if os.path.exists(raw): return raw

    # Take substring after common separators (label — /path)
    for sep in (" — ", " - ", " | ", " -> ", " : "):
        if sep in raw:
            cand = os.path.expanduser(raw.split(sep)[-1].strip())
            if os.path.exists(cand): return cand

    # Regex find a pathish chunk
    m = re.search(r"(~/?[^\s]+|/[^\s]+)", raw)
    if m:
        cand = os.path.expanduser(m.group(1)).strip("\"'()[]{}<>,;")
        if os.path.exists(cand): return cand

    # Fallback: last tokens
    for tok in reversed(raw.split()):
        t = tok.strip("\"'()[]{}<>,;")
        if os.path.exists(t): return t

    return None

def _sp_get_selected_text(widget):
    # Listbox
    if hasattr(widget, "curselection") and hasattr(widget, "get"):
        sel = widget.curselection()
        if not sel: return None
        return widget.get(sel[0])

    # Treeview
    if hasattr(widget, "selection") and hasattr(widget, "item"):
        sel = widget.selection()
        if not sel: return None
        item = widget.item(sel[0])
        v = item.get("text") or ""
        if not v and item.get("values"): v = item.get("values")[0]
        return v

    return None

def _sp_select_at_event(widget, event):
    # Listbox
    if hasattr(widget, "nearest") and hasattr(widget, "selection_clear") and hasattr(widget, "selection_set"):
        try:
            idx = widget.nearest(event.y)
            widget.selection_clear(0, "end")
            widget.selection_set(idx)
            return
        except Exception:
            return

    # Treeview
    if hasattr(widget, "identify_row") and hasattr(widget, "selection_set"):
        try:
            row = widget.identify_row(event.y)
            if row:
                widget.selection_set(row)
        except Exception:
            pass

def _sp_open_text_editor(path):
    if not path:
        _sp_dbg("[sp] open_text_editor: no path")
        return

    path = os.path.abspath(os.path.expanduser(str(path)))
    if not os.path.exists(path):
        _sp_dbg(f"[sp] open_text_editor: path missing: {path}")
        return

    editor = os.environ.get("SP_EDITOR") or os.environ.get("EDITOR")
    _sp_dbg(f"[sp] open_text_editor: editor={editor!r} path={path!r}")

    # Explicit editor first (never Firefox)
    if editor:
        try:
            subprocess.Popen(shlex.split(editor) + [path])
            return
        except Exception as ex:
            _sp_dbg(f"[sp] editor failed: {ex!r}")

    # GNOME Text Editor via app id (works on many Ubuntu installs)
    if _sp_cmd_exists("gio"):
        for appid in ("org.gnome.TextEditor", "org.gnome.gedit"):
            try:
                subprocess.Popen(["gio", "launch", appid, path])
                return
            except Exception:
                pass

    if _sp_cmd_exists("gtk-launch"):
        for appid in ("org.gnome.TextEditor", "org.gnome.gedit"):
            try:
                subprocess.Popen(["gtk-launch", appid, path])
                return
            except Exception:
                pass

    for exe, extra in (
        ("gnome-text-editor", []),
        ("gedit", []),
        ("code", ["--reuse-window"]),
        ("kate", []),
        ("mousepad", []),
        ("xed", []),
    ):
        if _sp_cmd_exists(exe):
            try:
                subprocess.Popen([exe] + extra + [path])
                return
            except Exception as ex:
                _sp_dbg(f"[sp] launch {exe} failed: {ex!r}")
                return

    _sp_dbg("[sp] No editor found. Set SP_EDITOR, e.g. export SP_EDITOR='gedit'")

def _sp_reveal_path(path):
    if not path:
        _sp_dbg("[sp] reveal: no path")
        return
    path = os.path.abspath(os.path.expanduser(str(path)))
    if not os.path.exists(path):
        _sp_dbg(f"[sp] reveal: path missing: {path}")
        return
    folder = path if os.path.isdir(path) else os.path.dirname(path)
    _sp_dbg(f"[sp] reveal: folder={folder!r}")

    if _sp_cmd_exists("nautilus"):
        try:
            subprocess.Popen(["nautilus", "--select", path])
            return
        except Exception:
            pass
    if _sp_cmd_exists("xdg-open"):
        subprocess.Popen(["xdg-open", folder])
        return
    if _sp_cmd_exists("gio"):
        subprocess.Popen(["gio", "open", folder])
        return

def _sp_open_selected(widget):
    txt = _sp_get_selected_text(widget)
    _sp_dbg(f"[sp] open_selected: raw={txt!r}")
    p = _sp_extract_path_from_text(txt) or txt
    p = _sp_extract_path_from_text(p) or p
    _sp_dbg(f"[sp] open_selected: resolved={p!r}")
    _sp_open_text_editor(p)
    return "break"

def _sp_popup_path_menu(event, widget):
    try:
        import tkinter as _tk
    except Exception:
        return
    _sp_select_at_event(widget, event)
    txt = _sp_get_selected_text(widget)
    p = _sp_extract_path_from_text(txt) or txt
    _sp_dbg(f"[sp] menu: raw={txt!r} resolved={p!r}")

    m = getattr(widget, "_sp_ctx_menu", None)
    if m is None:
        m = _tk.Menu(widget, tearoff=0)
        widget._sp_ctx_menu = m
    else:
        try: m.delete(0, "end")
        except Exception: pass

    m.add_command(label="Open in Text Editor", command=lambda: _sp_open_text_editor(p))
    m.add_command(label="Reveal in Folder",  command=lambda: _sp_reveal_path(p))
    m.add_separator()
    m.add_command(label="Copy Path",         command=lambda: (widget.clipboard_clear(), widget.clipboard_append(str(p))))
    try:
        m.tk_popup(event.x_root, event.y_root)
    finally:
        try: m.grab_release()
        except Exception: pass

def _sp_open_from_widget(event, widget):
    _sp_select_at_event(widget, event)
    return _sp_open_selected(widget)
# END SP_CTX_HANDLERS_CANON_V3
PY
)"

# Prepend preserving shebang if present
if head -n1 "$TMP.base" | grep -q '^#!'; then
  {
    head -n1 "$TMP.base"
    printf "%s\n\n" "$HANDLERS"
    tail -n +2 "$TMP.base"
  } > "$TMP"
else
  {
    printf "%s\n\n" "$HANDLERS"
    cat "$TMP.base"
  } > "$TMP"
fi
rm -f "$TMP.base"

# 2) Fix binds: use Double-Click + Enter for open, Button-3 for menu
awk '
{
  line=$0

  # receipts list
  if (line ~ /_rcpt_list\.bind\("<ButtonRelease-1>"/) {
    gsub(/<ButtonRelease-1>/, "<Double-Button-1>", line)
    print line
    print "    self._rcpt_list.bind(\"<Return>\",            lambda e: _sp_open_selected(self._rcpt_list))"
    next
  }
  # outputs list
  if (line ~ /_out_list\.bind\("<ButtonRelease-1>"/) {
    gsub(/<ButtonRelease-1>/, "<Double-Button-1>", line)
    print line
    print "    self._out_list.bind(\"<Return>\",             lambda e: _sp_open_selected(self._out_list))"
    next
  }

  print line
}
' "$TMP" > "$TARGET"
rm -f "$TMP"

echo "OK: CANON_V3 installed"
echo "Backup: $BAK"
