# Preload

Reusable Electron feature port for session-managed preload injection.

This bundle extends `session.registerPreloadScript` so applications can register
plain JavaScript preload scripts for:

- frames, with explicit `scope: 'main' | 'sub-frames' | 'all'`
- dedicated workers
- shared workers
- service workers

The frame `scope` option controls script injection only. It does not imply Node
integration or expose Node globals such as `process` or `require`.

The bundle also carries the same-origin subframe timing fix needed when early
JavaScript access, such as `frame-created` handlers or CDP new-document scripts,
touches an iframe before the iframe's real document commits.

Frame preload scripts can opt into those initial empty iframe contexts with
`runInInitialEmptyDocument: true`, which lets the preload run before CDP
`Page.addScriptToEvaluateOnNewDocument` scripts in early same-origin subframe
contexts and isolated/cross-origin subframe targets.

Target bundles live under:

```text
ports/preload/<target>/
```

Apply with:

```bash
scripts/port-bundle.sh apply preload --target <target> --src-root /path/to/src
```
