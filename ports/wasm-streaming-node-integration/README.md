# WASM Streaming with Node Integration

Fixes WebAssembly streaming compilation in Electron renderer and dedicated
worker contexts that enable Node integration.

Electron restores Blink's `fetch`/`Response` globals after Node initialization
in those contexts, but Node's V8 WASM streaming callback still expects a
registered JavaScript implementation. Without this port,
`WebAssembly.compileStreaming()` or `WebAssembly.instantiateStreaming()` can hit
Node's native `!impl.IsEmpty()` assertion instead of compiling the module.

This port registers an Electron implementation that consumes Blink `Response`
objects and streams their body chunks to V8.

Target bundles live under:

```text
ports/wasm-streaming-node-integration/<target>/
```
