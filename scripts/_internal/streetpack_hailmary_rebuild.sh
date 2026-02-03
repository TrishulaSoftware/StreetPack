#!/usr/bin/env bash
set -euo pipefail

SP="$HOME/Trishula-Infra_Linux/StreetPack"
VER="0.1.0"
STAMP="$(date -u +%Y%m%d_%H%M%S_Z)"
FOUND="$SP/StreetPack-Foundry-$STAMP"
BIN="$HOME/.local/bin"
RECEIPTS_BASE="$HOME/.local/share/streetpack/receipts"

TOOLS=(
  safedel diffwatch dirscope hashscan runshield permcheck
  secretsniff portguard "logtail+" netpulse procwatch pathdoctor
  bulkrename-safe dedupe-lite envvault packreceipt
)

mkdir -p "$FOUND"/{00_FOUNDATION,bootstrap,docs,repos}
mkdir -p "$BIN" "$RECEIPTS_BASE"

cat > "$FOUND/README.md" <<EOF
# Street Pack Foundry

Generated: $STAMP
Version: $VER

- repos/ contains per-tool repos
- install_all.sh installs tools into ~/.local/bin
- bootstrap/smoke_all.sh validates scripts
EOF

cat > "$FOUND/00_FOUNDATION/CONTRACT.md" <<EOF
# Street Pack CLI Contract (MVP)

All tools support:
  --help
  --version
  --json
  --out <file>
  --receipt-dir <dir>

Default receipt dir:
  ~/.local/share/streetpack/receipts/<tool>/
EOF

write_tool() {
  local tool="$1"
  local repo="$FOUND/repos/$tool"
  mkdir -p "$repo"/{lib,tests,releases}

  cat > "$repo/README.md" <<EOF
# $tool

Street Pack tool (v$VER).

Try:
  $tool --help
EOF

  cat > "$repo/CHANGELOG.md" <<EOF
## $VER
- Initial MVP (hailmary rebuild).
EOF

  cat > "$repo/SECURITY.md" <<EOF
Security: safe-by-default. No destructive behavior without explicit flags (MVP).
EOF

  cat > "$repo/LICENSE" <<EOF
All rights reserved. Trishula Software.
No permission granted to use/copy/modify/distribute without explicit authorization.
EOF

  cat > "$repo/tests/smoke.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
"../$tool" --help >/dev/null
"../$tool" --version >/dev/null
EOF
  chmod +x "$repo/tests/smoke.sh"

  cat > "$repo/$tool" <<'EOF'
#!/usr/bin/env bash
set -u

TOOL="$(basename "$0")"
VER="__VER__"

usage() {
  cat <<USAGE
$TOOL v$VER

Usage:
  $TOOL <path> [--json] [--out FILE] [--receipt-dir DIR] [--once]

Common:
  --help
  --version
  --json
  --out FILE
  --receipt-dir DIR
USAGE
}

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"; s="${s//$'\r'/\\r}"; s="${s//$'\t'/\\t}"
  printf "%s" "$s"
}

stamp() { date -u +%Y%m%d_%H%M%S_Z; }
default_receipt_dir() { printf "%s" "$HOME/.local/share/streetpack/receipts/$TOOL"; }

JSON=0
OUT=""
RDIR=""
TARGET=""
ONCE=0

[ "${1:-}" = "--help" ] && { usage; exit 0; }
[ "${1:-}" = "--version" ] && { echo "$TOOL $VER"; exit 0; }

while [ $# -gt 0 ]; do
  case "$1" in
    --help) usage; exit 0 ;;
    --version) echo "$TOOL $VER"; exit 0 ;;
    --json) JSON=1; shift ;;
    --out) OUT="${2:-}"; shift 2 ;;
    --receipt-dir) RDIR="${2:-}"; shift 2 ;;
    --once) ONCE=1; shift ;;
    --*) echo "ERROR: unknown flag: $1" >&2; exit 2 ;;
    *) TARGET="$1"; shift ;;
  esac
done

[ -n "$TARGET" ] || { echo "ERROR: missing <path>" >&2; exit 2; }
[ -n "$RDIR" ] || RDIR="$(default_receipt_dir)"

emit() {
  local s="$1"
  printf "%s" "$s"
  if [ -n "$OUT" ]; then
    mkdir -p "$(dirname "$OUT")" 2>/dev/null || true
    printf "%s" "$s" > "$OUT"
  fi
}

