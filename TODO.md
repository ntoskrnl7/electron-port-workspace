# Pending Work

## Investigate official Electron patch export flow for port bundles

Context:

- `port-bundle.sh export --chromium-base ... --chromium-head ...` currently
  uses its own feature-range export flow:
  - `git format-patch` Chromium commits into
    `ports/<feature>/<target>/chromium-direct`
  - copy those patches into `src/electron/patches/chromium`
  - append filenames to `src/electron/patches/chromium/.patches`
  - commit the Electron patch-stack change
  - export that Electron commit into `ports/<feature>/<target>/electron`

- Electron build-tools also has:
  - `e patches chromium`
  - `src/electron/script/git-export-patches`
  - `src/electron/script/export_all_patches.py`

- Do not replace the current `port-bundle.sh` behavior just because these
  official tools exist. `e patches chromium` refreshes the target patch stack
  and may rewrite existing patches, while `port-bundle.sh` needs feature-range
  bundle export behavior.

Investigation plan for a future feature branch:

1. Use a disposable branch or disposable workspace only.
2. Create or choose a small feature with both Chromium and Electron commits.
3. Export it with the current `port-bundle.sh` one-shot command:

   ```bash
   ./scripts/port-bundle.sh export <feature> \
     --target <target> \
     --src-root /path/to/workspace/41/src \
     --chromium-base <chromium-base-ref> \
     --chromium-head <chromium-feature-ref> \
     --electron-base <electron-base-ref> \
     --electron-head <electron-feature-ref> \
     --clear
   ```

4. Separately test whether Electron's official export helper can safely produce
   equivalent feature-range patch files without refreshing the full
   `patches/chromium` stack.
   Candidate to test first:

   ```bash
   cd /path/to/workspace/41/src
   ./electron/script/git-export-patches \
     -o /tmp/<feature>-chromium-patches \
     <chromium-base-ref>..<chromium-feature-ref>
   ```

5. Compare outputs:
   - patch filenames
   - patch headers
   - `Patch-Dir` / `Patch-Filename` metadata handling
   - `.patches` ordering
   - whether `e patches chromium` would rewrite unrelated existing patches

6. Only consider changing `port-bundle.sh` if the official-helper flow is
   proven to produce equivalent or better bundle output and can be tested
   without rewriting unrelated Electron patches.

7. Before any real script change, verify:
   - `bash -n scripts/port-bundle.sh`
   - disposable repo smoke test
   - real disposable Electron workspace export
   - applying the exported bundle to a temporary branch
   - Electron patch apply/sync flow for the generated Chromium patch stack

Current decision:

- Keep the current `port-bundle.sh` feature-range export implementation.
- Do not integrate `e patches chromium` into `port-bundle.sh` without the
  investigation above.

## Design worker context isolation as a future feature

Context:

- The current worker preload design intentionally keeps preload injection and
  Node.js integration as separate controls:
  - `nodeIntegrationInWorker` decides whether dedicated workers get Node.js
    globals such as `process` and `require`.
  - `session.registerPreloadScript({ type: 'dedicated-worker', ... })` decides
    whether a plain JavaScript preload script is injected into dedicated worker
    global scope.
  - `session.registerPreloadScript({ type: 'shared-worker' | 'service-worker',
    ... })` handles script injection for worker types that do not use
    `nodeIntegrationInWorker`.

- Dedicated workers currently do not have frame-style `contextIsolation`.
  When `nodeIntegrationInWorker` is enabled, Electron attaches the Node.js
  environment directly to the worker's execution context, so
  `globalThis.process` is visible in the worker global scope.

- A worker context isolation feature would likely need a separate worker
  isolated world or realm:

  ```text
  DedicatedWorker
  ├─ worker main world
  │  └─ worker author script globalThis
  └─ worker isolated world
     └─ preload globalThis
  ```

Design notes for a future feature branch:

1. Do not retrofit frame `contextIsolation` behavior onto workers as a small
   option-only change. Worker isolation needs its own design.
2. Decide how an isolated worker preload can expose APIs to the worker main
   world. A worker-specific bridge may be needed, for example:

   ```ts
   workerContextBridge.exposeInWorkerGlobal('api', { ... })
   ```

3. Define event semantics clearly:
   - which world receives `message` events first
   - how `postMessage` behaves across worlds
   - how `MessagePort`, transferable objects, promises, and errors cross the
     bridge
   - whether APIs such as `fetch`, `crypto`, `indexedDB`, `caches`, timers, and
     `navigator` are shared wrappers or per-world objects

