#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  upgrade-electron-target.sh --target <target> --tag <tag> [options] [-- package args]

Examples:
  scripts/upgrade-electron-target.sh \
    --target 42 \
    --tag v42.1.0 \
    --ports print-request-handler,vaapi-hevc-wip,widevine-cdm,preload,text-caret-info,user-agent-override,dispatch-input-event,picture-in-picture-handle-api \
    --build \
    --include-widevine-cdm

Options:
  --target <target>       Workspace target under <base-dir>, for example 42.
                          Defaults to ELECTRON_WORKSPACE_TARGET when set.
  --tag <tag>             Electron upstream tag to check out, for example v42.1.0.
  --ports <list>          Comma-separated port bundles to apply in order.
  --port <name>           Add one port bundle. May be repeated.
  --base-dir <path>       Workspace root. Default: parent of this script dir.
  --src-root <path>       Chromium src root. Default: <base-dir>/<target>/src.
  --config <name>         Build-tools config. Default: <target>-release.
  --branch-name <name>    Work branch created in both repos after sync.
                          Default: upgrade/<target>-<tag>-<timestamp>.
  --backup-branch-name <name>
                          Backup branch created in both repos before checkout.
                          Default: backup/<target>-before-<tag>-<timestamp>.
  --no-sync               Skip e --config=<config> sync after tag checkout.
  --no-backup             Do not create backup branches.
  --no-branch             Do not create a new work branch after sync.
  --skip-checkout         Do not check out the Electron tag, do not move
                          Chromium, and do not sync. Use only to continue after
                          the workspace is already at the desired clean base.
  --build                 Run build-dev-electron-npm.sh after applying ports.
  --include-widevine-cdm  Pass Widevine packaging flags to the build script.
  --no-e-use              Do not run e use <config> before building.
  -h, --help              Show this help.

Arguments after -- are forwarded to build-dev-electron-npm.sh when --build is
set.
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR=${BASE_DIR:-"$(cd "$SCRIPT_DIR/.." && pwd)"}
TARGET=${ELECTRON_WORKSPACE_TARGET:-}
TAG=
SRC_ROOT=
CONFIG_NAME=
BRANCH_NAME=
BACKUP_BRANCH_NAME=
DO_SYNC=1
DO_BACKUP=1
DO_BRANCH=1
SKIP_CHECKOUT=0
DO_BUILD=0
INCLUDE_WIDEVINE_CDM=0
DO_E_USE=1
PORTS=()
PACKAGE_ARGS=()

die() {
  echo "error: $*" >&2
  exit 1
}

run() {
  echo "+ $*"
  "$@"
}

append_ports_csv() {
  local csv=$1
  local old_ifs=$IFS
  local item
  IFS=,
  read -ra items <<<"$csv"
  IFS=$old_ifs
  for item in "${items[@]}"; do
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item%"${item##*[![:space:]]}"}"
    [[ -n "$item" ]] && PORTS+=("$item")
  done
}

