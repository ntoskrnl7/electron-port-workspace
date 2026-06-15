# web-notification-handler

Adds `session.setWebNotificationHandler(handler)` and the `WebNotification`
object used to observe and control Web Notifications from the Electron main
process.

The handler covers the notification sources that Chromium routes through
Electron's platform notification service:

- Frame and dedicated worker notifications created with `new Notification()`.
- Persistent service worker notifications created with
  `ServiceWorkerRegistration.showNotification()`.

The API lets callers suppress Electron's default native presentation and later
drive notification behavior with `show()`, `click()`, `clickAction()`,
`reply()`, and `close()`. Persistent service worker notifications dispatch the
matching web notification events back into the service worker.

The TypeScript surface intentionally models `WebNotification` as a
source-aware union:

- `WebFrameNotification` covers document/frame `new Notification()` calls.
- `WebWorkerNotification` covers worker `new Notification()` calls.
- `persistent: true` exposes `serviceWorkerScope`, `serviceWorker`, and
  `getServiceWorker()`.
