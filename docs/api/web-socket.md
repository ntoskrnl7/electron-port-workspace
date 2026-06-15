# WebSocket

## Class: WebSocket

> Intercept and handle WebSocket connections created by pages and workers in a
> session.

Process: [Main](../glossary.md#main-process)<br />
_This class is not exported from the `electron` module. It is only available as
the `webSocket` property of a `Session` instance._

Port: `websocket-main-bridge`

Instances of this class are accessed with `session.defaultSession.webSocket` or
`session.fromPartition(...).webSocket`.

### Instance Methods

#### `webSocket.setHandler([filter, ]handler)`

* `filter` [WebSocketFilter](#websocketfilter-object) (optional)
* `handler` Function | null
  * `socket` [WebSocketMain](#class-websocketmain)

Sets the handler used to intercept matching WebSocket connections. Passing
`null` removes the handler.

Only one handler can be active for a session. If no handler is set, or if the
URL does not match the filter, Electron continues with its default WebSocket
handling.

```js
const { session } = require('electron')

session.defaultSession.webSocket.setHandler(
  { urls: ['wss://example.test/*'] },
  socket => {
    if (socket.creatorType === 'frame') {
      socket.accept()
      return
    }

    socket.continue()
  }
)
```

The connection remains pending until the handler calls:

- `socket.continue()`
- `socket.accept([options])`
- `socket.fail([reason])`

The decision can be made asynchronously after the handler returns, but exactly
one decision must eventually be made. If the handler never calls one of these
methods, the renderer WebSocket connection remains pending until the page,
worker, or WebContents is destroyed.

## Class: WebSocketMain

> Represents one intercepted WebSocket connection.

Process: [Main](../glossary.md#main-process)<br />
_This class is not exported from the `electron` module. It is only available as
the argument passed to `webSocket.setHandler([filter, ]handler)`._

### Instance Events

#### Event: 'message'

Returns:

* `message` [WebSocketMessage](#websocketmessage-object)

Emitted when the renderer sends a WebSocket message to the accepted connection.

This event is emitted only for sockets accepted with `socket.accept(...)`.
Sockets continued with `socket.continue()` use Chromium's normal network path
and are not delivered to `WebSocketMain` as messages.

#### Event: 'close'

Returns:

* `details` [WebSocketCloseDetails](#websocketclosedetails-object)

Emitted when the renderer starts closing the WebSocket or when the connection is
destroyed.

### Instance Methods

#### `socket.continue()`

Continues the connection through Electron's default WebSocket handling. This
preserves existing `webRequest`, extension, and Chromium network behavior.

#### `socket.accept([options])`

* `options` Object (optional)
  * `protocol` string (optional) - The selected subprotocol.
  * `headers` Record<string, string> (optional) - Additional response headers
    for the WebSocket handshake.

Accepts the WebSocket and terminates it in the main process.

After `accept()`, the app is responsible for sending, receiving, and closing the
connection through this `WebSocketMain` object. Use `protocol` only when it is
one of the subprotocols requested by `socket.protocols`.

#### `socket.fail([reason])`

* `reason` string (optional)

Rejects the WebSocket connection.

#### `socket.send(message)`

* `message` string | Buffer | ArrayBuffer | ArrayBufferView

Returns `Promise<void>` - Resolves when the message is queued for delivery to
the renderer.

#### `socket.close([code, reason])`

* `code` Integer (optional)
* `reason` string (optional)

Starts closing the WebSocket connection.

#### `socket.pause()`

Pauses incoming renderer-to-main message delivery.

#### `socket.resume()`

Resumes incoming renderer-to-main message delivery.

#### `socket.isDestroyed()`

Returns `boolean` - Whether the WebSocket connection has been destroyed.

### Instance Properties

#### `socket.id` _Readonly_

A `string` identifying this WebSocket connection.

#### `socket.url` _Readonly_

A `string` containing the WebSocket URL.

#### `socket.protocols` _Readonly_

A `string[]` containing the subprotocols requested by the renderer.

#### `socket.creatorType` _Readonly_

A `string` identifying the object that created the WebSocket. Can be `frame`,
`dedicated-worker`, `shared-worker`, `service-worker`, or `unknown`.

#### `socket.creator` _Readonly_

A `WebFrameMain | DedicatedWorkerMain | SharedWorkerMain | ServiceWorkerMain | null`
identifying the object that created the WebSocket.

#### `socket.bufferedAmount` _Readonly_

An `Integer` indicating the number of bytes queued by `socket.send(message)` and
not yet written to the renderer.

## WebSocketFilter Object

* `urls` string[] (optional) - URL patterns used to match WebSocket URLs. If
  omitted, all URLs are matched.
* `excludeUrls` string[] (optional) - URL patterns used to exclude matching
  WebSocket URLs.

## WebSocketMessage Object

* `type` string - Can be `text` or `binary`.
* `data` string | Buffer - The message payload.

## WebSocketCloseDetails Object

* `code` Integer
* `reason` string
* `wasClean` boolean
