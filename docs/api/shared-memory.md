# SharedMemory

> Allocate `ArrayBuffer` and typed-array payloads backed by shared memory.

Process: [Main](../glossary.md#main-process),
[Renderer](../glossary.md#renderer-process)

Port: `shared-memory`

`SharedMemory` lets the main process create a shared memory pool for a renderer
frame. Buffers allocated inside `SharedMemory.withAllocator` are backed by that
pool and are restored automatically when passed through Electron IPC.

## Methods

### `SharedMemory.createPool(options)` _Experimental_

* `options` [CreateSharedMemoryPoolOptions](#createsharedmemorypooloptions-object)

Returns `Promise<SharedMemoryPool>` - Resolves with the shared memory pool.

Creates a shared memory pool and registers it in the main process and target
renderer frame. If `options.size` is omitted, Electron creates a 64 MiB pool.

```js
const { SharedMemory } = require('electron')

const pool = await SharedMemory.createPool({
  frame: win.webContents.mainFrame,
  size: 16 * 1024 * 1024
})
```

This method is only available in the main process.

The pool is shared only with the target `frame`. To stream data to another
renderer frame, create another pool for that frame.

### `SharedMemory.getPoolStats(pool)` _Experimental_

* `pool` [SharedMemoryPool](#sharedmemorypool-object)

Returns `SharedMemoryPoolStats | null` - Current allocation counters for `pool`,
or `null` if the pool is not registered in the current process.

### `SharedMemory.withAllocator(pool, fn[, options])` _Experimental_

* `pool` [SharedMemoryPool](#sharedmemorypool-object)
* `fn` Function
* `options` [SharedAllocatorOptions](#sharedallocatoroptions-object) (optional)

Runs `fn` with `ArrayBuffer` and typed-array allocations backed by `pool`.

```js
const payload = SharedMemory.withAllocator(pool, () => {
  const data = new Uint8Array(1024)
  data.fill(7)
  return data
})
```

Only shared-backed values returned from `fn`, or reachable from the returned
object, remain valid after the allocator scope exits. Temporary channel-affined
allocations that are not returned can be detached and returned to the channel
allocator automatically.

When `options.channel` is provided, the channel must use the same pool.
Allocations are affined to that channel so later `channel.send(data[, tag])`
can use the channel's fast path.

### `SharedMemory.isSharedBacked(value)` _Experimental_

* `value` any

Returns whether `value` is backed by a registered shared memory pool.

### `SharedMemory.createChannel(pool, options)` _Experimental_

* `pool` [SharedMemoryPool](#sharedmemorypool-object)
* `options` [SharedMemoryChannelOptions](#sharedmemorychanneloptions-object)

Returns `SharedMemoryChannel` - The sending channel endpoint.

Creates a sending `SharedMemoryChannel` endpoint.

```js
const channel = SharedMemory.createChannel(pool, {
  name: 'frames',
  ownership: 'transfer',
  delivery: 'snapshot'
})

channel.send(payload, 1)
```

The sending endpoint can be created in the main process or renderer process.
The peer process must create a matching receiving endpoint with
`SharedMemory.acceptChannel(pool, { name })` using the same pool and channel
name. The process that calls `createChannel()` is the producer.

By default, `send()` accepts only payloads backed by the same
`SharedMemoryPool`. Set `copyFallback: 'allow'` only when ordinary
`ArrayBuffer`, `Buffer`, or typed-array payloads should be copied into channel
ring storage.

### `SharedMemory.acceptChannel(pool, options)` _Experimental_

* `pool` [SharedMemoryPool](#sharedmemorypool-object)
* `options` Object
  * `name` string - Logical channel name.

Returns `SharedMemoryChannel` - The receiving channel endpoint.

Creates a receiving `SharedMemoryChannel` endpoint in the peer process.

```js
const channel = SharedMemory.acceptChannel(pool, { name: 'frames' })

channel.setMessageHandler(message => {
  console.log(message.tag, message.data.byteLength)
})
```

Both main-to-renderer and renderer-to-main channels are supported.

The receiver can be created before or after the sender. It starts receiving once
the matching channel descriptor has been announced by the producer.

### `SharedMemory.openChannel(pool, descriptor[, options])` _Experimental_

* `pool` [SharedMemoryPool](#sharedmemorypool-object)
* `descriptor` [SharedMemoryChannelDescriptor](#sharedmemorychanneldescriptor-object)
* `options` Object (optional)
  * `overflow` string (optional) - Can be `drop-oldest`, `drop-newest`, or
    `throw`.
  * `oversized` string (optional) - Can be `allocate`, `drop`, or `throw`.
  * `oversizedSlotCount` number (optional)
  * `views` Object (optional)
  * `maxTagSize` number (optional)

Returns `SharedMemoryChannel` - The opened channel endpoint.

Opens an existing channel descriptor in the current process. Most applications
should use `createChannel()` and `acceptChannel()` so descriptor discovery is
handled automatically.

### `SharedMemory.describe(value)` _Experimental_

* `value` any

Returns `SharedMemoryDescriptor | null` - A serializable descriptor for a
shared-backed `ArrayBuffer`, `Buffer`, typed array, or `DataView`, or `null` when
`value` is not shared-backed.

This is an advanced API. Normal Electron IPC and `SharedMemoryChannel` delivery
wrap and unwrap shared-backed payloads automatically.

### `SharedMemory.view(descriptor)` _Experimental_

* `descriptor` [SharedMemoryDescriptor](#sharedmemorydescriptor-object)

Returns `ArrayBuffer | Buffer | ArrayBufferView | null` - A local view for
`descriptor`, or `null` when the descriptor cannot be mapped in the current
process.

### `SharedMemory.release(value)` _Experimental_

* `value` any

Returns `boolean` - Whether local shared-memory tracking was released for
`value`.

Use this only for advanced lifetime management. Normal channel messages should
be released by returning from the message handler or by releasing the lease
returned by `message.retain()`.

## Class: SharedMemoryChannel

### Instance Methods

#### `channel.getAllocatorStats()` _Experimental_

Returns `Object` - Diagnostic counters for the channel's preallocated allocator.

#### `channel.send(data[, tag])` _Experimental_

* `data` ArrayBuffer | ArrayBufferView - Binary payload to queue.
* `tag` number | null (optional) - Unsigned 32-bit integer tag used to route or
  interpret the binary payload.

Returns `boolean` - Whether the message was queued.

When `data` is backed by the same `SharedMemoryPool` as the channel, Electron
transfers a reference to the existing shared-backed bytes without copying the
payload. Non-shared-backed inputs throw by default. Set `copyFallback` to
`allow` when ordinary `ArrayBuffer` and `ArrayBufferView` inputs should be
copied into reusable shared-memory slots.

With the default `ownership: 'transfer'`, a shared-backed sender payload is
transferred to the channel and may be detached on the sender side. With
`ownership: 'borrow'`, the sender keeps the object until the receiver releases
the message; the producer must not mutate borrowed bytes while the receiver owns
them.

With `delivery: 'latest'`, the sender may reuse the same shared-backed slot for
later sends before older messages are released. Receivers should treat that mode
as a latest-value stream, not as immutable per-send snapshots.

#### `channel.sendAndWait(data[, tag])` _Experimental_

* `data` ArrayBuffer | ArrayBufferView - Shared-backed binary payload to queue.
* `tag` number | null (optional) - Unsigned 32-bit integer tag used to route or
  interpret the binary payload.

Returns `Promise<void>` - Resolves after the receiver has finished handling the
message.

`sendAndWait()` is currently implemented only for renderer-to-main channels. Use
`send()` for main-to-renderer channels.

#### `channel.setMessageHandler(handler)` _Experimental_

* `handler` Function | null
  * `message` [SharedMemoryChannelMessage](#sharedmemorychannelmessage-object)

Registers the channel message handler.

Passing `null` clears the handler. If the handler returns a Promise,
`sendAndWait()` resolves after that Promise settles successfully.

#### `channel.setErrorHandler(handler)` _Experimental_

* `handler` Function | null
  * `error` Error

Registers a handler for channel dispatch errors.

#### `channel.setDropHandler(handler)` _Experimental_

* `handler` Function | null
  * `info` Object
    * `count` number - Number of dropped messages.
    * `reason` string - Drop reason.

Registers a handler for channel drop notifications.

#### `channel.close()` _Experimental_

Closes this local channel endpoint and removes registered handlers.

### Instance Properties

#### `channel.name` _Readonly_

A `string` containing the logical channel name.

#### `channel.pool` _Readonly_

The [SharedMemoryPool](#sharedmemorypool-object) used by this local endpoint.

#### `channel.descriptor` _Readonly_

The [SharedMemoryChannelDescriptor](#sharedmemorychanneldescriptor-object) that
can be used with `SharedMemory.openChannel(...)`.

#### `channel.closed` _Readonly_

A `boolean` indicating whether this endpoint has been closed.

## SharedMemoryChannelMessage Object

* `data` ArrayBuffer - The binary payload.
* `tag` number | null - Optional numeric tag.
* `byteLength` number - Payload byte length.
* `view` Function - Returns the typed view configured for this message tag, or
  a `Uint8Array` when no views map is configured.
* `retain` Function - Retains the payload after the handler returns and returns
  a lease object.
* `release` Function - Releases this message immediately.
* `retained` boolean - Whether `retain()` has been called.
* `released` boolean - Whether the message has been released.

Call `message.retain()` when the payload must outlive the handler callback. The
returned lease has `release()`, and the retained payload is released when that
lease is released.

## SharedMemoryChannelOptions Object

* `name` string - Logical channel name.
* `copyFallback` string (optional) - Can be `throw` or `allow`.
* `overflow` string (optional) - Can be `drop-oldest`, `drop-newest`, or
  `throw`.
* `oversized` string (optional) - Oversized-payload policy.
* `ownership` string (optional) - Can be `transfer` or `borrow`.
* `delivery` string (optional) - Can be `snapshot` or `latest`.
* `views` Object (optional) - Map of numeric tags to typed-array constructors.
* `allocator` boolean | string | Object (optional) - Enables preallocated
  channel allocator storage for `SharedMemory.withAllocator(..., { channel })`.

`copyFallback` defaults to `throw`. `ownership` defaults to `transfer`.
`delivery` defaults to `snapshot`. `delivery: 'latest'` requires borrowed
ownership and is intended for mutable latest-value streams.

## CreateSharedMemoryPoolOptions Object

* `frame` WebFrameMain - The target frame that shares the pool with the main
  process.
* `size` number (optional) - The pool size in bytes. Default is 64 MiB.
* `maxAllocationSize` number (optional) - Largest single allocation allowed.

## SharedAllocatorOptions Object

* `channel` SharedMemoryChannel (optional) - Channel allocator to prefer.

## SharedMemoryPool Object

* `id` string - The pool id.
* `size` number - Pool size in bytes.
* `maxAllocationSize` number - Largest single allocation allowed.

## SharedMemoryDescriptor Object

* `poolId` string - Shared memory pool identifier.
* `offset` number - Byte offset inside the pool.
* `byteLength` number - Described byte length.
* `viewType` string (optional) - Original view type.
* `length` number (optional) - Typed-array element length.

## SharedMemoryChannelDescriptor Object

* `poolId` string - Shared memory pool identifier.
* `name` string - Logical channel name.
* `rings` Object[] - Shared-memory rings used by this channel endpoint.

## SharedMemoryPoolStats Object

* `id` string - Pool id.
* `size` number - Pool size in bytes.
* `maxAllocationSize` number - Largest single allocation allowed.
* `used` number - Bytes reserved from the pool.
* `remaining` number - Bytes still available for future allocations.
* `allocationCount` number - Number of successful pool allocation reservations.
