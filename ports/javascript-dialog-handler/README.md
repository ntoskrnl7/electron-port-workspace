# javascript-dialog-handler

Adds `webContents.setJavaScriptDialogHandler(handler)` for renderer-initiated
JavaScript dialogs.

The handler covers the `content::JavaScriptDialogManager` family only:

- `alert`
- `confirm`
- `prompt`
- `beforeunload`

The public dialog argument is a discriminated union. Each dialog type exposes
only the methods that are valid for that type:

- `alert.ok()`
- `confirm.confirm()` / `confirm.cancel()`
- `prompt.submit(value)` / `prompt.cancel()`
- `beforeunload.leave()` / `beforeunload.stay()`

Dialog methods can be called asynchronously after the handler returns. Existing
default behavior is preserved when no handler is installed: `alert`, `confirm`,
and `prompt` use Electron's built-in message box handling, while
`beforeunload` keeps using the existing `will-prevent-unload` event.

Target bundles live under:

```text
ports/javascript-dialog-handler/<target>/
```
