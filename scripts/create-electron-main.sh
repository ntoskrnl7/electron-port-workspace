#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  create-electron-main.sh [options]

Examples:
  scripts/create-electron-main.sh
  scripts/create-electron-main.sh --sync

Options:
  --base-dir <path>       Parent directory for workspaces.
                          Default: parent directory of this script directory.
  --configs-dir <path>    electron-build-tools config directory.
                          Default: $HOME/.electron_build_tools/configs
  --branch <name>         Electron branch to checkout after sync. Default: main
  --sync                  Run e --config=main-release sync after creating configs.
  --set-current           Write main-release to evm-current.txt.
  --force-config          Overwrite existing build-tools config files.
  --use-ssh               Use git@github.com:electron/electron.git instead of https.
  -h, --help              Show this help.

What this creates:
  <base-dir>/main
  <base-dir>/main/.gclient
  $HOME/.electron_build_tools/configs/evm.main-release.json
  $HOME/.electron_build_tools/configs/evm.main-testing.json

This script creates a separate upstream-main workspace. It does not reuse or
switch <base-dir>/src, <base-dir>/41/src, or any other
existing workspace.
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BASE_DIR=${BASE_DIR:-$DEFAULT_BASE_DIR}
CONFIGS_DIR=${CONFIGS_DIR:-"$HOME/.electron_build_tools/configs"}
BRANCH=${BRANCH:-main}
DO_SYNC=0
SET_CURRENT=0
FORCE_CONFIG=0
USE_SSH=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-dir)
      BASE_DIR=$2
      shift 2
      ;;
    --configs-dir)
      CONFIGS_DIR=$2
      shift 2
      ;;
    --branch)
      BRANCH=$2
      shift 2
      ;;
    --sync)
      DO_SYNC=1
      shift
      ;;
    --set-current)
      SET_CURRENT=1
      shift
      ;;
    --force-config)
      FORCE_CONFIG=1
      shift
      ;;
    --use-ssh)
      USE_SSH=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

WORKSPACE_NAME=main
ROOT="$BASE_DIR/$WORKSPACE_NAME"
RELEASE_CONFIG="$WORKSPACE_NAME-release"
TESTING_CONFIG="$WORKSPACE_NAME-testing"
RELEASE_CONFIG_FILE="$CONFIGS_DIR/evm.$RELEASE_CONFIG.json"
TESTING_CONFIG_FILE="$CONFIGS_DIR/evm.$TESTING_CONFIG.json"
CURRENT_FILE="$CONFIGS_DIR/evm-current.txt"

if [[ "$USE_SSH" -eq 1 ]]; then
  ELECTRON_ORIGIN="git@github.com:electron/electron.git"
else
  ELECTRON_ORIGIN="https://github.com/electron/electron.git"
fi

run() {
  echo "+ $*"
  "$@"
}

write_config() {
  local path=$1
  local import_name=$2
  local out_name=$3
  local tmp
  tmp=$(mktemp)

  cat >"$tmp" <<EOF
{
  "\$schema": "file://$HOME/.electron_build_tools/evm-config.schema.json",
  "root": "$ROOT",
  "remotes": {
    "electron": {
      "origin": "$ELECTRON_ORIGIN"
    }
  },
  "gen": {
    "args": [
      "import(\"//electron/build/args/$import_name.gn\")",
      "use_remoteexec = false",
      "use_reclient = false",
      "use_siso = true"
    ],
    "out": "$out_name"
  },
  "preserveSDK": 5,
  "env": {
    "CHROMIUM_BUILDTOOLS_PATH": "$ROOT/src/buildtools",
    "GIT_CACHE_PATH": "$HOME/.git_cache"
  }
}
EOF

  if [[ -e "$path" ]]; then
    if cmp -s "$tmp" "$path"; then
      echo "+ config already up to date: $path"
      rm -f "$tmp"
      return
    fi
    if [[ "$FORCE_CONFIG" -ne 1 ]]; then
      echo "error: config exists with different content: $path" >&2
      echo "Use --force-config only if you intentionally want to replace it." >&2
      rm -f "$tmp"
      exit 1
    fi
  fi

  run mv "$tmp" "$path"
}

write_gclient() {
  local path="$ROOT/.gclient"
  local tmp
  tmp=$(mktemp)

  cat >"$tmp" <<EOF
solutions = [
  { "name"        : 'src/electron',
    "url"         : '$ELECTRON_ORIGIN',
    "deps_file"   : 'DEPS',
    "managed"     : False,
    "custom_deps" : {
    },
    "custom_vars": {},
  },
]
EOF

  if [[ -e "$path" ]]; then
    if cmp -s "$tmp" "$path"; then
      echo "+ .gclient already up to date: $path"
      rm -f "$tmp"
      return
    fi
    if [[ "$FORCE_CONFIG" -ne 1 ]]; then
      echo "error: .gclient exists with different content: $path" >&2
      echo "Use --force-config only if you intentionally want to replace it." >&2
      rm -f "$tmp"
      exit 1
    fi
  fi

  run mv "$tmp" "$path"
}

main() {
  run mkdir -p "$ROOT" "$CONFIGS_DIR"

  write_gclient
  write_config "$RELEASE_CONFIG_FILE" release Release
  write_config "$TESTING_CONFIG_FILE" testing Testing

  if [[ "$SET_CURRENT" -eq 1 ]]; then
    printf '%s\n' "$RELEASE_CONFIG" >"$CURRENT_FILE"
    echo "+ wrote $CURRENT_FILE"
  fi

  if [[ "$DO_SYNC" -eq 1 ]]; then
    run e --config="$RELEASE_CONFIG" sync
    if [[ -d "$ROOT/src/electron/.git" ]]; then
      run git -C "$ROOT/src/electron" fetch origin "$BRANCH"
      run git -C "$ROOT/src/electron" checkout "$BRANCH"
      run git -C "$ROOT/src/electron" pull --ff-only origin "$BRANCH"
    else
      echo "warning: sync completed but Electron checkout was not found: $ROOT/src/electron" >&2
    fi
  fi

  cat <<EOF

Done.
Workspace:
  $ROOT

Configs:
  $RELEASE_CONFIG
  $TESTING_CONFIG

Next commands:
  cd $ROOT/src
  e --config=$RELEASE_CONFIG sync
  git -C $ROOT/src/electron checkout $BRANCH
  PATH=/tmp/electron-build-tools-gperf/root/usr/bin:\$PATH e --config=$RELEASE_CONFIG build -local_jobs 2
EOF
}

main "$@"
