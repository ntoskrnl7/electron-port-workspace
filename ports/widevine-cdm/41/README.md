# widevine-cdm / 41

Electron 41 target bundle for Widevine/CDM integration.

## Contents

- `electron/*.patch`: Widevine/CDM integration for Electron `src/electron`,
  Chromium patch-stack entry, sandbox flag normalization, documentation patch,
  and default `enable_widevine = true` build args
- `chromium-direct/*.patch`: archived source Chromium patch

## Model

- The Chromium CDM renderer visibility change is stored in Electron's
  `src/electron/patches/chromium` stack to match Electron's distribution model.
- `chromium-direct/*.patch` is archived Chromium source material.

## Build Args

- Adds `enable_widevine = true` to Electron's common GN args.
- Does not set `bundle_widevine_cdm = true`. Until CDM binary redistribution
  rights are confirmed, runtime CDM files must be supplied separately.

## Packaging

The packaging scripts copy CDM files into the binary package's
`dist/WidevineCdm` only when a license-approved CDM source directory is provided:

```bash
ELECTRON_PACKAGE_INCLUDE_WIDEVINE_CDM=1 \
ELECTRON_PACKAGE_WIDEVINE_LICENSE_ACK=1 \
ELECTRON_PACKAGE_WIDEVINE_CDM_DIR=/path/to/WidevineCdm \
scripts/build-dev-electron-npm.sh --target 41
```

Scripts do not auto-discover or copy CDM files from an installed Chrome.

## Apply

```bash
scripts/port-bundle.sh apply widevine-cdm --target 41 --src-root /path/to/src
```

To apply on a test branch in a 41 workspace:

```bash
cd /path/to/workspace/41/src
git switch -c test/widevine-cdm
/path/to/electron-port-workspace/scripts/port-bundle.sh apply widevine-cdm --target 41 --src-root /path/to/workspace/41/src
```

## Undo

To preserve history and revert with commits:

```bash
scripts/port-bundle.sh undo widevine-cdm --target 41 --src-root /path/to/src
```

To remove the bundle without preserving revert commits immediately after apply:

```bash
scripts/port-bundle.sh drop widevine-cdm --target 41 --src-root /path/to/src
```
