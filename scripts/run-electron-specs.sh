#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  run-electron-specs.sh [options] [-- spec-runner args]

Options:
  --target <target>       Workspace target, for example 42.
                          Defaults to ELECTRON_WORKSPACE_TARGET when set.
  --src-root <path>       Chromium src root. Defaults to ELECTRON_WORKSPACE_SRC_DIR
                          or <workspace>/<target>/src.
  -h, --help              Show this help.

Examples:
  scripts/run-electron-specs.sh --target 42 -- --runners=main
  scripts/run-electron-specs.sh --target 42 -- --runners=main --grep "webContents"
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR=${BASE_DIR:-"$(cd "$SCRIPT_DIR/.." && pwd)"}
TARGET=${ELECTRON_WORKSPACE_TARGET:-}
SRC_ROOT=${ELECTRON_WORKSPACE_SRC_DIR:-}
SPEC_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET=$2; shift 2 ;;
    --target=*) TARGET=${1#--target=}; shift ;;
    --src-root) SRC_ROOT=$2; shift 2 ;;
    --src-root=*) SRC_ROOT=${1#--src-root=}; shift ;;
    -h|--help) usage; exit 0 ;;
    --)
      shift
      SPEC_ARGS+=("$@")
      break
      ;;
    *)
      SPEC_ARGS+=("$1")
      shift
      ;;
  esac
done

die() {
  echo "error: $*" >&2
  exit 1
}

[[ -n "$TARGET" ]] || die "--target is required, or set ELECTRON_WORKSPACE_TARGET"
if [[ -z "$SRC_ROOT" ]]; then
  SRC_ROOT="$BASE_DIR/$TARGET/src"
fi

ELECTRON_DIR="$SRC_ROOT/electron"
[[ -d "$ELECTRON_DIR" ]] || die "missing Electron checkout: $ELECTRON_DIR"
[[ -f "$ELECTRON_DIR/package.json" ]] || die "missing Electron package.json: $ELECTRON_DIR/package.json"

if [[ "${#SPEC_ARGS[@]}" -eq 0 ]]; then
  SPEC_ARGS=(--runners=main)
fi

has_skip_yarn_install=0
for arg in "${SPEC_ARGS[@]}"; do
  if [[ "$arg" == "--skipYarnInstall" ]]; then
    has_skip_yarn_install=1
    break
  fi
done
if [[ "$has_skip_yarn_install" -eq 0 ]]; then
  SPEC_ARGS=(--skipYarnInstall "${SPEC_ARGS[@]}")
fi

export ELECTRON_OUT_DIR="${ELECTRON_OUT_DIR:-Release}"
unset ELECTRON_RUN_AS_NODE

cmd=(npm run test -- "${SPEC_ARGS[@]}")
if [[ "$(uname -s)" == "Linux" ]] && command -v xvfb-run >/dev/null 2>&1; then
  cmd=(xvfb-run --auto-servernum --server-args="-screen 0 1280x1024x24" "${cmd[@]}")
fi

echo "Electron specs:"
echo "  Source root: $SRC_ROOT"
echo "  Electron dir: $ELECTRON_DIR"
echo "  ELECTRON_OUT_DIR: $ELECTRON_OUT_DIR"
printf '  Command:'
printf ' %q' "${cmd[@]}"
printf '\n'

cd "$ELECTRON_DIR"
exec "${cmd[@]}"
