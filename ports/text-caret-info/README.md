# text-caret-info

Adds Electron APIs for observing and reading editable text caret state from
`WebContents`.

- `webContents.on('text-caret-info-changed', ...)` reports caret, selection,
  composition, frame, URL, and input metadata when the caret or active selection
  edge changes.
- `webContents.getTextCaretInfo()` returns the current caret snapshot or `null`
  when no editable caret information is available.

Target bundles live under:

```text
ports/text-caret-info/<target>/
```
