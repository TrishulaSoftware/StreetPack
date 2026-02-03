#!/usr/bin/env bash
set -euo pipefail

# Street Pack Foundry Builder (one-shot)
# Generates: Foundry root + repo-per-tool scaffolding + install/uninstall + smoke tests
# Safe-by-default: tools are defensive/operator utilities; no exploit modules.

usage() {
  cat <<'EOF'
Usage:
  ./streetpack_foundry_build.sh [--root <path>]

Creates a Street Pack Foundry directory containing:
  - 00_FOUNDATION/ templates + contract docs
  - bootstrap/ smoke tests
  - repos/<tool>/ (repo-per-tool scaffolds, each includes install/uninstall/tests)
  - install_all.sh / uninstall_all.sh (Foundry-level)

EOF
}

ROOT_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT_ARG="${2:-}"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1" >&2; usage; exit 2;;
  esac
done

utc_stamp() { date -u +%Y%m%d_%H%M%S_Z; }

STAMP="$(utc_stamp)"
if [[ -n "${ROOT_ARG}" ]]; then
  FOUNDRY_ROOT="${ROOT_ARG}"
else
  FOUNDRY_ROOT="./StreetPack-Foundry-${STAMP}"
fi

mkdir -p "${FOUNDRY_ROOT}"/{00_FOUNDATION/templates,bootstrap,repos,docs}

# ----------------------------
# Foundation docs (contract)
# ----------------------------
cat > "${FOUNDRY_ROOT}/docs/CONTRACT.md" <<'EOF'
# Street Pack CLI Contract (v0.1)

## Required flags (every tool)
- `--help` / `-h`
- `--version`
- `--json` (emit machine-readable output)
- `--out <path>` (write report/output to file)
- `--receipt-dir <dir>` (override receipt directory)

## Recommended flags (mutating tools)
- `--dry-run` (do not mutate; report what would happen)

## Receipts
Tools SHOULD write a JSON receipt for each run under:
`~/.local/share/streetpack/receipts/<tool>/`

Receipt fields (baseline):
- tool, version
- utc, host, user, cwd
- argv (sanitized)
- elapsed_ms
- result (ok|findings|error)
- summary (counts)
- out_path (if used)

Street Pack doctrine:
- safe-by-default, dry-run-first, receipts/evidence-friendly
EOF

cat > "${FOUNDRY_ROOT}/README.md" <<EOF
# Street Pack Foundry

Generated: ${STAMP}

This is a **repo-per-tool** scaffolding pack for Street Pack CLI utilities.

