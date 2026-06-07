# Electron Port Bundles

This directory stores reusable feature patch bundles for Electron major-version
targets and optional upstream `main` workspaces.

The feature is the primary unit of management. If the same feature needs
different patches for Electron 41, Electron 42, or upstream `main`, keep each
target in a separate bundle directory.

## Layout

```text
ports/<feature>/
  README.md
  <target>/
    README.md
    electron/*.patch
    chromium/*.patch        # optional direct-only patches
    chromium-direct/*.patch # optional source/archive patches
    manifest.txt
```

Examples:

```text
ports/print-request-handler/41/
ports/print-request-handler/main/
ports/vaapi-hevc-wip/41/
ports/vaapi-hevc-wip/main/
```

- `ports/<feature>/README.md`: feature-level description and notes
- `ports/<feature>/<target>/README.md`: target-specific apply notes, conflict
  history, and caveats
- `ports/<feature>/<target>/manifest.txt`: target export metadata
- `electron/*.patch`: patches applied in `src/electron`
- `chromium/*.patch`: patches applied directly in Chromium `src`; use this only
  for exceptional direct-only bundles such as `--chromium-direct-only`
- `chromium-direct/*.patch`: archived Chromium source patches. For normal
  Chromium exports, these files are the source of truth.

`target` names such as `41`, `42`, and `main` identify the target line. The old
flat bundle layout is not used.

## Dependencies

Some ports require other ports for the same target to be applied first. Record
that relationship in the target manifest with `depends_on`:

```text
depends_on=preload,text-caret-info
```

`depends_on` is a comma-separated list of port names. The target is always the
current bundle target. For example, `ports/focused-editable-text/42` with
`depends_on=text-caret-info` requires `text-caret-info/42` to be applied first.

`port-bundle.sh apply` and `port-bundle.ps1 apply` check manifest dependencies
by default. If a dependency has no recorded applied state, apply stops. Use the
override only when the workspace has been prepared manually:

```bash
scripts/port-bundle.sh apply <feature> --target <target> --ignore-dependencies
```

```powershell
.\scripts\port-bundle.ps1 apply <feature> -Target <target> -IgnoreDependencies
```

Dependency checks do not auto-apply other ports. Electron port application often
requires conflict handling and validation in a deliberate order, so apply each
dependency explicitly before applying the next port.

## Tooling

Common script:

```bash
scripts/port-bundle.sh
```

Every bundle command requires an explicit target:

```bash
scripts/port-bundle.sh list
scripts/port-bundle.sh export <feature> --target <target> ...
scripts/port-bundle.sh apply <feature> --target <target> ...
scripts/port-bundle.sh undo <feature> --target <target> ...
scripts/port-bundle.sh drop <feature> --target <target> ...
scripts/port-bundle.sh status <feature> --target <target> ...
```

`list` prints entries as `<feature>/<target>`.

## Export Concept

`export` saves commits from a feature branch range into `.patch` files. The
important input is the `base..head` range:

```text
base commit -> feature commit 1 -> feature commit 2 -> head
```

`base` must be the commit immediately before feature work started. `head` is the
branch or commit containing the feature.

## Common Arguments

```text
--target <target>
```

Selects the bundle output directory. For example, `--target 41` writes to
`ports/<feature>/41`.

```text
--src-root <path>
```

Path to the target Chromium `src` checkout. That directory must contain the
Chromium repo, with the nested Electron repo at `src/electron`.

Examples:

```bash
--src-root /path/to/workspace/41/src
--src-root /path/to/workspace/main/src
```

## Chromium Export

Use these options to save Chromium-side feature commits:

```text
--chromium-base <ref>
--chromium-head <ref>
```

The default behavior stores Chromium `base..head` commits in
`ports/<feature>/<target>/chromium-direct/*.patch` and records these manifest
values:

```text
electronized_chromium_patches=true
electron_patch_stack_source=chromium-direct
chromium_direct_archive=chromium-direct
```

With this model, export does not store a target-specific Electron
`patches/chromium/.patches` diff. At apply time, the tool copies
`chromium-direct/*.patch` into the current target Electron tree's
`patches/chromium` stack, appends the filenames to `.patches`, and commits that
registration as `patches: add <feature> chromium patches`.

