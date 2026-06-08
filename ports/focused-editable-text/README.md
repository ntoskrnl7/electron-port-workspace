# focused-editable-text

Adds Electron `WebContents` APIs for reading and watching a text snapshot from
the focused editable element, and for editing that focused editable text through
Chromium's text input path:

```ts
webContents.getFocusedEditableText(options?)

const watcher = webContents.watchFocusedEditableText(options, info => {
  // info is FocusedEditableText | null
})
watcher.close()

await webContents.editFocusedEditableText({
  kind: 'replaceText',
  text: 'replacement',
  start: 0,
  end: 5,
  selectionAfter: { start: 11, end: 11 }
})
```

`getFocusedEditableText()` returns a plain `FocusedEditableText | null`
structure through a Promise. `watchFocusedEditableText()` calls its callback
asynchronously with the same structure for the initial focused editable text
snapshot and later observed input state changes.

Selection and composition offsets are relative to the returned `text` string,
so callers can read the selected text with:

```ts
const selectedText = info.text.slice(info.selection.start, info.selection.end)
```

Modes:

- `full`: best-effort full focused editable DOM text, truncated around the
  selection when `maxLength` is exceeded.
- `value`: Chromium's focused `TextInputState.value` snapshot when available.
- `surrounding`: Blink surrounding-selection text.

Watcher options default to `mode: 'surrounding'`, `maxLength: 100000`, and
`throttleMs: 50`. Each watcher owns its own options and can be closed
independently. The watcher remains active even when the returned object is not
retained by JavaScript, but callers must keep the returned object if they need
to call `close()` before the WebContents is destroyed.

`editFocusedEditableText()` returns a Promise that resolves with the final
`FocusedEditableText | null` snapshot. `insertText` edits the current selection
or active composition. `replaceText` can edit the current selection, a closed
UTF-16 range, or an open-ended range where only `start` or `end` is supplied.
`selectionAfter` is best-effort and clamped to the final text length.

Password inputs return `null`. DOM-backed contenteditable editors are handled
best-effort. Editors backed by canvas, hidden controls, or application-internal
models may only expose the focused DOM control.
Initially empty text controls, including empty `<textarea>` elements in iframes,
are treated as editable text with `text: ''` rather than as unreadable text.

Target bundles live under:

```text
ports/focused-editable-text/<target>/
```