4. Keep the current plain worker preload behavior stable unless a new opt-in is
   introduced. Candidate API shapes:

   ```ts
   session.registerPreloadScript({
     type: 'dedicated-worker',
     filePath,
     world: 'main' | 'isolated'
   })
   ```

   or:

   ```ts
   webPreferences: {
     workerContextIsolation: true
   }
   ```

5. Document that today's worker preload scripts run in the worker global scope,
   not in a frame-style isolated Electron context.

Current decision:

- Do not implement worker context isolation as part of the worker preload
  injection feature.
- Track it as a separate future design task because it requires bridge
  semantics, event ordering, and worker-global API policy decisions.

## Design dynamic preload selection hooks

Context:

- Static preload registration is good for simple, stable policy:

  ```ts
  session.registerPreloadScript({
    type: 'frame' | 'dedicated-worker' | 'shared-worker' | 'service-worker',
    filePath,
    scope: 'main' | 'sub-frames' | 'all'
  })
  ```

- Some applications need dynamic policy at the moment a JavaScript execution
  context is created:
  - choose different scripts for different frame URLs
  - use parent-frame, initiator, or top-frame information
  - treat `about:blank`, `srcdoc`, `blob:`, redirects, workers, and service
    workers differently
  - apply app-specific trust or tenancy policy that is hard to express as a
    small built-in `matches` option

- A first thought is an event such as:

  ```ts
  session.on('context-created', (event, details) => {
    // choose scripts for this target
  })
  ```

  However, a normal EventEmitter-style notification may be the wrong shape
  because preload selection happens extremely early and must decide scripts
  before the target's author code runs.

Preferred direction:

- Consider a preload selection resolver/handler API instead of a passive event:

  ```ts
  session.setPreloadScriptResolver((details) => {
    return [
      { filePath: path.join(__dirname, 'base-preload.js') },
      details.type === 'frame' && details.isMainFrame
        ? { filePath: path.join(__dirname, 'main-frame-preload.js') }
        : null
    ].filter(Boolean);
  });
  ```

  or:

  ```ts
  session.setPreloadScriptHandler((details) => ({
    scripts: [
      { filePath: path.join(__dirname, 'policy-preload.js') }
    ]
  }));
  ```

Design constraints:

1. Prefer a synchronous resolver. Avoid promises or arbitrary async work in the
   initial design because preload selection is on the critical path for frame
   and worker startup.
2. The resolver should return preload descriptors, not script source strings.
   Browser-side file loading can keep the same validation, absolute-path
   checks, and error reporting model as static registration.
3. Resolver failures should not crash or hang renderer startup. Decide whether
   to:
   - fail closed and inject no resolver-provided scripts
   - emit a preload resolver error event
   - still run statically registered preloads
4. Static registrations and dynamic resolver results need deterministic
   ordering. Candidate order:
   - static session preloads first
   - resolver-returned preloads next
   - `webPreferences.preload` last for frame contexts, preserving today's
     ordering
5. The resolver must not imply Node.js integration. It should only select
   preload injection. Node.js globals remain controlled by existing
   preferences such as `nodeIntegration`, `nodeIntegrationInSubFrames`, and
   `nodeIntegrationInWorker`.
6. It should cover all target kinds with one details shape:

   ```ts
   interface PreloadTargetDetails {
     type: 'frame' | 'dedicated-worker' | 'shared-worker' | 'service-worker';
     url: string;
     origin?: string;
     isMainFrame?: boolean;
     frameRoutingId?: number;
     parentFrameRoutingId?: number;
     topFrameUrl?: string;
     parentFrameUrl?: string;
     webContentsId?: number;
     workerId?: number;
     serviceWorkerVersionId?: number;
   }
   ```

7. Be careful with URL semantics:
   - `about:blank` and `srcdoc` often need parent-frame context.
   - `blob:` URLs often need creator or initiator context.
   - initial URLs may differ from committed URLs after redirects.
   - service workers have scope/registration URLs that may matter more than
     script URLs.
8. Avoid broad performance regressions. If every subframe or worker must sync
   into the browser process to ask for resolver output, measure the cost and
   consider caching compiled policy or precomputing session-level decisions.
9. Decide whether this API can coexist with, replace, or internally implement a
   future declarative URL filtering API.
10. If the API is exposed, document that it is a policy hook for preload
    selection, not a lifecycle event for observing every JS context.

Current decision:

- Do not implement this as part of the current frame/worker preload work.
- Keep the current `scope` option as the simple static control.
- Revisit this as a separate advanced preload policy feature when dynamic URL,
  parent-frame, or tenant-specific script selection becomes necessary.
