#!/usr/bin/env bash
set -euo pipefail
T="${1:-streetpack_dock.py}"
[[ -f "$T" ]] || { echo "ERR: missing $T" >&2; exit 2; }

STAMP="$(date -u +%Y%m%d_%H%M%S_%3NZ 2>/dev/null || date -u +%Y%m%d_%H%M%SZ)"
BAK="${T}.bak.${STAMP}"
cp -a -- "$T" "$BAK"

python3 - "$T" <<'PY'
from pathlib import Path
import re, sys

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")

ABOUT = r'''STREETPACK (StreetPack Dock) — Trishula Software
Operational Safety + Integrity Toolkit for Linux (CLI tools + a clean launcher UI)

StreetPack is a small, practical “ops pack” for day-to-day terminal work: file safety, integrity checking, permission auditing, and controlled execution. It’s designed for builders and operators who want repeatable results, clear artifacts, and no surprises.

What StreetPack is
- A curated set of focused tools (CLI-first) for common ops/defense workflows.
- A Dock UI (“streetpack_dock.py”) that lets you pick a tool, set a target + args, run it, and manage the resulting artifacts.
- A receipts + outputs system so every run leaves a trail you can review later.

What StreetPack does (core capabilities)
1) Safe file handling (safe-by-default)
- Avoids accidental destructive actions by favoring “inspect / verify / export” workflows.
- Tools are built to be explicit about what they touch and what they produce.
- You get clear outputs and receipts for accountability.

2) Integrity & change visibility
- Hashing and verification workflows for files and trees.
- “What changed?” views for directories and watched paths.
- Inventory-style scans so you can compare “before vs after” states.

3) Permission & path reality checks
- Permission checks that help you quickly answer:
  “Can I read/write/execute here?” “Is this mount noexec?” “Why is this failing?”
- Highlights common failure causes (ownership, mode bits, ACLs, mount flags).

4) Controlled execution (“run it, but keep it auditable”)
- Run tools with captured stdout/stderr into an output artifact.
- Stop / cancel runs (where supported).
- One-click open/reveal for artifacts so you’re not hunting paths.

Included tools (core set)
NOTE: The Dock is modular — your build may include only the core set, or additional modules.
Core tools are:
- SafeDel
  Safe deletion workflow (trash-first / confirm-first style). Intended to prevent “rm oops” events.
- DiffWatch
  Watches a file or directory for changes and reports what changed (time + path + delta signal).
- DirScope
  Directory inventory and scope report (counts, sizes, extensions, hotspots). Useful for “what’s in here?” fast.
- HashScan
  Hash generation/verification for files and trees. Used for tamper detection and “known-good” baselines.
- RunShield
  Runs commands/tools in a controlled way and captures outputs (good for repeatable runs and debugging).
- PermCheck
  Permission and access diagnostics for a path (read/write/exec checks + common blockers).

Optional / expansion modules (may be present depending on your build)
- SecretsSniff (find likely secrets in text files and repos)
- LogTail+ (fast tail/grep helpers for live logs)
- PortGuard / NetPulse (network quick-check utilities)
- ProcWatch (process observation/guard helpers)
- PathDoctor (path troubleshooting: exec bit, PATH resolution, noexec mounts)
- BulkRename-Safe (batch renames with preview/receipt)
- Dedupe-Lite (duplicate detection by hash/size)
- EnvVault (export/import safe environment snapshots)
- PackReceipt (package receipts/outputs into a shareable evidence bundle)

How the Dock UI works
Top controls:
- Tool: Select the tool you want to run.
- Filter: Quickly filter the tool list.
- Toggles (System/Danger): Lets you show/hide “system-level” or “dangerous” tools if your build tags them.
- Target: A file/folder target passed into the tool (when applicable).
- Args: Extra arguments passed to the tool.

Run controls:
- Run: Executes the selected tool using the current Target + Args.
- Stop: Attempts to stop a running tool (when supported).
- Open Receipts / Open Outputs: Opens the folders where artifacts are stored.

Tabs:
- Receipts: List of receipt artifacts (per-run metadata).
- Outputs: List of output artifacts (captured stdout/stderr or tool-generated reports).
- About: This page.

Receipts & Outputs (what gets produced)
StreetPack separates “what happened” from “what it printed”:
- Outputs are the actual artifacts you read (text logs, reports, JSON summaries, etc.).
- Receipts are the audit metadata for a run.

A receipt is intended to capture (fields vary by tool/build):
- Tool name + version (when available)
- UTC timestamp(s) + elapsed time
- Command invoked + args
- Target path (if any)
- Exit code / status
- Output artifact paths created
- Working directory
- Host/user/runtime basics (for reproducibility)

Where artifacts live (default)
StreetPack writes its artifacts under your user data folder, typically:
- ~/.local/share/streetpack/outputs/
- ~/.local/share/streetpack/receipts/

(Exact paths may vary by build; the Dock will reveal the active folders.)

Opening artifacts the “right way” (text editor, not browser)
Some desktops may try to open .txt/.json in a browser. StreetPack prefers a real editor.
- Use right-click on Receipts/Outputs items → “Open in Text Editor” / “Reveal in Folder”.
- You can set a preferred editor via environment variable:
  SP_EDITOR="gnome-text-editor"
  SP_EDITOR="gedit"
  SP_EDITOR="code --reuse-window"

Design principles (the StreetPack doctrine)
- Be explicit: show what will run and what it will touch.
- Be inspectable: outputs are human-readable; receipts tell you what happened.
- Be reversible when possible: favor non-destructive workflows (trash-first, preview-first, report-first).
- Keep it simple: small tools that do one job well, designed to compose.

Security / safety note
StreetPack is an operator toolset. Use judgment:
- Don’t point “dangerous” tools at system roots unless you understand the consequences.
- Prefer dry-run / report tools first.
- Treat receipts/outputs as evidence artifacts (they can contain paths, system details, and tool output).

© Trishula Software — StreetPack
'''

