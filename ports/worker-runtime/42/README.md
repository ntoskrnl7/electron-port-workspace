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

- Chromium range: none
- Electron base: `ef7c22501aab03d45e1eba30205c6a4b45241a43`
- Electron head: `fe865b21c188c0525a960101bc6fabe5eb996062`

Use:

```powershell
C:\work\electron\scripts\port-bundle.ps1 apply worker-runtime -Target 42 -SrcRoot C:\work\electron\42\src
C:\work\electron\scripts\port-bundle.ps1 undo worker-runtime -Target 42 -SrcRoot C:\work\electron\42\src
```

Validation performed before export:

- `e build --no-remote -t electron -local_jobs 20`
- `env -u ELECTRON_RUN_AS_NODE npm run test -- --skipYarnInstall --runners=main --grep "closing a WebContents with an active dedicated worker"`
- `env -u ELECTRON_RUN_AS_NODE npm run test -- --skipYarnInstall --runners=main --grep "WorkerMain module"`