## Quick start
1) Run smoke tests:
\`\`\`bash
./bootstrap/smoke_all.sh
\`\`\`

2) Install all tools to ~/.local/bin:
\`\`\`bash
./install_all.sh
\`\`\`

3) Test drive (safe commands):
\`\`\`bash
dirscope --root .
secretsniff --root .
hashscan --root . --manifest /tmp/hashscan.manifest
diffwatch --root . --state /tmp/diffwatch.state
\`\`\`

4) Uninstall all:
\`\`\`bash
./uninstall_all.sh
\`\`\`
EOF

# ----------------------------
# Foundry-level install/uninstall
# ----------------------------
cat > "${FOUNDRY_ROOT}/install_all.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
for d in "$HERE"/repos/*; do
  [[ -d "$d" ]] || continue
  if [[ -x "$d/install.sh" ]]; then
    echo "[install_all] $(basename "$d")"
    (cd "$d" && ./install.sh)
  fi
done
echo "[install_all] done"
EOF
chmod +x "${FOUNDRY_ROOT}/install_all.sh"

cat > "${FOUNDRY_ROOT}/uninstall_all.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
for d in "$HERE"/repos/*; do
  [[ -d "$d" ]] || continue
  if [[ -x "$d/uninstall.sh" ]]; then
    echo "[uninstall_all] $(basename "$d")"
    (cd "$d" && ./uninstall.sh)
  fi
done
echo "[uninstall_all] done"
EOF
chmod +x "${FOUNDRY_ROOT}/uninstall_all.sh"

# ----------------------------
# Bootstrap smoke-all
# ----------------------------
cat > "${FOUNDRY_ROOT}/bootstrap/smoke_all.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"
FAIL=0

echo "[smoke_all] bash -n on all tools..."
while IFS= read -r -d '' f; do
  if ! bash -n "$f" >/dev/null 2>&1; then
    echo "[FAIL] bash -n: $f"
    FAIL=1
  fi
done < <(find "$HERE/repos" -maxdepth 2 -type f -name "*" -perm -111 -print0)

echo "[smoke_all] per-repo smoke tests..."
for d in "$HERE"/repos/*; do
  [[ -d "$d" ]] || continue
  if [[ -x "$d/tests/smoke.sh" ]]; then
    echo "[smoke] $(basename "$d")"
    if ! (cd "$d" && ./tests/smoke.sh); then
      echo "[FAIL] tests: $d"
      FAIL=1
    fi
  fi
done

if [[ "$FAIL" -ne 0 ]]; then
  echo "[smoke_all] FAIL"
  exit 1
fi
echo "[smoke_all] PASS"
EOF
chmod +x "${FOUNDRY_ROOT}/bootstrap/smoke_all.sh"

# ----------------------------
# Shared library templates (written into each repo)
# ----------------------------
COMMON_LIB='lib/sp_common.sh'
RECEIPT_LIB='lib/sp_receipt.sh'

write_common_libs() {
  local repo="$1"
  mkdir -p "${repo}/lib"

  cat > "${repo}/${COMMON_LIB}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

sp_die()  { echo "[ERROR] $*" >&2; exit 2; }
sp_warn() { echo "[WARN]  $*" >&2; }
sp_info() { echo "[INFO]  $*" >&2; }

sp_now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }
sp_stamp()   { date -u +%Y%m%d_%H%M%S_Z; }

sp_has() { command -v "$1" >/dev/null 2>&1; }

sp_mkdirp() { mkdir -p "$1"; }

sp_json_escape() {
  # Minimal JSON string escape (quotes, backslashes, newlines, tabs)
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

sp_elapsed_ms() {
  # bash 5+: EPOCHREALTIME; fallback to seconds
  if [[ -n "${EPOCHREALTIME:-}" ]]; then
    local start="$1" end="$2"
    # EPOCHREALTIME is "seconds.microseconds"
    local s_sec="${start%.*}" s_us="${start#*.}"
    local e_sec="${end%.*}"   e_us="${end#*.}"
    local ds=$((10#$e_sec - 10#$s_sec))
    local dus=$((10#$e_us - 10#$s_us))
    local ms=$((ds*1000 + dus/1000))
    printf '%s' "$ms"
  else
    printf '0'
  fi
}

sp_text_file() {
  # best-effort "is text" check
  local f="$1"
  if sp_has file; then
    file -b --mime "$f" 2>/dev/null | grep -qi 'charset='
    return $?
  fi
  # fallback: grep -Iq
  LC_ALL=C grep -Iq . "$f" 2>/dev/null
}
EOF
  chmod +x "${repo}/${COMMON_LIB}"

  cat > "${repo}/${RECEIPT_LIB}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

# Requires: sp_common.sh already sourced

sp_receipt_dir_default() {
  local tool="$1"
  printf '%s' "${HOME}/.local/share/streetpack/receipts/${tool}"
}

sp_write_receipt() {
  # Args:
  #   tool version receipt_dir result summary_json out_path elapsed_ms extra_json
  local tool="$1" version="$2" rdir="$3" result="$4" summary="$5" out_path="$6" elapsed="$7" extra="${8:-}"
  local utc host user cwd
  utc="$(sp_now_utc)"
  host="$(hostname 2>/dev/null || echo unknown)"
  user="$(id -un 2>/dev/null || echo unknown)"
  cwd="$(pwd)"

  sp_mkdirp "$rdir"
  local stamp fname fpath
  stamp="$(sp_stamp)"
  fname="receipt.${tool}.${stamp}.json"
  fpath="${rdir}/${fname}"

  # argv (sanitized)
  local argv_json="[]"
  if [[ "${#SP_ARGV[@]:-0}" -gt 0 ]]; then
    local i
    argv_json="["
    for i in "${SP_ARGV[@]}"; do
      argv_json="${argv_json}\"$(sp_json_escape "$i")\","
    done
    argv_json="${argv_json%,}]"
  fi

  # allow extra raw JSON (must be an object fragment like: ,"foo":123)
  if [[ -n "$extra" ]]; then
    if [[ "$extra" != ,* ]]; then
      extra=",$extra"
    fi
  fi

  cat > "$fpath" <<EOF
{
  "tool": "$(sp_json_escape "$tool")",
  "version": "$(sp_json_escape "$version")",
  "utc": "$(sp_json_escape "$utc")",
  "host": "$(sp_json_escape "$host")",
  "user": "$(sp_json_escape "$user")",
  "cwd": "$(sp_json_escape "$cwd")",
  "argv": ${argv_json},
  "result": "$(sp_json_escape "$result")",
  "summary": ${summary},
  "out_path": "$(sp_json_escape "$out_path")",
  "elapsed_ms": ${elapsed}
  ${extra}
}
EOF
  echo "$fpath"
}
EOF
  chmod +x "${repo}/${RECEIPT_LIB}"
}

# ----------------------------
# Repo boilerplate
# ----------------------------
write_repo_boilerplate() {
  local repo="$1" tool="$2"
  mkdir -p "${repo}/tests" "${repo}/releases"

  cat > "${repo}/LICENSE" <<'EOF'
All rights reserved.

No permission is granted to use, copy, modify, merge, publish, distribute, sublicense, or sell copies of this software.
EOF

  cat > "${repo}/SECURITY.md" <<'EOF'
# Security

Street Pack tools are designed for defensive / operator use.
Report issues privately to the maintainer.
EOF

  cat > "${repo}/CHANGELOG.md" <<'EOF'
# Changelog

## 0.1.0
- Initial scaffold (Foundry one-shot)
EOF

  cat > "${repo}/README.md" <<EOF
# ${tool}

Street Pack utility: \`${tool}\`

## Install
\`\`\`bash
./install.sh
\`\`\`

## Uninstall
\`\`\`bash
./uninstall.sh
\`\`\`

## Help
\`\`\`bash
${tool} --help
\`\`\`
EOF

  cat > "${repo}/.gitignore" <<'EOF'
/dist/
/build/
/out/
/tmp/
/.releases/
/.reports/
EOF

  cat > "${repo}/install.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
HERE="\$(cd "\$(dirname "\$0")" && pwd)"
TOOL="${tool}"
DEST="\${HOME}/.local/share/streetpack/tools/\${TOOL}"
BIN="\${HOME}/.local/bin"
mkdir -p "\$DEST" "\$BIN"
rm -rf "\$DEST"
mkdir -p "\$DEST"
cp -a "\$HERE/"* "\$DEST/"
cat > "\$BIN/\$TOOL" <<'WRAP'
#!/usr/bin/env bash
set -euo pipefail
TOOL="${tool}"
HOME_DIR="\${HOME}/.local/share/streetpack/tools/\${TOOL}"
exec "\${HOME_DIR}/\${TOOL}" "\$@"
WRAP
chmod +x "\$BIN/\$TOOL"
echo "[install] \$TOOL -> \$BIN/\$TOOL"
EOF
  chmod +x "${repo}/install.sh"

  cat > "${repo}/uninstall.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
TOOL="${tool}"
DEST="\${HOME}/.local/share/streetpack/tools/\${TOOL}"
BIN="\${HOME}/.local/bin/\${TOOL}"
rm -f "\$BIN"
rm -rf "\$DEST"
echo "[uninstall] \$TOOL removed"
EOF
  chmod +x "${repo}/uninstall.sh"

  cat > "${repo}/tests/smoke.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
HERE="\$(cd "\$(dirname "\$0")/.." && pwd)"
TOOL="${tool}"
BIN="\$HERE/\$TOOL"

bash -n "\$BIN"
"\$BIN" --help >/dev/null
"\$BIN" --version >/dev/null

tmp="\$(mktemp -d)"
trap 'rm -rf "\$tmp"' EXIT

# tool-specific smoke runs
case "\$TOOL" in
  safedel)
    echo "hello" > "\$tmp/a.txt"
    "\$BIN" --dry-run "\$tmp/a.txt" >/dev/null
    ;;
  diffwatch)
    echo "x" > "\$tmp/x.txt"
    "\$BIN" --root "\$tmp" --state "\$tmp/state.txt" >/dev/null
    echo "y" >> "\$tmp/x.txt"
    "\$BIN" --root "\$tmp" --state "\$tmp/state.txt" >/dev/null
    ;;
  dirscope)
    echo "x" > "\$tmp/x.txt"
    "\$BIN" --root "\$tmp" >/dev/null
    ;;
  hashscan)
    echo "x" > "\$tmp/x.txt"
    "\$BIN" --root "\$tmp" --manifest "\$tmp/m.txt" >/dev/null
    "\$BIN" --verify --manifest "\$tmp/m.txt" >/dev/null || true
    ;;
  secretsniff)
    echo "AKIAAAAAAAAAAAAAAAA" > "\$tmp/secret.txt" || true
    "\$BIN" --root "\$tmp" >/dev/null || true
    ;;
  portguard|procwatch)
    "\$BIN" --state "\$tmp/s.txt" >/dev/null || true
    ;;
  logtail+)
    echo "line1" > "\$tmp/l.log"
    "\$BIN" --file "\$tmp/l.log" --lines 1 >/dev/null
    ;;
  netpulse)
    "\$BIN" >/dev/null || true
    ;;
  pathdoctor)
    "\$BIN" >/dev/null || true
    ;;
  bulkrename-safe)
    mkdir -p "\$tmp/r"
    echo "x" > "\$tmp/r/a.txt"
    "\$BIN" --root "\$tmp/r" --prefix "p_" --dry-run >/dev/null
    ;;
  dedupe-lite)
    echo "x" > "\$tmp/a"; echo "x" > "\$tmp/b"
    "\$BIN" --root "\$tmp" >/dev/null || true
    ;;
  envvault)
    "\$BIN" --out "\$tmp/env.json" >/dev/null
    ;;
  runshield)
    "\$BIN" --out "\$tmp/out.txt" -- echo "hi" >/dev/null
    ;;
  packreceipt)
    mkdir -p "\$tmp/r"
    echo "{}" > "\$tmp/r/receipt.json"
    "\$BIN" --src "\$tmp/r" --out "\$tmp/p.tgz" >/dev/null
    ;;
  permcheck)
    "\$BIN" --root "\$tmp" >/dev/null || true
    ;;
esac

echo "[smoke] PASS \$TOOL"
EOF
  chmod +x "${repo}/tests/smoke.sh"
}

# ----------------------------
# Tool scripts
# ----------------------------
write_tool_script() {
  local repo="$1" tool="$2"

  cat > "${repo}/${tool}" <<EOF
#!/usr/bin/env bash
set -euo pipefail

TOOL="${tool}"
VERSION="0.1.0"

HERE="\$(cd "\$(dirname "\$0")" && pwd)"
# shellcheck source=lib/sp_common.sh
source "\$HERE/lib/sp_common.sh"
# shellcheck source=lib/sp_receipt.sh
source "\$HERE/lib/sp_receipt.sh"

SP_ARGV=( "\$@" )

JSON=0
OUT_PATH=""
RECEIPT_DIR=""
DRYRUN=0

help() {
  cat <<'HLP'
${tool} (Street Pack) v0.1.0

Common flags:
  --help, -h        Show help
  --version         Show version
  --json            JSON output
  --out <path>      Write report/output to a file
  --receipt-dir <d> Override receipt directory
  --dry-run         No mutation (only for mutating tools)

Tool-specific usage:
HLP
  case "${tool}" in
    safedel)
      cat <<'X'
  safedel [--dry-run] [--trash-dir <dir>] <path>...

Moves files/dirs into a safe local trash area (no rm).
X
      ;;
    diffwatch)
      cat <<'X'
  diffwatch --root <dir> --state <file> [--out <path>] [--json]

Creates/updates a hash manifest state file and reports changes vs previous state.
X
      ;;
    dirscope)
      cat <<'X'
  dirscope --root <dir> [--out <path>] [--json]

Directory inventory: counts, bytes, top-largest, ext histogram.
X
      ;;
    hashscan)
      cat <<'X'
  hashscan --root <dir> [--manifest <file>] [--out <path>] [--json]
  hashscan --verify --manifest <file> [--out <path>] [--json]

Create or verify sha256 manifests.
X
      ;;
    secretsniff)
      cat <<'X'
  secretsniff --root <dir> [--max-bytes <n>] [--out <path>] [--json]

Find common secret patterns (defensive scanning). No network.
X
      ;;
    permcheck)
      cat <<'X'
  permcheck --root <dir> [--out <path>] [--json]

Find risky perms: world-writable, SUID/SGID, insecure PATH dirs.
X
      ;;
    portguard)
      cat <<'X'
  portguard --state <file> [--out <path>] [--json]

Baselines listening sockets and diffs drift.
X
      ;;
    procwatch)
      cat <<'X'
  procwatch --state <file> [--out <path>] [--json]

Baselines process list and diffs drift.
X
      ;;
    logtail+)
      cat <<'X'
  logtail+ --file <path> [--lines <n>] [--grep <pattern>] [--out <path>] [--json]

Tail with optional filter.
X
      ;;
    netpulse)
      cat <<'X'
  netpulse [--ping <host>] [--out <path>] [--json]

Local network snapshot; optional ping if requested.
X
      ;;
    pathdoctor)
      cat <<'X'
  pathdoctor [--out <path>] [--json]

PATH sanity: missing entries, duplicates, insecure perms (world-writable).
X
      ;;
    bulkrename-safe)
      cat <<'X'
  bulkrename-safe --root <dir> (--prefix <p> | --suffix <s> | --regex <re> --replace <r>) [--dry-run] [--out <path>] [--json]

Batch rename safely (no overwrite; receipts).
X
      ;;
    dedupe-lite)
      cat <<'X'
  dedupe-lite --root <dir> [--out <path>] [--json]

Find duplicates by size+sha256 (reports groups).
X
      ;;
    envvault)
      cat <<'X'
  envvault [--out <path>] [--json]

Export env snapshot with basic redaction of sensitive keys.
X
      ;;
    runshield)
      cat <<'X'
  runshield [--timeout <sec>] [--out <path>] [--json] -- <command> [args...]

Run a command with capture + best-effort timeout + receipts.
X
      ;;
    packreceipt)
      cat <<'X'
  packreceipt --src <dir> --out <file.tgz> [--json]

Create a tar.gz evidence pack from a directory (typically receipts).
X
      ;;
  esac
}

if [[ "\${1:-}" == "--version" ]]; then
  echo "\${TOOL} \${VERSION}"
  exit 0
fi

# Parse common flags
ARGS=()
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -h|--help) help; exit 0;;
    --json) JSON=1; shift;;
    --out) OUT_PATH="\${2:-}"; shift 2;;
    --receipt-dir) RECEIPT_DIR="\${2:-}"; shift 2;;
    --dry-run) DRYRUN=1; shift;;
    *) ARGS+=( "\$1" ); shift;;
  esac
done

start="\${EPOCHREALTIME:-}"

# Defaults
if [[ -z "\$RECEIPT_DIR" ]]; then
  RECEIPT_DIR="\$(sp_receipt_dir_default "\$TOOL")"
fi

emit_out() {
  local s="\$1"
  if [[ -n "\$OUT_PATH" ]]; then
    printf '%s\n' "\$s" > "\$OUT_PATH"
  else
    printf '%s\n' "\$s"
  fi
}

emit_json() {
  local json="\$1"
  if [[ -n "\$OUT_PATH" ]]; then
    printf '%s\n' "\$json" > "\$OUT_PATH"
  else
    printf '%s\n' "\$json"
  fi
}

# -----------------------
# Tool implementations
# -----------------------
RESULT="ok"
SUMMARY='{}'
EXTRA=""

case "\$TOOL" in
  safedel)
    TRASH_DIR="\${HOME}/.local/share/streetpack/trash/\$(sp_stamp)"
    i=0
    while [[ \$i -lt \${#ARGS[@]} ]]; do
      case "\${ARGS[\$i]}" in
        --trash-dir) TRASH_DIR="\${ARGS[\$((i+1))]:-}"; i=\$((i+2));;
        *) break;;
      esac
    done
    PATHS=( "\${ARGS[@]:\$i}" )
    [[ \${#PATHS[@]} -gt 0 ]] || sp_die "safedel: provide at least one path"

    sp_mkdirp "\$TRASH_DIR"
    moved=0 skipped=0
    details=""
    for p in "\${PATHS[@]}"; do
      if [[ ! -e "\$p" ]]; then
        skipped=\$((skipped+1))
        details+="missing:\$(sp_json_escape "\$p")\n"
        continue
      fi
      base="\$(basename "\$p")"
      dest="\$TRASH_DIR/\$base"
      n=0
      while [[ -e "\$dest" ]]; do
        n=\$((n+1))
        dest="\$TRASH_DIR/\${base}.\$n"
      done
      if [[ "\$DRYRUN" -eq 1 ]]; then
        : # no-op
      else
        mv -- "\$p" "\$dest"
      fi
      moved=\$((moved+1))
    done
    SUMMARY="{\"moved\":\$moved,\"skipped\":\$skipped,\"dry_run\":\$DRYRUN,\"trash_dir\":\"\$(sp_json_escape "\$TRASH_DIR")\"}"
    if [[ "\$JSON" -eq 1 ]]; then
      emit_json "{ \"tool\":\"\$TOOL\",\"result\":\"\$RESULT\",\"summary\":\$SUMMARY }"
    else
      emit_out "moved=\$moved skipped=\$skipped dry_run=\$DRYRUN trash_dir=\$TRASH_DIR"
    fi
    ;;

  diffwatch)
    ROOT=""
    STATE=""
    i=0
    while [[ \$i -lt \${#ARGS[@]} ]]; do
      case "\${ARGS[\$i]}" in
        --root) ROOT="\${ARGS[\$((i+1))]:-}"; i=\$((i+2));;
        --state) STATE="\${ARGS[\$((i+1))]:-}"; i=\$((i+2));;
        *) sp_die "diffwatch: unknown arg \${ARGS[\$i]}";;
      esac
    done
    [[ -n "\$ROOT" && -n "\$STATE" ]] || sp_die "diffwatch: --root and --state required"
    [[ -d "\$ROOT" ]] || sp_die "diffwatch: root not a dir: \$ROOT"

    tmp="\$(mktemp)"
    trap 'rm -f "\$tmp"' EXIT

    # Manifest format: path<TAB>sha256<TAB>bytes<TAB>mtime_epoch
    while IFS= read -r -d '' f; do
      rel="\${f#\$ROOT/}"
      bytes="\$(stat -c %s "\$f" 2>/dev/null || wc -c <"\$f")"
      mtime="\$(stat -c %Y "\$f" 2>/dev/null || echo 0)"
      sha="\$(sha256sum "\$f" | awk '{print \$1}')"
      printf '%s\t%s\t%s\t%s\n' "\$rel" "\$sha" "\$bytes" "\$mtime" >> "\$tmp"
    done < <(find "\$ROOT" -type f -print0 | sort -z)

    added=0 removed=0 changed=0
    report=""
    if [[ -f "\$STATE" ]]; then
      # compare with previous
      awk -F'\t' '
        NR==FNR { old[\$1]=\$2 "\t" \$3 "\t" \$4; next }
        {
          new[\$1]=\$2 "\t" \$3 "\t" \$4
        }
        END{
          for (k in old) {
            if (!(k in new)) print "REMOVED\t" k
            else if (old[k] != new[k]) print "CHANGED\t" k
          }
          for (k in new) {
            if (!(k in old)) print "ADDED\t" k
          }
        }
      ' "\$STATE" "\$tmp" | while IFS=$'\t' read -r kind path; do
        case "\$kind" in
          ADDED) added=\$((added+1));;
          REMOVED) removed=\$((removed+1));;
          CHANGED) changed=\$((changed+1));;
        esac
        report+="\$kind\t\$path\n"
      done
    else
      report="(no prior state)\n"
    fi

    mkdir -p "\$(dirname "\$STATE")"
    cp "\$tmp" "\$STATE"

    SUMMARY="{\"added\":\$added,\"removed\":\$removed,\"changed\":\$changed,\"state\":\"\$(sp_json_escape "\$STATE")\"}"
    if [[ \$((added+removed+changed)) -gt 0 ]]; then
      RESULT="findings"
    fi
    if [[ "\$JSON" -eq 1 ]]; then
      emit_json "{ \"tool\":\"\$TOOL\",\"result\":\"\$RESULT\",\"summary\":\$SUMMARY }"
    else
      printf '%b' "\$report" | ( [[ -n "\$OUT_PATH" ]] && cat > "\$OUT_PATH" || cat )
      echo "added=\$added removed=\$removed changed=\$changed state=\$STATE"
    fi
    ;;

  dirscope)
    ROOT=""
    i=0
    while [[ \$i -lt \${#ARGS[@]} ]]; do
      case "\${ARGS[\$i]}" in
        --root) ROOT="\${ARGS[\$((i+1))]:-}"; i=\$((i+2));;
        *) sp_die "dirscope: unknown arg \${ARGS[\$i]}";;
      esac
    done
    [[ -n "\$ROOT" ]] || sp_die "dirscope: --root required"
    [[ -d "\$ROOT" ]] || sp_die "dirscope: root not a dir: \$ROOT"

    files="\$(find "\$ROOT" -type f | wc -l | tr -d ' ')"
    bytes="\$(du -sb "\$ROOT" 2>/dev/null | awk '{print \$1}' || echo 0)"
    top="\$(find "\$ROOT" -type f -printf '%s\t%p\n' 2>/dev/null | sort -nr | head -n 10 || true)"
    exts="\$(find "\$ROOT" -type f -printf '%f\n' 2>/dev/null | awk -F. 'NF>1{print tolower(\$NF)}' | sort | uniq -c | sort -nr | head -n 12 || true)"

    SUMMARY="{\"files\":\$files,\"bytes\":\$bytes}"
    if [[ "\$JSON" -eq 1 ]]; then
      emit_json "{ \"tool\":\"\$TOOL\",\"result\":\"\$RESULT\",\"summary\":\$SUMMARY }"
    else
      out="files=\$files bytes=\$bytes\n\nTop 10 largest:\n\$top\n\nTop extensions:\n\$exts\n"
      printf '%b' "\$out" | ( [[ -n "\$OUT_PATH" ]] && cat > "\$OUT_PATH" || cat )
    fi
    ;;

  hashscan)
    ROOT=""
    MANIFEST=""
    VERIFY=0
    i=0
    while [[ \$i -lt \${#ARGS[@]} ]]; do
      case "\${ARGS[\$i]}" in
        --root) ROOT="\${ARGS[\$((i+1))]:-}"; i=\$((i+2));;
        --manifest) MANIFEST="\${ARGS[\$((i+1))]:-}"; i=\$((i+2));;
        --verify) VERIFY=1; i=\$((i+1));;
        *) sp_die "hashscan: unknown arg \${ARGS[\$i]}";;
      esac
    done

    if [[ "\$VERIFY" -eq 1 ]]; then
      [[ -n "\$MANIFEST" ]] || sp_die "hashscan: --verify requires --manifest"
      [[ -f "\$MANIFEST" ]] || sp_die "hashscan: manifest missing: \$MANIFEST"
      bad=0 ok=0
      while IFS= read -r line; do
        [[ -n "\$line" ]] || continue
        sha="\$(echo "\$line" | awk '{print \$1}')"
        path="\$(echo "\$line" | cut -d' ' -f2-)"
        if [[ ! -f "\$path" ]]; then
          bad=\$((bad+1))
          continue
        fi
        cur="\$(sha256sum "\$path" | awk '{print \$1}')"
        if [[ "\$cur" == "\$sha" ]]; then ok=\$((ok+1)); else bad=\$((bad+1)); fi
      done < "\$MANIFEST"
      SUMMARY="{\"ok\":\$ok,\"bad\":\$bad,\"manifest\":\"\$(sp_json_escape "\$MANIFEST")\"}"
      if [[ "\$bad" -gt 0 ]]; then RESULT="findings"; fi
      if [[ "\$JSON" -eq 1 ]]; then
        emit_json "{ \"tool\":\"\$TOOL\",\"result\":\"\$RESULT\",\"summary\":\$SUMMARY }"
      else
        emit_out "ok=\$ok bad=\$bad manifest=\$MANIFEST"
      fi
    else
      [[ -n "\$ROOT" ]] || sp_die "hashscan: --root required (or use --verify)"
      [[ -d "\$ROOT" ]] || sp_die "hashscan: root not a dir: \$ROOT"
      if [[ -z "\$MANIFEST" ]]; then
        MANIFEST="\${OUT_PATH:-}"
      fi

      tmp="\$(mktemp)"
      trap 'rm -f "\$tmp"' EXIT

      while IFS= read -r -d '' f; do
        sha256sum "\$f" >> "\$tmp"
      done < <(find "\$ROOT" -type f -print0 | sort -z)

      if [[ -n "\$MANIFEST" ]]; then
        cp "\$tmp" "\$MANIFEST"
        OUT_PATH="\$MANIFEST"
      fi
      count="\$(wc -l < "\$tmp" | tr -d ' ')"
      SUMMARY="{\"count\":\$count,\"root\":\"\$(sp_json_escape "\$ROOT")\",\"manifest\":\"\$(sp_json_escape "\${MANIFEST:-}")\"}"
      if [[ "\$JSON" -eq 1 ]]; then
        emit_json "{ \"tool\":\"\$TOOL\",\"result\":\"\$RESULT\",\"summary\":\$SUMMARY }"
      else
        if [[ -n "\$OUT_PATH" ]]; then
          : # already written
          emit_out "wrote manifest: \$OUT_PATH (count=\$count)"
        else
          cat "\$tmp"
        fi
      fi
    fi
    ;;

  secretsniff)
    ROOT=""
    MAXB=2097152
    i=0
    while [[ \$i -lt \${#ARGS[@]} ]]; do
      case "\${ARGS[\$i]}" in
        --root) ROOT="\${ARGS[\$((i+1))]:-}"; i=\$((i+2));;
        --max-bytes) MAXB="\${ARGS[\$((i+1))]:-}"; i=\$((i+2));;
        *) sp_die "secretsniff: unknown arg \${ARGS[\$i]}";;
      esac
    done
    [[ -n "\$ROOT" ]] || sp_die "secretsniff: --root required"
    [[ -d "\$ROOT" ]] || sp_die "secretsniff: root not a dir: \$ROOT"

    patterns=(
      'AKIA[0-9A-Z]{16}'                # AWS access key id (common form)
      '-----BEGIN ([A-Z ]+)?PRIVATE KEY-----'
      'ghp_[A-Za-z0-9]{20,}'            # GitHub PAT
      'xox[baprs]-[A-Za-z0-9-]{10,}'    # Slack tokens
      'AIza[0-9A-Za-z\\-_]{20,}'        # Google API key
      'sk_live_[0-9a-zA-Z]{20,}'        # Stripe live key (common)
    )

    hits=0 files_scanned=0
    report=""

    while IFS= read -r -d '' f; do
      # basic excludes
      case "\$f" in
        */.git/*|*/node_modules/*|*/vendor/*|*/dist/*|*/build/*) continue;;
      esac
      bytes="\$(stat -c %s "\$f" 2>/dev/null || wc -c <"\$f")"
      [[ "\$bytes" -le "\$MAXB" ]] || continue
      sp_text_file "\$f" || continue

      files_scanned=\$((files_scanned+1))
      for re in "\${patterns[@]}"; do
        if grep -E -n -m 1 "\$re" "\$f" >/dev/null 2>&1; then
          hits=\$((hits+1))
          report+="HIT\t\$(sp_json_escape "\$re")\t\$(sp_json_escape "\$f")\n"
        fi
      done
    done < <(find "\$ROOT" -type f -print0)

    SUMMARY="{\"files_scanned\":\$files_scanned,\"hits\":\$hits}"
    if [[ "\$hits" -gt 0 ]]; then RESULT="findings"; fi

    if [[ "\$JSON" -eq 1 ]]; then
      emit_json "{ \"tool\":\"\$TOOL\",\"result\":\"\$RESULT\",\"summary\":\$SUMMARY }"
    else
      if [[ -n "\$report" ]]; then
        printf '%b' "\$report" | ( [[ -n "\$OUT_PATH" ]] && cat > "\$OUT_PATH" || cat )
      else
        emit_out "no hits (files_scanned=\$files_scanned)"
      fi
    fi
    ;;

  permcheck)
    ROOT=""
    i=0
    while [[ \$i -lt \${#ARGS[@]} ]]; do
      case "\${ARGS[\$i]}" in
        --root) ROOT="\${ARGS[\$((i+1))]:-}"; i=\$((i+2));;
        *) sp_die "permcheck: unknown arg \${ARGS[\$i]}";;
      esac
    done
    [[ -n "\$ROOT" ]] || sp_die "permcheck: --root required"
    [[ -d "\$ROOT" ]] || sp_die "permcheck: root not a dir: \$ROOT"

    ww="\$(find "\$ROOT" -xdev -perm -0002 -type f -o -type d 2>/dev/null | wc -l | tr -d ' ')"
    suid="\$(find "\$ROOT" -xdev -perm -4000 -type f 2>/dev/null | wc -l | tr -d ' ')"
    sgid="\$(find "\$ROOT" -xdev -perm -2000 -type f 2>/dev/null | wc -l | tr -d ' ')"
    insecure_path=0
    IFS=':' read -r -a pe <<< "\${PATH:-}"
    for d in "\${pe[@]}"; do
      [[ -d "\$d" ]] || continue
      if [[ -w "\$d" ]] && find "\$d" -maxdepth 0 -perm -0002 >/dev/null 2>&1; then
        insecure_path=\$((insecure_path+1))
      fi
    done

    findings=\$((ww + suid + sgid + insecure_path))
    if [[ "\$findings" -gt 0 ]]; then RESULT="findings"; fi

    SUMMARY="{\"world_writable\":\$ww,\"suid\":\$suid,\"sgid\":\$sgid,\"insecure_path_dirs\":\$insecure_path}"
    if [[ "\$JSON" -eq 1 ]]; then
      emit_json "{ \"tool\":\"\$TOOL\",\"result\":\"\$RESULT\",\"summary\":\$SUMMARY }"
    else
      emit_out "world_writable=\$ww suid=\$suid sgid=\$sgid insecure_path_dirs=\$insecure_path"
    fi
    ;;

  portguard)
    STATE=""
    i=0
    while [[ \$i -lt \${#ARGS[@]} ]]; do
      case "\${ARGS[\$i]}" in
        --state) STATE="\${ARGS[\$((i+1))]:-}"; i=\$((i+2));;
        *) sp_die "portguard: unknown arg \${ARGS[\$i]}";;
      esac
    done
    [[ -n "\$STATE" ]] || sp_die "portguard: --state required"

    tmp="\$(mktemp)"
    trap 'rm -f "\$tmp"' EXIT

    if sp_has ss; then
      ss -lntup 2>/dev/null | sed 's/[[:space:]]\\+/ /g' > "\$tmp" || true
    elif sp_has netstat; then
      netstat -tulpn 2>/dev/null > "\$tmp" || true
    else
      sp_die "portguard: needs ss or netstat"
    fi

    drift=0
    if [[ -f "\$STATE" ]]; then
      if ! diff -u "\$STATE" "\$tmp" >/dev/null 2>&1; then
        drift=1
      fi
    fi
    mkdir -p "\$(dirname "\$STATE")"
    cp "\$tmp" "\$STATE"

    SUMMARY="{\"drift\":\$drift,\"state\":\"\$(sp_json_escape "\$STATE")\"}"
    if [[ "\$drift" -eq 1 ]]; then RESULT="findings"; fi
    if [[ "\$JSON" -eq 1 ]]; then
      emit_json "{ \"tool\":\"\$TOOL\",\"result\":\"\$RESULT\",\"summary\":\$SUMMARY }"
    else
      emit_out "state=\$STATE drift=\$drift"
    fi
    ;;

  procwatch)
    STATE=""
    i=0
    while [[ \$i -lt \${#ARGS[@]} ]]; do
      case "\${ARGS[\$i]}" in
        --state) STATE="\${ARGS[\$((i+1))]:-}"; i=\$((i+2));;
        *) sp_die "procwatch: unknown arg \${ARGS[\$i]}";;
      esac
    done
    [[ -n "\$STATE" ]] || sp_die "procwatch: --state required"

    tmp="\$(mktemp)"
    trap 'rm -f "\$tmp"' EXIT
    ps auxww 2>/dev/null | sed '1d' | sort > "\$tmp" || true

    drift=0
    if [[ -f "\$STATE" ]]; then
      if ! diff -u "\$STATE" "\$tmp" >/dev/null 2>&1; then
        drift=1
      fi
    fi
    mkdir -p "\$(dirname "\$STATE")"
    cp "\$tmp" "\$STATE"

    SUMMARY="{\"drift\":\$drift,\"state\":\"\$(sp_json_escape "\$STATE")\"}"
    if [[ "\$drift" -eq 1 ]]; then RESULT="findings"; fi
    if [[ "\$JSON" -eq 1 ]]; then
      emit_json "{ \"tool\":\"\$TOOL\",\"result\":\"\$RESULT\",\"summary\":\$SUMMARY }"
    else
      emit_out "state=\$STATE drift=\$drift"
    fi
    ;;

  logtail+)
    FILE=""
    LINES=100
    GREP_RE=""
    i=0
    while [[ \$i -lt \${#ARGS[@]} ]]; do
      case "\${ARGS[\$i]}" in
        --file) FILE="\${ARGS[\$((i+1))]:-}"; i=\$((i+2));;
        --lines) LINES="\${ARGS[\$((i+1))]:-}"; i=\$((i+2));;
        --grep) GREP_RE="\${ARGS[\$((i+1))]:-}"; i=\$((i+2));;
        *) sp_die "logtail+: unknown arg \${ARGS[\$i]}";;
      esac
    done
    [[ -n "\$FILE" ]] || sp_die "logtail+: --file required"
    [[ -f "\$FILE" ]] || sp_die "logtail+: file missing: \$FILE"

    data="\$(tail -n "\$LINES" "\$FILE" 2>/dev/null || true)"
    if [[ -n "\$GREP_RE" ]]; then
      data="\$(printf '%s\n' "\$data" | grep -E "\$GREP_RE" || true)"
    fi
    SUMMARY="{\"file\":\"\$(sp_json_escape "\$FILE")\",\"lines\":\$LINES}"
    if [[ "\$JSON" -eq 1 ]]; then
      emit_json "{ \"tool\":\"\$TOOL\",\"result\":\"\$RESULT\",\"summary\":\$SUMMARY }"
    else
      ( [[ -n "\$OUT_PATH" ]] && printf '%s\n' "\$data" > "\$OUT_PATH" || printf '%s\n' "\$data" )
    fi
    ;;

  netpulse)
    PING_HOST=""
    i=0
    while [[ \$i -lt \${#ARGS[@]} ]]; do
      case "\${ARGS[\$i]}" in
        --ping) PING_HOST="\${ARGS[\$((i+1))]:-}"; i=\$((i+2));;
        *) sp_die "netpulse: unknown arg \${ARGS[\$i]}";;
      esac
    done

    snap=""
    if sp_has ip; then
      snap+="## ip addr\n\$(ip addr 2>/dev/null)\n\n## ip route\n\$(ip route 2>/dev/null)\n\n"
    fi
    if [[ -f /etc/resolv.conf ]]; then
      snap+="## resolv.conf\n\$(cat /etc/resolv.conf)\n\n"
    fi
    if [[ -n "\$PING_HOST" ]]; then
      if sp_has ping; then
        snap+="## ping \$PING_HOST\n\$(ping -c 2 "\$PING_HOST" 2>/dev/null || true)\n"
      else
        snap+="(ping not available)\n"
      fi
    fi

    SUMMARY="{\"ping\":\"\$(sp_json_escape "\$PING_HOST")\"}"
    if [[ "\$JSON" -eq 1 ]]; then
      emit_json "{ \"tool\":\"\$TOOL\",\"result\":\"\$RESULT\",\"summary\":\$SUMMARY }"
    else
      printf '%b' "\$snap" | ( [[ -n "\$OUT_PATH" ]] && cat > "\$OUT_PATH" || cat )
    fi
    ;;

  pathdoctor)
    missing=0 dup=0 insecure=0 total=0
    declare -A seen
    IFS=':' read -r -a pe <<< "\${PATH:-}"
    for d in "\${pe[@]}"; do
      [[ -n "\$d" ]] || continue
      total=\$((total+1))
      if [[ -n "\${seen[\$d]:-}" ]]; then dup=\$((dup+1)); else seen[\$d]=1; fi
      if [[ ! -d "\$d" ]]; then missing=\$((missing+1)); continue; fi
      if find "\$d" -maxdepth 0 -perm -0002 >/dev/null 2>&1; then insecure=\$((insecure+1)); fi
    done
    findings=\$((missing+dup+insecure))
    if [[ "\$findings" -gt 0 ]]; then RESULT="findings"; fi
    SUMMARY="{\"total\":\$total,\"missing\":\$missing,\"duplicates\":\$dup,\"world_writable\":\$insecure}"
    if [[ "\$JSON" -eq 1 ]]; then
      emit_json "{ \"tool\":\"\$TOOL\",\"result\":\"\$RESULT\",\"summary\":\$SUMMARY }"
    else
      emit_out "total=\$total missing=\$missing duplicates=\$dup world_writable=\$insecure"
    fi
    ;;

  bulkrename-safe)
    ROOT=""
    PREFIX=""
    SUFFIX=""
    REGEX=""
    REPL=""
    i=0
    while [[ \$i -lt \${#ARGS[@]} ]]; do
      case "\${ARGS[\$i]}" in
        --root) ROOT="\${ARGS[\$((i+1))]:-}"; i=\$((i+2));;
        --prefix) PREFIX="\${ARGS[\$((i+1))]:-}"; i=\$((i+2));;
        --suffix) SUFFIX="\${ARGS[\$((i+1))]:-}"; i=\$((i+2));;
        --regex) REGEX="\${ARGS[\$((i+1))]:-}"; i=\$((i+2));;
        --replace) REPL="\${ARGS[\$((i+1))]:-}"; i=\$((i+2));;
        *) sp_die "bulkrename-safe: unknown arg \${ARGS[\$i]}";;
      esac
    done
    [[ -n "\$ROOT" ]] || sp_die "bulkrename-safe: --root required"
    [[ -d "\$ROOT" ]] || sp_die "bulkrename-safe: root not a dir: \$ROOT"
    if [[ -z "\$PREFIX" && -z "\$SUFFIX" && -z "\$REGEX" ]]; then
      sp_die "bulkrename-safe: need --prefix or --suffix or --regex/--replace"
    fi
    if [[ -n "\$REGEX" && -z "\$REPL" ]]; then
      sp_die "bulkrename-safe: --regex requires --replace"
    fi

    renamed=0 skipped=0
    report=""
    while IFS= read -r -d '' f; do
      base="\$(basename "\$f")"
      dir="\$(dirname "\$f")"
      new="\$base"
      if [[ -n "\$PREFIX" ]]; then new="\${PREFIX}\${new}"; fi
      if [[ -n "\$SUFFIX" ]]; then new="\${new}\${SUFFIX}"; fi
      if [[ -n "\$REGEX" ]]; then new="\$(printf '%s' "\$new" | sed -E "s/\$REGEX/\$REPL/g")"; fi
      if [[ "\$new" == "\$base" ]]; then continue; fi
      dest="\$dir/\$new"
      if [[ -e "\$dest" ]]; then
        skipped=\$((skipped+1))
        report+="SKIP\t\$(sp_json_escape "\$f")\t\$(sp_json_escape "\$dest")\n"
        continue
      fi
      if [[ "\$DRYRUN" -eq 0 ]]; then
        mv -n -- "\$f" "\$dest"
      fi
      renamed=\$((renamed+1))
      report+="REN\t\$(sp_json_escape "\$f")\t\$(sp_json_escape "\$dest")\n"
    done < <(find "\$ROOT" -maxdepth 1 -type f -print0)

    SUMMARY="{\"renamed\":\$renamed,\"skipped\":\$skipped,\"dry_run\":\$DRYRUN}"
    if [[ "\$skipped" -gt 0 ]]; then RESULT="findings"; fi
    if [[ "\$JSON" -eq 1 ]]; then
      emit_json "{ \"tool\":\"\$TOOL\",\"result\":\"\$RESULT\",\"summary\":\$SUMMARY }"
    else
      printf '%b' "\$report" | ( [[ -n "\$OUT_PATH" ]] && cat > "\$OUT_PATH" || cat )
      echo "renamed=\$renamed skipped=\$skipped dry_run=\$DRYRUN"
    fi
    ;;

  dedupe-lite)
    ROOT=""
    i=0
    while [[ \$i -lt \${#ARGS[@]} ]]; do
      case "\${ARGS[\$i]}" in
        --root) ROOT="\${ARGS[\$((i+1))]:-}"; i=\$((i+2));;
        *) sp_die "dedupe-lite: unknown arg \${ARGS[\$i]}";;
      esac
    done
    [[ -n "\$ROOT" ]] || sp_die "dedupe-lite: --root required"
    [[ -d "\$ROOT" ]] || sp_die "dedupe-lite: root not a dir: \$ROOT"

    tmp="\$(mktemp)"
    trap 'rm -f "\$tmp"' EXIT

    # size|path
    find "\$ROOT" -type f -printf '%s\t%p\n' 2>/dev/null | sort -n > "\$tmp" || true

    groups=0 dups=0
    report=""
    last_size=""
    bucket=""
    while IFS=$'\t' read -r sz p; do
      if [[ "\$sz" != "\$last_size" ]]; then
        # process bucket
        if [[ -n "\$bucket" ]]; then
          cnt="\$(printf '%b' "\$bucket" | wc -l | tr -d ' ')"
          if [[ "\$cnt" -gt 1 ]]; then
            # hash bucket
            declare -A hmap=()
            while IFS= read -r bp; do
              h="\$(sha256sum "\$bp" | awk '{print \$1}')"
              hmap["\$h"]="\${hmap[\$h]:-}\$bp\n"
            done < <(printf '%b' "\$bucket")
            for h in "\${!hmap[@]}"; do
              c2="\$(printf '%b' "\${hmap[\$h]}" | wc -l | tr -d ' ')"
              if [[ "\$c2" -gt 1 ]]; then
                groups=\$((groups+1))
                dups=\$((dups + c2))
                report+="GROUP\t\$h\n\${hmap[\$h]}\n"
              fi
            done
          fi
        fi
        bucket=""
        last_size="\$sz"
      fi
      bucket+="\$p\n"
    done < "\$tmp"

    if [[ "\$groups" -gt 0 ]]; then RESULT="findings"; fi
    SUMMARY="{\"groups\":\$groups,\"dup_files\":\$dups}"
    if [[ "\$JSON" -eq 1 ]]; then
      emit_json "{ \"tool\":\"\$TOOL\",\"result\":\"\$RESULT\",\"summary\":\$SUMMARY }"
    else
      if [[ -n "\$report" ]]; then
        printf '%b' "\$report" | ( [[ -n "\$OUT_PATH" ]] && cat > "\$OUT_PATH" || cat )
      else
        emit_out "no duplicates found"
      fi
    fi
    ;;

  envvault)
    # basic env export with redaction
    outfile="\${OUT_PATH:-\${HOME}/.local/share/streetpack/envvault/env.\$(sp_stamp).json}"
    mkdir -p "\$(dirname "\$outfile")"
    redacted=0
    {
      echo "{"
      first=1
      while IFS='=' read -r k v; do
        [[ -n "\$k" ]] || continue
        vv="\$v"
        if echo "\$k" | grep -Eqi '(PASS|TOKEN|SECRET|KEY|AUTH|COOKIE)'; then
          vv="***"
          redacted=\$((redacted+1))
        fi
        if [[ "\$first" -eq 0 ]]; then echo ","; fi
        first=0
        printf '  "%s": "%s"' "\$(sp_json_escape "\$k")" "\$(sp_json_escape "\$vv")"
      done < <(env)
      echo
      echo "}"
    } > "\$outfile"
    SUMMARY="{\"out\":\"\$(sp_json_escape "\$outfile")\",\"redacted\":\$redacted}"
    if [[ "\$JSON" -eq 1 ]]; then
      emit_json "{ \"tool\":\"\$TOOL\",\"result\":\"\$RESULT\",\"summary\":\$SUMMARY }"
    else
      emit_out "wrote: \$outfile (redacted=\$redacted)"
    fi
    OUT_PATH="\$outfile"
    ;;

  runshield)
    TIMEOUT=0
    # parse until --
    cmd=()
    i=0
    while [[ \$i -lt \${#ARGS[@]} ]]; do
      if [[ "\${ARGS[\$i]}" == "--" ]]; then
        cmd=( "\${ARGS[@]:\$((i+1))}" )
        break
      fi
      case "\${ARGS[\$i]}" in
        --timeout) TIMEOUT="\${ARGS[\$((i+1))]:-}"; i=\$((i+2));;
        *) sp_die "runshield: unknown arg \${ARGS[\$i]}";;
      esac
    done
    [[ \${#cmd[@]} -gt 0 ]] || sp_die "runshield: provide command after --"

    out="\${OUT_PATH:-\${HOME}/.local/share/streetpack/runshield/run.\$(sp_stamp).log}"
    mkdir -p "\$(dirname "\$out")"

    if [[ "\$DRYRUN" -eq 1 ]]; then
      echo "[dry-run] would run: \${cmd[*]}" > "\$out"
      rc=0
    else
      if [[ "\$TIMEOUT" -gt 0 ]] && sp_has timeout; then
        timeout "\$TIMEOUT" "\${cmd[@]}" > "\$out" 2>&1 || rc=\$?
      else
        "\${cmd[@]}" > "\$out" 2>&1 || rc=\$?
      fi
      rc="\${rc:-0}"
    fi

    SUMMARY="{\"rc\":\$rc,\"out\":\"\$(sp_json_escape "\$out")\",\"dry_run\":\$DRYRUN}"
    if [[ "\$rc" -ne 0 ]]; then RESULT="findings"; fi
    if [[ "\$JSON" -eq 1 ]]; then
      emit_json "{ \"tool\":\"\$TOOL\",\"result\":\"\$RESULT\",\"summary\":\$SUMMARY }"
    else
      emit_out "rc=\$rc out=\$out"
    fi
    OUT_PATH="\$out"
    ;;

  packreceipt)
    SRC=""
    OUT=""
    i=0
    while [[ \$i -lt \${#ARGS[@]} ]]; do
      case "\${ARGS[\$i]}" in
        --src) SRC="\${ARGS[\$((i+1))]:-}"; i=\$((i+2));;
        --out) OUT="\${ARGS[\$((i+1))]:-}"; i=\$((i+2));;
        *) sp_die "packreceipt: unknown arg \${ARGS[\$i]}";;
      esac
    done
    [[ -n "\$SRC" && -n "\$OUT" ]] || sp_die "packreceipt: --src and --out required"
    [[ -d "\$SRC" ]] || sp_die "packreceipt: src not a dir: \$SRC"
    mkdir -p "\$(dirname "\$OUT")"

    tmpd="\$(mktemp -d)"
    trap 'rm -rf "\$tmpd"' EXIT

    # Copy source into staging
    cp -a "\$SRC" "\$tmpd/src"

    # Build manifest
    (cd "\$tmpd/src" && find . -type f -print0 | sort -z | xargs -0 sha256sum) > "\$tmpd/SHA256SUMS.txt" 2>/dev/null || true
    {
      echo "Street Pack Evidence Pack"
      echo "UTC: \$(sp_now_utc)"
      echo "SRC: \$SRC"
      echo "FILES:"
      (cd "\$tmpd/src" && find . -type f | sort)
    } > "\$tmpd/MANIFEST.txt"

    # Build tar.gz
    (cd "\$tmpd" && tar -czf "\$OUT" "src" "MANIFEST.txt" "SHA256SUMS.txt")

    SUMMARY="{\"src\":\"\$(sp_json_escape "\$SRC")\",\"out\":\"\$(sp_json_escape "\$OUT")\"}"
    if [[ "\$JSON" -eq 1 ]]; then
      emit_json "{ \"tool\":\"\$TOOL\",\"result\":\"\$RESULT\",\"summary\":\$SUMMARY }"
    else
      emit_out "packed: \$OUT"
    fi
    OUT_PATH="\$OUT"
    ;;

  *)
    sp_die "tool not implemented: \$TOOL"
    ;;
esac

end="\${EPOCHREALTIME:-}"
elapsed="\$(sp_elapsed_ms "\${start:-0}" "\${end:-0}")"

# Write receipt (always)
receipt_path="\$(sp_write_receipt "\$TOOL" "\$VERSION" "\$RECEIPT_DIR" "\$RESULT" "\$SUMMARY" "\${OUT_PATH:-}" "\${elapsed:-0}" "")" || true
EOF

  chmod +x "${repo}/${tool}"
}

# ----------------------------
# Tools list (your pinned sets)
# ----------------------------
TOOLS=(
  "safedel"
  "diffwatch"
  "dirscope"
  "hashscan"
  "runshield"
  "permcheck"
  "secretsniff"
  "logtail+"
  "portguard"
  "netpulse"
  "procwatch"
  "pathdoctor"
  "bulkrename-safe"
  "dedupe-lite"
  "envvault"
  "packreceipt"
)

# Build each tool repo
for tool in "${TOOLS[@]}"; do
  repo="${FOUNDRY_ROOT}/repos/${tool}"
  mkdir -p "${repo}"
  write_common_libs "${repo}"
  write_repo_boilerplate "${repo}" "${tool}"
  write_tool_script "${repo}" "${tool}"
done

# Friendly finish
echo
echo "[DONE] Foundry created at:"
echo "  ${FOUNDRY_ROOT}"
echo
echo "Next:"
echo "  cd \"${FOUNDRY_ROOT}\""
echo "  ./bootstrap/smoke_all.sh"
echo "  ./install_all.sh"
echo
echo "Test drive:"
echo "  dirscope --root ."
echo "  secretsniff --root ."
echo "  hashscan --root . --manifest /tmp/hashscan.manifest"
echo "  diffwatch --root . --state /tmp/diffwatch.state"
