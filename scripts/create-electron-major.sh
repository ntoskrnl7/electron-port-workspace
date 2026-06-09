#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  create-electron-major.sh <major> [options]

Examples:
  scripts/create-electron-major.sh 42
  scripts/create-electron-major.sh 42 --tag v42.0.0 --sync

Options:
  --base-dir <path>       Parent directory for major workspaces.
                          Default: parent directory of this script directory.
  --configs-dir <path>    electron-build-tools config directory.
                          Default: $HOME/.electron_build_tools/configs
  --tag <tag>             Electron tag to checkout after init, for example v42.0.0.
  --sync                  Run e --config=<major>-release sync after creating configs.
  --set-current           Write <major>-release to evm-current.txt.
  --force-config          Overwrite existing build-tools config files.
  --no-git-cache          Do not set GIT_CACHE_PATH in build-tools configs.
                          Useful for one-shot hosted CI runners with limited
                          disk space.
  --use-ssh               Use git@github.com:electron/electron.git instead of https.
  -h, --help              Show this help.

What this creates:
  <base-dir>/<major>
  <base-dir>/<major>/.gclient
  $HOME/.electron_build_tools/configs/evm.<major>-release.json
  $HOME/.electron_build_tools/configs/evm.<major>-testing.json

The script does not delete or clean any existing out/Release or out/Testing cache.
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BASE_DIR=${BASE_DIR:-$DEFAULT_BASE_DIR}
CONFIGS_DIR=${CONFIGS_DIR:-"$HOME/.electron_build_tools/configs"}
TAG=
DO_SYNC=0
SET_CURRENT=0
FORCE_CONFIG=0
USE_SSH=0
USE_GIT_CACHE=1

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 1 ]]; then
  usage
  exit 2
fi

MAJOR=$1
shift

if [[ ! "$MAJOR" =~ ^[0-9]+$ ]]; then
  echo "error: major must be a number, for example 42" >&2
  exit 2
fi

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
    --tag)
      TAG=$2
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
    --no-git-cache)
      USE_GIT_CACHE=0
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

ROOT="$BASE_DIR/$MAJOR"
RELEASE_CONFIG="$MAJOR-release"
TESTING_CONFIG="$MAJOR-testing"
RELEASE_CONFIG_FILE="$CONFIGS_DIR/evm.$RELEASE_CONFIG.json"
TESTING_CONFIG_FILE="$CONFIGS_DIR/evm.$TESTING_CONFIG.json"
CURRENT_FILE="$CONFIGS_DIR/evm-current.txt"

if [[ "$USE_SSH" -eq 1 ]]; then
  ELECTRON_ORIGIN="git@github.com:electron/electron.git"
else
  ELECTRON_ORIGIN="https://github.com/electron/electron.git"
fi

write_config() {
  local path=$1
  local import_name=$2
  local out_name=$3
  local git_cache_path
  local tmp
  tmp=$(mktemp)
  git_cache_path=${ELECTRON_WORKSPACE_GIT_CACHE_PATH:-"$HOME/.git_cache"}

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
    "CHROMIUM_BUILDTOOLS_PATH": "$ROOT/src/buildtools"$(if [[ "$USE_GIT_CACHE" -eq 1 ]]; then printf ',\n    "GIT_CACHE_PATH": "%s"' "$git_cache_path"; fi)
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

run() {
  echo "+ $*"
  "$@"
}

bootstrap_electron_checkout() {
  local tag=$1
  local electron_dir="$ROOT/src/electron"

  if [[ -e "$electron_dir" && ! -d "$electron_dir/.git" ]]; then
    echo "error: Electron checkout path exists but is not a git repo: $electron_dir" >&2
    exit 1
  fi

  echo "Electron checkout is not present; bootstrapping Electron at $tag before sync."
  run mkdir -p "$ROOT/src"
  run git init "$electron_dir"
  run git -C "$electron_dir" remote add origin "$ELECTRON_ORIGIN"
  run git -C "$electron_dir" fetch --no-tags --filter=blob:none origin "refs/tags/$tag:refs/tags/$tag"
  run git -C "$electron_dir" checkout "$tag"
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

  if [[ -n "$TAG" ]]; then
    if [[ ! -d "$ROOT/src/electron/.git" ]]; then
      bootstrap_electron_checkout "$TAG"
    else
      run git -C "$ROOT/src/electron" fetch --no-tags origin "refs/tags/$TAG:refs/tags/$TAG"
      run git -C "$ROOT/src/electron" checkout "$TAG"
    fi
  fi

  if [[ "$DO_SYNC" -eq 1 ]]; then
    run e --config="$RELEASE_CONFIG" sync
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
  PATH=/tmp/electron-build-tools-gperf/root/usr/bin:\$PATH e --config=$RELEASE_CONFIG build -local_jobs 2
  PATH=/tmp/electron-build-tools-gperf/root/usr/bin:\$PATH e --config=$RELEASE_CONFIG build -local_jobs 2 -t electron:electron_dist_zip
EOF
}

main "$@"
