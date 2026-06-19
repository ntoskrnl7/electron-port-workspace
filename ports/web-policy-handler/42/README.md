# web-policy-handler / 42

Electron 42 target bundle for `session.setWebPolicyHandler(handler)`.

## Contents

- `chromium-direct/0001-feat-expose-Blink-web-policy-checks-to-embedder.patch`
  - Adds a Blink platform web policy check hook and content renderer client
    bridge.
  - Wires CSP, Permissions Policy, Document Policy, sync XHR, and sync XHR page
    dismissal checks into the hook.
  - Avoids reading `ExecutionContext::Url()` during early SecurityContext
    attachment because that path can run before the initial document is fully
    safe to inspect.
- `chromium-direct/0002-fix-handle-sandboxed-document-policy-edge-cases.patch`
  - Allows the origin-sandboxed document transition to its opaque origin when
    the new origin keeps the previous origin as its precursor.
  - Skips the Electron web policy callback for valid internal Permissions
    Policy features that do not have a stable directive name, so Chromium's
    default behavior is preserved instead of crashing on `NOTREACHED()`.
- `electron/0001-feat-add-session-web-policy-handler.patch`
  - Adds `session.setWebPolicyHandler(handler)`.
  - Adds sync Mojo plumbing from renderer policy checks to the owning
    `Session`.
  - Adds docs, TypeScript post-processing, and main-process specs.
- `electron/0002-fix-skip-web-policy-IPC-without-a-handler.patch`
  - Short-circuits browser-side policy handling to Chromium's default result
    when the target session has no registered handler.

## Type Shape

Generated `electron.d.ts` is post-processed by
`script/fix-web-policy-typescript-definitions.mjs` so handler details are a
discriminated union:

```ts
type WebPolicyHandlerDetails =
  | WebContentSecurityPolicyHandlerDetails
  | WebPermissionsPolicyHandlerDetails
  | WebDocumentPolicyHandlerDetails
  | WebBrowserRuntimePolicyHandlerDetails;
```

`details.policy` narrows `details.name` to the corresponding exact string
union. There is no open-ended `string & {}` fallback.

## Validation

Validated on Electron 42.4.1 with:

```bash
npm run create-typescript-definitions
env -u ELECTRON_RUN_AS_NODE npm run test -- --skipYarnInstall --runners=main --grep "ses.setWebPolicyHandler"
env -u ELECTRON_RUN_AS_NODE npm run test -- --skipYarnInstall --runners=main --grep "sandboxed subframe initialization"
ELECTRON_BUILD_NO_REMOTE=1 ELECTRON_BUILD_REMOTE_JOBS=0 ELECTRON_BUILD_JOBS=16 ./scripts/build-dev-electron-npm.sh --target 42
ELECTRON_BUILD_NO_REMOTE=1 ELECTRON_BUILD_REMOTE_JOBS=0 ELECTRON_BUILD_JOBS=16 ./scripts/build-dev-electron-npm.sh --target 42 --include-widevine-cdm --widevine-license-ack
```

The package artifact is written under the selected target's Electron npm output
directory, for example:

```text
<workspace>/<target>/src/out/electron-npm/electron-linux-x64-<version>.tgz
```

Patch directories:

- `electron/*.patch`: primary patch sequence for `src/electron`
- `chromium-direct/*.patch`: archived Chromium source patches for review/debugging
- `chromium/*.patch`: direct Chromium `src` patches for explicit direct-only bundles

For `electronized_chromium_patches=true`, apply registers the archived
Chromium patches in Electron's `patches/chromium` stack, then materializes
those Chromium patches into Chromium `src`.

Use:

```bash
scripts/port-bundle.sh apply web-policy-handler --target 42 --src-root /path/to/src
scripts/port-bundle.sh undo web-policy-handler --target 42 --src-root /path/to/src
```

```powershell
.\scripts\port-bundle.ps1 apply web-policy-handler -Target 42 -SrcRoot C:\path\to\src
.\scripts\port-bundle.ps1 undo web-policy-handler -Target 42 -SrcRoot C:\path\to\src
```
