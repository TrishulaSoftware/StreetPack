#!/usr/bin/env bash
# StreetPack ShipCheck — verify runtime receipts/outputs + repo build junk.
# Bash-only, no deps beyond coreutils/find/du.
set -euo pipefail

APP_NAME="StreetPack ShipCheck"
SPHOME_DEFAULT="${HOME}/.local/share/streetpack"
REPO_DEFAULT="$(pwd)"

usage() {
  cat <<'USAGE'
StreetPack ShipCheck

Usage:
  streetpack_shipcheck.sh [--home <path>] [--repo <path>] [check|clean|paths]

Commands:
  check   (default) show whether receipts/outputs/logs/cache/tmp exist and summarize counts/sizes
  clean   remove runtime artifacts (receipts/outputs/logs/cache/tmp) and repo build junk (egg-info/dist/build/__pycache__/pyc)
  paths   print the resolved paths used for checks

Options:
  --home <path>   override StreetPack data home (default: ~/.local/share/streetpack)
  --repo <path>   override repo path for build-junk scan/clean (default: current directory)

Exit codes:
  0  OK (no runtime artifacts present in check mode; or clean completed)
  10 Runtime artifacts exist (check mode)
  11 Repo build junk exists (check mode)
  12 Both runtime artifacts and repo build junk exist (check mode)
USAGE
}

die(){ echo "ERROR: $*" >&2; exit 2; }

human_du() {
  # best-effort human size; fall back to bytes if du -sh fails
  local p="$1"
  if command -v du >/dev/null 2>&1; then
    du -sh "$p" 2>/dev/null | awk '{print $1}'
  else
    echo "?"
  fi
}

count_files() {
  local p="$1"
  [ -e "$p" ] || { echo "0"; return; }
  find "$p" -type f 2>/dev/null | wc -l | tr -d ' '
}

exists_any() {
  local any=1
  for p in "$@"; do
    if [ -e "$p" ]; then any=0; fi
  done
  return $any
}

scan_repo_junk() {
  local repo="$1"
  local found=0
  # directories
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    echo "$line"
    found=1
  done < <(find "$repo" -maxdepth 6 \( -name '*.egg-info' -o -name dist -o -name build -o -name '__pycache__' -o -name '.pytest_cache' -o -name '.mypy_cache' -o -name '.ruff_cache' \) -print 2>/dev/null || true)

  # files
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    echo "$line"
    found=1
  done < <(find "$repo" -maxdepth 12 -type f \( -name '*.pyc' -o -name '*.pyo' \) -print 2>/dev/null || true)

  return $found
}

cmd_paths() {
  echo "home: $SPHOME"
  echo "repo: $REPO"
}

cmd_check() {
  echo "== $APP_NAME =="
  echo "home: $SPHOME"
  echo "repo: $REPO"
  echo

  local r_receipts="$SPHOME/receipts"
  local r_outputs="$SPHOME/outputs"
  local r_logs="$SPHOME/logs"
  local r_tmp="$SPHOME/tmp"
  local r_cache="$SPHOME/cache"

  echo "== Runtime artifacts (StreetPack data home) =="
  printf "receipts: %s\n" "$r_receipts"
  printf "  exists: %s | files: %s | size: %s\n" \
    "$( [ -e "$r_receipts" ] && echo yes || echo no )" \
    "$(count_files "$r_receipts")" \
    "$( [ -e "$r_receipts" ] && human_du "$r_receipts" || echo 0 )"

  printf "outputs:  %s\n" "$r_outputs"
  printf "  exists: %s | files: %s | size: %s\n" \
    "$( [ -e "$r_outputs" ] && echo yes || echo no )" \
    "$(count_files "$r_outputs")" \
    "$( [ -e "$r_outputs" ] && human_du "$r_outputs" || echo 0 )"

  printf "logs:     %s\n" "$r_logs"
  printf "  exists: %s | files: %s | size: %s\n" \
    "$( [ -e "$r_logs" ] && echo yes || echo no )" \
    "$(count_files "$r_logs")" \
    "$( [ -e "$r_logs" ] && human_du "$r_logs" || echo 0 )"

  printf "tmp:      %s\n" "$r_tmp"
  printf "  exists: %s | files: %s | size: %s\n" \
    "$( [ -e "$r_tmp" ] && echo yes || echo no )" \
    "$(count_files "$r_tmp")" \
    "$( [ -e "$r_tmp" ] && human_du "$r_tmp" || echo 0 )"

  printf "cache:    %s\n" "$r_cache"
  printf "  exists: %s | files: %s | size: %s\n" \
    "$( [ -e "$r_cache" ] && echo yes || echo no )" \
    "$(count_files "$r_cache")" \
    "$( [ -e "$r_cache" ] && human_du "$r_cache" || echo 0 )"

  echo
  echo "== Repo build junk (packaging/caches) =="
  local junk_list
  junk_list="$(scan_repo_junk "$REPO" || true)"
  if [ -n "$junk_list" ]; then
    echo "found:"
    echo "$junk_list"
  else
    echo "found: none"
  fi

  # exit code mapping
  local runtime_exists=0 repo_exists=0
  exists_any "$r_receipts" "$r_outputs" "$r_logs" "$r_tmp" "$r_cache" && runtime_exists=1 || runtime_exists=0
  if [ -n "$junk_list" ]; then repo_exists=1; fi

  if [ "$runtime_exists" -eq 1 ] && [ "$repo_exists" -eq 1 ]; then
    echo; echo "RESULT: runtime artifacts exist + repo junk exists"
    exit 12
  elif [ "$runtime_exists" -eq 1 ]; then
    echo; echo "RESULT: runtime artifacts exist"
    exit 10
  elif [ "$repo_exists" -eq 1 ]; then
    echo; echo "RESULT: repo junk exists"
    exit 11
  else
    echo; echo "RESULT: clean (no runtime artifacts, no repo junk)"
    exit 0
  fi
}

cmd_clean() {
  echo "== CLEAN =="
  echo "home: $SPHOME"
  echo "repo: $REPO"
  echo

  echo "Deleting runtime artifacts under: $SPHOME"
  rm -rf -- "$SPHOME/receipts" "$SPHOME/outputs" "$SPHOME/logs" "$SPHOME/tmp" "$SPHOME/cache" 2>/dev/null || true

  echo "Deleting repo build junk under: $REPO"
  find "$REPO" -maxdepth 6 \( -name '*.egg-info' -o -name dist -o -name build -o -name '__pycache__' -o -name '.pytest_cache' -o -name '.mypy_cache' -o -name '.ruff_cache' \) -print -exec rm -rf -- {} + 2>/dev/null || true
  find "$REPO" -maxdepth 12 -type f \( -name '*.pyc' -o -name '*.pyo' \) -print -delete 2>/dev/null || true

  echo
  echo "Done."
  exit 0
}

# ---- arg parsing ----
SPHOME="$SPHOME_DEFAULT"
REPO="$REPO_DEFAULT"
CMD="check"

while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --home) shift; [ $# -gt 0 ] || die "--home needs a value"; SPHOME="$1" ;;
    --repo) shift; [ $# -gt 0 ] || die "--repo needs a value"; REPO="$1" ;;
    check|clean|paths) CMD="$1" ;;
    *) die "unknown arg: $1 (use --help)" ;;
  esac
  shift
done

# normalize paths
SPHOME="${SPHOME/#\~/$HOME}"
REPO="${REPO/#\~/$HOME}"

case "$CMD" in
  paths) cmd_paths ;;
  check) cmd_check ;;
  clean) cmd_clean ;;
  *) usage; exit 2 ;;
esac
