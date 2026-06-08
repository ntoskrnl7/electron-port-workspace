# worker-runtime / 42

Reusable Electron 42 target bundle for worker runtime APIs.

Patch sequence:

- `chromium-direct/0001-gin-add-worker-main-wrappable-tags.patch`
- `electron/0001-feat-add-worker-runtime-APIs.patch`

Dependencies:

- `preload`

The dependency is recorded in `manifest.txt` as `depends_on=preload` because
this port extends worker and preload/runtime surfaces that overlap with the
preload port. Apply `preload` first.

The Chromium patch is archived under `chromium-direct` and the manifest uses
`electron_patch_stack_source=chromium-direct`. Applying this port registers the
Chromium patch into Electron's `patches/chromium` stack for the target tree, then
applies the Electron patch and materializes the Chromium patch in `src`.

Export source:

- Chromium base: `58b612a872f04c6a68fce0bfa26b9bb92cb4787a`
- Chromium head: `75c8f62795dbdfb387884f8b86548f1087daa246`
- Electron base: `ea9ee25884e24f0cdbe7fede3c5509f467a768cf`
- Electron head: `dd0247591d3eb732b5d9a911ca7e614e24da8da2`

Use:

```bash
scripts/port-bundle.sh apply worker-runtime --target 42 --src-root /path/to/src
scripts/port-bundle.sh undo worker-runtime --target 42 --src-root /path/to/src
```

```powershell
.\scripts\port-bundle.ps1 apply worker-runtime -Target 42 -SrcRoot C:\path\to\src
.\scripts\port-bundle.ps1 undo worker-runtime -Target 42 -SrcRoot C:\path\to\src
```

Validation performed before export:

- `npm run create-typescript-definitions`
- `npm run test -- --skipYarnInstall --runners=main --grep "isReturnValueSet|WorkerMain module"`
- `e --config=42-release build -local_jobs 20 -t electron`
- `.\scripts\build-dev-electron-npm.ps1 -Target 42 --include-widevine-cdm --widevine-license-ack`
