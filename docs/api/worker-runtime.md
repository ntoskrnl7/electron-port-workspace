# Worker Runtime

Process: [Main](../glossary.md#main-process)

Port: `worker-runtime`

The worker runtime port adds main-process objects for dedicated workers and
shared workers, extends service worker IPC behavior, and adds scoped IPC
dispatch.

Workers receive messages through the normal worker-side
`require('electron').ipcRenderer` API when the worker context has access to the
Electron preload or Node integration path that exposes it.

## Class: DedicatedWorkers

> Collection of dedicated workers associated with a WebContents.

Process: [Main](../glossary.md#main-process)<br />
_This class is not exported from the `electron` module. It is accessed through
`webContents.dedicatedWorkers`._

### Instance Events

#### Event: 'created'

Returns:

* `details` Object
  * `id` string
  * `url` string

Emitted when Electron starts tracking a dedicated worker. The URL may still be
the initial script URL; listen for `final-response-url-determined` when the
final response URL matters.

#### Event: 'destroyed'

Returns:

* `details` Object
  * `id` string

#### Event: 'final-response-url-determined'

Returns:

* `details` Object
  * `id` string
  * `url` string

### Instance Methods

#### `dedicatedWorkers.getAllRunning()` _Experimental_

Returns `Record<string, Object>` - Current running worker details keyed by
worker id.

The returned object is a snapshot. Use `getWorkerFromID(id)` to retrieve the
live `DedicatedWorkerMain` object for a worker that is still running.

#### `dedicatedWorkers.getWorkerFromID(id)` _Experimental_

* `id` string

Returns `DedicatedWorkerMain | null`.

```js
const workers = win.webContents.dedicatedWorkers

workers.on('created', details => {
  console.log(details.id, details.url)
})

const worker = workers.getWorkerFromID('dedicated-worker-id')
worker?.send('ping')
```

## Class: DedicatedWorkerMain

> An instance of a dedicated worker associated with a WebContents.

Process: [Main](../glossary.md#main-process)<br />
_This class is not exported from the `electron` module. It is only available as
a return value of other APIs._

### Instance Methods

#### `dedicatedWorker.isDestroyed()` _Experimental_

Returns `boolean` - Whether the dedicated worker has been destroyed.

#### `dedicatedWorker.send(channel, ...args)` _Experimental_

* `channel` string
* `...args` any[]

Sends an asynchronous message to the dedicated worker.

In the worker, receive the message with `ipcRenderer.on(channel, listener)`.
Arguments are serialized using Electron IPC semantics. Destroyed workers cannot
receive messages; check `isDestroyed()` when the lifetime is uncertain.

#### `dedicatedWorker.executeJavaScript(code)` _Experimental_

* `code` string

Returns `Promise<unknown>` - Resolves with the result of the executed code.

The promise rejects if the worker has already been destroyed or if the evaluated
script throws. Code runs in the worker's JavaScript global scope.

### Instance Properties

#### `dedicatedWorker.ipc` _Readonly_ _Experimental_

An `IpcMainDedicatedWorker` instance scoped to this dedicated worker.

Handlers registered here run before `webContents.ipc` and global `ipcMain`
handlers for messages sent by this worker.

#### `dedicatedWorker.id` _Readonly_ _Experimental_

A `string` representing the unique ID of the dedicated worker.

#### `dedicatedWorker.processId` _Readonly_ _Experimental_

An `Integer` representing the Chromium internal process ID.

#### `dedicatedWorker.url` _Readonly_ _Experimental_

A `string` representing the final response URL of the worker script.

#### `dedicatedWorker.sender` _Readonly_ _Experimental_

The `WebContents` that owns the dedicated worker's ancestor frame.

#### `dedicatedWorker.ownerFrame` _Readonly_ _Experimental_

A `WebFrameMain | null` representing the frame that created the dedicated
worker. This is `null` for nested dedicated workers.

#### `dedicatedWorker.parentWorker` _Readonly_ _Experimental_

A `DedicatedWorkerMain | null` representing the dedicated worker that created
this nested dedicated worker.

## Class: SharedWorkers

> Collection of shared workers associated with a Session.

Process: [Main](../glossary.md#main-process)<br />
_This class is not exported from the `electron` module. It is accessed through
`session.sharedWorkers`._

### Instance Events

#### Event: 'created'

Returns:

* `details` Object
  * `id` string
  * `url` string

#### Event: 'destroyed'

Returns:

* `details` Object
  * `id` string

#### Event: 'final-response-url-determined'

Returns:

* `details` Object
  * `id` string
  * `url` string

#### Event: 'client-added'

Returns:

* `details` Object
  * `id` string - The shared worker id.
  * `frame` WebFrameMain | null - The client frame.

Emitted when a frame starts being a client of a shared worker.

#### Event: 'client-removed'

Returns:

* `details` Object
  * `id` string - The shared worker id.
  * `frame` WebFrameMain | null - The client frame.

Emitted when a frame stops being a client of a shared worker.

### Instance Methods

#### `sharedWorkers.getAllRunning()` _Experimental_

Returns `Record<string, Object>` - Current running worker details keyed by
worker id.

The returned object is a snapshot. Use `getWorkerFromID(id)` to retrieve the
live `SharedWorkerMain` object for a worker that is still running.

#### `sharedWorkers.getWorkerFromID(id)` _Experimental_

* `id` string

Returns `SharedWorkerMain | null`.

```js
const workers = session.defaultSession.sharedWorkers

workers.on('client-added', details => {
  console.log(details.workerId, details.frame)
})
```

## Class: SharedWorkerMain

> An instance of a shared worker associated with a Session.

Process: [Main](../glossary.md#main-process)<br />
_This class is not exported from the `electron` module. It is only available as
a return value of other APIs._

### Instance Methods

#### `sharedWorker.isDestroyed()` _Experimental_

Returns `boolean` - Whether the shared worker has been destroyed.

#### `sharedWorker.send(channel, ...args)` _Experimental_

* `channel` string
* `...args` any[]

Sends an asynchronous message to the shared worker.

In the shared worker, receive the message with `ipcRenderer.on(channel,
listener)`.

#### `sharedWorker.executeJavaScript(code)` _Experimental_

* `code` string

Returns `Promise<unknown>` - Resolves with the result of the executed code.

The promise rejects if the shared worker has already been destroyed or if the
evaluated script throws. Code runs in the shared worker's JavaScript global
scope.

#### `sharedWorker.getClientFrames()` _Experimental_

Returns `WebFrameMain[]` - Frames currently connected to the shared worker.

The returned list is a snapshot. It can change as frames navigate, reload, or
disconnect from the shared worker.

### Instance Properties

#### `sharedWorker.ipc` _Readonly_ _Experimental_

An `IpcMainSharedWorker` instance scoped to this shared worker.

Handlers registered here run before `session.ipc` and global `ipcMain` handlers
for messages sent by this shared worker.

#### `sharedWorker.id` _Readonly_ _Experimental_

A `string` representing the unique ID of the shared worker.

#### `sharedWorker.processId` _Readonly_ _Experimental_

An `Integer` representing the Chromium internal process ID.

#### `sharedWorker.url` _Readonly_ _Experimental_

A `string` representing the final response URL of the worker script.

#### `sharedWorker.name` _Readonly_ _Experimental_

A `string` containing the shared worker name.

#### `sharedWorker.session` _Readonly_ _Experimental_

The `Session` that owns the shared worker.

## Service Worker Extensions

The port extends `ServiceWorkerMain` with:

- `serviceWorker.executeJavaScript(code)`
- `serviceWorker.ipc`

Service worker IPC also participates in session-scoped and global `ipcMain`
dispatch.

`serviceWorker.executeJavaScript(code)` runs only when Electron can address a
running service worker. If a notification exposes a persistent service worker
that is stopped, use `notification.getServiceWorker()` to retrieve or start it
before using service-worker runtime APIs.

## Scoped IPC

The port adds scoped IPC objects so handlers can be registered at the narrowest
useful level.

### Handler Scopes

Messages dispatch from narrow to broad scopes:

1. worker-scoped IPC, such as `dedicatedWorker.ipc`
2. `webContents.ipc` or `session.ipc`
3. global `ipcMain`

Use this when one channel name must behave differently for a specific worker,
WebContents, session, or the global main process.

For dedicated workers, the owner scope is `webContents.ipc`. For shared workers
and service workers, the owner scope is `session.ipc`. If a narrow handler is
registered for a synchronous message and sets `event.returnValue`, broader
handlers are not used for that message.

## Worker Preload Injection Point

Dedicated worker preload scripts can opt into early execution:

```js
session.defaultSession.registerPreloadScript({
  type: 'dedicated-worker',
  injectionPoint: 'context-created',
  filePath: '/path/to/worker-preload.js'
})
```

Use `context-created` only when the preload must run before the worker script is
evaluated.

## DedicatedWorkerInfo Object

* `id` string - The dedicated worker id.
* `url` string - The final response URL of the worker script.
* `scriptURL` string - Alias for `url`.
* `renderProcessId` number - The virtual renderer process id.

## SharedWorkerInfo Object

* `id` string - The shared worker id.
* `name` string - The shared worker name.
* `url` string - The initial shared worker script URL.
* `scriptURL` string - The final response URL of the shared worker script.
* `renderProcessId` number - The virtual renderer process id.

## Worker IPC Event Objects

Dedicated worker IPC events include `type: 'dedicated-worker'`,
`senderDedicatedWorker`, `sender`, `processId`, `ports`, `reply(...)`, and, for
synchronous messages, `returnValue` and `isReturnValueSet`.

Shared worker IPC events include `type: 'shared-worker'`, `sharedWorker`,
`session`, `processId`, `ports`, `reply(...)`, and, for synchronous messages,
`returnValue` and `isReturnValueSet`.

Service worker IPC events include `type: 'service-worker'`, `serviceWorker`,
`session`, `versionId`, `processId`, `ports`, `reply(...)`, and, for synchronous
messages, `returnValue` and `isReturnValueSet`.
