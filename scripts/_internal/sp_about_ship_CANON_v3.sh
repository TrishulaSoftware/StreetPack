#!/usr/bin/env bash
set -euo pipefail
T="${1:-streetpack_dock.py}"
[[ -f "$T" ]] || { echo "ERR: missing $T" >&2; exit 2; }

pyok(){ python3 -m py_compile "$1" >/dev/null 2>&1; }

# 1) If current file doesn't compile, restore newest compiling backup
if ! pyok "$T"; then
  echo "WARN: $T not compiling — restoring newest compiling backup..."
  restored=""
  for b in $(ls -1t "${T}.bak."* 2>/dev/null); do
    if pyok "$b"; then
      cp -a -- "$b" "$T"
      restored="$b"
      echo "OK: restored from $b"
      break
    fi
  done
  pyok "$T" || { echo "ERR: no compiling backup found for $T" >&2; exit 10; }
fi

STAMP="$(date -u +%Y%m%d_%H%M%S_%3NZ 2>/dev/null || date -u +%Y%m%d_%H%M%SZ)"
BAK="${T}.bak.${STAMP}.aboutv3"
cp -a -- "$T" "$BAK"

# 2) Write About text file (safe, shippable, editable)
cat > streetpack_about.txt <<'TXT'
STREETPACK (StreetPack Dock) — Trishula Software
Operational Safety + Integrity Toolkit for Linux (CLI tools + a clean launcher UI)

StreetPack is a practical “ops pack” for day-to-day terminal work: file safety, integrity checks, permission auditing, and controlled execution — with clear artifacts so you can prove what happened.

──────────────────────────────────────────────────────────────────────────────
WHAT YOU GET
1) StreetPack CLI tools (small, composable commands)
2) StreetPack Dock (streetpack_dock.py): a minimal GUI launcher that:
   - selects a tool
   - lets you provide Target + Args
   - runs the tool
   - captures outputs
   - records receipts
   - lets you open/reveal artifacts safely

StreetPack is built for repeatability: run → artifacts → review.

──────────────────────────────────────────────────────────────────────────────
THE DOCK UI (HOW TO USE IT)
TOP BAR
- Tool: choose a StreetPack tool
- Filter: quickly narrow tool list
- System / Danger toggles: show/hide tools that are system-level or risky (if tagged)
- Target: file/folder path the tool operates on (when applicable)
- Args: extra args passed to the tool

BUTTONS
- Run: executes the selected tool
- Stop: attempts to interrupt a running tool (when supported)
- Open Receipts: opens the receipts folder
- Open Outputs: opens the outputs folder

TABS
- Receipts: audit trail artifacts (what ran, when, exit status, paths created)
- Outputs: readable results (txt/json reports, logs, summaries)
- About: this page

RIGHT-CLICK ON RECEIPTS/OUTPUTS ITEMS
- Open in Text Editor (preferred)  ✅
- Reveal in Folder                 ✅
- Copy Full Path                   ✅
(Left-click should not force a browser.)

Preferred editor:
  export SP_EDITOR="gnome-text-editor"
or:
  export SP_EDITOR="gedit"
or:
  export SP_EDITOR="code --reuse-window"

──────────────────────────────────────────────────────────────────────────────
ARTIFACTS (RECEIPTS + OUTPUTS)
Outputs = what you read.
Receipts = what happened.

Typical folders:
- Outputs:  ~/.local/share/streetpack/outputs/
- Receipts: ~/.local/share/streetpack/receipts/
(Your build may vary; the Dock uses its configured folders.)

Naming is timestamped so runs are traceable (example patterns):
- outputs/<tool>.<stamp>.txt
- outputs/<tool>.<stamp>.json
- receipts/<tool>.<stamp>.json

──────────────────────────────────────────────────────────────────────────────
TOOLS (CORE SET — MAY VARY BY BUILD)
The Dock is a launcher for the StreetPack tool suite. Common tools include:

SAFEDEL
- Safer delete workflow to avoid “rm oops” patterns.

DIFFWATCH
- Watches/compares files or directories and reports deltas.

DIRSCOPE
- Directory inventory/scope report: counts, sizes, extension breakdown, hotspots.

HASHSCAN
- Hash generation/verification for files and directory trees (baseline + validate).

RUNSHIELD
- Controlled runner that captures stdout/stderr and produces consistent artifacts.

PERMCHECK
- Permission/access diagnostics (read/write/exec checks + common-cause hints).

Optional expansion modules (if present in your build):
- SecretsSniff, LogTail+, PortGuard, NetPulse, ProcWatch, PathDoctor,
  BulkRename-Safe, Dedupe-Lite, EnvVault, PackReceipt, etc.

──────────────────────────────────────────────────────────────────────────────
DESIGN PRINCIPLES (THE “WHY”)
- Explicit: you can see exactly what will run
- Inspectable: results are readable; receipts explain the run
- Repeatable: consistent artifact locations + timestamps
- Safer-by-default: avoids accidental destructive behavior
- Practical: small tools that compose

StreetPack Dock is intentionally “thin”: it orchestrates tools and artifacts, it
doesn’t try to hide the terminal or magic away the system.

© Trishula Software — StreetPack
TXT

# 3) Patch python: loader helper + About tab uses file + start lists clean
python3 - "$T" <<'PY'
from pathlib import Path
import re, sys

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")

# --- Insert loader helper (top-level) ---
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
    for i, line in enumerate(lines[:500]):
        if line.startswith("import ") or line.startswith("from "):
            insert_at = i + 1
    lines.insert(insert_at, "\n" + helper + "\n")
    s = "".join(lines)

# --- Clear Receipts/Outputs lists on launch (UI only; no deletes) ---
def ensure_clear(block_name: str):
    global s
    pat = re.compile(r'(?m)^(?P<ind>\s*)self\.' + re.escape(block_name) + r'\.(pack|grid)\(.*\)\s*$')
    m = pat.search(s)
    if not m:
        return
    ind = m.group("ind")
    inject = (
        f"{ind}# start clean on launch (UI list only)\n"
        f"{ind}try: self.{block_name}.delete(0, 'end')\n"
        f"{ind}except Exception: pass\n"
    )
    # don’t double-insert
    tail = s[m.end():m.end()+200]
    if "start clean on launch" in tail:
        return
    s = s[:m.end()] + "\n" + inject + s[m.end():]

ensure_clear("_rcpt_list")
ensure_clear("_out_list")

# --- Patch About tab: insert about text from file into the About Text widget ---
# Look for the About tab's Text widget creation pattern (the one using wrap="word")
pat_about_text = re.compile(
    r'(?m)^(?P<ind>\s*)txt\s*=\s*tk\.Text\(\s*root\s*,[^\n]*wrap\s*=\s*[\'"]word[\'"][^\n]*\)\s*$'
)
m = pat_about_text.search(s)
if not m:
    raise SystemExit("ERR: could not find About Text widget line (txt = tk.Text(root, wrap='word'...))")

ind = m.group("ind")
inject = f"{ind}txt.delete('1.0','end')\n{ind}txt.insert('1.0', _sp_load_about_text())\n"

# don’t double insert
tail = s[m.end():m.end()+300]
if "_sp_load_about_text()" not in tail:
    s = s[:m.end()] + "\n" + inject + s[m.end():]

p.write_text(s, encoding="utf-8")
print("OK: About wired to streetpack_about.txt + lists start clean (CANON_V3)")
PY

python3 -m py_compile "$T" && echo "OK: syntax clean"
echo "Backup: $BAK"
echo "OK: About file: $(pwd)/streetpack_about.txt"
