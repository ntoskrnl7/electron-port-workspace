#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEFAULT_BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BASE_DIR=${BASE_DIR:-$DEFAULT_BASE_DIR}
SRC_ROOT=${SRC_ROOT:-}

usage() {
  cat <<'USAGE'
Usage:
  port-bundle.sh <command> [args] [options]

Commands:
  list
      List port bundles and targets under <base-dir>/ports.

  export <port-name> --target <target> [options]
      Save patch files from Chromium and/or Electron refs into a reusable port.

  apply <port-name> --target <target> [options]
      Apply saved patches to a workspace with git am -3.

  undo <port-name> --target <target> [options]
      Revert commits previously applied by this script.

  drop <port-name> --target <target> [options]
      Remove a previously applied port without revert commits.
      This rewinds the current branch to the recorded pre-apply commit with
      git reset --keep. It refuses to run if additional commits were added
      after the port. Pass --backup-branch to create a backup branch first.

  status <port-name> --target <target> [options]
      Show whether the port is recorded as applied in the workspace.

Common options:
  --base-dir <path>       Default: parent directory of this script directory.
  --src-root <path>       Chromium src root. Default: <base-dir>/<target>/src
  --target <target>       Port target under ports/<feature>/<target>.
                          Examples: 41, 42, main.
  --repos <list>          Comma-separated: chromium,electron. Default: auto.
  --backup-branch         Before drop, create a backup branch at the current
                          HEAD in each affected repo.
  --backup-branch-name <name>
                          Optional explicit backup branch name. Valid only when
                          dropping a single repo. Without this option, drop
                          creates repo-specific timestamped branch names.

Export options:
  --chromium-base <ref>   Base ref before Chromium-side port commits.
  --chromium-head <ref>   Head ref containing Chromium-side port commits.
  --chromium-direct-only  Save Chromium patches for direct src application only.
                          Default Chromium exports archive Chromium patches and
                          register them in Electron's patches/chromium stack at
                          apply time.
  --electron-base <ref>   Base ref before Electron-side port commits.
  --electron-head <ref>   Head ref containing Electron-side port commits.
  --electronized-chromium-patches
                          Mark an Electron-only export as a Chromium patch-stack
                          bundle so apply also applies its patches into src.
  --depends-on <list>     Comma-separated port names that must be applied first
                          for the same target. Recorded in manifest.txt.
  --clear                 Remove existing patch files for this port first.

Apply options:
  --ignore-dependencies   Apply even when manifest dependencies are not recorded
                          as applied. Intended only for manually prepared trees.

Examples:
  # Save VAAPI/HEVC WIP from Chromium commits as an Electron patch-stack port.
  scripts/port-bundle.sh export vaapi-hevc-wip \
    --target 41 \
    --src-root /path/to/workspace/41/src \
    --chromium-base 29569258b0bc5 \
    --chromium-head checkpoint \
    --clear

  # Save a feature that has both Chromium and Electron commits. Chromium commits
  # are archived and registered into Electron's patches/chromium stack at apply
  # time, then Electron commits are appended into the same port bundle.
  scripts/port-bundle.sh export some-feature \
    --target 41 \
    --src-root /path/to/workspace/41/src \
    --chromium-base chromium-base-ref \
    --chromium-head chromium-feature-ref \
    --electron-base electron-base-ref \
    --electron-head electron-feature-ref \
    --clear

  # Save print request handler from Electron repo commits. Its Electron commit
  # already includes the Chromium patch-stack file under patches/chromium.
  scripts/port-bundle.sh export print-request-handler \
    --target 41 \
    --src-root /path/to/workspace/41/src \
    --electron-base v41.3.0 \
    --electron-head features/print-request-handler \
    --electronized-chromium-patches \
    --clear

  # Apply a port to a temporary branch.
  cd /path/to/electron-port-workspace
  git -C 41/src switch -c test/print-plus-vaapi-hevc
  scripts/port-bundle.sh apply vaapi-hevc-wip \
    --target 41

  # Undo a previously applied port with revert commits.
  scripts/port-bundle.sh undo vaapi-hevc-wip --target 41

  # Drop a previously applied port without keeping revert commits.
  scripts/port-bundle.sh drop vaapi-hevc-wip --target 41 \
    --backup-branch

Notes:
  apply/undo never reset or delete branches. undo creates revert commits.
  drop rewinds only the current branch for the selected repo with git reset --keep.
  When using drop, creating a backup branch first is strongly recommended.
  If git am conflicts, resolve and run git am --continue, or abort with git am --abort.
USAGE
}

die() {
  echo "error: $*" >&2
  exit 1
}

run() {
  echo "+ $*"
  "$@"
}

sanitize_name() {
  local name=$1
  [[ -n "$name" ]] || die "empty port name"
  [[ "$name" != *"/"* ]] || die "port name must not contain slash: $name"
  [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || die "port name may contain only A-Za-z0-9._-: $name"
  printf '%s\n' "$name"
}

sanitize_target() {
  local target=$1
  [[ -n "$target" ]] || die "--target is required"
  [[ "$target" != *"/"* ]] || die "target must not contain slash: $target"
  [[ "$target" =~ ^[A-Za-z0-9._-]+$ ]] || die "target may contain only A-Za-z0-9._-: $target"
  printf '%s\n' "$target"
}

port_dir_for() {
  local port_name=$1
  local target=$2
  printf '%s/ports/%s/%s\n' "$BASE_DIR" "$port_name" "$target"
}

resolve_src_root_for_target() {
  local target=$1
  if [[ -z "${SRC_ROOT:-}" ]]; then
    SRC_ROOT="$BASE_DIR/$target/src"
  fi
}

state_name_for() {
  local port_name=$1
  local target=$2
  printf '%s.%s\n' "$port_name" "$target"
}

timestamp_for_branch() {
  date +%Y%m%d-%H%M%S
}

repo_path() {
  local repo=$1
  case "$repo" in
    chromium) printf '%s\n' "$SRC_ROOT" ;;
    electron) printf '%s\n' "$SRC_ROOT/electron" ;;
    *) die "unknown repo: $repo" ;;
  esac
}

