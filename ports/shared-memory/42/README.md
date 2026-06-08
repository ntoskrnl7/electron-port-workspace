# shared-memory / 42

Reusable Electron 42 target bundle for shared-memory channel APIs.

Patch sequence:

- `electron/0001-feat-add-shared-memory-channel-APIs.patch`

This is an Electron-only bundle. It does not register Chromium patch-stack
entries.

Use:

```bash
scripts/port-bundle.sh apply shared-memory --target 42 --src-root /path/to/src
scripts/port-bundle.sh undo shared-memory --target 42 --src-root /path/to/src
```

```powershell
.\scripts\port-bundle.ps1 apply shared-memory -Target 42 -SrcRoot C:\path\to\src
.\scripts\port-bundle.ps1 undo shared-memory -Target 42 -SrcRoot C:\path\to\src
```

## Electron 42.3.3 import note

This bundle carries the shared-memory implementation that was already working
on Electron 42.3.0, with the import/rebase adjustment needed for Electron
42.3.3. It has no dependency on `vaapi-hevc-wip`; include or omit that media
port according to the target build. The shared-memory patch applies after:

- `websocket-main-bridge`
- `worker-runtime`
- `window-prompt-dialog`
- `javascript-dialog-handler`

The dependency order is recorded in `manifest.txt`.

During the 42.3.3 import the semantic conflict was in
`shell/renderer/service_worker_data.h`. The stored patch keeps the
`worker-runtime` service-worker helpers (`GetCurrent`, `process_metrics`, and
`MarkServiceWorkerPreloadRealmInitialized`) and adds the shared-memory
`RegisterSharedMemoryPool` override.

Validation after the 42.3.3 import adjustment:

```powershell
.\scripts\port-bundle.ps1 apply shared-memory -Target 42 -SrcRoot <src-root> -Repos electron
git diff --check HEAD~1..HEAD
```

The verified apply base was Electron commit
`e9dc7dccbb8c34b0f9b153e0b1c9945c6ae50b13`, and the resulting tree matched
the adjusted shared-memory commit
`f5cd74174c44e91dc1d7879934548d7d793282bc`.
