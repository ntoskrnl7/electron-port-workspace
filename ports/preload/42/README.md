# preload / 42

Reusable Electron target bundle.

Notes:

- `0001` extends session preload scripts to frame and worker scopes, including
  the generated TypeScript definitions for frame-only `scope`.
- `0002` delays subframe preload and Node initialization for the initial empty
  same-origin subframe document, including `frame-created` JavaScript execution
  and CDP new-document iframe access before the real frame document commits.
- `0003` adds the `runInInitialEmptyDocument` frame preload registration option
  so explicitly scoped frame preloads can opt into iframe initial empty document
  contexts and run before CDP new-document scripts. This covers both
  same-origin subframes and isolated/cross-origin subframe targets.
- `0004` disables sandbox by default when `nodeIntegrationInSubFrames` enables
  subframe Node integration, unless `sandbox: true` is explicit.
- `0005` merges the worker preload hook with Electron 42's existing renderer
  worker hook so the OOM stack trace hook remains registered and the class does
  not redeclare the same override.
- `0006` excludes Chromium's built-in PDF viewer extension from the DevTools
  extension preload path.
- `0007` disables DOM storage in PDF renderer processes so the built-in PDF
  viewer does not trigger a bad Mojo localStorage request.
- `0008` adds service worker preload targets so a service worker preload can run
  in Electron's existing shadow realm, the actual `ServiceWorkerGlobalScope`, or
  both.
- `0009` aligns preload startup data typing with Electron 42.3.x renderer
  startup data so the rebased bundle applies cleanly to `v42.3.3`.

This target was regenerated against a clean `v42.3.3` Electron tree after
`print-request-handler` and `widevine-cdm` were applied, matching the CI apply
order used by `electron-port-release.yml`.

Patch directories:

- `electron/*.patch`: apply in `src/electron`

There are no direct Chromium patches in this target bundle.

Use:

```bash
scripts/port-bundle.sh apply preload --target 42 --src-root /path/to/src
scripts/port-bundle.sh undo preload --target 42 --src-root /path/to/src
```

Verified apply sequence:

```bash
git -C <src>/electron am -3 ports/print-request-handler/42/electron/*.patch
git -C <src>/electron am -3 ports/widevine-cdm/42/electron/*.patch
git -C <src>/electron am -3 ports/preload/42/electron/*.patch
```
