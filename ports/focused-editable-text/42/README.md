# focused-editable-text / 42

Electron 42 target bundle for `webContents.getFocusedEditableText()`,
`webContents.watchFocusedEditableText()`, and
`webContents.editFocusedEditableText()`.

Dependencies:

- `text-caret-info`
- `dispatch-input-event`

The dependencies are recorded in `manifest.txt` as
`depends_on=text-caret-info,dispatch-input-event`. Apply those 42 target bundles
first. `port-bundle` validates this before applying the bundle.

This bundle contains:

- `webContents.getFocusedEditableText(options?)`
- `webContents.watchFocusedEditableText([options, ]callback)`
- `webContents.editFocusedEditableText(edit)`
- `FocusedEditableText`, `FocusedEditableTextOptions`, selection, and
  composition docs/types
- `FocusedEditableTextWatchOptions` and `FocusedEditableTextWatcher`
- `FocusedEditableTextInsertTextEdit`, `FocusedEditableTextReplaceTextEdit`,
  and `FocusedEditableTextEditSelection`
- watcher close semantics, per-watcher options, throttled/coalesced callback
  delivery, callback lifetime without retaining the return object, password
  input snapshots, and focus-loss null handling
- edit semantics for insert, replace current selection, closed/open-ended
  replace ranges, best-effort clamped `selectionAfter`, password input editing,
  contenteditable editing, and invalid input rejection
- initially empty text control normalization, including empty `<textarea>`
  elements in iframes
- Specs covering no editable focus, password input snapshots, input value mode,
  empty textarea value mode, contenteditable full mode, truncation, surrounding
  mode, and invalid options
- Specs covering watcher initial callback, updates, close, independent watcher
  options, callback lifetime without retaining the return object,
  password input snapshots, focus-loss nulls, and invalid watcher options

Patch directories:

- `electron/*.patch`: primary patch sequence for `src/electron`
- `chromium-direct/*.patch`: archived Chromium source patches for review/debugging
- `chromium/*.patch`: direct Chromium `src` patches for explicit direct-only bundles

There are no Chromium patches in this target bundle.

Verified on Electron 42:

```bash
npm run create-typescript-definitions
PATH=/tmp/electron-build-tools-gperf/root/usr/bin:$PATH e build --target electron --no-remote -j 16 -remote_jobs 0
env -u ELECTRON_RUN_AS_NODE npm run test -- --skipYarnInstall --runners=main --files spec/api-web-contents-spec.ts --grep "getFocusedEditableText"
env -u ELECTRON_RUN_AS_NODE npm run test -- --skipYarnInstall --runners=main --files spec/api-web-contents-spec.ts --grep "watchFocusedEditableText"
env -u ELECTRON_RUN_AS_NODE npm run test -- --skipYarnInstall --runners=main --files spec/api-web-contents-spec.ts --grep "editFocusedEditableText"
env -u ELECTRON_RUN_AS_NODE npm run test -- --skipYarnInstall --runners=main --files spec/api-web-contents-spec.ts --grep "FocusedEditableText"
env -u ELECTRON_RUN_AS_NODE npm run test -- --skipYarnInstall --runners=main --files spec/api-web-contents-spec.ts --grep "text-caret-info-changed event"
scripts/build-dev-electron-npm.sh --target 42 --include-widevine-cdm --widevine-license-ack
```

Use:

```bash
scripts/port-bundle.sh apply focused-editable-text --target 42 --src-root /path/to/src
scripts/port-bundle.sh undo focused-editable-text --target 42 --src-root /path/to/src
```

```powershell
.\scripts\port-bundle.ps1 apply focused-editable-text -Target 42 -SrcRoot C:\path\to\src
.\scripts\port-bundle.ps1 undo focused-editable-text -Target 42 -SrcRoot C:\path\to\src
```
