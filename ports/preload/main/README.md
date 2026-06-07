# preload / main

Reusable Electron target bundle.

Notes:

- `0001` extends session preload scripts to frame and worker scopes.
- `0002` delays subframe preload and Node initialization for the initial empty
  same-origin subframe document.
- `0003` disables sandbox by default when `nodeIntegrationInSubFrames` enables
  subframe Node integration, unless `sandbox: true` is explicit.
- `0004` merges the worker preload hook with Electron main's existing renderer
  worker hook so the OOM stack trace hook remains registered and the class does
  not redeclare the same override.
- `0005` excludes Chromium's built-in PDF viewer extension from the DevTools
  extension preload path.
- `0006` disables DOM storage in PDF renderer processes so the built-in PDF
  viewer does not trigger a bad Mojo localStorage request.

Patch directories:

- `electron/*.patch`: apply in `src/electron`

There are no direct Chromium patches in this target bundle.

Use:

```bash
scripts/port-bundle.sh apply preload --target main --src-root /path/to/src
scripts/port-bundle.sh undo preload --target main --src-root /path/to/src
```
