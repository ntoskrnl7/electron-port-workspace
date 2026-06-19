# Port API Usage

This page is a short entry point for the APIs exposed by Electron Port
Workspace bundles.

The reference pages under [docs/api](api/README.md) are organized closer to
Electron's own API documentation style. The patch files under `ports/` remain
the source of truth for the Electron `docs/api/*.md` files that are applied to a
target Electron source tree.

## Reference Pages

| Page | Covers |
| --- | --- |
| [App](api/app.md) | App-level User-Agent override and Picture-in-Picture handle APIs. |
| [Session](api/session.md) | Preload scripts, session User-Agent override, WebSocket handlers, notifications, web policy checks, and shared worker access. |
| [WebContents](api/web-contents.md) | Input dispatch, caret snapshots, focused editable text, print requests, JavaScript dialogs, tab User-Agent override, dedicated workers, and PiP events. |
| [Worker Runtime](api/worker-runtime.md) | Dedicated worker, shared worker, service worker runtime objects and scoped IPC. |
| [WebSocket](api/web-socket.md) | Main-process WebSocket interception classes and socket control. |
| [WebNotification](api/web-notification.md) | Main-process Web Notification object and notification control methods. |
| [Web Policy](api/web-policy.md) | Main-process policy decisions for CSP, Permissions Policy, Document Policy, and runtime browser gates. |
| [SharedMemory](api/shared-memory.md) | Shared memory pools, channels, allocators, and binary message delivery. |
| [Runtime And Packaging](api/runtime-packaging.md) | WASM streaming fix, Widevine packaging, and VA-API HEVC notes. |

## Port Notes

Use the `ports/<feature>/README.md` and `ports/<feature>/<target>/README.md`
files for port maintenance details, apply order, conflict history, validation
commands, and target-specific caveats.
