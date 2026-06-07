# vaapi-hevc-wip / main

Reusable Electron target bundle.

Patch directories:

- `electron/*.patch`: apply in `src/electron`; adds and refreshes Electron
  `patches/chromium` patch-stack entries.

There are no direct Chromium archive files in this target bundle.

Use:

```bash
scripts/port-bundle.sh apply vaapi-hevc-wip --target main --src-root /path/to/src
scripts/port-bundle.sh undo vaapi-hevc-wip --target main --src-root /path/to/src
```
