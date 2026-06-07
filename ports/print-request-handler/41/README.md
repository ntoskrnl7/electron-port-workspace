# print-request-handler / 41

Electron 41 target bundle for the `webContents` print request handler.

Patch directories:

- `electron/*.patch`: apply in `src/electron`

Use:

```bash
scripts/port-bundle.sh apply print-request-handler --target 41 --src-root /path/to/src
scripts/port-bundle.sh undo print-request-handler --target 41 --src-root /path/to/src
```