repo_patch_dir() {
  local port_dir=$1
  local repo=$2
  printf '%s/%s\n' "$port_dir" "$repo"
}

state_file() {
  local repo_dir=$1
  local state_name=$2
  local state_dir
  state_dir=$(git -C "$repo_dir" rev-parse --path-format=absolute --git-path port-bundles)
  printf '%s/%s.state\n' "$state_dir" "$state_name"
}

patches_for_repo() {
  local port_dir=$1
  local repo=$2
  local dir
  dir=$(repo_patch_dir "$port_dir" "$repo")
  [[ -d "$dir" ]] || return 0
  find "$dir" -maxdepth 1 -type f -name '*.patch' | sort -V
}

patch_filename_from_file() {
  local patch=$1
  local filename
  filename=$(sed -n 's/^Patch-Filename: //p' "$patch" | sed -n '1p')
  if [[ -z "$filename" ]]; then
    local subject
    subject=$(sed -n 's/^Subject: //p' "$patch" | sed -n '1p')
    subject=${subject#\[PATCH\] }
    subject=${subject#\[PATCH [0-9]*/[0-9]*\] }
    filename=$(printf '%s\n' "$subject" \
      | tr '[:upper:]' '[:lower:]' \
      | sed -E 's/[^a-z0-9]+/_/g; s/^_+//; s/_+$//')
    [[ -n "$filename" ]] || filename=$(basename "$patch" .patch)
    filename="${filename}.patch"
  fi
  printf '%s\n' "$filename"
}

require_clean_worktree() {
  local repo_dir=$1
  git -C "$repo_dir" diff --quiet || die "worktree has unstaged changes: $repo_dir"
  git -C "$repo_dir" diff --cached --quiet || die "worktree has staged changes: $repo_dir"
}

ensure_git_identity() {
  local repo_dir=$1
  if ! git -C "$repo_dir" config --get user.name >/dev/null; then
    run git -C "$repo_dir" config user.name "Electron Scripts"
  fi
  if ! git -C "$repo_dir" config --get user.email >/dev/null; then
    run git -C "$repo_dir" config user.email "scripts@electron"
  fi
}

normalize_patch_files() {
  local patch_dir=$1
  [[ -d "$patch_dir" ]] || return 0

  local patch
  while IFS= read -r patch; do
    [[ -n "$patch" ]] || continue
    run perl -pi -e 's/[ \t]+$//' "$patch"
  done < <(find "$patch_dir" -maxdepth 1 -type f -name '*.patch' | sort -V)
}

append_patches_to_electron_dir() {
  local src_dir=$1
  local port_dir=$2
  local dest_dir="$port_dir/electron"

  [[ -d "$src_dir" ]] || return 0
  run mkdir -p "$dest_dir"

  local next=1
  local existing
  existing=$(find "$dest_dir" -maxdepth 1 -type f -name '*.patch' -printf '%f\n' \
    | sed -nE 's/^([0-9]+)-.*$/\1/p' \
    | sort -n \
    | tail -1)
  if [[ -n "$existing" ]]; then
    next=$((10#$existing + 1))
  fi

  local patch base suffix target
  while IFS= read -r patch; do
    [[ -n "$patch" ]] || continue
    base=$(basename "$patch")
    suffix=$(printf '%s\n' "$base" | sed -E 's/^[0-9]+-//')
    printf -v target '%s/%04d-%s' "$dest_dir" "$next" "$suffix"
    run cp "$patch" "$target"
    next=$((next + 1))
  done < <(find "$src_dir" -maxdepth 1 -type f -name '*.patch' | sort -V)
}

electronize_chromium_patches() {
  local port_name=$1
  local patch_dir=$2
  local port_dir=$3
  local electron_patch_output_dir=${4:-"$port_dir/electron"}

  local electron_dir="$SRC_ROOT/electron"
  local chromium_patch_dir="$electron_dir/patches/chromium"
  local patch_list="$chromium_patch_dir/.patches"

  require_git_repo "$electron_dir"
  require_clean_worktree "$electron_dir"

  local before
  before=$(git -C "$electron_dir" rev-parse HEAD)

  run mkdir -p "$chromium_patch_dir"

  local patch filename target
  while IFS= read -r patch; do
    [[ -n "$patch" ]] || continue
    filename=$(patch_filename_from_file "$patch")
    target="$chromium_patch_dir/$filename"
    run cp "$patch" "$target"
    run perl -pi -e 's/[ \t]+$//' "$target"
    if ! grep -Fxq "$filename" "$patch_list"; then
      printf '%s\n' "$filename" >>"$patch_list"
    fi
  done < <(find "$patch_dir" -maxdepth 1 -type f -name '*.patch' | sort -V)

  run git -C "$electron_dir" add patches/chromium
  ensure_git_identity "$electron_dir"
  run git -C "$electron_dir" commit -m "patches: add $port_name chromium patches"

  local after
  after=$(git -C "$electron_dir" rev-parse HEAD)
  run mkdir -p "$electron_patch_output_dir"
  run git -C "$electron_dir" format-patch --keep-subject --no-signature \
    -o "$electron_patch_output_dir" "$before..$after"
  normalize_patch_files "$electron_patch_output_dir"

  ELECTRONIZED_BEFORE=$before
  ELECTRONIZED_AFTER=$after
}

has_patches_for_repo() {
  local port_dir=$1
  local repo=$2
  local first
  first=$(patches_for_repo "$port_dir" "$repo" | sed -n '1p')
  [[ -n "$first" ]]
}

manifest_value() {
  local port_dir=$1
  local key=$2
  local manifest="$port_dir/manifest.txt"
  [[ -f "$manifest" ]] || return 0
  sed -n "s/^$key=//p" "$manifest" | tail -1 | tr -d '\r'
}

normalize_port_list() {
  local value=$1
  local names=()
  local name
  while IFS= read -r name; do
    name=$(printf '%s\n' "$name" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
    [[ -n "$name" ]] || continue
    names+=("$(sanitize_name "$name")")
  done < <(tr ',' '\n' <<<"$value")

  local IFS=,
  printf '%s\n' "${names[*]:-}"
}

port_dependencies() {
  local port_dir=$1
  local depends_on
  depends_on=$(manifest_value "$port_dir" depends_on || true)
  [[ -n "$depends_on" ]] || return 0
  tr ',' '\n' <<<"$depends_on" | while read -r dependency; do
    dependency=$(printf '%s\n' "$dependency" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
    [[ -n "$dependency" ]] || continue
    sanitize_name "$dependency"
  done
}

append_unique_repo() {
  local repo=$1
  local existing
  for existing in "${dependency_repos[@]}"; do
    [[ "$existing" != "$repo" ]] || return 0
  done
  dependency_repos+=("$repo")
}

dependency_required_repos() {
  local dependency_port_dir=$1
  local dependency_state_name=$2

  dependency_repos=()
  local repo
  while IFS= read -r repo; do
    [[ -n "$repo" ]] || continue
    append_unique_repo "$repo"
  done < <(parse_repos auto "$dependency_port_dir" "$dependency_state_name")

  if is_electronized_chromium_port "$dependency_port_dir"; then
    append_unique_repo chromium
  fi

  printf '%s\n' "${dependency_repos[@]}"
  dependency_repos=()
}

print_dependency_status() {
  local dependency=$1
  local target=$2
  local dependency_port_dir=$3
  local dependency_state_name
  dependency_state_name=$(state_name_for "$dependency" "$target")

  local repo status state repo_dir
  while IFS= read -r repo; do
    [[ -n "$repo" ]] || continue
    repo_dir=$(repo_path "$repo")
    require_git_repo "$repo_dir"
    state=$(state_file "$repo_dir" "$dependency_state_name")
    if [[ -f "$state" ]]; then
      status=applied
    else
      status=missing
    fi
    echo "  $dependency/$target ($repo): $status"
  done < <(dependency_required_repos "$dependency_port_dir" "$dependency_state_name")
}

check_port_dependencies() {
  local port_name=$1
  local target=$2
  local port_dir=$3

  local dependencies=()
  mapfile -t dependencies < <(port_dependencies "$port_dir")
  [[ ${#dependencies[@]} -gt 0 ]] || return 0

  local missing=0
  local dependency dependency_port_dir dependency_state_name repo repo_dir state
  for dependency in "${dependencies[@]}"; do
    [[ "$dependency" != "$port_name" ]] || die "$port_name/$target cannot depend on itself"
    dependency_port_dir=$(port_dir_for "$dependency" "$target")
    if [[ ! -d "$dependency_port_dir" ]]; then
      echo "Missing dependency bundle: $dependency/$target ($dependency_port_dir)" >&2
      missing=1
      continue
    fi

    dependency_state_name=$(state_name_for "$dependency" "$target")
    while IFS= read -r repo; do
      [[ -n "$repo" ]] || continue
      repo_dir=$(repo_path "$repo")
      require_git_repo "$repo_dir"
      state=$(state_file "$repo_dir" "$dependency_state_name")
      if [[ ! -f "$state" ]]; then
        echo "Missing dependency apply state: $dependency/$target in $repo repo" >&2
        echo "  expected state: $state" >&2
        missing=1
      fi
    done < <(dependency_required_repos "$dependency_port_dir" "$dependency_state_name")
  done

  if [[ "$missing" -eq 1 ]]; then
    cat >&2 <<EOF

Cannot apply $port_name/$target until its dependencies are applied.
Apply the missing dependency ports first, or rerun with --ignore-dependencies
only if this workspace was prepared manually and you have verified the order.
EOF
    exit 1
  fi
}

is_electronized_chromium_port() {
  local port_dir=$1
  [[ "$(manifest_value "$port_dir" electronized_chromium_patches)" == "true" ]]
}

is_chromium_direct_electron_patch_stack_port() {
  local port_dir=$1
  [[ "$(manifest_value "$port_dir" electron_patch_stack_source)" == "chromium-direct" ]]
}

chromium_direct_archive_patches() {
  local port_dir=$1
  local dir="$port_dir/chromium-direct"
  [[ -d "$dir" ]] || return 0
  find "$dir" -maxdepth 1 -type f -name '*.patch' | sort -V
}

same_file_content() {
  local left=$1
  local right=$2
  [[ -f "$left" && -f "$right" ]] || return 1
  cmp -s "$left" "$right"
}

register_chromium_direct_electron_patch_stack() {
  local port_name=$1
  local port_dir=$2
  is_chromium_direct_electron_patch_stack_port "$port_dir" || return 0

  local electron_dir="$SRC_ROOT/electron"
  local chromium_patch_dir="$electron_dir/patches/chromium"
  local patch_list="$chromium_patch_dir/.patches"

  require_clean_worktree "$electron_dir"
  run mkdir -p "$chromium_patch_dir"
  [[ -f "$patch_list" ]] || run touch "$patch_list"

  local patches=()
  mapfile -t patches < <(chromium_direct_archive_patches "$port_dir")
  [[ ${#patches[@]} -gt 0 ]] || die "electron_patch_stack_source=chromium-direct but no chromium-direct patches found in $port_dir"

  local changed=0
  local patch filename target
  for patch in "${patches[@]}"; do
    filename=$(patch_filename_from_file "$patch")
    target="$chromium_patch_dir/$filename"

    if [[ -f "$target" ]]; then
      same_file_content "$patch" "$target" || die "target Chromium patch already exists with different content: $target"
    else
      run cp "$patch" "$target"
      run perl -pi -e 's/[ \t]+$//' "$target"
      changed=1
    fi

    if ! grep -Fxq "$filename" "$patch_list"; then
      printf '%s\n' "$filename" >>"$patch_list"
      changed=1
    fi
  done

  if [[ "$changed" -eq 1 ]]; then
    run git -C "$electron_dir" add patches/chromium
    ensure_git_identity "$electron_dir"
    run git -C "$electron_dir" commit -m "patches: add $port_name chromium patches"
  else
    echo "Electron Chromium patch stack already contains $port_name patches."
  fi
}

parse_repos() {
  local requested=$1
  local port_dir=$2
  local state_name=$3

  if [[ "$requested" == "auto" ]]; then
    local repos=()
    local chromium_dir electron_dir
    chromium_dir=$(repo_path chromium)
    electron_dir=$(repo_path electron)
    if has_patches_for_repo "$port_dir" chromium || [[ -f "$(state_file "$chromium_dir" "$state_name")" ]]; then
      repos+=("chromium")
    fi
    if has_patches_for_repo "$port_dir" electron ||
      is_chromium_direct_electron_patch_stack_port "$port_dir" ||
      [[ -f "$(state_file "$electron_dir" "$state_name")" ]]; then
      repos+=("electron")
    fi
    [[ ${#repos[@]} -gt 0 ]] || die "no patches found in $port_dir"
    printf '%s\n' "${repos[@]}"
    return
  fi

  tr ',' '\n' <<<"$requested" | while read -r repo; do
    [[ -n "$repo" ]] || continue
    case "$repo" in
      chromium|electron) printf '%s\n' "$repo" ;;
      *) die "invalid repo in --repos: $repo" ;;
    esac
  done
}

require_git_repo() {
  local repo_dir=$1
  [[ -d "$repo_dir/.git" || -f "$repo_dir/.git" ]] || die "not a git repo: $repo_dir"
}

require_no_in_progress_am() {
  local repo_dir=$1
  local git_dir
  git_dir=$(git -C "$repo_dir" rev-parse --git-dir)
  [[ ! -d "$git_dir/rebase-apply" ]] || die "git am is already in progress in $repo_dir"
}

cmd_list() {
  local ports_dir="$BASE_DIR/ports"
  [[ -d "$ports_dir" ]] || {
    echo "No ports directory: $ports_dir"
    return
  }
  find "$ports_dir" -mindepth 2 -maxdepth 2 -type d -printf '%P\n' | sort
}

write_manifest() {
  local port_dir=$1
  local port_name=$2
  local target=$3
  shift 3
  {
    echo "schema_version=1"
    echo "name=$port_name"
    echo "target=$target"
    for line in "$@"; do
      echo "$line"
    done
  } >"$port_dir/manifest.txt"
}

cmd_export() {
  local port_name=$1
  shift

  local chromium_base=
  local chromium_head=
  local electron_base=
  local electron_head=
  local chromium_direct_only=0
  local electronized_chromium_patches=0
  local depends_on=
  local depends_on_set=0
  local clear=0
  local target=

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --base-dir) BASE_DIR=$2; shift 2 ;;
      --src-root) SRC_ROOT=$2; shift 2 ;;
      --target) target=$2; shift 2 ;;
      --chromium-base) chromium_base=$2; shift 2 ;;
      --chromium-head) chromium_head=$2; shift 2 ;;
      --chromium-direct-only) chromium_direct_only=1; shift ;;
      --electron-base) electron_base=$2; shift 2 ;;
      --electron-head) electron_head=$2; shift 2 ;;
      --electronized-chromium-patches) electronized_chromium_patches=1; shift ;;
      --depends-on) depends_on=$2; depends_on_set=1; shift 2 ;;
      --clear) clear=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown option for export: $1" ;;
    esac
  done

  port_name=$(sanitize_name "$port_name")
  target=$(sanitize_target "$target")
  resolve_src_root_for_target "$target"
  if [[ "$electronized_chromium_patches" -eq 1 ]]; then
    [[ -n "$electron_head" ]] || die "--electronized-chromium-patches requires --electron-head"
    if [[ -n "$chromium_head" && "$chromium_direct_only" -eq 0 ]]; then
      die "--electronized-chromium-patches is only for Electron-only or Chromium direct-only exports"
    fi
  fi
  local port_dir
  port_dir=$(port_dir_for "$port_name" "$target")
  local existing_notes
  existing_notes=$(manifest_value "$port_dir" notes || true)
  local existing_depends_on
  existing_depends_on=$(manifest_value "$port_dir" depends_on || true)
  if [[ "$depends_on_set" -eq 1 ]]; then
    depends_on=$(normalize_port_list "$depends_on")
  elif [[ -n "$existing_depends_on" ]]; then
    depends_on=$(normalize_port_list "$existing_depends_on")
  fi
  local electronized_manifest=false
  local electron_patch_stack_source=
  local electron_base_resolved=
  local electron_head_resolved=
  local export_tmp="$port_dir/.tmp-export-$$"

  [[ -n "$chromium_head" || -n "$electron_head" ]] || die "nothing to export: pass --chromium-head and/or --electron-head"

  if [[ "$clear" -eq 1 ]]; then
    run rm -rf "$port_dir/chromium" "$port_dir/chromium-direct" "$port_dir/electron"
  fi
  run mkdir -p "$port_dir"
  run rm -rf "$export_tmp"
  run mkdir -p "$export_tmp"

  if [[ -n "$electron_head" ]]; then
    local electron_dir="$SRC_ROOT/electron"
    [[ -n "$electron_base" ]] || die "--electron-base is required with --electron-head"
    require_git_repo "$electron_dir"
    electron_base_resolved=$(git -C "$electron_dir" rev-parse --verify "$electron_base")
    electron_head_resolved=$(git -C "$electron_dir" rev-parse --verify "$electron_head")
  fi

  if [[ -n "$chromium_head" ]]; then
    [[ -n "$chromium_base" ]] || die "--chromium-base is required with --chromium-head"
    require_git_repo "$SRC_ROOT"
    run git -C "$SRC_ROOT" rev-parse --verify "$chromium_base"
    run git -C "$SRC_ROOT" rev-parse --verify "$chromium_head"
    local chromium_export_dir="$port_dir/chromium-direct"
    if [[ "$chromium_direct_only" -eq 1 ]]; then
      chromium_export_dir="$port_dir/chromium"
    fi
    run mkdir -p "$chromium_export_dir"
    run git -C "$SRC_ROOT" format-patch --keep-subject --no-signature \
      -o "$chromium_export_dir" "$chromium_base..$chromium_head"
    normalize_patch_files "$chromium_export_dir"

    if [[ "$chromium_direct_only" -eq 0 ]]; then
      electronized_manifest=true
      electron_patch_stack_source=chromium-direct
    fi
  fi

  if [[ -n "$electron_head" ]]; then
    local electron_patch_dir="$export_tmp/electron"
    if [[ "$electron_patch_stack_source" == "chromium-direct" ]]; then
      run git -C "$electron_dir" format-patch --keep-subject --no-signature \
        -o "$electron_patch_dir" "$electron_base_resolved..$electron_head_resolved" \
        -- . ':(exclude)patches/chromium'
    else
      run git -C "$electron_dir" format-patch --keep-subject --no-signature \
        -o "$electron_patch_dir" "$electron_base_resolved..$electron_head_resolved"
    fi
    normalize_patch_files "$electron_patch_dir"
    append_patches_to_electron_dir "$electron_patch_dir" "$port_dir"
  fi

  if [[ "$electronized_chromium_patches" -eq 1 ]]; then
    electronized_manifest=true
  fi

  run rm -rf "$export_tmp"
  local manifest_lines=("electronized_chromium_patches=$electronized_manifest")
  if [[ -n "$depends_on" ]]; then
    manifest_lines+=("depends_on=$depends_on")
  fi
  if [[ -n "$electron_patch_stack_source" ]]; then
    manifest_lines+=("electron_patch_stack_source=$electron_patch_stack_source")
  fi
  if has_patches_for_repo "$port_dir" electron; then
    manifest_lines+=("electron_patch_files=electron/*.patch")
  fi
  if has_patches_for_repo "$port_dir" chromium; then
    manifest_lines+=("chromium_patch_files=chromium/*.patch")
  fi
  if [[ -n "$(patches_for_repo "$port_dir" chromium-direct | sed -n '1p')" ]]; then
    manifest_lines+=("chromium_direct_archive=chromium-direct")
  fi
  if [[ -n "$existing_notes" ]]; then
    manifest_lines+=("notes=$existing_notes")
  fi
  write_manifest "$port_dir" "$port_name" "$target" "${manifest_lines[@]}"

  local feature_dir="$BASE_DIR/ports/$port_name"
  if [[ ! -f "$feature_dir/README.md" ]]; then
    cat >"$feature_dir/README.md" <<EOF
# $port_name

Reusable Electron feature port.

Target bundles live under:

\`\`\`text
ports/$port_name/<target>/
\`\`\`
EOF
  fi

  if [[ ! -f "$port_dir/README.md" ]]; then
    cat >"$port_dir/README.md" <<EOF
# $port_name / $target

Reusable Electron target bundle.

Patch directories:

- \`electron/*.patch\`: primary patch sequence for \`src/electron\`
- \`chromium-direct/*.patch\`: archived Chromium source patches for review/debugging
- \`chromium/*.patch\`: direct Chromium \`src\` patches for explicit direct-only bundles

For \`electronized_chromium_patches=true\`, apply registers the archived
Chromium patches in Electron's \`patches/chromium\` stack, then materializes
those Chromium patches into Chromium \`src\`.

Use:

\`\`\`bash
scripts/port-bundle.sh apply $port_name --target $target --src-root /path/to/src
scripts/port-bundle.sh undo $port_name --target $target --src-root /path/to/src
\`\`\`

\`\`\`powershell
.\scripts\port-bundle.ps1 apply $port_name -Target $target -SrcRoot C:\path\to\src
.\scripts\port-bundle.ps1 undo $port_name -Target $target -SrcRoot C:\path\to\src
\`\`\`
EOF
  fi

  echo
  echo "Saved port bundle: $port_dir"
}

cmd_apply() {
  local port_name=$1
  shift

  local repos_arg=auto
  local ignore_dependencies=0
  local target=
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --base-dir) BASE_DIR=$2; shift 2 ;;
      --src-root) SRC_ROOT=$2; shift 2 ;;
      --target) target=$2; shift 2 ;;
      --repos) repos_arg=$2; shift 2 ;;
      --ignore-dependencies) ignore_dependencies=1; shift ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown option for apply: $1" ;;
    esac
  done

  port_name=$(sanitize_name "$port_name")
  target=$(sanitize_target "$target")
  resolve_src_root_for_target "$target"
  local port_dir state_name
  port_dir=$(port_dir_for "$port_name" "$target")
  state_name=$(state_name_for "$port_name" "$target")
  [[ -d "$port_dir" ]] || die "port not found: $port_dir"

  if [[ "$ignore_dependencies" -eq 0 ]]; then
    check_port_dependencies "$port_name" "$target" "$port_dir"
  fi

  mapfile -t repos < <(parse_repos "$repos_arg" "$port_dir" "$state_name")
  for repo in "${repos[@]}"; do
    local repo_dir
    repo_dir=$(repo_path "$repo")
    require_git_repo "$repo_dir"
    require_no_in_progress_am "$repo_dir"

    local state
    state=$(state_file "$repo_dir" "$state_name")
    if [[ -f "$state" ]]; then
      if [[ "$repo" == "electron" ]] && is_electronized_chromium_port "$port_dir"; then
        local recorded_before recorded_after current
        recorded_before=$(read_state_value "$state" before)
        recorded_after=$(read_state_value "$state" after)
        current=$(git -C "$repo_dir" rev-parse HEAD)
        [[ "$current" == "$recorded_after" ]] || die "$port_name is already recorded as applied in $repo_dir, but HEAD differs: $state"
        apply_electronized_chromium_patches "$port_name" "$target" "$port_dir" "$recorded_before" "$recorded_after"
        continue
      fi
      die "$port_name is already recorded as applied in $repo_dir: $state"
    fi

    mapfile -t patches < <(patches_for_repo "$port_dir" "$repo")
    local register_chromium_direct_patch_stack=0
    if [[ "$repo" == "electron" ]] && is_chromium_direct_electron_patch_stack_port "$port_dir"; then
      register_chromium_direct_patch_stack=1
    fi
    [[ ${#patches[@]} -gt 0 || "$register_chromium_direct_patch_stack" -eq 1 ]] || die "no $repo patches found for $port_name"

    local before
    before=$(git -C "$repo_dir" rev-parse HEAD)

    echo "Applying $port_name to $repo repo: $repo_dir"
    if [[ "$register_chromium_direct_patch_stack" -eq 1 ]]; then
      register_chromium_direct_electron_patch_stack "$port_name" "$port_dir"
    fi
    ensure_git_identity "$repo_dir"
    for patch in "${patches[@]}"; do
      run git -C "$repo_dir" am -3 "$patch" || {
        cat >&2 <<EOF

Patch failed: $patch
Resolve conflicts in $repo_dir, then run:
  git -C "$repo_dir" am --continue

Or abort this apply:
  git -C "$repo_dir" am --abort

No applied-state file was written for this repo.
EOF
        exit 1
      }
    done

    local after
    after=$(git -C "$repo_dir" rev-parse HEAD)
    local state_dir
    state_dir=$(dirname "$state")
    run mkdir -p "$state_dir"
    {
      echo "port=$port_name"
      echo "target=$target"
      echo "repo=$repo"
      echo "repo_dir=$repo_dir"
      echo "before=$before"
      echo "after=$after"
      echo "applied_at=$(date -Iseconds)"
      echo "patch_count=${#patches[@]}"
      printf 'patch=%s\n' "${patches[@]}"
    } >"$state"
    echo "Recorded apply state: $state"

    if [[ "$repo" == "electron" ]]; then
      apply_electronized_chromium_patches "$port_name" "$target" "$port_dir" "$before" "$after"
    fi
  done
}

read_state_value() {
  local file=$1
  local key=$2
  sed -n "s/^$key=//p" "$file" | tail -1
}

electronized_chromium_patch_list() {
  local electron_dir=$1
  local before=$2
  local after=$3
  local patch_list="$electron_dir/patches/chromium/.patches"
  local changed
  changed=$(mktemp)
  git -C "$electron_dir" diff --name-only --diff-filter=AM "$before..$after" -- patches/chromium \
    | sed -n 's#^patches/chromium/##p' \
    | grep '\.patch$' >"$changed" || true

  while IFS= read -r filename; do
    [[ -n "$filename" ]] || continue
    if grep -Fxq "$filename" "$changed"; then
      printf '%s/patches/chromium/%s\n' "$electron_dir" "$filename"
    fi
  done <"$patch_list"
  rm -f "$changed"
}

apply_electronized_chromium_patches() {
  local port_name=$1
  local target=$2
  local port_dir=$3
  local electron_before=$4
  local electron_after=$5

  is_electronized_chromium_port "$port_dir" || return 0

  local chromium_dir="$SRC_ROOT"
  local electron_dir="$SRC_ROOT/electron"
  require_git_repo "$chromium_dir"
  require_no_in_progress_am "$chromium_dir"

  local chromium_state
  chromium_state=$(state_file "$chromium_dir" "$(state_name_for "$port_name" "$target")")
  if [[ -f "$chromium_state" ]]; then
    echo "Chromium patch apply state already recorded: $chromium_state"
    return 0
  fi

  if is_chromium_direct_electron_patch_stack_port "$port_dir"; then
    mapfile -t chromium_patches < <(chromium_direct_archive_patches "$port_dir")
  else
    mapfile -t chromium_patches < <(electronized_chromium_patch_list "$electron_dir" "$electron_before" "$electron_after")
  fi
  [[ ${#chromium_patches[@]} -gt 0 ]] || die "no electronized Chromium patches found in $electron_dir for $port_name"

  local before
  before=$(git -C "$chromium_dir" rev-parse HEAD)

  echo "Applying $port_name Chromium patches from Electron patch stack: $chromium_dir"
  ensure_git_identity "$chromium_dir"
  local patch
  for patch in "${chromium_patches[@]}"; do
    run git -C "$chromium_dir" am -3 "$patch" || {
      cat >&2 <<EOF

Chromium patch apply failed: $patch
Resolve conflicts in $chromium_dir, then run:
  git -C "$chromium_dir" am --continue

Or abort:
  git -C "$chromium_dir" am --abort

Electron repo state was kept; Chromium state was not written.
EOF
      exit 1
    }
  done

  local after state_dir
  after=$(git -C "$chromium_dir" rev-parse HEAD)
  state_dir=$(dirname "$chromium_state")
  run mkdir -p "$state_dir"
  {
    echo "port=$port_name"
    echo "target=$target"
    echo "repo=chromium"
    echo "repo_dir=$chromium_dir"
    echo "source=electronized_chromium_patches"
    echo "electron_before=$electron_before"
    echo "electron_after=$electron_after"
    echo "before=$before"
    echo "after=$after"
    echo "applied_at=$(date -Iseconds)"
    echo "patch_count=${#chromium_patches[@]}"
    printf 'patch=%s\n' "${chromium_patches[@]}"
  } >"$chromium_state"
  echo "Recorded Chromium patch apply state: $chromium_state"
}

cmd_undo() {
  local port_name=$1
  shift

  local repos_arg=auto
  local target=
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --base-dir) BASE_DIR=$2; shift 2 ;;
      --src-root) SRC_ROOT=$2; shift 2 ;;
      --target) target=$2; shift 2 ;;
      --repos) repos_arg=$2; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown option for undo: $1" ;;
    esac
  done

  port_name=$(sanitize_name "$port_name")
  target=$(sanitize_target "$target")
  resolve_src_root_for_target "$target"
  local port_dir state_name
  port_dir=$(port_dir_for "$port_name" "$target")
  state_name=$(state_name_for "$port_name" "$target")
  [[ -d "$port_dir" ]] || die "port not found: $port_dir"

  mapfile -t repos < <(parse_repos "$repos_arg" "$port_dir" "$state_name")
  for repo in "${repos[@]}"; do
    local repo_dir
    repo_dir=$(repo_path "$repo")
    require_git_repo "$repo_dir"
    require_no_in_progress_am "$repo_dir"

    local state
    state=$(state_file "$repo_dir" "$state_name")
    [[ -f "$state" ]] || die "$port_name is not recorded as applied in $repo_dir"

    local before after
    before=$(read_state_value "$state" before)
    after=$(read_state_value "$state" after)
    [[ -n "$before" && -n "$after" ]] || die "invalid state file: $state"

    run git -C "$repo_dir" rev-parse --verify "$before"
    run git -C "$repo_dir" rev-parse --verify "$after"
    git -C "$repo_dir" merge-base --is-ancestor "$after" HEAD || \
      die "recorded applied head $after is not an ancestor of current HEAD in $repo_dir"

    mapfile -t commits < <(git -C "$repo_dir" rev-list "$before..$after")
    [[ ${#commits[@]} -gt 0 ]] || die "no commits to revert for $port_name in $repo_dir"

    echo "Reverting $port_name from $repo repo: $repo_dir"
    ensure_git_identity "$repo_dir"
    for commit in "${commits[@]}"; do
      run git -C "$repo_dir" revert --no-edit "$commit" || {
        cat >&2 <<EOF

Revert failed at commit: $commit
Resolve conflicts in $repo_dir, then run:
  git -C "$repo_dir" revert --continue

Or abort:
  git -C "$repo_dir" revert --abort

State file is still kept:
  $state
EOF
        exit 1
      }
    done

    local archive="${state}.undone-$(date +%Y%m%d-%H%M%S)"
    run mv "$state" "$archive"
    echo "Archived apply state: $archive"
  done
}

cmd_drop() {
  local port_name=$1
  shift

  local repos_arg=auto
  local target=
  local backup_branch=0
  local backup_branch_name=
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --base-dir) BASE_DIR=$2; shift 2 ;;
      --src-root) SRC_ROOT=$2; shift 2 ;;
      --target) target=$2; shift 2 ;;
      --repos) repos_arg=$2; shift 2 ;;
      --backup-branch) backup_branch=1; shift ;;
      --backup-branch-name) backup_branch_name=$2; backup_branch=1; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown option for drop: $1" ;;
    esac
  done

  port_name=$(sanitize_name "$port_name")
  target=$(sanitize_target "$target")
  resolve_src_root_for_target "$target"
  local port_dir state_name
  port_dir=$(port_dir_for "$port_name" "$target")
  state_name=$(state_name_for "$port_name" "$target")
  [[ -d "$port_dir" ]] || die "port not found: $port_dir"

  mapfile -t repos < <(parse_repos "$repos_arg" "$port_dir" "$state_name")
  if [[ -n "$backup_branch_name" && ${#repos[@]} -ne 1 ]]; then
    die "--backup-branch-name requires dropping exactly one repo; use --repos electron or --repos chromium"
  fi

  for repo in "${repos[@]}"; do
    local repo_dir
    repo_dir=$(repo_path "$repo")
    require_git_repo "$repo_dir"
    require_no_in_progress_am "$repo_dir"

    local state
    state=$(state_file "$repo_dir" "$state_name")
    [[ -f "$state" ]] || die "$port_name is not recorded as applied in $repo_dir"

    local before after current
    before=$(read_state_value "$state" before)
    after=$(read_state_value "$state" after)
    current=$(git -C "$repo_dir" rev-parse HEAD)
    [[ -n "$before" && -n "$after" ]] || die "invalid state file: $state"

    run git -C "$repo_dir" rev-parse --verify "$before"
    run git -C "$repo_dir" rev-parse --verify "$after"

    if [[ "$current" != "$after" ]]; then
      cat >&2 <<EOF
error: refusing to drop $port_name in $repo_dir

The recorded applied head is:
  $after

Current HEAD is:
  $current

This usually means extra commits were added after the port was applied.
Use undo if you want revert commits, or manually inspect before resetting.
EOF
      exit 1
    fi

    if [[ "$backup_branch" -eq 1 ]]; then
      local branch_name
      if [[ -n "$backup_branch_name" ]]; then
        branch_name=$backup_branch_name
      else
        branch_name="backup/drop-${port_name}-${target}-${repo}-$(timestamp_for_branch)"
      fi
      if git -C "$repo_dir" show-ref --verify --quiet "refs/heads/$branch_name"; then
        die "backup branch already exists in $repo_dir: $branch_name"
      fi
      echo "Creating backup branch for $port_name in $repo repo: $repo_dir"
      run git -C "$repo_dir" branch "$branch_name" "$current"
    fi

    echo "Dropping $port_name from $repo repo without revert commits: $repo_dir"
    run git -C "$repo_dir" reset --keep "$before"

    local archive="${state}.dropped-$(date +%Y%m%d-%H%M%S)"
    run mv "$state" "$archive"
    echo "Archived apply state: $archive"
  done
}

cmd_status() {
  local port_name=$1
  shift

  local repos_arg=auto
  local target=
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --base-dir) BASE_DIR=$2; shift 2 ;;
      --src-root) SRC_ROOT=$2; shift 2 ;;
      --target) target=$2; shift 2 ;;
      --repos) repos_arg=$2; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "unknown option for status: $1" ;;
    esac
  done

  port_name=$(sanitize_name "$port_name")
  target=$(sanitize_target "$target")
  resolve_src_root_for_target "$target"
  local port_dir state_name
  port_dir=$(port_dir_for "$port_name" "$target")
  state_name=$(state_name_for "$port_name" "$target")
  [[ -d "$port_dir" ]] || die "port not found: $port_dir"

  local dependencies=()
  mapfile -t dependencies < <(port_dependencies "$port_dir")
  if [[ ${#dependencies[@]} -gt 0 ]]; then
    echo "dependencies:"
    local dependency dependency_port_dir
    for dependency in "${dependencies[@]}"; do
      dependency_port_dir=$(port_dir_for "$dependency" "$target")
      if [[ -d "$dependency_port_dir" ]]; then
        print_dependency_status "$dependency" "$target" "$dependency_port_dir"
      else
        echo "  $dependency/$target: missing bundle"
      fi
    done
  fi

  mapfile -t repos < <(parse_repos "$repos_arg" "$port_dir" "$state_name")
  for repo in "${repos[@]}"; do
    local repo_dir state
    repo_dir=$(repo_path "$repo")
    require_git_repo "$repo_dir"
    state=$(state_file "$repo_dir" "$state_name")
    if [[ -f "$state" ]]; then
      echo "$repo: applied"
      sed 's/^/  /' "$state"
    else
      echo "$repo: not applied"
    fi
  done
}

if [[ $# -lt 1 ]]; then
  usage
  exit 2
fi

command=$1
shift

case "$command" in
  list)
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --base-dir) BASE_DIR=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown option for list: $1" ;;
      esac
    done
    cmd_list
    ;;
  export)
    [[ $# -ge 1 ]] || die "export requires <port-name>"
    cmd_export "$@"
    ;;
  apply)
    [[ $# -ge 1 ]] || die "apply requires <port-name>"
    cmd_apply "$@"
    ;;
  undo)
    [[ $# -ge 1 ]] || die "undo requires <port-name>"
    cmd_undo "$@"
    ;;
  drop)
    [[ $# -ge 1 ]] || die "drop requires <port-name>"
    cmd_drop "$@"
    ;;
  status)
    [[ $# -ge 1 ]] || die "status requires <port-name>"
    cmd_status "$@"
    ;;
  -h|--help)
    usage
    ;;
  *)
    die "unknown command: $command"
    ;;
esac
