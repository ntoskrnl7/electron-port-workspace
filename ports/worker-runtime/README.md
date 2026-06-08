# worker-runtime

Reusable Electron worker runtime APIs and IPC port.

This port adds main-process runtime objects and scoped IPC dispatch for
dedicated workers, shared workers, and service workers.

Included behavior:

- `DedicatedWorkerMain`, `DedicatedWorkers`, `SharedWorkerMain`, and
  `SharedWorkers` APIs.
- `webContents.dedicatedWorkers` and `session.sharedWorkers`.
- dedicated/shared/service worker scoped IPC objects.
- worker-aware `ipcMain` event and invoke event unions.
- `event.isReturnValueSet` for synchronous IPC handlers.
- dedicated worker preload `injectionPoint`.

Target bundles live under:

```text
ports/worker-runtime/<target>/
```
