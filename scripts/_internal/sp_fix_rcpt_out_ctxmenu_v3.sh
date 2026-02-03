#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-streetpack_dock.py}"
[[ -f "$TARGET" ]] || { echo "ERR: target not found: $TARGET" >&2; exit 2; }

STAMP="$(date -u +%Y%m%d_%H%M%S_%3NZ 2>/dev/null || date -u +%Y%m%d_%H%M%SZ)"
BAK="${TARGET}.bak.${STAMP}"
cp -a -- "$TARGET" "$BAK"

# If marker exists, don’t double-insert
if grep -q "StreetPack Context Menu v3" "$TARGET"; then
  echo "OK: v3 already present. Backup: $BAK"
  exit 0
fi

TMP="${TARGET}.tmp.${STAMP}"

awk '
function emit_block(){
  print ""
  print "# --- StreetPack Context Menu v3 (receipts/outputs open in editor; right-click menu) ---"
  print "import os, shutil, subprocess, shlex"
  print ""
  print "def _sp_cmd_exists(name):"
  print "    return shutil.which(name) is not None"
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
  print "        (\"code\", [\"--reuse-window\"]),"
  print "        (\"gnome-text-editor\", []),"
  print "        (\"gedit\", []),"
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
  print "    # fallback (may still use default app)"
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
  print "# --- end StreetPack Context Menu v3 ---"
  print ""
}

BEGIN{ inserted=0; saw_nonimport=0 }
{
  line=$0

  # Insert after imports/comments/blank
  if (!saw_nonimport) {
    if (line ~ /^[[:space:]]*(import[[:space:]]|from[[:space:]].*[[:space:]]import[[:space:]])/ ||
        line ~ /^[[:space:]]*$/ ||
        line ~ /^[[:space:]]*#/ ) {
      print line
      next
    } else {
      if (!inserted) { emit_block(); inserted=1 }
      saw_nonimport=1
      print line
      next
    }
  }

  print line
}
END{
  if (!inserted) emit_block()
}
' "$TARGET" > "$TMP"

mv -f -- "$TMP" "$TARGET"

# Rebind receipts/outputs: remove ALL existing binds on these widgets, then add clean ones
TMP2="${TARGET}.tmp.${STAMP}.b"

awk '
function indent_of(s){ match(s, /^[ \t]*/); return substr(s, RSTART, RLENGTH) }

{
  line=$0

  # Strip prior binds so we own behavior
  if (line ~ /self\._rcpt_list\.bind\(/) next
  if (line ~ /self\._out_list\.bind\(/)  next

  print line

  # Inject binds after pack() (no left-click open; only double-click/enter/right-click)
  if (line ~ /self\._rcpt_list\.pack\(/) {
    ind = indent_of(line)
    print ind "self._rcpt_list.bind(\"<Double-Button-1>\", lambda e: _sp_open_from_widget(e, self._rcpt_list))"
    print ind "self._rcpt_list.bind(\"<Return>\",          lambda e: _sp_open_from_widget(e, self._rcpt_list))"
    print ind "self._rcpt_list.bind(\"<Button-3>\",        lambda e: _sp_popup_path_menu(e, self._rcpt_list))"
  }
  if (line ~ /self\._out_list\.pack\(/) {
    ind = indent_of(line)
    print ind "self._out_list.bind(\"<Double-Button-1>\",  lambda e: _sp_open_from_widget(e, self._out_list))"
    print ind "self._out_list.bind(\"<Return>\",           lambda e: _sp_open_from_widget(e, self._out_list))"
    print ind "self._out_list.bind(\"<Button-3>\",         lambda e: _sp_popup_path_menu(e, self._out_list))"
  }
}
' "$TARGET" > "$TMP2"

mv -f -- "$TMP2" "$TARGET"

echo "OK: installed missing handlers + rebound receipts/outputs"
echo "Backup: $BAK"