write_receipt() {
  mkdir -p "$RDIR"
  local ts; ts="$(stamp)"
  local rp="$RDIR/run.$ts.json"
  cat > "$rp" <<JSON
{"tool":"$(json_escape "$TOOL")","version":"$(json_escape "$VER")","utc":"$ts","target":"$(json_escape "$TARGET")","json":$JSON,"out":"$(json_escape "$OUT")","exitCode":$1,"meta":$2}
JSON
  echo "$rp" >/dev/null
}

do_secretsniff() {
  local root="$1"
  local re='(AKIA[0-9A-Z]{16}|password[[:space:]]*=[[:space:]]*[^[:space:]]+|api[_-]?key[[:space:]]*=[[:space:]]*[^[:space:]]+|BEGIN[[:space:]]+PRIVATE[[:space:]]+KEY)'
  local first=1
  local n=0

  if [ "$JSON" -eq 1 ]; then emit "["; fi

  while IFS= read -r -d "" f; do
    while IFS= read -r line; do
      n=$((n+1))
      if [ "$JSON" -eq 1 ]; then
        [ $first -eq 1 ] || emit ","
        first=0
        local ln="${line%%:*}"; local body="${line#*:}"
        emit "{\"file\":\"$(json_escape "$f")\",\"line\":$ln,\"match\":\"$(json_escape "$body")\"}"
      else
        emit "$f:$line"$'\n'
      fi
    done < <(grep -nE "$re" "$f" 2>/dev/null || true)
  done < <(find "$root" -type f -print0 2>/dev/null || true)

  if [ "$JSON" -eq 1 ]; then emit "]"; fi
  echo "$n"
}

do_hashscan() {
  local root="$1"
  local first=1
  local n=0
  if [ "$JSON" -eq 1 ]; then emit "["; fi

  while IFS= read -r -d "" f; do
    local h sz
    h="$(sha256sum "$f" 2>/dev/null | awk "{print \$1}" || true)"
    [ -n "$h" ] || continue
    sz="$(stat -c %s "$f" 2>/dev/null || echo 0)"
    n=$((n+1))
    if [ "$JSON" -eq 1 ]; then
      [ $first -eq 1 ] || emit ","
      first=0
      emit "{\"file\":\"$(json_escape "$f")\",\"sha256\":\"$h\",\"bytes\":$sz}"
    else
      emit "$h  $f"$'\n'
    fi
  done < <(find "$root" -type f -print0 2>/dev/null || true)

  if [ "$JSON" -eq 1 ]; then emit "]"; fi
  echo "$n"
}

do_permcheck() {
  local root="$1"
  local first=1
  local n=0
  if [ "$JSON" -eq 1 ]; then emit "["; fi

  while IFS= read -r p; do
    [ -n "$p" ] || continue
    n=$((n+1))
    if [ "$JSON" -eq 1 ]; then
      [ $first -eq 1 ] || emit ","
      first=0
      emit "{\"path\":\"$(json_escape "$p")\"}"
    else
      emit "$p"$'\n'
    fi
  done < <(find "$root" \( -perm -0002 -o -perm -4000 -o -perm -2000 \) -print 2>/dev/null || true)

  if [ "$JSON" -eq 1 ]; then emit "]"; fi
  echo "$n"
}

do_diffwatch_once() {
  local root="$1"
  local state="$HOME/.local/share/streetpack/state/diffwatch"
  mkdir -p "$state"
  local key prev now
  key="$(printf "%s" "$root" | sha256sum | awk "{print \$1}")"
  prev="$state/$key.prev.txt"
  now="$state/$key.now.txt"

  # snapshot: sha256sum list (sorted)
  find "$root" -type f -print0 2>/dev/null \
    | xargs -0 sha256sum 2>/dev/null \
    | sort > "$now" || true

  if [ ! -f "$prev" ]; then
    cp -f "$now" "$prev"
    emit "baseline_created: $prev"$'\n'
    echo "0"
    return
  fi

  local added removed
  added="$(comm -13 "$prev" "$now" | wc -l | tr -d " ")"
  removed="$(comm -23 "$prev" "$now" | wc -l | tr -d " ")"
  cp -f "$now" "$prev"

  if [ "$JSON" -eq 1 ]; then
    emit "{\"added_or_changed\":$added,\"removed\":$removed}"
  else
    emit "added_or_changed: $added"$'\n'"removed: $removed"$'\n'"state_updated: $prev"$'\n'
  fi
  echo "$added"
}

