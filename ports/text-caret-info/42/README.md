# text-caret-info / 42

Electron 42 target bundle for editable text caret state APIs.

This bundle contains:

- `text-caret-info-changed` on `WebContents`
- `webContents.getTextCaretInfo()`

Patch directories:

- `electron/*.patch`: primary patch sequence for `src/electron`
- `chromium-direct/*.patch`: archived Chromium source patches for review/debugging
- `chromium/*.patch`: direct Chromium `src` patches for explicit direct-only bundles

For `electronized_chromium_patches=true`, apply first commits the Electron
patch-stack changes, then materializes the Chromium patches from
`src/electron/patches/chromium` into Chromium `src`.

Use:

```bash
scripts/port-bundle.sh apply text-caret-info --target 42 --src-root /path/to/src
scripts/port-bundle.sh undo text-caret-info --target 42 --src-root /path/to/src
```

```powershell
.\scripts\port-bundle.ps1 apply text-caret-info -Target 42 -SrcRoot C:\path\to\src
.\scripts\port-bundle.ps1 undo text-caret-info -Target 42 -SrcRoot C:\path\to\src
```
