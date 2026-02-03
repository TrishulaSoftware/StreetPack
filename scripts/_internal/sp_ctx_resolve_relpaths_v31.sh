#!/usr/bin/env bash
set -euo pipefail
T="${1:-streetpack_dock.py}"
[[ -f "$T" ]] || { echo "ERR: missing $T" >&2; exit 2; }

STAMP="$(date -u +%Y%m%d_%H%M%S_%3NZ 2>/dev/null || date -u +%Y%m%d_%H%M%SZ)"
BAK="${T}.bak.${STAMP}"
cp -a -- "$T" "$BAK"

python3 - "$T" <<'PY'
from pathlib import Path
import sys, re

p = Path(sys.argv[1])
s = p.read_text(encoding="utf-8")

if "_sp_resolve_existing_path(" in s:
    print("OK: resolver already present")
    sys.exit(0)

# ensure pathlib import exists in the canon block
s = s.replace("import os, shutil, subprocess, shlex, sys, re\n",
              "import os, shutil, subprocess, shlex, sys, re\nfrom pathlib import Path\n")

resolver = r'''
def _sp_resolve_existing_path(raw):
    if raw is None:
        return None
    raw = str(raw).strip()
    if raw.startswith("file://"):
        raw = raw[7:]
    raw = os.path.expanduser(raw)

    # direct (absolute or relative)
    try:
        rp = Path(raw)
        if rp.exists():
            return str(rp.resolve())
    except Exception:
        pass

    # filename-only resolution
    name = Path(raw).name

    bases = []
    # env overrides
    for k in ("SP_RECEIPTS_DIR", "SP_OUTPUTS_DIR", "SP_DATA_DIR"):
        v = os.environ.get(k)
        if v:
            bases.append(Path(os.path.expanduser(v)))

    # common project subdirs
    cwd = Path.cwd()
    for d in ("receipts", "receipt", "outputs", "output", "out", "logs", "runs", "reports"):
        bases.append(cwd / d)

    # common user data locations
    home = Path.home()
    for d in (
        home / ".local" / "share" / "streetpack",
        home / ".local" / "share" / "StreetPack",
        home / ".local" / "share" / "trishula" / "streetpack",
    ):
        bases.append(d)
        bases.append(d / "receipts")
        bases.append(d / "outputs")

    # 1) direct join on bases
    for b in bases:
        try:
            cand = b / name
            if cand.exists():
                return str(cand.resolve())
        except Exception:
            pass

    # 2) shallow search in bases (fast-ish)
    for b in bases:
        try:
            if b.exists():
                for cand in b.rglob(name):
                    return str(cand.resolve())
        except Exception:
            pass

    # 3) last resort: search cwd
    try:
        for cand in cwd.rglob(name):
            return str(cand.resolve())
    except Exception:
        pass

    return None
'''

# insert resolver right before open_text_editor
marker = "def _sp_open_text_editor(path):"
if marker not in s:
    raise SystemExit("ERR: cannot find _sp_open_text_editor in canon block")

s = s.replace(marker, resolver + "\n" + marker, 1)

# patch open_text_editor to use resolver
s = re.sub(
    r"def _sp_open_text_editor\(path\):\n"
    r"(\s+)if not path:\n"
    r"\1\s+_sp_dbg\(\"\[sp\] open_text_editor: no path\"\)\n"
    r"\1\s+return\n\n"
    r"\1path = os\.path\.abspath\(os\.path\.expanduser\(str\(path\)\)\)\n"
    r"\1if not os\.path\.exists\(path\):\n"
    r"\1\s+_sp_dbg\(f\"\[sp\] open_text_editor: path missing: \{path\}\"\)\n"
    r"\1\s+return\n\n"
    r"\1editor = os\.environ\.get\(\"SP_EDITOR\"\) or os\.environ\.get\(\"EDITOR\"\)\n"
    r"\1_sp_dbg\(f\"\[sp\] open_text_editor: editor=\{editor!r\} path=\{path!r\}\"\)\n",
    "def _sp_open_text_editor(path):\n"
    "\\1if not path:\n"
    "\\1    _sp_dbg(\"[sp] open_text_editor: no path\")\n"
    "\\1    return\n\n"
    "\\1raw = str(path).strip()\n"
    "\\1resolved = _sp_resolve_existing_path(raw)\n"
    "\\1_sp_dbg(f\"[sp] open_text_editor: raw={raw!r} resolved={resolved!r}\")\n"
    "\\1if not resolved:\n"
    "\\1    _sp_dbg(f\"[sp] open_text_editor: path missing (unresolved): {raw}\")\n"
    "\\1    return\n\n"
    "\\1path = resolved\n"
    "\\1editor = os.environ.get(\"SP_EDITOR\") or os.environ.get(\"EDITOR\")\n"
    "\\1_sp_dbg(f\"[sp] open_text_editor: editor={editor!r} path={path!r}\")\n",
    s,
    flags=re.S
)

# patch reveal_path to use resolver
s = re.sub(
    r"def _sp_reveal_path\(path\):\n"
    r"(\s+)if not path:\n"
    r"\1\s+_sp_dbg\(\"\[sp\] reveal: no path\"\)\n"
    r"\1\s+return\n"
    r"\1path = os\.path\.abspath\(os\.path\.expanduser\(str\(path\)\)\)\n"
    r"\1if not os\.path\.exists\(path\):\n"
    r"\1\s+_sp_dbg\(f\"\[sp\] reveal: path missing: \{path\}\"\)\n"
    r"\1\s+return\n"
    r"\1folder = path if os\.path\.isdir\(path\) else os\.path\.dirname\(path\)\n"
    r"\1_sp_dbg\(f\"\[sp\] reveal: folder=\{folder!r\}\"\)\n",
    "def _sp_reveal_path(path):\n"
    "\\1if not path:\n"
    "\\1    _sp_dbg(\"[sp] reveal: no path\")\n"
    "\\1    return\n"
    "\\1raw = str(path).strip()\n"
    "\\1resolved = _sp_resolve_existing_path(raw)\n"
    "\\1_sp_dbg(f\"[sp] reveal: raw={raw!r} resolved={resolved!r}\")\n"
    "\\1if not resolved:\n"
    "\\1    _sp_dbg(f\"[sp] reveal: path missing (unresolved): {raw}\")\n"
    "\\1    return\n"
    "\\1path = resolved\n"
    "\\1folder = path if os.path.isdir(path) else os.path.dirname(path)\n"
    "\\1_sp_dbg(f\"[sp] reveal: folder={folder!r}\")\n",
    s,
    flags=re.S
)

p.write_text(s, encoding="utf-8")
print("OK: CANON_V3.1 resolver installed")
PY

echo "OK: patched $T"
echo "Backup: $BAK"
