# dispatch-input-event / 42

Reusable Electron 42 target bundle for `webContents.dispatchInputEvent`.

This bundle was exported from the current Electron 42 ports stack, not
from a pristine `v42.0.1` checkout. Apply it to a tree that already has the same
baseline ports applied, or validate conflicts in a temporary branch first.

Tested baseline order before this bundle:

1. `print-request-handler`
2. `widevine-cdm`
3. `preload`
4. `text-caret-info`
5. `user-agent-override`

The same relationship is recorded in `manifest.txt` as:

```text
depends_on=print-request-handler,widevine-cdm,preload,text-caret-info,user-agent-override
```

`port-bundle` checks those dependencies during apply. Apply the baseline ports
first instead of relying on this bundle to reorder them.

Verified on Windows with:

```powershell
Remove-Item Env:ELECTRON_RUN_AS_NODE -ErrorAction SilentlyContinue
node electron/script/spec-runner.js --runners main --skipYarnInstall --files spec/api-web-contents-spec.ts -g "dispatchInputEvent\(inputEvent\)"
```

Expected result: 25 passing `dispatchInputEvent(inputEvent)` tests.

Patch directories:

- `electron/*.patch`: primary patch sequence for `src/electron`
- `chromium-direct/*.patch`: archived Chromium source patches for review/debugging
- `chromium/*.patch`: direct Chromium `src` patches for explicit direct-only bundles

For `electronized_chromium_patches=true`, apply registers the archived
Chromium patches in Electron's `patches/chromium` stack, then materializes
those Chromium patches into Chromium `src`.

Use:

```bash
scripts/port-bundle.sh apply dispatch-input-event --target 42 --src-root /path/to/src
scripts/port-bundle.sh undo dispatch-input-event --target 42 --src-root /path/to/src
```

```powershell
.\scripts\port-bundle.ps1 apply dispatch-input-event -Target 42 -SrcRoot C:\path\to\src
.\scripts\port-bundle.ps1 undo dispatch-input-event -Target 42 -SrcRoot C:\path\to\src
```
