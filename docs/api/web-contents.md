# WebContents Additions

Process: [Main](../glossary.md#main-process)

This page documents `WebContents` APIs and events added by Electron Port
Workspace bundles.

## Methods

### `contents.dispatchInputEvent(inputEvent)` _Experimental_

Port: `dispatch-input-event`

* `inputEvent` [DispatchInputEventParams](#dispatchinputeventparams-object)

Returns `Promise<DispatchInputEventResult>` - Resolves with Chromium input ACK
details for the dispatched event.

Dispatches a trusted Chromium-backed input event to the page.

```js
const result = await win.webContents.dispatchInputEvent({
  kind: 'key',
  type: 'keyDown',
  code: 'KeyA',
  key: 'a'
})

if (!result.consumed) {
  await win.webContents.dispatchInputEvent({
    kind: 'insertText',
    text: 'a'
  })
}
```

Keyboard, text, and IME composition requests target the focused frame. Mouse and
touch requests route by coordinate hit testing.

Mouse and touch coordinates use CSS pixels in the WebContents coordinate space.
For keyboard input, use the returned `consumed` value to decide whether to send a
follow-up `insertText` event. A consumed key event means Chromium or the page
handled the key event.

### `contents.getTextCaretInfo()` _Experimental_

Port: `text-caret-info`

Returns `TextCaretInfo | null` - The current editable caret snapshot, or `null`
when no editable caret state is available.

The caret `bounds` are in WebContents coordinates. `screenBounds` is present
when Electron can map the caret rectangle into screen coordinates.

### `contents.getFocusedEditableText([options])` _Experimental_

Port: `focused-editable-text`

* `options` [FocusedEditableTextOptions](#focusededitabletextoptions-object)
  (optional)

Returns `Promise<FocusedEditableText | null>`.

```js
const info = await win.webContents.getFocusedEditableText({
  mode: 'full',
  maxLength: 100000,
  html: { maxLength: 20000, inlineStyles: true }
})
```

Supported modes are `full`, `value`, and `surrounding`.

`full` mode reads a best-effort DOM text snapshot of the focused editable
element. For contenteditable editors, block-like DOM structure such as `<p>`,
`<div>`, and `<br>` is represented with line breaks in `text`. Pass
`html: true` to include the focused contenteditable host's raw `innerHTML`, or
`html: { maxLength, inlineStyles }` to bound the HTML snapshot and optionally
copy computed styles into inline `style` attributes.

`value` mode reads Chromium's focused input value snapshot when it is available.
`surrounding` mode reads Blink's surrounding-selection text. Selection and
composition offsets are UTF-16 offsets into the returned `text` string.
Password inputs are returned with `inputType: 'password'`.

### `contents.watchFocusedEditableText([options, ]callback)` _Experimental_

Port: `focused-editable-text`

* `options` [FocusedEditableTextWatchOptions](#focusededitabletextwatchoptions-object)
  (optional)
* `callback` Function
  * `info` FocusedEditableText | null

Returns `FocusedEditableTextWatcher`.

Watches the currently focused editable text. The watcher owns its options and can
be closed independently.

```js
const watcher = win.webContents.watchFocusedEditableText({
  mode: 'surrounding',
  throttleMs: 50
}, info => {
  console.log(info?.text)
})

watcher.close()
```

The watcher delivers an initial callback and then coalesces later changes by
`throttleMs`. The default watch mode is `surrounding`, so HTML snapshots require
`mode: 'full'` when using watcher options.

### `contents.editFocusedEditableText(edit)` _Experimental_

Port: `focused-editable-text`

* `edit` [FocusedEditableTextEdit](#focusededitabletextedit-object)

Returns `Promise<FocusedEditableText | null>` - Resolves with the final focused
editable text snapshot.

Edits the currently focused editable text through Chromium's text input path.

```js
await win.webContents.editFocusedEditableText({
  kind: 'replaceText',
  start: 0,
  end: 5,
  text: 'replacement',
  selectionAfter: { start: 11, end: 11 }
})
```

`insertText` replaces the active selection or composition. `replaceText` can use
an explicit UTF-16 range in the current focused editable snapshot. If
`selectionAfter` is provided, Electron clamps it to the final text length.

### Extended `contents.loadURL(url[, options])`

Port: `user-agent-override`

* `url` string
* `options` Object (optional)
  * `userAgent` string (optional) - The legacy `User-Agent` string to use for
    this navigation.
  * `userAgentMetadata` [UserAgentMetadata](app.md#useragentmetadata-object)
    (optional) - User-Agent Client Hints metadata for this navigation. When this
    option is specified, `userAgent` must also be specified.

The `userAgentMetadata` option extends Electron's existing `loadURL` options. It
applies only to that navigation and does not install a persistent WebContents
override.

### `contents.setPrintRequestHandler(handler)` _Experimental_

Port: `print-request-handler`

* `handler` Function | null
  * `details` [PrintRequestDetails](#printrequestdetails-object)
  * `request` [PrintRequest](#printrequest-object)

Sets a handler for renderer-initiated print requests, such as `window.print()`
and PDF viewer print requests. Passing `null` clears the handler and restores
Electron's default print behavior.

If no handler is installed, Electron continues to use the normal native print
flow. When a handler is installed, the app must choose one of these outcomes for
each request:

* Continue the original native print flow by calling `request.continue()`
  synchronously before the handler returns.
* Cancel the original print request by returning without calling
  `request.continue()` or `request.handle(...)`.
* Take ownership of the request with `request.handle(callback)` and then call
  `job.print(options)` or `job.toPDF(options)` from the callback.

There is no separate `request.cancel()` method. Returning without handling the
request is the cancellation path.

```js
win.webContents.setPrintRequestHandler((details, request) => {
  if (shouldBlockPrinting(details)) {
    return
  }

  request.continue()
})
```

The handler may perform asynchronous work before deciding what to do. This is
useful when print options depend on frame state, for example when the app needs
to call `details.frame.executeJavaScript(...)`.

```js
win.webContents.setPrintRequestHandler(async (details, request) => {
  const html = await details.frame.executeJavaScript(
    'document.documentElement.outerHTML'
  )
  const options = await getPrintOptions(details.url, html)

  request.handle(job => {
    job.toPDF(options).then(pdf => {
      console.log(pdf.length)
    })
  })
})
```

`request.continue()` cannot be used after asynchronous work. It only continues
the original native print flow when called synchronously before the handler
returns. If the app needs to await before deciding and still print, use
`request.handle(...)` and call `job.print(options)`.

```js
win.webContents.setPrintRequestHandler(async (details, request) => {
  const options = await getPrintOptions(details)

  request.handle(async job => {
    await job.print(options)
  })
})
```

If `request` is not handled before the handler returns, Electron releases the
renderer from the original `window.print()` call and cancels that original print
request. A later `request.handle(...)` starts an independent app-controlled job
for the same frame; it does not resume the original native print continuation.

`request.continue()` or `request.handle(...)` may be called at most once for each
print request. App-initiated `webContents.print()` and `webContents.printToPDF()`
are not routed through this handler.

### `contents.setUserAgentOverride(options)`

Port: `user-agent-override`

* `options` Object
  * `userAgent` string - The legacy `User-Agent` string to use for this
    `WebContents`.
  * `userAgentMetadata` [UserAgentMetadata](app.md#useragentmetadata-object) -
    The User-Agent Client Hints metadata that matches `userAgent`.
  * `inheritToNewWindows` boolean (optional) - Whether child windows opened from
    this `WebContents` should inherit the override. Default is `false`.

Sets a WebContents-specific User-Agent string and Client Hints metadata for
future navigations and dedicated workers.

```js
win.webContents.setUserAgentOverride({
  userAgent: 'Mozilla/5.0 ElectronTabProfile',
  userAgentMetadata,
  inheritToNewWindows: true
})
```

Call this before `loadURL()` when the override must apply to the first
navigation. For frames and dedicated workers, the WebContents override wins over
the session and app overrides. Shared workers and service workers use the
session/app override chain because they are not owned by one WebContents.

`inheritToNewWindows` controls child windows opened from this WebContents. It is
`false` by default so a tab-specific identity does not leak into unrelated
windows unless the app opts in.

### `contents.clearUserAgentOverride()`

Port: `user-agent-override`

Clears the WebContents-specific User-Agent override. Future navigations and
future dedicated workers fall back to the session override, then the app
override, then Chromium defaults. Existing documents and already-running workers
are not changed retroactively.

### `contents.setJavaScriptDialogHandler(handler)`

Ports: `javascript-dialog-handler`, `window-prompt-dialog`

* `handler` Function | null
  * `dialog` AlertJavaScriptDialog | ConfirmJavaScriptDialog |
    PromptJavaScriptDialog | BeforeUnloadJavaScriptDialog

Handles renderer `alert`, `confirm`, `prompt`, and `beforeunload` dialogs.
Passing `null` clears the handler and restores Electron's default handling.

```js
win.webContents.setJavaScriptDialogHandler(async dialog => {
  switch (dialog.type) {
    case 'alert':
      dialog.ok()
      break
    case 'confirm':
      dialog.confirm()
      break
    case 'prompt':
      dialog.submit(dialog.defaultPromptText)
      break
    case 'beforeunload':
      dialog.stay()
      break
  }
})
```

Dialog objects include frame, URL, message text, and type-specific response
methods. Response methods can be called after the handler returns, which allows
custom asynchronous UI. Each dialog can be answered only once; later response
method calls return `false`.

When no handler is installed, `alert`, `confirm`, and `prompt` use Electron's
built-in message box behavior. `beforeunload` continues through Electron's
normal unload prevention flow.

## Events

### Event: 'text-caret-info-changed' _Experimental_

Port: `text-caret-info`

Returns:

* `event` Event
* `info` TextCaretInfo

Emitted when editable caret or active selection-edge state changes. The payload
has the same shape as [TextCaretInfo](#textcaretinfo-object) and includes a
`reason` string such as `focus` or `caret-move`.

### Event: 'dedicated-worker-created' _Experimental_

Port: `worker-runtime`

Returns:

* `event` Event
* `details` Object
  * `id` string
  * `url` string

Emitted when a dedicated worker associated with this WebContents is created.

### Event: 'dedicated-worker-destroyed' _Experimental_

Port: `worker-runtime`

Returns:

* `event` Event
* `details` Object
  * `id` string

Emitted before a dedicated worker associated with this WebContents is destroyed.

### Event: 'enter-picture-in-picture'

Port: `picture-in-picture-handle-api`

Returns:

* `event` Event
* `pip` VideoPictureInPicture | DocumentPictureInPicture

Emitted when this WebContents enters Picture-in-Picture.

### Event: 'leave-picture-in-picture'

Port: `picture-in-picture-handle-api`

Returns:

* `event` Event
* `pip` VideoPictureInPicture | DocumentPictureInPicture

Emitted when this WebContents leaves Picture-in-Picture.

## Properties

### `contents.dedicatedWorkers` _Readonly_ _Experimental_

Port: `worker-runtime`

The [DedicatedWorkers](worker-runtime.md#class-dedicatedworkers) collection for
this WebContents.

```js
win.webContents.dedicatedWorkers.on('created', details => {
  console.log(details.id, details.url)
})

const workers = win.webContents.dedicatedWorkers.getAllRunning()
```

See [Worker Runtime](worker-runtime.md).

### `contents.ipc` _Readonly_ _Experimental_

Port: `worker-runtime`

Provides WebContents-scoped IPC handlers.

## DispatchInputEventParams Object

The `inputEvent` parameter can be one of these shapes:

* Key event
  * `kind` string - `key`
  * `type` string - `rawKeyDown`, `keyDown`, `keyUp`, or `char`
  * `code` string (optional)
  * `key` string (optional)
  * `text` string (optional)
  * `modifiers` Integer (optional)
* Mouse event
  * `kind` string - `mouse`
  * `type` string - `mousePressed`, `mouseReleased`, `mouseMoved`, or
    `mouseWheel`
  * `x` number
  * `y` number
  * `button` string (optional)
  * `clickCount` Integer (optional)
  * `deltaX` number (optional)
  * `deltaY` number (optional)
  * `buttons` Integer (optional)
  * `pointerType` string (optional) - Can be `mouse` or `pen`.
* Touch event
  * `kind` string - `touch`
  * `type` string - `touchStart`, `touchEnd`, `touchMove`, or `touchCancel`
  * `touchPoints` Object[] (optional)
    * `id` Integer (optional)
    * `x` number
    * `y` number
    * `radiusX` number (optional)
    * `radiusY` number (optional)
    * `rotationAngle` number (optional)
    * `force` number (optional)
* Insert text event
  * `kind` string - `insertText`
  * `text` string
* IME composition event
  * `kind` string - `imeSetComposition`
  * `text` string
  * `selectionStart` Integer
  * `selectionEnd` Integer

## DispatchInputEventResult Object

* `inputEventId` string
* `consumed` boolean
* `ackState` string
* `ackSource` string
* `frame` WebFrameMain (optional)

Use `consumed` for ordinary routing decisions and `ackState` / `ackSource` for
diagnostics. `ackState` is Chromium's raw input ACK state and may be more
detailed than the boolean.

## FocusedEditableTextOptions Object

* `mode` string (optional) - Can be `full`, `value`, or `surrounding`.
* `maxLength` Integer (optional) - Maximum UTF-16 code units to return in
  `text`. Default is `100000`.
* `html` boolean | Object (optional) - Only valid with `mode: 'full'`, or when
  `mode` is omitted because `full` is the default.
  * `maxLength` Integer (optional) - Maximum UTF-16 code units to return in
    `html`.
  * `inlineStyles` boolean (optional) - Whether to clone computed styles into
    inline `style` attributes before returning `html`.

When `html` is enabled, the returned `html` is an inspection snapshot of the
focused contenteditable host. It is not sanitized and should not be treated as
trusted input.

## FocusedEditableTextWatchOptions Object

Extends [FocusedEditableTextOptions](#focusededitabletextoptions-object).

* `throttleMs` Integer (optional)

The watcher default `mode` is `surrounding`, unlike
`getFocusedEditableText()`, whose default is `full`. Pass `mode: 'full'`
explicitly when using `html` watcher options.

## FocusedEditableTextEdit Object

* `kind` string - Can be `insertText` or `replaceText`.
* `text` string
* `start` Integer (optional)
* `end` Integer (optional)
* `selectionAfter` Object (optional)
  * `start` Integer
  * `end` Integer

For `replaceText`, `start` and `end` are UTF-16 offsets into the focused editable
snapshot. If both are omitted, the current selection is replaced.

## FocusedEditableText Object

* `frame` WebFrameMain - The frame that owns the focused editable element.
* `url` string - The current URL of `frame`.
* `isMainFrame` boolean - Whether `frame` is the main frame of the WebContents.
* `inputType` string - The current Chromium text input type for the focused
  editable context. Examples include `text`, `password`, `textArea`,
  `contentEditable`, `null`, and `unknown`.
* `inputMode` string - The input mode requested by the focused editable
  context.
* `inputAction` string - The enter-key action requested by the focused editable
  context.
* `text` string - The captured editable text.
* `selection` Object
  * `start` Integer - UTF-16 offset into `text`.
  * `end` Integer - UTF-16 offset into `text`.
  * `isCollapsed` boolean - Whether the selection is collapsed to a caret.
* `composition` Object
  * `isComposing` boolean
  * `start` Integer (optional)
  * `end` Integer (optional)
* `source` string - The snapshot source. Can be `value`, `surrounding-selection`,
  or `dom`.
* `isPartial` boolean - Whether `text` was truncated.
* `html` string (optional) - The focused contenteditable host HTML when
  requested.
* `isHtmlPartial` boolean (optional) - Whether `html` was truncated.

Offsets are relative to the returned `text`, not necessarily the full backing
document when `isPartial` is `true`.

## FocusedEditableTextWatcher Object

### `watcher.close()`

Stops this watcher and releases its callback. A watcher also closes
automatically when the owning WebContents is destroyed.

## TextCaretInfo Object

* `frame` WebFrameMain - The frame that owns the focused editable caret.
* `url` string - The current URL of `frame`.
* `isMainFrame` boolean - Whether `frame` is the main frame of the WebContents.
* `inputType` string
* `inputMode` string
* `inputAction` string
* `caret` Object
  * `visible` boolean - Whether a caret or active selection edge is visible.
  * `bounds` Rectangle - Caret rectangle in WebContents coordinates.
  * `screenBounds` Rectangle (optional) - Caret rectangle in screen coordinates.
* `selection` Object (optional)
  * `isCollapsed` boolean
  * `start` number
  * `end` number
* `composition` Object
  * `isComposing` boolean
  * `start` number (optional)
  * `end` number (optional)
* `reason` string (optional) - Present on `text-caret-info-changed` events.

## PrintRequestDetails Object

* `frame` WebFrameMain - The frame that requested printing.
* `url` string - The URL associated with the print request.

## PrintRequest Object

### `request.continue()`

Continues the original native print flow.

This must be called synchronously before the print request handler returns. Do
not call this after `await`, a timer, IPC, or any other asynchronous boundary.
Use `request.handle(...)` for asynchronous decisions.

### `request.handle(callback)`

* `callback` Function
  * `job` [PrintRequestJob](#printrequestjob-object)

Handles the print request through an app-owned job.

If called before the handler returns, Electron does not continue the original
native print request. If called after the handler returns, Electron has already
released and canceled the original print request, and the callback starts an
independent app-controlled print or PDF job for the original requesting frame.

`request.handle(...)` may be called at most once.

### Cancellation

To cancel a renderer-initiated print request, return from the print request
handler without calling `request.continue()` or `request.handle(...)`.

```js
win.webContents.setPrintRequestHandler((details, request) => {
  if (isPrintingDisabledFor(details.url)) {
    return
  }

  request.continue()
})
```

## PrintRequestJob Object

### `job.print(options)`

Returns `Promise<void>`.

Prints the requesting frame.

### `job.toPDF(options)`

Returns `Promise<Buffer>`.

Creates a PDF for the requesting frame.

## JavaScriptDialog Object

All JavaScript dialog objects include:

* `type` string - `alert`, `confirm`, `prompt`, or `beforeunload`.
* `frame` WebFrameMain - The frame that requested the dialog.
* `title` string - The Chromium-provided dialog title.
* `messageText` string - The dialog message text. For `beforeunload`, this is
  Chromium's localized unload message.
* `defaultPromptText` string - The default text for `prompt` dialogs. Empty for
  other dialog types.
* `url` string - The last committed URL of the requesting frame.
* `isMainFrame` boolean - Whether the requesting frame is the main frame.

Type-specific response methods:

* Alert dialogs expose `ok()`.
* Confirm dialogs expose `confirm()` and `cancel()`.
* Prompt dialogs expose `submit(value)` and `cancel()`.
* Before-unload dialogs expose `leave()` and `stay()`.

Response methods return `true` when they successfully answer the pending dialog
and `false` when the dialog was already answered or canceled.
