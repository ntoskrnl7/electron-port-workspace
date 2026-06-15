# shared-memory / 42

Reusable Electron target bundle.

Dependencies:

- `websocket-main-bridge`
- `worker-runtime`
- `window-prompt-dialog`
- `javascript-dialog-handler`

The dependencies are recorded in `manifest.txt` as
`depends_on=websocket-main-bridge,worker-runtime,window-prompt-dialog,javascript-dialog-handler`.
Apply those 42 target bundles first. `port-bundle` validates this before
applying the bundle.

Patch directories:

- `electron/*.patch`: primary patch sequence for `src/electron`
- `chromium-direct/*.patch`: archived Chromium source patches for review/debugging
- `chromium/*.patch`: direct Chromium `src` patches for explicit direct-only bundles

For `electronized_chromium_patches=true`, apply registers the archived
Chromium patches in Electron's `patches/chromium` stack, then materializes
those Chromium patches into Chromium `src`.

Use:

```bash
scripts/port-bundle.sh apply shared-memory --target 42 --src-root /path/to/src
scripts/port-bundle.sh undo shared-memory --target 42 --src-root /path/to/src
```

```powershell
.\scripts\port-bundle.ps1 apply shared-memory -Target 42 -SrcRoot C:\path\to\src
.\scripts\port-bundle.ps1 undo shared-memory -Target 42 -SrcRoot C:\path\to\src
```

## Electron 42.3.3 integration note

This bundle is rebased for the Electron 42.3.3 port stack with
`vaapi-hevc-wip` excluded. The patch applies after:

- `websocket-main-bridge`
- `worker-runtime`
- `window-prompt-dialog`
- `javascript-dialog-handler`

During the 42.3.x integration the main semantic conflict was in
`shell/renderer/service_worker_data.h`. The stored patch keeps the
`worker-runtime` service-worker helpers (`GetCurrent`, `process_metrics`, and
`MarkServiceWorkerPreloadRealmInitialized`) and adds the shared-memory
`RegisterSharedMemoryPool` override.

## Main-to-renderer channel follow-up

`0002-feat-support-main-to-renderer-shared-memory-channels.patch` extends
`SharedMemoryChannel` so the process that calls `SharedMemory.createChannel()`
is the producer and the peer process can call `SharedMemory.acceptChannel()`.
This keeps the existing renderer-to-main API shape and adds main-to-renderer
`send()` support without a public direction option.

The follow-up also keeps `sendAndWait()` scoped to renderer-to-main channels,
adds renderer-side channel acceptance, routes main sender wakeups through the
pool's target `WebFrameMain`, and returns borrowed main-process payloads after
the renderer releases the message.

Validated on Electron 42.4.0 with:

```bash
env -u ELECTRON_RUN_AS_NODE npm run test -- --skipYarnInstall --runners=main --grep "SharedMemory module"
```
