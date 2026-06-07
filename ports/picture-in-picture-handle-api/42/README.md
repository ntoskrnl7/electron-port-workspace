# picture-in-picture-handle-api / 42

Electron 42 target bundle for the Picture-in-Picture handle API.

Patch directories:

- `chromium-direct/*.patch`: native Chromium PiP window state support.
- `electron/*.patch`: Electron app/WebContents events, handle classes, docs,
  and TypeScript types.

This bundle uses `electronized_chromium_patches=true`. Applying it registers
the archived Chromium patch into Electron's `patches/chromium` stack, applies
the Electron patch sequence, then materializes the Chromium patch in `src`.

Use:

```powershell
C:\work\electron\scripts\port-bundle.ps1 apply picture-in-picture-handle-api `
  -Target 42 `
  -SrcRoot C:\work\electron\42\src
```

```bash
scripts/port-bundle.sh apply picture-in-picture-handle-api \
  --target 42 \
  --src-root /path/to/electron/42/src
```
