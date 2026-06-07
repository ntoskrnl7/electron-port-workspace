# picture-in-picture-handle-api

Reusable Electron port bundle for exposing the active Picture-in-Picture window
as a main-process handle.

The API adds:

- `app.getCurrentPictureInPicture()`
- `app` and `webContents` `enter-picture-in-picture` events
- `app` and `webContents` `leave-picture-in-picture` events
- `PictureInPicture`, `VideoPictureInPicture`, and
  `DocumentPictureInPicture` handle docs/types

The Chromium-side patch exposes the native PiP window source id, bounds, close
state, and intrinsic video size so Electron can surface them through the handle.
