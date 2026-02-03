#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-streetpack_dock.py}"
[[ -f "$TARGET" ]] || { echo "ERR: target not found: $TARGET" >&2; exit 2; }

STAMP="$(date -u +%Y%m%d_%H%M%S_%3NZ 2>/dev/null || date -u +%Y%m%d_%H%M%SZ)"
BAK="${TARGET}.bak.${STAMP}"
cp -a -- "$TARGET" "$BAK"

# If already patched, exit clean.
if grep -q "def _sp_open_text_editor(" "$TARGET"; then
  echo "OK: context-menu helpers already present. Backup: $BAK"
else
  TMP="${TARGET}.tmp.${STAMP}"

  awk '
  function emit_helpers(){
    print ""
    print "# --- StreetPack: open receipts/outputs in text editor + right-click menu ---"
    print "import os, shutil, subprocess, shlex"
    print ""
    print "def _sp_cmd_exists(name):"
    print "    return shutil.which(name) is not None"
    print ""
    print "def _sp_open_text_editor(path):"
    print "    if not path: return"
    print "    path = os.path.expanduser(str(path))"
    print "    path = os.path.abspath(path)"
    print "    if not os.path.exists(path):"
    print "        return"
    print "    # Prefer explicit env overrides"
    print "    editor = os.environ.get(\"SP_EDITOR\") or os.environ.get(\"EDITOR\")"
    print "    tried = []"
    print "    if editor:"
    print "        try:"
    print "            cmd = shlex.split(editor) + [path]"
    print "            subprocess.Popen(cmd)"
    print "            return"
    print "        except Exception:"
    print "            tried.append(editor)"
    print "    # Common GUI editors (GNOME + general)"
    print "    for exe, extra in ("
    print "        (\"code\", [\"--reuse-window\"]),"
    print "        (\"gnome-text-editor\", []),"
    print "        (\"gedit\", []),"
    print "        (\"kate\", []),"
    print "        (\"mousepad\", []),"
    print "        (\"xed\", []),"
    print "        (\"leafpad\", []),"
    print "    ):"
    print "        if _sp_cmd_exists(exe):"
    print "            try:"
    print "                subprocess.Popen([exe] + extra + [path])"
    print "                return"
    print "            except Exception:"
    print "                tried.append(exe)"
    print "    # Last resort: system opener (may be browser depending on mime assoc)"
    print "    for exe in (\"gio\", \"xdg-open\"):"
    print "        if _sp_cmd_exists(exe):"
    print "            try:"
    print "                subprocess.Popen([exe, \"open\", path] if exe==\"gio\" else [exe, path])"
    print "                return"
    print "            except Exception:"
    print "                tried.append(exe)"
    print ""
    print "def _sp_reveal_path(path):"
    print "    if not path: return"
    print "    path = os.path.expanduser(str(path))"
    print "    path = os.path.abspath(path)"
    print "    if not os.path.exists(path):"
    print "        return"
    print "    # Try to select file in Nautilus if present"
    print "    if _sp_cmd_exists(\"nautilus\"):"
    print "        try:"
    print "            subprocess.Popen([\"nautilus\", \"--select\", path])"
    print "            return"
    print "        except Exception:"
    print "            pass"
    print "    folder = path if os.path.isdir(path) else os.path.dirname(path)"
    print "    for exe in (\"gio\", \"xdg-open\"):"
    print "        if _sp_cmd_exists(exe):"
    print "            try:"
    print "                subprocess.Popen([exe, \"open\", folder] if exe==\"gio\" else [exe, folder])"
    print "                return"
    print "            except Exception:"
    print "                pass"
    print ""
    print "def _sp_extract_existing_path(s):"
    print "    if s is None: return None"
    print "    s = str(s).strip()"
    print "    if os.path.exists(s):"
    print "        return s"
    print "    # Try tokens (often list items include extra text)"
    print "    for tok in reversed(s.split()):"
    print "        t = tok.strip(\"\\\"'()[]{}<>,;\")"
    print "        if os.path.exists(t):"
    print "            return t"
    print "    return None"
    print ""
    print "def _sp_selected_path(widget):"
    print "    try:"
    print "        # Listbox"
    print "        if hasattr(widget, \"curselection\"):"
    print "            sel = widget.curselection()"
    print "            if not sel: return None"
    print "            val = widget.get(sel[0])"
    print "            return _sp_extract_existing_path(val) or val"
    print "        # Treeview"
    print "        if hasattr(widget, \"selection\"):"
    print "            sel = widget.selection()"
    print "            if not sel: return None"
    print "            item = widget.item(sel[0])"
    print "            val = item.get(\"text\") or \"\""
    print "            if not val and item.get(\"values\"):"
    print "                val = item.get(\"values\")[0]"
    print "            return _sp_extract_existing_path(val) or val"
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
    print "    # Build menu lazily per-widget"
    print "    try:"
    print "        import tkinter as _tk"
    print "    except Exception:"
    print "        return"
    print "    m = getattr(widget, \"_sp_ctx_menu\", None)"
    print "    if m is None:"
    print "        m = _tk.Menu(widget, tearoff=0)"
    print "        widget._sp_ctx_menu = m"
    print "    else:"
    print "        try: m.delete(0, \"end\")"
    print "        except Exception: pass"
    print ""
    print "    p = _sp_selected_path(widget)"
    print "    m.add_command(label=\"Open in Text Editor\", command=lambda: _sp_open_text_editor(p))"
    print "    m.add_command(label=\"Reveal in Folder\", command=lambda: _sp_reveal_path(p))"
    print "    m.add_separator()"
    print "    m.add_command(label=\"Copy Path\", command=lambda: _sp_copy_path(widget, p))"
    print "    try:"
    print "        m.tk_popup(event.x_root, event.y_root)"
    print "    finally:"
    print "        try: m.grab_release()"
    print "        except Exception: pass"
    print "# --- end StreetPack helpers ---"
    print ""
  }

  BEGIN{ inserted=0; saw_nonimport=0 }
  {
    line=$0
    if (!saw_nonimport) {
      if (line ~ /^[[:space:]]*(import[[:space:]]|from[[:space:]].*[[:space:]]import[[:space:]])/ ||
          line ~ /^[[:space:]]*$/ ||
          line ~ /^[[:space:]]*#/ ) {
        print line
        next
      } else {
        if (!inserted) { emit_helpers(); inserted=1 }
        saw_nonimport=1
        print line
        next
      }
    }
    print line
  }
  END{
    if (!inserted) emit_helpers()
  }
  ' "$TARGET" > "$TMP"

  mv -f -- "$TMP" "$TARGET"
  echo "OK: inserted helpers"
