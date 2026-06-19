# Port API Reference

These pages summarize the application-facing APIs provided by the port bundles.
They intentionally mirror Electron's API documentation shape: module pages,
class pages, method names, event names, option objects, and short examples.

The complete Electron docs that land inside a target source tree are carried in
the patch files under `ports/<feature>/<target>/electron/*.patch`. This directory
is a readable reference for this workspace, not a replacement for generated
Electron API docs after the patches are applied.

| API page | Primary ports |
| --- | --- |
| [App](app.md) | `user-agent-override`, `picture-in-picture-handle-api` |
| [Session](session.md) | `preload`, `user-agent-override`, `websocket-main-bridge`, `web-notification-handler`, `web-policy-handler`, `worker-runtime` |
| [WebContents](web-contents.md) | `dispatch-input-event`, `text-caret-info`, `focused-editable-text`, `print-request-handler`, `javascript-dialog-handler`, `window-prompt-dialog`, `user-agent-override`, `worker-runtime`, `picture-in-picture-handle-api` |
| [Worker Runtime](worker-runtime.md) | `worker-runtime`, `preload` |
| [WebSocket](web-socket.md) | `websocket-main-bridge` |
| [WebNotification](web-notification.md) | `web-notification-handler` |
| [Web Policy](web-policy.md) | `web-policy-handler` |
| [SharedMemory](shared-memory.md) | `shared-memory` |
| [Runtime And Packaging](runtime-packaging.md) | `wasm-streaming-node-integration`, `widevine-cdm`, `vaapi-hevc-wip` |
