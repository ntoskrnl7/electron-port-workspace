# Electron Port Workspace

Electron Port Workspace manages Electron source checkouts by target and stores
reusable feature work as portable patch bundles.

The exported tree intentionally contains management scripts, documentation, and
port bundles only. It does not include large Chromium/Electron source checkouts;
create those with the scripts below.

Examples assume commands are run from the repository root. Replace
`./<target>/src` with the target source checkout path when using a different
workspace layout.

## Layout

```text
electron-port-workspace/
  <major>/src                 Electron/Chromium source tree for a major line
  main/src                    optional upstream main workspace
  ports/<feature>/<target>/   reusable patch bundle
  scripts/                    workspace automation
```

## Create Workspaces

Create a major-version workspace:

```bash
./scripts/create-electron-major.sh 42
```

Create it and sync a specific Electron tag:

```bash
./scripts/create-electron-major.sh 42 --tag v42.0.0 --sync
```

Create a separate upstream `main` workspace:

```bash
./scripts/create-electron-main.sh --sync
```

The scripts create build-tools configs in
`$HOME/.electron_build_tools/configs` by default. New targets use config names
such as `42-release`, `42-testing`, `main-release`, and `main-testing`.

## Build

Select the matching build-tools config before running the packaging scripts:

```bash
e use 42-release
./scripts/build-dev-electron-npm.sh --target 42
```

Release packaging uses the same target model:

```bash
e use 42-release
./scripts/build-release-electron-npm.sh --target 42
```

Useful environment overrides:

```text
ELECTRON_WORKSPACE_TARGET=<target>
ELECTRON_WORKSPACE_SRC_DIR=/path/to/src
ELECTRON_BUILD_NO_REMOTE=1
ELECTRON_BUILD_JOBS=16
ELECTRON_BUILD_REMOTE_JOBS=0
ELECTRON_PACKAGE_DEV_NUMBER=7
ELECTRON_PACKAGE_NAME=electron
ELECTRON_PACKAGE_KIND=platform|wrapper|split|bundled
ELECTRON_PACKAGE_STAGING_DIR=/path/to/output
```

The package script defaults to platform packages such as
`electron-linux-x64`. Use `--package-kind wrapper` to create a wrapper package
with platform packages in `optionalDependencies`, or `--package-kind bundled`
for a single-package layout.

## Widevine

Widevine CDM packaging is optional and requires explicit license
acknowledgement.

```bash
./scripts/build-dev-electron-npm.sh \
  --target 42 \
  --include-widevine-cdm \
  --widevine-license-ack
```

Equivalent environment overrides:

```text
ELECTRON_PACKAGE_INCLUDE_WIDEVINE_CDM=1
ELECTRON_PACKAGE_WIDEVINE_LICENSE_ACK=1
ELECTRON_PACKAGE_WIDEVINE_CDM_DIR=/path/to/WidevineCdm
```

To prepare a CDM directory manually on Linux:

```bash
./scripts/resolve-widevine-cdm.sh \
  --target 42 \
  --license-ack \
  --download-if-missing \
  --prefer-download \
  --require-chrome-major-match \
  --force \
  --print-environment
```

## Port Bundles

List bundles:

```bash
./scripts/port-bundle.sh list
```

Apply a bundle to a target workspace:

```bash
./scripts/port-bundle.sh apply <feature> --target 42
```

Export feature commits into a bundle:

```bash
./scripts/port-bundle.sh export <feature> \
  --target 42 \
  --src-root ./42/src \
  --electron-base <base-ref> \
  --electron-head <head-ref> \
  --clear
```

For features with Chromium commits, export the Chromium range too. The bundle
stores those patches under `chromium-direct/` and registers them into
Electron's `patches/chromium` stack at apply time.

## Upgrade Target

Use the wrapper to move an existing target to a new Electron tag and reapply
selected port bundles:

```bash
./scripts/upgrade-electron-target.sh \
  --target 42 \
  --tag v42.1.0 \
  --ports print-request-handler,preload,text-caret-info,user-agent-override \
  --build
```

The wrapper checks both Chromium `src` and nested `src/electron` for a clean
state, creates backup branches, syncs the requested upstream tag, creates a new
work branch, applies ports in the given order, and optionally runs the dev npm
package build.

## Tests

When running Electron specs, make sure `ELECTRON_RUN_AS_NODE` is not set.

```powershell
$env:ELECTRON_RUN_AS_NODE=$null
npm run test -- --skipYarnInstall --runners=main --grep "<test name>"
```

## License

The management scripts and documentation in this repository are licensed under
the MIT License. See [LICENSE](LICENSE).

Patch files under `ports/` preserve the original commit authorship from the
Electron and Chromium source trees they are meant to modify. Use those patch
files together with the applicable upstream project licenses, copyright notices,
and redistribution terms. This repository does not include Widevine CDM
binaries; any Widevine packaging requires separate license acknowledgement and
redistribution rights.