The original Chromium patches remain archived under
`ports/<feature>/<target>/chromium-direct/*.patch`.

To save patches only for direct Chromium application:

```text
--chromium-direct-only
```

That option writes only `ports/<feature>/<target>/chromium/*.patch` and does not
modify the Electron repo. It is an exceptional path for normal port management.

## Electron Export

Use these options to save Electron-side feature commits:

```text
--electron-base <ref>
--electron-head <ref>
```

The tool saves the `base..head` range from `src/electron` into
`ports/<feature>/<target>/electron/*.patch`.

For features with both Chromium and Electron changes, pass Chromium refs and
Electron refs to the same export command. Chromium changes are archived in
`chromium-direct/*.patch`, and Electron feature commits are appended in
`electron/*.patch`.

When `electron_patch_stack_source=chromium-direct` is recorded, Electron export
excludes `patches/chromium`. This keeps the bundle independent of the exporting
machine's current `.patches` context, even if the Electron head range contains an
older patch-stack commit.

Use `--clear` to replace an existing target bundle:

```text
--clear
```

This removes existing `chromium`, `chromium-direct`, and `electron` patch files
for the target before exporting.

Use `--depends-on` to record dependencies in the manifest:

```text
--depends-on <port-name[,port-name...]>
```

If an existing manifest already has `depends_on`, export preserves that value.
Pass `--depends-on` explicitly to set or change dependencies.

## Export Examples

Export Chromium-only work as an Electron patch-stack port:

```bash
scripts/port-bundle.sh export vaapi-hevc-wip \
  --target 41 \
  --src-root /path/to/workspace/41/src \
  --chromium-base chromium-base-ref \
  --chromium-head chromium-feature-ref \
  --clear
```

Export a feature with both Chromium and Electron commits:

```bash
scripts/port-bundle.sh export some-feature \
  --target 41 \
  --src-root /path/to/workspace/41/src \
  --chromium-base chromium-base-ref \
  --chromium-head chromium-feature-ref \
  --electron-base electron-base-ref \
  --electron-head electron-feature-ref \
  --clear
```

Export an Electron commit that already contains Chromium patch-stack files:

```bash
scripts/port-bundle.sh export print-request-handler \
  --target 41 \
  --src-root /path/to/workspace/41/src \
  --electron-base v41.5.0 \
  --electron-head features/print-request-handler \
  --clear
```

## Applying

Apply bundles on a temporary branch first:

```bash
cd /path/to/workspace/41/src
git switch -c test/some-feature
/path/to/electron-port-workspace/scripts/port-bundle.sh apply vaapi-hevc-wip \
  --target 41 \
  --src-root /path/to/workspace/41/src
```

For `electronized_chromium_patches=true`, apply performs these steps:

```text
1. Create an Electron repo commit that registers chromium-direct patches in
   patches/chromium.
2. Apply electron/*.patch in src/electron with git am -3, when present.
3. Materialize chromium-direct/*.patch in Chromium src with git am -3.
```

The registration commit is created in the target tree at apply time. If another
port already changed `patches/chromium/.patches`, the new filenames are appended
to that current state instead of being tied to the exporting tree's context.

You can apply only selected repos:

```bash
scripts/port-bundle.sh apply print-request-handler \
  --target 41 \
  --repos electron
```

If a conflict occurs, the affected repo is left in `git am` state:

```bash
git status
# Resolve conflicts.
git am --continue
```

To abort:

```bash
git am --abort
```

## Applied State

```bash
scripts/port-bundle.sh status vaapi-hevc-wip \
  --target 41 \
  --src-root /path/to/workspace/41/src
```

After a successful apply, each affected repo records the before/after commits in
`.git/port-bundles/<feature>.<target>.state`.

## Undoing

To preserve history and revert with commits:

```bash
scripts/port-bundle.sh undo vaapi-hevc-wip \
  --target 41 \
  --src-root /path/to/workspace/41/src
```

To discard apply state and commits immediately after testing:

```bash
scripts/port-bundle.sh drop vaapi-hevc-wip \
  --target 41 \
  --src-root /path/to/workspace/41/src \
  --backup-branch
```

`drop` runs `git reset --keep` only when the current `HEAD` exactly matches the
recorded applied head. Because `drop` rewinds history, use `--backup-branch` to
create backup branches before dropping.