archive_port_bundle_state_for_target() {
  local repo_dir=$1
  local target=$2
  local safe_tag=$3
  local timestamp=$4
  local state_dir archive_dir

  state_dir="$(git -C "$repo_dir" rev-parse --path-format=absolute --git-path port-bundles)"
  [[ -d "$state_dir" ]] || return 0

  shopt -s nullglob
  local states=("$state_dir"/*."$target".state)
  shopt -u nullglob
  [[ ${#states[@]} -gt 0 ]] || return 0

  archive_dir="$state_dir/archive-before-$safe_tag-$timestamp"
  run mkdir -p "$archive_dir"

  local state
  for state in "${states[@]}"; do
    run mv "$state" "$archive_dir/"
  done
}

electron_chromium_version() {
  local deps_path="$ELECTRON_DIR/DEPS"
  [[ -f "$deps_path" ]] || die "missing Electron DEPS file: $deps_path"
  python3 - "$deps_path" <<'PY'
import re
import sys

path = sys.argv[1]
lines = open(path, encoding='utf-8').read().splitlines()
for i, line in enumerate(lines):
    if "'chromium_version'" not in line:
        continue
    inline = re.search(r":\s*'([^']+)'", line)
    if inline:
        print(inline.group(1))
        raise SystemExit(0)
    for candidate in lines[i + 1:i + 4]:
        match = re.search(r"'([^']+)'", candidate)
        if match:
            print(match.group(1))
            raise SystemExit(0)
raise SystemExit(f"could not find chromium_version in {path}")
PY
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET=$2; shift 2 ;;
    --target=*) TARGET=${1#--target=}; shift ;;
    --tag) TAG=$2; shift 2 ;;
    --tag=*) TAG=${1#--tag=}; shift ;;
    --ports) append_ports_csv "$2"; shift 2 ;;
    --ports=*) append_ports_csv "${1#--ports=}"; shift ;;
    --port) PORTS+=("$2"); shift 2 ;;
    --port=*) PORTS+=("${1#--port=}"); shift ;;
    --base-dir) BASE_DIR=$2; shift 2 ;;
    --base-dir=*) BASE_DIR=${1#--base-dir=}; shift ;;
    --src-root) SRC_ROOT=$2; shift 2 ;;
    --src-root=*) SRC_ROOT=${1#--src-root=}; shift ;;
    --config) CONFIG_NAME=$2; shift 2 ;;
    --config=*) CONFIG_NAME=${1#--config=}; shift ;;
    --branch-name) BRANCH_NAME=$2; shift 2 ;;
    --branch-name=*) BRANCH_NAME=${1#--branch-name=}; shift ;;
    --backup-branch-name) BACKUP_BRANCH_NAME=$2; shift 2 ;;
    --backup-branch-name=*) BACKUP_BRANCH_NAME=${1#--backup-branch-name=}; shift ;;
    --no-sync) DO_SYNC=0; shift ;;
    --no-backup) DO_BACKUP=0; shift ;;
    --no-branch) DO_BRANCH=0; shift ;;
    --skip-checkout) SKIP_CHECKOUT=1; shift ;;
    --build) DO_BUILD=1; shift ;;
    --include-widevine-cdm) INCLUDE_WIDEVINE_CDM=1; shift ;;
    --no-e-use) DO_E_USE=0; shift ;;
    -h|--help) usage; exit 0 ;;
    --)
      shift
      PACKAGE_ARGS+=("$@")
      break
      ;;
    *)
      die "unknown option: $1"
      ;;
  esac
done

[[ -n "$TARGET" ]] || die "--target is required, or set ELECTRON_WORKSPACE_TARGET"
[[ -n "$TAG" ]] || die "--tag is required, for example v42.1.0"
[[ "$TARGET" != */* ]] || die "target must not contain slash: $TARGET"

if [[ -z "$SRC_ROOT" ]]; then
  SRC_ROOT="$BASE_DIR/$TARGET/src"
fi
if [[ -z "$CONFIG_NAME" ]]; then
  CONFIG_NAME="$TARGET-release"
fi

ELECTRON_DIR="$SRC_ROOT/electron"
PORT_BUNDLE_SCRIPT="$SCRIPT_DIR/port-bundle.sh"
BUILD_SCRIPT="$SCRIPT_DIR/build-dev-electron-npm.sh"

safe_tag_name() {
  printf '%s\n' "$1" | sed -E 's/[^A-Za-z0-9._-]+/-/g; s/^-+//; s/-+$//'
}

timestamp_for_branch() {
  date +%Y%m%d-%H%M%S
}

git_output() {
  git "$@" | tr -d '\r'
}

git_ref_exists() {
  local repo_dir=$1
  local ref=$2
  git -C "$repo_dir" rev-parse --verify --quiet "$ref" >/dev/null
}

require_git_repo() {
  local repo_dir=$1
  git -C "$repo_dir" rev-parse --is-inside-work-tree >/dev/null || die "not a git repo: $repo_dir"
}

