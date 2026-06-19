# Session Additions

Process: [Main](../glossary.md#main-process)

This page documents `Session` APIs added by Electron Port Workspace bundles.

## Methods

### `ses.registerPreloadScript(script)`

Port: `preload`

* `script` Object
  * `type` string - Can be `frame`, `dedicated-worker`, `shared-worker`, or
    `service-worker`.
  * `filePath` string - Absolute path to the preload script file.
  * `scope` string (optional) - For frame preloads, can be `main`,
    `sub-frames`, or `all`.
  * `runInInitialEmptyDocument` boolean (optional) - For frame preloads, whether
    to run in early iframe initial-empty-document contexts.
  * `injectionPoint` string (optional) - For dedicated worker preloads, can be
    `worker-script-ready` or `context-created`.
  * `target` string (optional) - For service worker preloads, can be
    `shadow-realm-global-scope`, `service-worker-global-scope`, or `both`.

Returns `string` - The registered preload script id.

Registers a session-managed preload script for frames, workers, or service
workers.

`scope` and `runInInitialEmptyDocument` are valid only for `type: 'frame'`.
When `scope` is omitted, Electron keeps its existing frame preload behavior:
main-frame preloads run normally and subframe preloads still depend on the
WebContents preferences that enable subframe preload execution. `scope: 'all'`
targets both main frames and subframes, but it does not by itself enable Node.js
integration in a frame.

`injectionPoint` is valid only for `type: 'dedicated-worker'`. Use
`context-created` only when the preload must run before the worker's main script
evaluates.

`target` is valid only for `type: 'service-worker'`. The default is
`shadow-realm-global-scope` for compatibility. Use
`service-worker-global-scope` to run in the actual service worker global scope,
or `both` to run the preload twice, once in each global scope.

```js
const path = require('node:path')
const { session } = require('electron')

const id = session.defaultSession.registerPreloadScript({
  type: 'frame',
  scope: 'all',
  runInInitialEmptyDocument: true,
  filePath: path.join(__dirname, 'frame-preload.js')
})

session.defaultSession.unregisterPreloadScript(id)
```

Supported targets:

- `type: 'frame'` with `scope: 'main' | 'sub-frames' | 'all'`
- `type: 'dedicated-worker'`
- `type: 'shared-worker'`
- `type: 'service-worker'`

### `ses.unregisterPreloadScript(id)`

Port: `preload`

* `id` string - The id returned by `ses.registerPreloadScript(script)`.

Unregisters a session-managed preload script.

Already-created frames and workers keep whatever preload code has already run.
Unregistering affects future contexts created in this session.

### `ses.setUserAgentOverride(options)`

Port: `user-agent-override`

* `options` Object
  * `userAgent` string - The legacy `User-Agent` string to use for this session.
  * `userAgentMetadata` [UserAgentMetadata](app.md#useragentmetadata-object) -
    The User-Agent Client Hints metadata that matches `userAgent`.
  * `acceptLanguages` string (optional) - A comma-separated ordered list of
    language codes.

Sets a session-level User-Agent string, Client Hints metadata, and optional
Accept-Language value.

```js
session.defaultSession.setUserAgentOverride({
  userAgent: 'Mozilla/5.0 ElectronSessionProfile',
  userAgentMetadata,
  acceptLanguages: 'en-US,ko'
})
```

Session overrides apply to frames, dedicated workers, shared workers, and
service workers created in that session. For frames and dedicated workers, a
WebContents override wins over the session override. For shared workers and
service workers, the session override wins over the app override. Set the
session override before creating or loading WebContents in that session when it
must affect the first navigation.

### `ses.clearUserAgentOverride()`

Port: `user-agent-override`

Clears the session-level User-Agent override for future navigations and worker
creation. After clearing, the session falls back to the app-level override when
one exists, otherwise Chromium's default values are used. Existing documents and
running workers are not changed retroactively.

### `ses.setWebNotificationHandler(handler)`

Port: `web-notification-handler`

* `handler` Function | null
  * `notification` [WebNotification](web-notification.md)

Sets a handler for Web Notifications created by frames, workers, and service
workers in this session.

```js
session.defaultSession.setWebNotificationHandler(notification => {
  notification.suppress()
  notification.on('click', () => console.log(notification.id))
})
```

See [WebNotification](web-notification.md).

Passing `null` clears the handler. If a handler is installed and it does not call
`notification.suppress()` before the callback returns, Electron shows the
notification through the native notification presenter after the callback
returns.

### `ses.setWebPolicyHandler(handler)`

Port: `web-policy-handler`

* `handler` Function | null
  * `details` [WebPolicyHandlerDetails](web-policy.md#webpolicyhandlerdetails-object)

Returns `void`.

Sets a synchronous handler for renderer web policy checks in this session. The
handler can return `{ action: 'default' }`, `{ action: 'allow' }`, or
`{ action: 'deny' }`.

```js
session.defaultSession.setWebPolicyHandler(details => {
  if (details.policy === 'content-security-policy' &&
      details.name === 'connect-src' &&
      details.resourceUrl === 'https://api.example.test/private') {
    return { action: 'deny' }
  }

  return { action: 'default' }
})
```

Passing `null` clears the handler. `allow` or `deny` affects only the specific
policy check that produced the callback; it does not grant unrelated browser
permissions, bypass CORS, or force a network request to succeed.

See [Web Policy](web-policy.md).

## Properties

### `ses.webSocket` _Readonly_

Port: `websocket-main-bridge`

The session-scoped [WebSocket](web-socket.md) interception object.

```js
session.defaultSession.webSocket.setHandler(
  { urls: ['wss://example.test/*'] },
  socket => socket.continue()
)
```

See [WebSocket](web-socket.md).

### `ses.sharedWorkers` _Readonly_

Port: `worker-runtime`

The [SharedWorkers](worker-runtime.md#class-sharedworkers) collection for this
session.

```js
session.defaultSession.sharedWorkers.on('created', details => {
  console.log(details.id, details.url)
})
```

See [Worker Runtime](worker-runtime.md).

### `ses.ipc` _Readonly_

Port: `worker-runtime`

Provides session-scoped IPC handlers for shared workers and service workers.
Messages can still fall through to `ipcMain` when no narrower handler consumes
them.

Use `ses.ipc` for channels that should be shared by every shared worker and
service worker in a session. Worker-specific `worker.ipc` handlers run first;
global `ipcMain` handlers run only when no narrower scope handles the message.
