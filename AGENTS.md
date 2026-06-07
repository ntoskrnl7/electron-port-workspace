# Maintainer Notes for Electron Port Workspace

## Purpose

Electron Port Workspace manages Electron source trees by target and keeps
reusable feature patches as portable bundles.

These notes are checked in so future maintainers and scripted workflows can
preserve the same safety rules. The important thing is not who runs a command,
but that work happens in the correct Chromium or Electron repository and that
reusable port bundles stay reproducible.

The main goal is to implement or collect a feature once, store it in
`ports/<feature>/<target>/`, and apply it consistently to new Electron major
versions, upstream `main`, or temporary test branches.

## Workspace Layout

- `<repo>/<major>/src`
  - Electron/Chromium source tree for a specific Electron major version.

- `<repo>/main/src`
  - Optional upstream `main` source tree.

- `<repo>/ports/<feature>`
  - Feature-level notes.

- `<repo>/ports/<feature>/<target>`
  - Reusable target-specific feature patch bundle.

- `<repo>/scripts`
  - Workspace automation scripts.

The workspace root may be a small management git repository for scripts,
documents, and port bundles. Do not use that status as a proxy for source-tree
state; check git state inside the relevant Chromium `src` repo and the nested
Electron `src/electron` repo.

## First Checks

Run or inspect these before making changes:

```bash
cd <repo>
sed -n '1,220p' README.md
sed -n '1,220p' TODO.md
sed -n '1,220p' ports/README.md
find ports -maxdepth 3 -type f | sort
find scripts -maxdepth 1 -type f | sort
```

When working on a specific target:

```bash
cd <repo>/<target>/src
git status --short --branch

cd <repo>/<target>/src/electron
git status --short --branch
```

When working on a specific bundle:

```bash
sed -n '1,220p' ports/<feature>/README.md
sed -n '1,220p' ports/<feature>/<target>/README.md
cat ports/<feature>/<target>/manifest.txt
./scripts/port-bundle.sh status <feature> --target <target>
```

## Core Scripts

- `scripts/create-electron-major.sh`
  - Creates a new major-version workspace and build-tools configs.

- `scripts/create-electron-main.sh`
  - Creates a separate upstream-main workspace and build-tools configs.

- `scripts/upgrade-electron-target.sh`
  - Checks out a new Electron tag for an existing target, syncs Chromium,
    creates backup/work branches, applies selected ports, and can run a dev npm
    package build.

- `scripts/build-dev-electron-npm.sh`
  - Builds `electron:electron_dist_zip`, generates TypeScript definitions, and
    packages a dev npm tarball.

- `scripts/build-release-electron-npm.sh`
  - Uses the same workspace target model and packages a release npm tarball.

- `scripts/resolve-widevine-cdm.sh`
  - Resolves a Linux Widevine CDM directory compatible with the target Electron
    Chromium version when Widevine packaging is explicitly requested.

- `scripts/port-bundle.sh`
  - Lists, exports, applies, reverts, drops, and checks reusable port bundles.

Useful generic environment overrides:

```text
ELECTRON_WORKSPACE_TARGET=<target>
ELECTRON_WORKSPACE_SRC_DIR=/path/to/src
ELECTRON_BUILD_NO_REMOTE=1
ELECTRON_BUILD_JOBS=16
ELECTRON_BUILD_REMOTE_JOBS=0
ELECTRON_PACKAGE_INCLUDE_WIDEVINE_CDM=1
ELECTRON_PACKAGE_WIDEVINE_LICENSE_ACK=1
ELECTRON_PACKAGE_WIDEVINE_CDM_DIR=/path/to/WidevineCdm
```

## Port Bundle Model

Feature bundles live under:

```text
ports/<feature>/
  README.md
  <target>/
    README.md
    chromium/*.patch
    chromium-direct/*.patch
    electron/*.patch
    manifest.txt
```

`electron/*.patch` applies to `src/electron`. `chromium-direct/*.patch`
archives Chromium commits and is registered into Electron's Chromium patch
stack at apply time when `electron_patch_stack_source=chromium-direct` is set.

If `depends_on` is present in a manifest, apply dependency ports explicitly
first. The bundle tools validate dependency state but do not reorder or
auto-apply dependencies.

## Safety Rules

- Do not use destructive reset commands unless explicitly requested.
- Do not revert unrelated user changes.
- Prefer `port-bundle.sh undo` when removing an applied bundle while keeping
  history.
- Use `port-bundle.sh drop` only on experimental branches where the
  apply/revert history can be discarded.
- Apply feature bundles on a temporary branch first unless the user explicitly
  asks to modify the current branch.
- Before exporting a bundle, verify that the chosen `base..head` range contains
  only the intended feature commits.
- For ports with Chromium commits, prefer exporting from the Chromium commit
  range and let `electron_patch_stack_source=chromium-direct` handle Electron
  patch-stack registration at apply time.
- Before applying a bundle, check git status in both Chromium `src` and
  Electron `src/electron`.

## Build Notes

Do not invoke `ninja` directly for Electron builds. Use one of:

```bash
./scripts/build-dev-electron-npm.sh --target <target>
e build
```

On Windows, use the matching PowerShell scripts:

```powershell
.\scripts\build-dev-electron-npm.ps1 -Target 42
.\scripts\build-release-electron-npm.ps1 -Target 42
```

When running Electron specs, make sure `ELECTRON_RUN_AS_NODE` is not set.
