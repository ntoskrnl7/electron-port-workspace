# Runtime And Packaging

This page covers port bundles that primarily affect runtime behavior or package
contents instead of adding a new app-facing JavaScript API.

## WASM Streaming With Node Integration

Port: `wasm-streaming-node-integration`

This port restores expected Web Platform behavior for Node-integrated renderer
and dedicated worker contexts.

```js
const module = await WebAssembly.compileStreaming(fetch('/module.wasm'))
```

It covers:

- `WebAssembly.compileStreaming(Response | Promise<Response>)`
- `WebAssembly.instantiateStreaming(Response | Promise<Response>, imports)`
- Blink `Response` bodies backed by `ReadableStream`
- Node-integrated renderer contexts
- Node-integrated dedicated worker contexts

There is no Electron-specific JavaScript API for this port. Validate it by
running WebAssembly streaming calls in the renderer or dedicated worker context
that previously failed.

## Widevine CDM

Port: `widevine-cdm`

This port enables Widevine support code in Electron builds and adds package
assembly support for CDM files. CDM binary redistribution requires a separate
license decision and explicit acknowledgement.

```bash
ELECTRON_PACKAGE_INCLUDE_WIDEVINE_CDM=1 \
ELECTRON_PACKAGE_WIDEVINE_LICENSE_ACK=1 \
ELECTRON_PACKAGE_WIDEVINE_CDM_DIR=/path/to/WidevineCdm \
scripts/build-dev-electron-npm.sh --target 42
```

On Linux, the resolver can prepare a compatible CDM directory:

```bash
scripts/resolve-widevine-cdm.sh \
  --target 42 \
  --license-ack \
  --download-if-missing \
  --prefer-download \
  --require-chrome-major-match \
  --force \
  --print-environment
```

Build scripts require the explicit license acknowledgement before packaging CDM
files. Successful packaging means the CDM directory was copied into the Electron
artifact; it is not a guarantee that playback for a particular service is
licensed or accepted by that service.

## VA-API HEVC

Port: `vaapi-hevc-wip`

This port carries Linux VA-API HEVC/H.265 Chromium patch-stack work. It is
validated through target Electron media playback and encode/decode scenarios,
not through a dedicated Electron JavaScript API.

Applications should treat this as runtime media capability work. Confirm it with
the target GPU, driver stack, Chromium flags, and media pipeline that the release
will actually use.
