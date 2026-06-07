# user-agent-override / 42

Reusable Electron target bundle.

Patch directories:

- `electron/*.patch`: primary patch sequence for `src/electron`
- `chromium-direct/*.patch`: archived Chromium source patches for review/debugging
- `chromium/*.patch`: direct Chromium `src` patches for explicit direct-only bundles

For `electronized_chromium_patches=true`, apply registers the archived
Chromium patches in Electron's `patches/chromium` stack, then materializes
those Chromium patches into Chromium `src`.

Use:

```bash
scripts/port-bundle.sh apply user-agent-override --target 42 --src-root /path/to/src
scripts/port-bundle.sh undo user-agent-override --target 42 --src-root /path/to/src
```

```powershell
.\scripts\port-bundle.ps1 apply user-agent-override -Target 42 -SrcRoot C:\path\to\src
.\scripts\port-bundle.ps1 undo user-agent-override -Target 42 -SrcRoot C:\path\to\src
```
