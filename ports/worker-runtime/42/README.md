# worker-runtime / 42

Reusable Electron 42 target bundle for worker runtime APIs.

Patch sequence:

- `electron/0001-feat-add-worker-runtime-APIs.patch`
- `electron/0002-fix-align-worker-wrappable-tags-with-Electron-tag-ra.patch`

Dependencies:

- `preload`
- `picture-in-picture-handle-api`

The dependencies are recorded in `manifest.txt` as
`depends_on=preload,picture-in-picture-handle-api` because this port extends
worker, preload, and type/runtime surfaces that overlap with earlier bundles in
the 42 all-port apply order. Apply those ports first.

This target no longer carries a Chromium direct patch. Worker context wrappable
tags are assigned in Electron's `wrappable_pointer_tags.h`.

Export source:

- Chromium base: `58b612a872f04c6a68fce0bfa26b9bb92cb4787a`
- Chromium head: `75c8f62795dbdfb387884f8b86548f1087daa246`
- Electron base: `ea9ee25884e24f0cdbe7fede3c5509f467a768cf`
- Electron head: `dd0247591d3eb732b5d9a911ca7e614e24da8da2`

Use:

```powershell
C:\work\electron\scripts\port-bundle.ps1 apply worker-runtime -Target 42 -SrcRoot C:\work\electron\42\src
C:\work\electron\scripts\port-bundle.ps1 undo worker-runtime -Target 42 -SrcRoot C:\work\electron\42\src
```

Validation performed before export:

- `npm run create-typescript-definitions`
- `npm run test -- --skipYarnInstall --runners=main --grep "isReturnValueSet|WorkerMain module"`
- `e --config=42-release build -local_jobs 20 -t electron`
- `C:\work\electron\scripts\build-dev-electron-npm.ps1 -Target 42 --include-widevine-cdm --widevine-license-ack`
