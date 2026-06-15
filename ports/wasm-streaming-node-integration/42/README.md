# WASM Streaming with Node Integration / 42

Electron 42 target bundle for WebAssembly streaming compilation in
Node-integrated renderer and dedicated worker contexts.

## What It Fixes

When `nodeIntegration` or `nodeIntegrationInWorker` is enabled, Electron keeps
Blink's `fetch` implementation instead of Node's Undici implementation. Node
still installs its V8 WASM streaming callback, so streaming WASM APIs can enter
`node::wasm_web_api::StartStreamingCompilation()` before a JavaScript streaming
implementation has been registered.

This bundle registers an Electron-side implementation after Blink `fetch` and
`Response` are restored. It supports:

- `WebAssembly.compileStreaming(Response | Promise<Response>)`
- `WebAssembly.instantiateStreaming(Response | Promise<Response>, imports)`
- Blink `Response` bodies backed by `ReadableStream`
- case-insensitive `application/wasm` MIME matching
- stable behavior when page code later replaces `globalThis.Response` or
  `globalThis.Promise`

## Verification

Validated on Electron 42.4.0 with:

```bash
env -u ELECTRON_RUN_AS_NODE npm run test -- --skipYarnInstall --runners=main --grep "supports wasm streaming compilation with nodeIntegration enabled|Worker supports wasm streaming compilation with nodeIntegrationInWorker"
```

On Windows PowerShell:

```powershell
Remove-Item Env:ELECTRON_RUN_AS_NODE -ErrorAction SilentlyContinue
npm run test -- --skipYarnInstall --runners=main --grep "supports wasm streaming compilation with nodeIntegration enabled|Worker supports wasm streaming compilation with nodeIntegrationInWorker"
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
scripts/port-bundle.sh apply wasm-streaming-node-integration --target 42 --src-root /path/to/src
scripts/port-bundle.sh undo wasm-streaming-node-integration --target 42 --src-root /path/to/src
```

```powershell
.\scripts\port-bundle.ps1 apply wasm-streaming-node-integration -Target 42 -SrcRoot C:\path\to\src
.\scripts\port-bundle.ps1 undo wasm-streaming-node-integration -Target 42 -SrcRoot C:\path\to\src
```
