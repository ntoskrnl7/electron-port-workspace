# websocket-main-bridge

Adds a session-scoped WebSocket interception API for Electron main process code.

The API is exposed as `session.defaultSession.webSocket` and
`session.fromPartition(...).webSocket`. A handler can inspect one renderer-created
WebSocket and then asynchronously choose one of:

- `socket.continue()` to keep the default Electron/Chromium network path.
- `socket.accept([options])` to terminate the WebSocket in the main process.
- `socket.fail([reason])` to reject the connection.

Accepted sockets support `message` and `close` events, `send()`, `close()`,
`pause()`, `resume()`, `bufferedAmount`, and creator metadata through
`creatorType` / `creator`.

Target bundles live under:

```text
ports/websocket-main-bridge/<target>/
```

Chromium-side changes expose WebSocket creator metadata and requested protocols
to `ContentBrowserClient`. Electron-side changes implement the public API,
documentation, TypeScript generation surface, and a focused runtime spec.
