#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-streetpack_dock.py}"
[[ -f "$TARGET" ]] || { echo "ERR: target not found: $TARGET" >&2; exit 2; }

STAMP="$(date -u +%Y%m%d_%H%M%S_%3NZ 2>/dev/null || date -u +%Y%m%d_%H%M%SZ)"
BAK="${TARGET}.bak.${STAMP}"
cp -a -- "$TARGET" "$BAK"

# If already installed, exit
if grep -q "StreetPack Missing Click Handlers v5" "$TARGET"; then
  echo "OK: v5 already present. Backup: $BAK"
  exit 0
fi

TMP="${TARGET}.tmp.${STAMP}"

awk '
function emit_block(){
  print ""
  print "# --- StreetPack Missing Click Handlers v5 (defines names used by list binds) ---"
  print "import os, shutil, subprocess, shlex"
  print ""
  print "def _sp_cmd_exists(name):"
  print "    return shutil.which(name) is not None"
  print ""
  print "def _sp_extract_existing_path(s):"
  print "    if s is None: return None"
  print "    s = str(s).strip()"
  print "    if s.startswith(\"file://\"): s = s[7:]"
  print "    if os.path.exists(s): return s"
  print "    for tok in reversed(s.split()):"
  print "        t = tok.strip(\"\\\"'()[]{}<>,;\")"
  print "        if os.path.exists(t): return t"
  print "    return None"
  print ""
  print "def _sp_selected_path(widget):"
  print "    try:"
  print "        if hasattr(widget, \"curselection\"):"
  print "            sel = widget.curselection()"
  print "            if not sel: return None"
  print "            v = widget.get(sel[0])"
  print "            return _sp_extract_existing_path(v) or v"
  print "        if hasattr(widget, \"selection\"):"
  print "            sel = widget.selection()"
  print "            if not sel: return None"
  print "            item = widget.item(sel[0])"
  print "            v = item.get(\"text\") or \"\""
  print "            if not v and item.get(\"values\"): v = item.get(\"values\")[0]"
  print "            return _sp_extract_existing_path(v) or v"
  print "    except Exception:"
  print "        return None"
  print "    return None"
  print ""
  print "def _sp_open_text_editor(path):"
  print "    if not path: return"
  print "    path = os.path.abspath(os.path.expanduser(str(path)))"
  print "    if not os.path.exists(path): return"
  print "    editor = os.environ.get(\"SP_EDITOR\") or os.environ.get(\"EDITOR\")"
  print "    if editor:"
  print "        try:"
  print "            subprocess.Popen(shlex.split(editor) + [path])"
  print "            return"
  print "        except Exception:"
  print "            pass"
  print "    for exe, extra in ("
  print "        (\"gnome-text-editor\", []),"
  print "        (\"gedit\", []),"
  print "        (\"code\", [\"--reuse-window\"]),"
  print "        (\"kate\", []),"
  print "        (\"mousepad\", []),"
  print "        (\"xed\", []),"
  print "    ):"
  print "        if _sp_cmd_exists(exe):"
  print "            try:"
  print "                subprocess.Popen([exe] + extra + [path])"
  print "                return"
  print "            except Exception:"
  print "                pass"
  print "    # last resort"
  print "    if _sp_cmd_exists(\"gio\"):"
  print "        try: subprocess.Popen([\"gio\", \"open\", path]); return"
  print "        except Exception: pass"
  print "    if _sp_cmd_exists(\"xdg-open\"):"
  print "        try: subprocess.Popen([\"xdg-open\", path]); return"
  print "        except Exception: pass"
  print ""
  print "def _sp_reveal_path(path):"
  print "    if not path: return"
  print "    path = os.path.abspath(os.path.expanduser(str(path)))"
  print "    if not os.path.exists(path): return"
  print "    if _sp_cmd_exists(\"nautilus\"):"
  print "        try: subprocess.Popen([\"nautilus\", \"--select\", path]); return"
  print "        except Exception: pass"
  print "    folder = path if os.path.isdir(path) else os.path.dirname(path)"
  print "    if _sp_cmd_exists(\"gio\"):"
  print "        try: subprocess.Popen([\"gio\", \"open\", folder]); return"
  print "        except Exception: pass"
  print "    if _sp_cmd_exists(\"xdg-open\"):"
  print "        try: subprocess.Popen([\"xdg-open\", folder]); return"
  print "        except Exception: pass"
  print ""
  print "def _sp_copy_path(widget, path):"
  print "    if not path: return"
  print "    try:"
  print "        widget.clipboard_clear()"
  print "        widget.clipboard_append(str(path))"
  print "        widget.update_idletasks()"
  print "    except Exception:"
  print "        pass"
  print ""
  print "def _sp_popup_path_menu(event, widget):"
  print "    try:"
  print "        import tkinter as _tk"
  print "    except Exception:"
  print "        return"
  print "    p = _sp_selected_path(widget)"
  print "    m = getattr(widget, \"_sp_ctx_menu\", None)"
  print "    if m is None:"
  print "        m = _tk.Menu(widget, tearoff=0)"
  print "        widget._sp_ctx_menu = m"
  print "    else:"
  print "        try: m.delete(0, \"end\")"
  print "        except Exception: pass"
  print "    m.add_command(label=\"Open in Text Editor\", command=lambda: _sp_open_text_editor(p))"
  print "    m.add_command(label=\"Reveal in Folder\",  command=lambda: _sp_reveal_path(p))"
  print "    m.add_separator()"
  print "    m.add_command(label=\"Copy Path\",         command=lambda: _sp_copy_path(widget, p))"
  print "    try:"
  print "        m.tk_popup(event.x_root, event.y_root)"
  print "    finally:"
  print "        try: m.grab_release()"
  print "        except Exception: pass"
  print ""
  print "def _sp_open_from_widget(event, widget):"
  print "    p = _sp_selected_path(widget)"
  print "    _sp_open_text_editor(p)"
  print "    return \"break\""
  print "# --- end StreetPack Missing Click Handlers v5 ---"
  print ""
}

BEGIN{ inserted=0 }
{
  line=$0
  # Insert block right before __main__ launcher so it DEFINITELY executes
  if (!inserted && line ~ /^[ \t]*if[ \t]+__name__[ \t]*==[ \t]*[\"\047]__main__[\"\047][ \t]*:/) {
    emit_block()
    inserted=1
  }
  print line
}
END{
  if (!inserted) {
    # Fallback: append (only used if no __main__ block exists)
    emit_block()
  }
}
' "$TARGET" > "$TMP"

mv -f -- "$TMP" "$TARGET"

echo "OK: injected missing handler defs before __main__"
echo "Backup: $BAK"