# --- 1) Install/replace SP_ABOUT_TEXT block (marker-based) ---
blk_re = re.compile(r'(?s)# SP_ABOUT_CANON_V1.*?# END SP_ABOUT_CANON_V1\s*')
blk = "# SP_ABOUT_CANON_V1\nSP_ABOUT_TEXT = r'''%s'''\n# END SP_ABOUT_CANON_V1\n" % ABOUT.replace("'''", "''\\'")
if blk_re.search(s):
    s = blk_re.sub(blk, s, count=1)
    blk_action = "replaced"
else:
    # insert after imports (best-effort)
    lines = s.splitlines(True)
    insert_at = 0
    for i, line in enumerate(lines[:250]):
        if line.startswith("import ") or line.startswith("from "):
            insert_at = i + 1
    lines.insert(insert_at, "\n" + blk + "\n")
    s = "".join(lines)
    blk_action = "inserted"

# --- 2) Hook About tab insert to SP_ABOUT_TEXT ---
# Find the line that adds the About tab
m = re.search(r'(?m)^\s*self\.nb\.add\([^)]*text\s*=\s*[\'"]About[\'"][^)]*\)\s*$', s)
if not m:
    raise SystemExit("ERR: couldn't find Notebook add(... text='About') line")

# From that point forward, find first txt.insert(...) and replace (including multiline triple-quote inserts)
start = m.end()
tail = s[start:]

ins = re.search(r'(?m)^(?P<ind>\s*)(?P<var>\w+)\.insert\(\s*[\'"]1\.0[\'"]\s*,.*$', tail)
if not ins:
    ins = re.search(r'(?m)^(?P<ind>\s*)(?P<var>\w+)\.insert\(\s*[\'"]end[\'"]\s*,.*$', tail)
if not ins:
    raise SystemExit("ERR: couldn't find a txt.insert('1.0', ...) after the About tab is created")

ind = ins.group("ind")
var = ins.group("var")
ins_line_start = start + ins.start()
ins_line_end = s.find("\n", start + ins.end())
if ins_line_end == -1:
    ins_line_end = len(s)
else:
    ins_line_end += 1

# If the insert line starts a triple-quoted string, remove through its terminator
chunk = s[ins_line_start:ins_line_end]
if '"""' in chunk or "'''" in chunk:
    q = '"""' if '"""' in chunk else "'''"
    # remove until next q appears again AFTER this line
    after = s[ins_line_end:]
    qpos = after.find(q)
    if qpos != -1:
        # move to end of line containing closing triple quote
        endpos = ins_line_end + qpos + len(q)
        endline = s.find("\n", endpos)
        if endline != -1:
            ins_line_end = endline + 1

replacement = f"{ind}{var}.insert('1.0', SP_ABOUT_TEXT)\n"
s = s[:ins_line_start] + replacement + s[ins_line_end:]

p.write_text(s, encoding="utf-8")
print(f"OK: About canon installed ({blk_action}); About insert now uses SP_ABOUT_TEXT")
PY

echo "OK: patched $T"
echo "Backup: $BAK"
python3 -m py_compile "$T" && echo "OK: syntax clean"
