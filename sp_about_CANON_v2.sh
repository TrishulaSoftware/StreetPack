#!/usr/bin/env bash
set -euo pipefail
T="${1:-streetpack_dock.py}"
[[ -f "$T" ]] || { echo "ERR: missing $T" >&2; exit 2; }

STAMP="$(date -u +%Y%m%d_%H%M%S_%3NZ 2>/dev/null || date -u +%Y%m%d_%H%M%SZ)"
BAK="${T}.bak.${STAMP}"
cp -a -- "$T" "$BAK"

# Write About text file (shippable, editable, no Python indentation risk)
cat > streetpack_about.txt <<'TXT'
STREETPACK (StreetPack Dock) — Trishula Software
Operational Safety + Integrity Toolkit for Linux (CLI tools + a clean launcher UI)

StreetPack is a small, practical ops pack for day-to-day terminal work: file safety, integrity checking, permission auditing, and controlled execution. It’s designed for builders/operators who want repeatable results, clear artifacts, and no surprises.

WHAT STREETPACK IS
- A curated set of focused tools (CLI-first) for common ops/defense workflows.
- A Dock UI (streetpack_dock.py) that lets you pick a tool, set Target + Args, run it, and manage artifacts.
- A receipts + outputs system so every run leaves a trail you can review later.

WHAT STREETPACK DOES (CORE CAPABILITIES)
1) Safe file handling (safe-by-default)
- Favors inspect/verify/export workflows.
- Tools are explicit about what they touch and what they produce.
- Clear outputs + receipts for accountability.

2) Integrity & change visibility
- Hashing + verification workflows for files and trees.
- “What changed?” visibility for directories and watched paths.
- Inventory scans so you can compare “before vs after”.

3) Permission & path reality checks
- Quick answers to: can I read/write/execute here? why is this failing?
- Highlights common blockers (ownership, mode bits, ACLs, mount flags like noexec).

4) Controlled execution (auditable runs)
- Runs capture stdout/stderr into output artifacts.
- Stop/cancel where supported.
- Open/Reval actions for artifacts so you’re not hunting paths.

TOOLS (CORE SET)
- SafeDel: Safe deletion workflow (trash/confirm-first style) to avoid “rm oops”.
- DiffWatch: Watches file/dir for changes and reports deltas.
- DirScope: Directory inventory/scope report (counts, sizes, extensions, hotspots).
- HashScan: Hash generation/verification for files/trees (baseline + tamper detection).
- RunShield: Controlled runner that captures outputs and improves repeatability.
- PermCheck: Permission/access diagnostics (read/write/exec) with common-cause hints.

OPTIONAL / EXPANSION MODULES (IF PRESENT IN YOUR BUILD)
- SecretsSniff, LogTail+, PortGuard, NetPulse, ProcWatch, PathDoctor,
  BulkRename-Safe, Dedupe-Lite, EnvVault, PackReceipt, etc.

HOW THE DOCK UI WORKS
Top controls:
- Tool: Select a tool
- Filter: Filter tools
- Toggles (System/Danger): show/hide system-level or risky tools (if tagged)
- Target: file/folder target path (when applicable)
- Args: extra arguments passed to the tool

Run controls:
- Run: executes tool with Target + Args
- Stop: attempts to stop a running tool (when supported)
- Open Receipts / Open Outputs: opens artifact folders

Tabs:
- Receipts: per-run metadata artifacts (audit trail)
- Outputs: human-readable outputs / reports
- About: this page

RECEIPTS & OUTPUTS
Outputs = what you read (text logs, reports, json summaries).
Receipts = what happened (tool, args, target, timestamps, status/exit, paths created).

DEFAULT ARTIFACT PATHS
Typically:
- ~/.local/share/streetpack/outputs/
- ~/.local/share/streetpack/receipts/
(Your build may vary; the Dock’s Reveal/Open uses the active folders.)

