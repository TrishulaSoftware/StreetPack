#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-streetpack_dock.py}"
[[ -f "$TARGET" ]] || { echo "ERR: target not found: $TARGET" >&2; exit 2; }

STAMP="$(date -u +%Y%m%d_%H%M%S_%3NZ 2>/dev/null || date -u +%Y%m%d_%H%M%SZ)"
BAK="${TARGET}.bak.${STAMP}"
cp -a -- "$TARGET" "$BAK"

TMP="${TARGET}.tmp.${STAMP}"

# 1) Ensure we have a "break"-returning click handler and a safe opener that avoids Firefox for files
awk '
BEGIN{ins=0}
{
  print $0
  if (!ins && $0 ~ /# --- end StreetPack helpers ---/) {
    print ""
    print "# --- v2: force receipts/outputs to open in editor; stop Firefox/file:// ---"
    print "def _sp_open_any(target):"
    print "    \"\"\"Open URLs in browser, but open real file paths in a text editor.\"\"\""
    print "    try:"
    print "        import os as _os"
    print "        s = str(target).strip() if target is not None else \"\""
    print "        # normalize file://"
    print "        if s.startswith(\"file://\"):"
    print "            s = s[7:]"
    print "        p = _sp_extract_existing_path(s) or s"
    print "        if p and _os.path.exists(p):"
    print "            _sp_open_text_editor(p)"
    print "            return"
    print "    except Exception:"
    print "        pass"
    print "    try:"
    print "        import webbrowser as _wb"
    print "        _wb.open(str(target))"
    print "    except Exception:"
    print "        pass"
    print ""
    print "def _sp_open_from_widget(event, widget):"
    print "    p = _sp_selected_path(widget)"
    print "    _sp_open_text_editor(p)"
    print "    return \"break\"  # stops any other click handler (Firefox path) from firing"
    print "# --- end v2 ---"
    print ""
    ins=1
  }
}
' "$TARGET" > "$TMP"
mv -f -- "$TMP" "$TARGET"

# 2) Redirect any lingering webbrowser opens to _sp_open_any(...)
TMP2="${TARGET}.tmp.${STAMP}.b"
awk '
{
  line=$0
  gsub(/webbrowser\.open_new_tab[ \t]*\(/, "_sp_open_any(", line)
  gsub(/webbrowser\.open_new[ \t]*\(/, "_sp_open_any(", line)
  gsub(/webbrowser\.open[ \t]*\(/, "_sp_open_any(", line)
  print line
}
' "$TARGET" > "$TMP2"
mv -f -- "$TMP2" "$TARGET"

# 3) Hard-bind receipts/outputs widgets: left click opens editor + breaks; right click menu
TMP3="${TARGET}.tmp.${STAMP}.c"
awk '
function indent_of(s){ match(s, /^[ \t]*/); return substr(s, RSTART, RLENGTH) }
{
  line=$0

  # Strip prior bindings so we own the behavior
  if (line ~ /self\._rcpt_list\.bind\(/) next
  if (line ~ /self\._out_list\.bind\(/)  next

  print line

  # Inject bindings immediately after pack()
  if (line ~ /self\._rcpt_list\.pack\(/) {
    ind = indent_of(line)
    print ind "self._rcpt_list.bind(\"<ButtonRelease-1>\",  lambda e: _sp_open_from_widget(e, self._rcpt_list))"
    print ind "self._rcpt_list.bind(\"<Double-Button-1>\",  lambda e: _sp_open_from_widget(e, self._rcpt_list))"
    print ind "self._rcpt_list.bind(\"<Return>\",           lambda e: _sp_open_from_widget(e, self._rcpt_list))"
    print ind "self._rcpt_list.bind(\"<Button-3>\",         lambda e: _sp_popup_path_menu(e, self._rcpt_list))"
  }
  if (line ~ /self\._out_list\.pack\(/) {
    ind = indent_of(line)
    print ind "self._out_list.bind(\"<ButtonRelease-1>\",   lambda e: _sp_open_from_widget(e, self._out_list))"
    print ind "self._out_list.bind(\"<Double-Button-1>\",   lambda e: _sp_open_from_widget(e, self._out_list))"
    print ind "self._out_list.bind(\"<Return>\",            lambda e: _sp_open_from_widget(e, self._out_list))"
    print ind "self._out_list.bind(\"<Button-3>\",          lambda e: _sp_popup_path_menu(e, self._out_list))"
  }
}
' "$TARGET" > "$TMP3"
mv -f -- "$TMP3" "$TARGET"

echo "OK: forced editor open + right-click menu (and blocked Firefox handlers)"
echo "Backup: $BAK"
