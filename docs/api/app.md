# App Additions

Process: [Main](../glossary.md#main-process)

This page documents `app` APIs added by Electron Port Workspace bundles.

## Methods

### `app.setUserAgentOverride(options)`

Port: `user-agent-override`

* `options` Object
  * `userAgent` string - The legacy `User-Agent` string to use as the global
    fallback.
  * `userAgentMetadata` [UserAgentMetadata](#useragentmetadata-object) - The
    User-Agent Client Hints metadata that matches `userAgent`.

Sets the global fallback User-Agent string and User-Agent Client Hints metadata.
Call this before creating windows or sessions when the override must apply to
the first navigation.

The app override is the broadest fallback. Effective User-Agent resolution is:

1. `webContents.setUserAgentOverride(...)` for frames and dedicated workers
2. `session.setUserAgentOverride(...)`
3. `app.setUserAgentOverride(...)`
4. Chromium's default User-Agent

Shared workers and service workers do not belong to one WebContents, so they use
the session override first, then the app override. Overrides affect future
navigations and future worker creation only; they do not rewrite requests,
workers, or documents that are already running.

```js
const { app } = require('electron')

app.setUserAgentOverride({
  userAgent: 'Mozilla/5.0 ElectronAppProfile',
  userAgentMetadata: {
    brands: [{ brand: 'Chromium', version: '148' }],
    fullVersionList: [{ brand: 'Chromium', version: '148.0.7778.218' }],
    platform: 'Windows',
    platformVersion: '19.0.0',
    architecture: 'x86',
    model: '',
    mobile: false,
    bitness: '64',
    wow64: false,
    formFactors: ['Desktop']
  }
})
```

### `app.clearUserAgentOverride()`

Port: `user-agent-override`

Clears the app-level User-Agent override for future sessions, WebContents, and
worker creation. Existing sessions keep their own explicit overrides, and
already-running documents or workers are not changed retroactively.

### `app.getCurrentPictureInPicture()`

Port: `picture-in-picture-handle-api`

Returns `VideoPictureInPicture | DocumentPictureInPicture | null` - A handle for
the active Picture-in-Picture window, or `null` if there is no active
Picture-in-Picture window.

The returned handle is a snapshot of the currently active Picture-in-Picture
session. Use `pip.isDestroyed()` or a `null` result from bounds/size methods to
detect that the session has ended.

```js
const pip = app.getCurrentPictureInPicture()
if (pip) {
  pip.setSize({ width: 480, height: 270 })
}
```

## Events

### Event: 'enter-picture-in-picture'

Port: `picture-in-picture-handle-api`

Returns:

- `event` Event
- `pip` `VideoPictureInPicture | DocumentPictureInPicture`

Emitted when a Picture-in-Picture window becomes active.

### Event: 'leave-picture-in-picture'

Port: `picture-in-picture-handle-api`

Returns:

- `event` Event
- `pip` `VideoPictureInPicture | DocumentPictureInPicture`

Emitted when the active Picture-in-Picture window closes.

## Class: PictureInPicture

Port: `picture-in-picture-handle-api`

> Represents an active Picture-in-Picture window.

### Instance Methods

#### `pip.getBounds()`

Returns `Rectangle | null` - The current Picture-in-Picture window bounds in
screen coordinates, or `null` if this handle is no longer active.

#### `pip.setBounds(bounds)`

* `bounds` Rectangle

Returns `Rectangle | null` - The actual bounds after Chromium and the operating
system apply size constraints, or `null` if this handle is no longer active.

#### `pip.getSize()`

Returns `Size | null` - The current Picture-in-Picture window size, or `null` if
this handle is no longer active.

#### `pip.setSize(size)`

* `size` Size

Returns `Size | null` - The actual size after Chromium and the operating system
apply constraints, or `null` if this handle is no longer active.

#### `pip.getSourceId()`

Returns `string | null` - The capture source id for the Picture-in-Picture
window, or `null` if unavailable.

#### `pip.getSource([options])`

* `options` Object (optional)

Returns `Promise<DesktopCapturerSource | null>` - Resolves with the matching
capture source, or `null`.

#### `pip.close()`

Returns `boolean` - Whether the close request was accepted.

#### `pip.isDestroyed()`

Returns `boolean` - Whether this handle no longer represents the active
Picture-in-Picture window.

### Instance Properties

#### `pip.id` _Readonly_

An `Integer` identifying this Picture-in-Picture session.

#### `pip.type` _Readonly_

A `string` that can be `video` or `document`.

#### `pip.sourceWebContents` _Readonly_

The `WebContents` that created the Picture-in-Picture window.

## Class: VideoPictureInPicture extends `PictureInPicture`

### Instance Properties

#### `pip.videoSize` _Readonly_

The intrinsic video frame size.

## Class: DocumentPictureInPicture extends `PictureInPicture`

### Instance Properties

#### `pip.pipWebContents` _Readonly_

The `WebContents` hosted inside the document Picture-in-Picture window.

## UserAgentMetadata Object

* `brands` Object[] (optional)
  * `brand` string
  * `version` string
* `fullVersionList` Object[] (optional)
  * `brand` string
  * `version` string
* `fullVersion` string (optional)
* `platform` string
* `platformVersion` string
* `architecture` string
* `model` string
* `mobile` boolean
* `bitness` string (optional)
* `wow64` boolean (optional)
* `formFactors` string[] (optional)
