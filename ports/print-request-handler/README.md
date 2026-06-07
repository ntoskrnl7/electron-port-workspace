# print-request-handler

Reusable Electron port bundle for the `webContents` print request handler.
The handler covers scripted print requests and PDF viewer plugin print requests.

This is an Electron-only export because the Electron feature commit already
contains the Chromium change as an Electron `patches/chromium` patch-stack
entry:

```text
patches/chromium/feat_allow_electron_to_handle_renderer_print_requests.patch
```

Do not also export or apply the Chromium `features/print` commit for this port,
or the same Chromium change can be applied twice.

## Current API direction

The active API is `webContents.setPrintRequestHandler(handler)`, not the older
`webContents` `will-print` event idea.

The handler receives the printing frame details and a request controller. It may
await renderer-dependent work such as `details.frame.executeJavaScript(...)`
before deciding what to do:

```js
webContents.setPrintRequestHandler(async (details, request) => {
  const html = await details.frame.executeJavaScript(
    'document.documentElement.outerHTML'
  )
  const options = await decidePrintOptions(details.url, html)

  request.handle(job => {
    job.toPDF(options).then(pdf => {
      // Store, inspect, upload, or print through an application pipeline.
    })
  })
})
```

`request.continue()` only continues the original native print flow when it is
called synchronously before the handler returns. If the handler returns without
calling `request.continue()` or `request.handle(...)`, Electron releases the
renderer from the original `window.print()` call and cancels that original print
request. A later `request.handle(job => { ... })` starts an independent
application-controlled job for the same frame through `job.print(options)` or
`job.toPDF(options)`.

## Retired `will-print` design

The earlier `will-print + takeRequest()` design was intentionally not carried
forward. It looked like a natural cancellable Electron event, but after
`takeRequest()` the initiating renderer could already be waiting on Chromium's
print settings response. If application code then awaited
`details.frame.executeJavaScript(...)`, renderer IPC, or preload bridge work from
that same frame before calling `request.toPDF(...)`, it could deadlock.

Keep these goals from the old design:

- identify the real printing frame, including subframes
- preserve the default behavior when no handler is installed
- support cancellation before native print UI/output
- let the app create a PDF for the requesting frame
- keep page print lifecycle cleanup, especially `afterprint`
- avoid affecting app-initiated `webContents.print()` and `printToPDF()`

Do not revive the `will-print` API shape unless the renderer-blocking problem is
solved with a different ownership model.

## Validation notes

The bundle includes public docs and TypeScript smoke coverage. Runtime coverage
is still the useful follow-up when testing a target workspace:

- main-frame and iframe `window.print()` requests
- PDF viewer plugin print requests
- synchronous `request.continue()`
- handler return without `continue()` or `handle(...)`
- asynchronous `request.handle(...)` followed by `job.toPDF(...)`
- asynchronous `request.handle(...)` followed by `job.print(...)`
- `beforeprint` / `afterprint` cleanup behavior
- unchanged `webContents.print()` and `webContents.printToPDF()` behavior
