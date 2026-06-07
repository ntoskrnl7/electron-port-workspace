# widevine-cdm / 42

Reusable Electron target bundle.

Patch directories:

- `electron/*.patch`: apply in `src/electron`
- `chromium-direct/*.patch`: archived direct Chromium patches

Chromium CDM renderer visibility is stored through Electron's
`patches/chromium` stack. `chromium-direct` is reference material only.

Build args:

- Adds `enable_widevine = true` to Electron's common GN args.
- Does not set `bundle_widevine_cdm = true`; CDM binary redistribution needs a
  separate Widevine license decision.

Packaging:

```bash
ELECTRON_PACKAGE_INCLUDE_WIDEVINE_CDM=1 \
ELECTRON_PACKAGE_WIDEVINE_LICENSE_ACK=1 \
ELECTRON_PACKAGE_WIDEVINE_CDM_DIR=/path/to/WidevineCdm \
scripts/build-dev-electron-npm.sh --target 42
```

The packaging script copies the explicitly supplied CDM directory into the
binary package's `dist/WidevineCdm` and regenerates the platform zip. It does
not auto-discover or copy CDM files from an installed Chrome.

Use:

```bash
scripts/port-bundle.sh apply widevine-cdm --target 42 --src-root /path/to/src
scripts/port-bundle.sh undo widevine-cdm --target 42 --src-root /path/to/src
```
