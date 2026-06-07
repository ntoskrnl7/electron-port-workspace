#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TARGET="${ELECTRON_WORKSPACE_TARGET:-41}"

PACKAGE_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET=$2
      shift 2
      ;;
    --target=*)
      TARGET=${1#--target=}
      shift
      ;;
    *)
      PACKAGE_ARGS+=("$1")
      shift
      ;;
  esac
done

if [[ -n "${ELECTRON_WORKSPACE_SRC_DIR:-}" ]]; then
  ELECTRON_SRC_DIR="$ELECTRON_WORKSPACE_SRC_DIR"
else
  ELECTRON_SRC_DIR="$SCRIPT_DIR/../$TARGET/src"
fi

truthy() {
  case "${1:-}" in
    1|true|TRUE|True|yes|YES|Yes|on|ON|On) return 0 ;;
    *) return 1 ;;
  esac
}

get_package_arg_value() {
  local name=$1
  local flag="--$name"
  local i=0
  while (( i < ${#PACKAGE_ARGS[@]} )); do
    local arg="${PACKAGE_ARGS[$i]}"
    if [[ "$arg" == "$flag" ]]; then
      if (( i + 1 < ${#PACKAGE_ARGS[@]} )) && [[ "${PACKAGE_ARGS[$((i + 1))]}" != --* ]]; then
        echo "${PACKAGE_ARGS[$((i + 1))]}"
      else
        echo "true"
      fi
      return 0
    fi
    if [[ "$arg" == "$flag="* ]]; then
      echo "${arg#"$flag="}"
      return 0
    fi
    ((i += 1))
  done
  return 1
}

resolve_widevine_cdm_for_package() {
  local include_arg cdm_dir_arg license_arg
  include_arg="$(get_package_arg_value include-widevine-cdm || true)"
  if ! truthy "${ELECTRON_PACKAGE_INCLUDE_WIDEVINE_CDM:-}" && ! truthy "$include_arg"; then
    return
  fi

  cdm_dir_arg="$(get_package_arg_value widevine-cdm-dir || true)"
  if [[ -n "${ELECTRON_PACKAGE_WIDEVINE_CDM_DIR:-}" || -n "$cdm_dir_arg" ]]; then
    return
  fi

  license_arg="$(get_package_arg_value widevine-license-ack || true)"
  if ! truthy "${ELECTRON_PACKAGE_WIDEVINE_LICENSE_ACK:-}" && ! truthy "$license_arg"; then
    echo "error: Widevine packaging was requested, but license acknowledgement is missing. Pass --widevine-license-ack or set ELECTRON_PACKAGE_WIDEVINE_LICENSE_ACK=1." >&2
    exit 1
  fi

  local resolver="$SCRIPT_DIR/resolve-widevine-cdm.sh"
  if [[ ! -x "$resolver" ]]; then
    echo "error: missing executable resolver: $resolver" >&2
    exit 1
  fi

  local resolved
  resolved="$("$resolver" \
    --target "$TARGET" \
    --src-dir "$ELECTRON_SRC_DIR" \
    --license-ack \
    --download-if-missing \
    --prefer-download \
    --require-chrome-major-match \
    --force | tail -n 1)"
  if [[ -z "$resolved" || ! -d "$resolved" ]]; then
    echo "error: Widevine resolver did not produce a valid CDM directory: $resolved" >&2
    exit 1
  fi

  export ELECTRON_PACKAGE_WIDEVINE_CDM_DIR="$resolved"
  export ELECTRON_PACKAGE_WIDEVINE_LICENSE_ACK=1
  echo "Resolved target Chromium Widevine CDM: $resolved"
}

resolve_widevine_cdm_for_package

cd "$ELECTRON_SRC_DIR"

BUILD_ARGS=(--target electron:electron_dist_zip)
if [[ "${ELECTRON_BUILD_NO_REMOTE:-0}" == "1" ]]; then
  BUILD_ARGS+=(--no-remote)
fi
if [[ -n "${ELECTRON_BUILD_JOBS:-}" ]]; then
  BUILD_ARGS+=(-j "$ELECTRON_BUILD_JOBS")
fi
if [[ -n "${ELECTRON_BUILD_REMOTE_JOBS:-}" ]]; then
  BUILD_ARGS+=(-remote_jobs "$ELECTRON_BUILD_REMOTE_JOBS")
fi

e build "${BUILD_ARGS[@]}"
npm --prefix electron run create-typescript-definitions

node "$SCRIPT_DIR/package-electron-npm.js" \
  --mode dev \
  --src-dir "$ELECTRON_SRC_DIR" \
  --dev-number "${ELECTRON_PACKAGE_DEV_NUMBER:-auto}" \
  "${PACKAGE_ARGS[@]}"