fi

# Now patch bindings for receipts/outputs lists: remove old binds, add ours after pack()
TMP2="${TARGET}.tmp.${STAMP}.b"
awk '
function indent_of(s){ match(s, /^[ \t]*/); return substr(s, RSTART, RLENGTH) }

BEGIN{
  # We drop existing binds for these widgets to prevent Firefox behavior.
}

{
  line=$0

  # Drop any existing binds for rcpt/out lists (we will rebind cleanly)
  if (line ~ /self\._rcpt_list\.bind\(/) next
  if (line ~ /self\._out_list\.bind\(/)  next

  print line

  # After pack lines, inject our bindings (same indent)
  if (line ~ /self\._rcpt_list\.pack\(/) {
    ind = indent_of(line)
    print ind "self._rcpt_list.bind(\"<Double-Button-1>\", lambda e: _sp_open_text_editor(_sp_selected_path(self._rcpt_list)))"
    print ind "self._rcpt_list.bind(\"<Return>\",          lambda e: _sp_open_text_editor(_sp_selected_path(self._rcpt_list)))"
    print ind "self._rcpt_list.bind(\"<Button-3>\",        lambda e: _sp_popup_path_menu(e, self._rcpt_list))"
  }
  if (line ~ /self\._out_list\.pack\(/) {
    ind = indent_of(line)
    print ind "self._out_list.bind(\"<Double-Button-1>\", lambda e: _sp_open_text_editor(_sp_selected_path(self._out_list)))"
    print ind "self._out_list.bind(\"<Return>\",          lambda e: _sp_open_text_editor(_sp_selected_path(self._out_list)))"
    print ind "self._out_list.bind(\"<Button-3>\",        lambda e: _sp_popup_path_menu(e, self._out_list))"
  }
}
' "$TARGET" > "$TMP2"

mv -f -- "$TMP2" "$TARGET"

echo "OK: patched rcpt/out list bindings (double-click/enter opens editor, right-click menu)"
echo "Backup: $BAK"
