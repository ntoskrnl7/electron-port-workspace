# websocket-main-bridge / 42

Reusable Electron 42 target bundle.

Dependency:

- `worker-runtime`

The dependency is recorded in `manifest.txt` as `depends_on=worker-runtime`.
Apply `worker-runtime/42` first. `port-bundle` validates this before applying
the bundle.

Patch directories:

- `electron/*.patch`: Electron API, docs, TypeScript surface, and spec.
- `chromium-direct/*.patch`: Chromium WebSocket connector and
  `ContentBrowserClient` metadata changes.

The manifest uses `electron_patch_stack_source=chromium-direct`. On apply, the
archived Chromium patch is registered into Electron's `patches/chromium` stack,
then applied to Chromium `src`. This keeps the Chromium patch-stack update
generated at apply time so it can coexist with other ports that also modify
`patches/chromium/.patches`.

Export source refs:

- Chromium: `e94e0cd13142c..239ca09aee366`
- Electron patch sequence:
  - `electron/0001-feat-add-session-websocket-handler.patch`
  - `electron/0002-fix-align-websocket-wrappable-tag-with-Electron-tag-.patch`

Verification on Electron 42:

- `e --config=42-release build -local_jobs 16 -t electron:electron`
- Direct focused spec:
  `./out/Release/electron electron/spec --files spec/chromium-spec.ts --grep "can be accepted and handled by the session WebSocket handler"`
- Dev npm package generated successfully with Widevine packaging enabled.

Use:

```bash
scripts/port-bundle.sh apply websocket-main-bridge --target 42 --src-root /path/to/src
scripts/port-bundle.sh undo websocket-main-bridge --target 42 --src-root /path/to/src
```

```powershell
.\scripts\port-bundle.ps1 apply websocket-main-bridge -Target 42 -SrcRoot C:\path\to\src
.\scripts\port-bundle.ps1 undo websocket-main-bridge -Target 42 -SrcRoot C:\path\to\src
```