OPENING ARTIFACTS THE RIGHT WAY (TEXT EDITOR, NOT BROWSER)
Some desktops open .txt/.json in a browser. StreetPack prefers a real editor:
- Right-click Receipts/Outputs items → Open in Text Editor / Reveal in Folder
- Preferred editor can be set:
  SP_EDITOR="gnome-text-editor"
  SP_EDITOR="gedit"
  SP_EDITOR="code --reuse-window"

DESIGN PRINCIPLES
- Explicit: show what will run and what it will touch
- Inspectable: outputs are readable; receipts explain the run
- Reversible when possible: trash/preview/report-first
- Simple: small tools that compose

© Trishula Software — StreetPack
TXT

python3 - "$T" <<'PY'
from pathlib import Path
import re, sys

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")

# Remove any prior embedded About canon blocks if present (defensive cleanup)
s = re.sub(r'(?s)^# SP_ABOUT_CANON_V\d+.*?^# END SP_ABOUT_CANON_V\d+\s*', '', s, flags=re.M)

# Ensure loader helper exists (top-level, safe)
if "SP_ABOUT_LOADER_CANON_V1" not in s:
    helper = r'''
# SP_ABOUT_LOADER_CANON_V1
from pathlib import Path as _SP_Path
def _sp_load_about_text():
    try:
        here = _SP_Path(__file__).resolve().parent
        fp = here / "streetpack_about.txt"
        return fp.read_text(encoding="utf-8")
    except Exception as e:
        return "StreetPack — About file missing: streetpack_about.txt\n" + str(e)
# END SP_ABOUT_LOADER_CANON_V1
'''.lstrip("\n")

    lines = s.splitlines(True)
    insert_at = 0
    for i, line in enumerate(lines[:300]):
        if line.startswith("import ") or line.startswith("from "):
            insert_at = i + 1
    lines.insert(insert_at, "\n" + helper + "\n")
    s = "".join(lines)

# Patch About tab insert to use loader
m = re.search(r'(?m)^\s*self\.nb\.add\([^)]*text\s*=\s*[\'"]About[\'"][^)]*\)\s*$', s)
if not m:
    raise SystemExit("ERR: could not find Notebook add(... text='About')")

start = m.end()
tail = s[start:]

# Find the first Text widget creation after About tab is added
t = re.search(r'(?m)^(?P<ind>\s*)(?P<var>\w+)\s*=\s*tk\.Text\(', tail)
if not t:
    raise SystemExit("ERR: could not find tk.Text(...) after About tab")

var = t.group("var")
ind = t.group("ind")

# Find first var.insert(...) after that and replace it
tail2 = tail[t.end():]
ins = re.search(r'(?m)^\s*' + re.escape(var) + r'\.insert\(\s*[\'"](1\.0|end)[\'"]\s*,.*$', tail2)
if not ins:
    raise SystemExit(f"ERR: could not find {var}.insert(...) after About Text widget")

ins_abs_start = start + t.end() + ins.start()
ins_abs_end = s.find("\n", start + t.end() + ins.end())
if ins_abs_end == -1:
    ins_abs_end = len(s)
else:
    ins_abs_end += 1

# If that insert starts a triple-quoted blob, delete through its closing quotes
chunk = s[ins_abs_start:ins_abs_end]
if '"""' in chunk or "'''" in chunk:
    q = '"""' if '"""' in chunk else "'''"
    after = s[ins_abs_end:]
    qpos = after.find(q)
    if qpos != -1:
        endpos = ins_abs_end + qpos + len(q)
        endline = s.find("\n", endpos)
        if endline != -1:
            ins_abs_end = endline + 1

replacement = f"{ind}{var}.insert('1.0', _sp_load_about_text())\n"
s = s[:ins_abs_start] + replacement + s[ins_abs_end:]

p.write_text(s, encoding="utf-8")
print("OK: About now loads streetpack_about.txt via _sp_load_about_text()")
PY

echo "OK: installed About CANON V2"
echo "Backup: $BAK"
python3 -m py_compile "$T" && echo "OK: syntax clean"