meta='{"note":"stub"}'
count="0"
case "$TOOL" in
  secretsniff) count="$(do_secretsniff "$TARGET")"; meta="{\"findings\":$count}" ;;
  hashscan)    count="$(do_hashscan "$TARGET")";    meta="{\"files\":$count}" ;;
  permcheck)   count="$(do_permcheck "$TARGET")";   meta="{\"findings\":$count}" ;;
  diffwatch)   count="$(do_diffwatch_once "$TARGET")"; meta="{\"changes\":$count}" ;;
  *)           if [ "$JSON" -eq 1 ]; then emit "{\"tool\":\"$TOOL\",\"target\":\"$(json_escape "$TARGET")\",\"note\":\"mvp_stub\"}"; else emit "$TOOL: mvp_stub (target=$TARGET)"$'\n'; fi ;;
esac

rc=$?
write_receipt "$rc" "$meta" || true
exit $rc
EOF

  sed -i "s/__VER__/$VER/g" "$repo/$tool"
  chmod +x "$repo/$tool"
}

for t in "${TOOLS[@]}"; do
  write_tool "$t"
done

cat > "$FOUND/install_all.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HOME/.local/bin"
mkdir -p "$BIN"
count=0
for repo in "$ROOT"/repos/*; do
  [ -d "$repo" ] || continue
  tool="$(basename "$repo")"
  src="$repo/$tool"
  if [ -f "$src" ]; then
    install -m 755 "$src" "$BIN/$tool"
    count=$((count+1))
  fi
done
echo "[install_all] installed=$count -> $BIN"
EOF
chmod +x "$FOUND/install_all.sh"

cat > "$FOUND/bootstrap/smoke_all.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "[smoke_all] bash -n..."
for f in "$ROOT"/repos/*/*; do
  [ -f "$f" ] || continue
  bash -n "$f" >/dev/null
