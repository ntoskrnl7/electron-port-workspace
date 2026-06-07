# dispatch-input-event

Adds `webContents.dispatchInputEvent(inputEvent)` for trusted Chromium-backed
keyboard, mouse, wheel, touch, text insertion, and IME composition dispatch.
IME composition dispatch supports optional composition highlight styling, so
callers can keep composition semantics while suppressing Chromium's default
composition background.

The API is intended for RBI-style input forwarding where DOM events must be
trusted and where callers need Chromium input ACK information to know whether a
page consumed an event.

This port also contains a Chromium-side fix for DevTools synthetic drag
sequences. When a renderer-started drag begins in one frame and drops in another
frame, Chromium must finish the original drag source frame so that hover and
click handling continue to work after the drop.

Target bundles live under:

```text
ports/dispatch-input-event/<target>/
```
