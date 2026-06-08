# javascript-dialog-handler / 42

Reusable Electron 42 target bundle for
`webContents.setJavaScriptDialogHandler(handler)`.

This target patch is Electron-only. It changes:

- `lib/browser/api/web-contents.ts` for the public handler and type-specific
  dialog response objects.
- `shell/browser/api/electron_api_web_contents.*` so `beforeunload` can be
  bridged through the same handler when one is installed, while preserving the
  legacy `will-prevent-unload` path otherwise, and so JavaScript dialog titles
  are populated from Chromium's localized title helpers/resources.
- API docs and generated-type source docs for the public discriminated union.
- Specs covering `alert`, `confirm`, `prompt`, async `beforeunload`, and legacy
  `will-prevent-unload` behavior.

Dependency:

- `focused-editable-text`

The dependency is recorded in `manifest.txt` as
`depends_on=focused-editable-text`. Apply `focused-editable-text/42` first.
`port-bundle` validates this before applying the bundle.

Patch sequence:

- `electron/0001-feat-add-JavaScript-dialog-handler.patch`
- `electron/0002-fix-pass-JavaScript-dialog-object-first.patch`
- `electron/0003-fix-fold-JavaScript-dialog-details-into-dialog.patch`
- `electron/0004-fix-expose-localized-beforeunload-dialog-text.patch`
- `electron/0005-fix-expose-JavaScript-dialog-titles.patch`

Validation used for this target:

```bash
cd /path/to/workspace/42/src/electron
npm run create-typescript-definitions
cd /path/to/workspace/42/src
# Standard build:
e --config=42-release build -local_jobs 16 -t electron:electron
# Local fallback used when remote build auth is unavailable:
e --config=42-release build --no-remote -local_jobs 16 -t electron:electron
cd /path/to/workspace/42/src/electron
env -u ELECTRON_RUN_AS_NODE npm run test -- --skipYarnInstall --runners=main --grep "synchronous prompts|will-prevent-unload event"
env -u ELECTRON_RUN_AS_NODE npm run test -- --skipYarnInstall --runners=main --grep "setJavaScriptDialogHandler"
env -u ELECTRON_RUN_AS_NODE npm run test -- --skipYarnInstall --runners=main --grep "setJavaScriptDialogHandler|synchronous prompts"
cd /path/to/workspace
scripts/build-dev-electron-npm.sh --target 42 --include-widevine-cdm --widevine-license-ack
```

Patch directories:

- `electron/*.patch`: primary patch sequence for `src/electron`
- `chromium-direct/*.patch`: archived Chromium source patches for review/debugging
- `chromium/*.patch`: direct Chromium `src` patches for explicit direct-only bundles

For `electronized_chromium_patches=true`, apply registers the archived
Chromium patches in Electron's `patches/chromium` stack, then materializes
those Chromium patches into Chromium `src`.

Use:

```bash
scripts/port-bundle.sh apply javascript-dialog-handler --target 42 --src-root /path/to/src
scripts/port-bundle.sh undo javascript-dialog-handler --target 42 --src-root /path/to/src
```

```powershell
.\scripts\port-bundle.ps1 apply javascript-dialog-handler -Target 42 -SrcRoot C:\path\to\src
.\scripts\port-bundle.ps1 undo javascript-dialog-handler -Target 42 -SrcRoot C:\path\to\src
```