done
echo "[smoke_all] repo smoke..."
for repo in "$ROOT"/repos/*; do
  [ -d "$repo/tests" ] || continue
  (cd "$repo/tests" && bash ./smoke.sh)
done
echo "[smoke_all] PASS"
EOF
chmod +x "$FOUND/bootstrap/smoke_all.sh"

# write Dock file (do NOT launch here)
cat > "$SP/streetpack_dock.py" <<'PY'
#!/usr/bin/env python3
import os, shlex, subprocess, threading, time, glob
import tkinter as tk
from tkinter import ttk, filedialog, messagebox

HOME=os.path.expanduser("~")
SP=os.path.join(HOME,"Trishula-Infra_Linux","StreetPack")
BIN=os.path.join(HOME,".local","bin")
RECEIPTS=os.path.join(HOME,".local","share","streetpack","receipts")

TOOLS=["safedel","diffwatch","dirscope","hashscan","runshield","permcheck","secretsniff","portguard","logtail+","netpulse","procwatch","pathdoctor","bulkrename-safe","dedupe-lite","envvault","packreceipt"]

def latest_foundry():
  c=sorted(glob.glob(os.path.join(SP,"StreetPack-Foundry-*")))
  return c[-1] if c else None

def resolve(tool):
  p=os.path.join(BIN,tool)
  if os.path.isfile(p) and os.access(p,os.X_OK): return p
  f=latest_foundry()
  if f:
    p2=os.path.join(f,"repos",tool,tool)
    if os.path.isfile(p2) and os.access(p2,os.X_OK): return p2
  return None

def xdg_open(path):
  try: subprocess.Popen(["xdg-open",path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
  except Exception: pass

class App(ttk.Frame):
  def __init__(self, master):
    super().__init__(master)
    master.title("StreetPack Dock")
    master.geometry("980x640")
    self.proc=None
    self.tool=tk.StringVar(value=TOOLS[0])
    self.target=tk.StringVar(value=os.getcwd())
    self.args=tk.StringVar(value="--help")
    self.json=tk.BooleanVar(value=False)
    self.out=tk.StringVar(value="")
    self.status=tk.StringVar(value="Ready")
    self._ui()

  def _ui(self):
    top=ttk.Frame(self); top.pack(fill="x", padx=10, pady=8)
    ttk.Label(top,text="Tool").grid(row=0,column=0,sticky="w")
    cb=ttk.Combobox(top,textvariable=self.tool,values=TOOLS,state="readonly",width=26)
    cb.grid(row=0,column=1,sticky="w",padx=(8,8))
    ttk.Button(top,text="Help",command=lambda:self.run("--help")).grid(row=0,column=2,padx=(0,6))
    ttk.Button(top,text="Version",command=lambda:self.run("--version")).grid(row=0,column=3)

    ttk.Label(top,text="Target").grid(row=1,column=0,sticky="w",pady=(10,0))
    ttk.Entry(top,textvariable=self.target,width=70).grid(row=1,column=1,columnspan=3,sticky="we",padx=(8,8),pady=(10,0))
    ttk.Button(top,text="Browse",command=self.browse).grid(row=1,column=4,pady=(10,0))

    ttk.Label(top,text="Args").grid(row=2,column=0,sticky="w",pady=(10,0))
    ttk.Entry(top,textvariable=self.args,width=70).grid(row=2,column=1,columnspan=3,sticky="we",padx=(8,8),pady=(10,0))

    row=ttk.Frame(self); row.pack(fill="x", padx=10, pady=(0,8))
    ttk.Checkbutton(row,text="--json",variable=self.json).pack(side="left")
    ttk.Label(row,text="--out").pack(side="left",padx=(12,4))
    ttk.Entry(row,textvariable=self.out,width=48).pack(side="left")
    ttk.Button(row,text="Pick",command=self.pick_out).pack(side="left",padx=(6,0))
    ttk.Button(row,text="Open Receipts",command=lambda:xdg_open(RECEIPTS)).pack(side="right")
    ttk.Button(row,text="Stop",command=self.stop).pack(side="right",padx=(6,6))
    ttk.Button(row,text="Run",command=lambda:self.run(None)).pack(side="right")

    box=ttk.LabelFrame(self,text="Output"); box.pack(fill="both", expand=True, padx=10, pady=(0,8))
    self.txt=tk.Text(box,wrap="none"); self.txt.pack(fill="both", expand=True, padx=8, pady=8)
    ttk.Label(self,textvariable=self.status).pack(fill="x", padx=10, pady=(0,8))
    self.pack(fill="both", expand=True)

  def browse(self):
    d=filedialog.askdirectory(initialdir=self.target.get() or os.getcwd())
    if d: self.target.set(d)

  def pick_out(self):
    f=filedialog.asksaveasfilename(initialdir=os.getcwd(), title="Output file")
    if f: self.out.set(f)

  def append(self,s):
    self.txt.insert("end",s); self.txt.see("end")

  def stop(self):
    if self.proc and self.proc.poll() is None:
      try: self.proc.terminate()
      except Exception: pass

  def run(self, forced):
    exe=resolve(self.tool.get())
    if not exe:
      messagebox.showerror("Not found","Tool not found. Run install_all first.")
      return
    targ=self.target.get().strip()
    if not targ:
      messagebox.showerror("Missing","Target path required.")
      return
    args = forced if forced is not None else self.args.get().strip()
    cmd=[exe, targ]
    if self.json.get() and "--json" not in args: cmd.append("--json")
    if self.out.get().strip() and "--out" not in args: cmd += ["--out", self.out.get().strip()]
    if args: cmd += shlex.split(args)

    self.append("\n$ " + " ".join(shlex.quote(x) for x in cmd) + "\n")
    self.status.set("Running...")

    def worker():
      t0=time.time()
      try:
        self.proc=subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        for line in self.proc.stdout:
          self.append(line)
        rc=self.proc.wait()
        self.status.set(f"Done rc={rc} in {int((time.time()-t0)*1000)}ms")
      except Exception as e:
        self.status.set(f"Error: {e}")

    threading.Thread(target=worker, daemon=True).start()

def main():
  root=tk.Tk()
  style=ttk.Style()
  if "clam" in style.theme_names(): style.theme_use("clam")
  App(root)
  root.mainloop()

if __name__=="__main__":
  main()
PY
chmod +x "$SP/streetpack_dock.py"

# smoke + install
bash "$FOUND/bootstrap/smoke_all.sh"
bash "$FOUND/install_all.sh"

echo "[OK] New Foundry: $FOUND"
echo "[OK] repos count: $(ls -1 "$FOUND/repos" | wc -l | tr -d " ")"
echo "[OK] installed sample:"
ls -1 "$BIN" | grep -E "secretsniff|hashscan|diffwatch|permcheck|safedel" || true

