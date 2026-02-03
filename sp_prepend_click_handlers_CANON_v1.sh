#!/usr/bin/env bash
set -euo pipefail
TARGET="${1:-streetpack_dock.py}"
[[ -f "$TARGET" ]] || { echo "ERR: target not found: $TARGET" >&2; exit 2; }

# already installed?
if grep -q "SP_CTX_HANDLERS_CANON_V1" "$TARGET"; then
  echo "OK: handlers already present"
  exit 0
fi

STAMP="$(date -u +%Y%m%d_%H%M%S_%3NZ 2>/dev/null || date -u +%Y%m%d_%H%M%SZ)"
BAK="${TARGET}.bak.${STAMP}"
cp -a -- "$TARGET" "$BAK"

TMP="${TARGET}.tmp.${STAMP}"

HANDLERS="$(cat <<'PY'
# SP_CTX_HANDLERS_CANON_V1  (receipts/outputs: open in text editor; right-click menu)
import os, shutil, subprocess, shlex

def _sp_cmd_exists(name: str) -> bool:
    return shutil.which(name) is not None

def _sp_extract_existing_path(s):
    if s is None:
        return None
    s = str(s).strip()
    if s.startswith("file://"):
        s = s[7:]
    if os.path.exists(s):
        return s
    # try last tokens (handles list entries like: "name — /path/to/file.json")
    for tok in reversed(s.split()):
        t = tok.strip("\"'()[]{}<>,;")
        if os.path.exists(t):
            return t
    return None

def _sp_value_from_widget_event(event, widget):
    # Listbox path
    if hasattr(widget, "nearest") and hasattr(widget, "get"):
        try:
            idx = widget.nearest(event.y)
            try:
                widget.selection_clear(0, "end")
                widget.selection_set(idx)
            except Exception:
                pass
            return widget.get(idx)
        except Exception:
            return None

    # Treeview path
    if hasattr(widget, "identify_row") and hasattr(widget, "item"):
        try:
            row = widget.identify_row(event.y)
            if not row:
                return None
            try:
                widget.selection_set(row)
            except Exception:
                pass
            item = widget.item(row)
            v = item.get("text") or ""
            if not v and item.get("values"):
                v = item.get("values")[0]
            return v
        except Exception:
            return None

    return None

def _sp_path_from_widget_event(event, widget):
    v = _sp_value_from_widget_event(event, widget)
    return _sp_extract_existing_path(v) or v

def _sp_open_text_editor(path):
    if not path:
        return
    path = os.path.abspath(os.path.expanduser(str(path)))
    if not os.path.exists(path):
        return

    editor = os.environ.get("SP_EDITOR") or os.environ.get("EDITOR")
    if editor:
        try:
            subprocess.Popen(shlex.split(editor) + [path])
            return
        except Exception:
            pass

    # Prefer real editors first (avoids Firefox defaulting)
    for exe, extra in (
        ("gnome-text-editor", []),
        ("gedit", []),
        ("code", ["--reuse-window"]),
        ("kate", []),
        ("mousepad", []),
        ("xed", []),
        ("nano", []),   # last-resort terminal editor
    ):
        if _sp_cmd_exists(exe):
            try:
                subprocess.Popen([exe] + extra + [path])
                return
            except Exception:
                pass

    # absolute last resort
    if _sp_cmd_exists("gio"):
        try: subprocess.Popen(["gio", "open", path]); return
        except Exception: pass
    if _sp_cmd_exists("xdg-open"):
        try: subprocess.Popen(["xdg-open", path]); return
        except Exception: pass

def _sp_reveal_path(path):
    if not path:
        return
    path = os.path.abspath(os.path.expanduser(str(path)))
    if not os.path.exists(path):
        return

    if _sp_cmd_exists("nautilus"):
        try:
            subprocess.Popen(["nautilus", "--select", path])
            return
        except Exception:
            pass

    folder = path if os.path.isdir(path) else os.path.dirname(path)
    if _sp_cmd_exists("gio"):
        try: subprocess.Popen(["gio", "open", folder]); return
        except Exception: pass
    if _sp_cmd_exists("xdg-open"):
        try: subprocess.Popen(["xdg-open", folder]); return
        except Exception: pass

def _sp_copy_path(widget, path):
    if not path:
        return
    try:
        widget.clipboard_clear()
        widget.clipboard_append(str(path))
        widget.update_idletasks()
    except Exception:
        pass

def _sp_popup_path_menu(event, widget):
    try:
        import tkinter as _tk
    except Exception:
        return
    p = _sp_path_from_widget_event(event, widget)

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
    m.add_command(label="Copy Path",         command=lambda: _sp_copy_path(widget, p))

    try:
        m.tk_popup(event.x_root, event.y_root)
    finally:
        try: m.grab_release()
        except Exception: pass

def _sp_open_from_widget(event, widget):
    p = _sp_path_from_widget_event(event, widget)
    _sp_open_text_editor(p)
    return "break"
# END SP_CTX_HANDLERS_CANON_V1
PY
)"

# Preserve shebang if present
if head -n1 "$TARGET" | grep -q '^#!'; then
  {
    head -n1 "$TARGET"
    printf "%s\n\n" "$HANDLERS"
    tail -n +2 "$TARGET"
  } > "$TMP"
else
  {
    printf "%s\n\n" "$HANDLERS"
    cat "$TARGET"
  } > "$TMP"
fi

mv -f -- "$TMP" "$TARGET"
echo "OK: prepended handlers. Backup: $BAK"