require_clean_worktree() {
  local repo_dir=$1
  git -C "$repo_dir" diff --quiet || die "worktree has unstaged changes: $repo_dir"
  git -C "$repo_dir" diff --cached --quiet || die "worktree has staged changes: $repo_dir"
}

require_clean_or_gitlink_changes_only() {
  local repo_dir=$1
  git -C "$repo_dir" diff --cached --quiet || die "worktree has staged changes: $repo_dir"
  git -C "$repo_dir" diff --quiet && return 0

  local meta path old_mode new_mode new_oid status found
  found=0
  while IFS=$'\t' read -r meta path; do
    [[ -n "$meta" ]] || continue
    found=1
    # raw diff meta format: :<old-mode> <new-mode> <old-sha> <new-sha> <status>
    set -- $meta
    [[ $# -ge 5 ]] || die "could not parse raw diff line in $repo_dir: $meta"
    old_mode="${1#:}"
    new_mode=$2
    new_oid=$4
    status=$5
    [[ "$old_mode" == "160000" && "$new_mode" == "160000" && "$status" == "M" && "$new_oid" =~ ^0+$ ]] || {
      die "worktree has non-dirty-gitlink unstaged changes: $repo_dir"
    }
    [[ -n "$path" ]] || die "could not parse gitlink path from raw diff in $repo_dir"

    local nested_path nested_top nested_path_real nested_top_real
    nested_path="$repo_dir/$path"
    nested_top="$(git -C "$nested_path" rev-parse --show-toplevel 2>/dev/null)" || {
      die "gitlink path is not a nested git repo: $nested_path"
    }
    nested_path_real="$(cd "$nested_path" && pwd -P)"
    nested_top_real="$(cd "$nested_top" && pwd -P)"
    [[ "$nested_path_real" == "$nested_top_real" ]] || {
      die "gitlink path resolves to a parent repo instead of a nested repo: $nested_path"
    }
    git -C "$nested_path" diff --quiet || die "nested gitlink repo has unstaged changes: $nested_path"
    git -C "$nested_path" diff --cached --quiet || die "nested gitlink repo has staged changes: $nested_path"
  done < <(git -C "$repo_dir" diff --raw --no-ext-diff)

  [[ "$found" -eq 0 ]] || echo "Worktree has only clean gitlink dirty markers; continuing: $repo_dir"
}

require_no_git_operation() {
  local repo_dir=$1
  local git_dir
  git_dir="$(git_output -C "$repo_dir" rev-parse --path-format=absolute --git-dir)"
  local path
  for path in rebase-apply rebase-merge MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD; do
    [[ ! -e "$git_dir/$path" ]] || die "git operation is already in progress in $repo_dir: $path"
  done
}

create_branch_at_head() {
  local repo_dir=$1
  local name=$2
  git_ref_exists "$repo_dir" "refs/heads/$name" && die "branch already exists in $repo_dir: $name"
  run git -C "$repo_dir" branch "$name" HEAD
}

switch_new_branch() {
  local repo_dir=$1
  local name=$2
  git_ref_exists "$repo_dir" "refs/heads/$name" && die "branch already exists in $repo_dir: $name"
  run git -C "$repo_dir" switch -c "$name"
}

require_git_repo "$SRC_ROOT"
require_git_repo "$ELECTRON_DIR"
[[ -f "$PORT_BUNDLE_SCRIPT" ]] || die "missing script: $PORT_BUNDLE_SCRIPT"
if [[ "$DO_BUILD" -eq 1 ]]; then
  [[ -f "$BUILD_SCRIPT" ]] || die "missing script: $BUILD_SCRIPT"
fi

if [[ "$SKIP_CHECKOUT" -eq 1 ]]; then
  require_clean_or_gitlink_changes_only "$SRC_ROOT"
else
  require_clean_worktree "$SRC_ROOT"
fi
require_clean_worktree "$ELECTRON_DIR"
require_no_git_operation "$SRC_ROOT"
require_no_git_operation "$ELECTRON_DIR"

timestamp="$(timestamp_for_branch)"
safe_tag="$(safe_tag_name "$TAG")"
if [[ -z "$BRANCH_NAME" ]]; then
  BRANCH_NAME="upgrade/$TARGET-$safe_tag-$timestamp"
fi
if [[ -z "$BACKUP_BRANCH_NAME" ]]; then
  BACKUP_BRANCH_NAME="backup/$TARGET-before-$safe_tag-$timestamp"
fi

echo "Upgrade target: $TARGET"
echo "Electron tag: $TAG"
echo "Source root: $SRC_ROOT"
echo "Config: $CONFIG_NAME"
if [[ "${#PORTS[@]}" -gt 0 ]]; then
  printf 'Ports: %s\n' "$(IFS=,; echo "${PORTS[*]}")"
else
  echo "Ports: (none)"
fi
if [[ "$DO_BACKUP" -eq 1 ]]; then
  echo "Backup branch: $BACKUP_BRANCH_NAME"
fi
if [[ "$DO_BRANCH" -eq 1 ]]; then
  echo "Work branch: $BRANCH_NAME"
fi

if [[ "$DO_BACKUP" -eq 1 ]]; then
  create_branch_at_head "$SRC_ROOT" "$BACKUP_BRANCH_NAME"
  create_branch_at_head "$ELECTRON_DIR" "$BACKUP_BRANCH_NAME"
fi

if [[ "$SKIP_CHECKOUT" -eq 0 ]]; then
  run git -C "$ELECTRON_DIR" fetch --no-tags origin "refs/tags/$TAG:refs/tags/$TAG"
  run git -C "$ELECTRON_DIR" checkout "$TAG"

  chromium_version="$(electron_chromium_version)"
  echo "Chromium revision from Electron DEPS: $chromium_version"
  run git -C "$SRC_ROOT" fetch --no-tags origin "refs/tags/$chromium_version:refs/tags/$chromium_version"
  run git -C "$SRC_ROOT" switch --detach "$chromium_version"

  if [[ "$DO_SYNC" -eq 1 ]]; then
    run e --config="$CONFIG_NAME" sync
  fi
elif [[ "$DO_SYNC" -eq 1 ]]; then
  echo "Skipping checkout and sync because --skip-checkout was set."
fi

require_clean_or_gitlink_changes_only "$SRC_ROOT"
require_clean_worktree "$ELECTRON_DIR"
require_no_git_operation "$SRC_ROOT"
require_no_git_operation "$ELECTRON_DIR"

if [[ "$DO_BRANCH" -eq 1 ]]; then
  switch_new_branch "$SRC_ROOT" "$BRANCH_NAME"
  switch_new_branch "$ELECTRON_DIR" "$BRANCH_NAME"
fi

archive_port_bundle_state_for_target "$SRC_ROOT" "$TARGET" "$safe_tag" "$timestamp"
archive_port_bundle_state_for_target "$ELECTRON_DIR" "$TARGET" "$safe_tag" "$timestamp"

for port in "${PORTS[@]}"; do
  run bash "$PORT_BUNDLE_SCRIPT" apply "$port" \
    --target "$TARGET" \
    --src-root "$SRC_ROOT" \
    --base-dir "$BASE_DIR"
done

if [[ "$DO_BUILD" -eq 1 ]]; then
  if [[ "$DO_E_USE" -eq 1 ]]; then
    run e use "$CONFIG_NAME"
  fi

  build_args=(--target "$TARGET")
  if [[ "$INCLUDE_WIDEVINE_CDM" -eq 1 ]]; then
    build_args+=(--include-widevine-cdm --widevine-license-ack)
  fi
  build_args+=("${PACKAGE_ARGS[@]}")
  run bash "$BUILD_SCRIPT" "${build_args[@]}"
fi

cat <<EOF

Done.
Chromium repo: $SRC_ROOT
Electron repo: $ELECTRON_DIR
EOF
if [[ "$DO_BRANCH" -eq 1 ]]; then
  echo "Work branch: $BRANCH_NAME"
fi
