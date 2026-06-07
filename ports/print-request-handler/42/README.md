# print-request-handler / 42

Reusable Electron target bundle.

Patch directories:

- `electron/*.patch`: apply in `src/electron`; includes the Electron
  `patches/chromium` patch-stack entry.

There are no direct Chromium patch files in this target bundle.

Use:

```bash
scripts/port-bundle.sh apply print-request-handler --target 42 --src-root /path/to/src
scripts/port-bundle.sh undo print-request-handler --target 42 --src-root /path/to/src
```
