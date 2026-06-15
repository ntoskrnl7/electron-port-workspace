# WebNotification

## Class: WebNotification

> Represents a Web Notification created by a frame or worker.

Process: [Main](../glossary.md#main-process)<br />
_This class is not exported from the `electron` module. It is only available as
the argument passed to `session.setWebNotificationHandler(handler)`._

Port: `web-notification-handler`

If the session handler returns without calling `notification.suppress()`,
Electron automatically shows the notification through the native notification
presenter. Call `suppress()` inside the handler callback when the app wants to
inspect, delay, replace, or silently handle the notification.

```js
const { session } = require('electron')

session.defaultSession.setWebNotificationHandler(notification => {
  notification.suppress()

  console.log(notification.title, notification.body)

  notification.on('click', () => {
    console.log(notification.id)
  })

  if (notification.persistent) {
    notification.getServiceWorker().then(worker => {
      console.log(worker.id)
    })
  }
})
```

### Instance Events

#### Event: 'show'

Emitted when Electron's native notification presenter displays the notification.

#### Event: 'click'

Emitted when the notification body is clicked.

For persistent service worker notifications, this dispatches the web
`notificationclick` event to the service worker.

#### Event: 'action'

Returns:

* `details` [WebNotificationActionEvent](#webnotificationactionevent-object)

Emitted when an action button is clicked.

For persistent service worker notifications, `click`, `action`, `reply`, and
user-initiated `close` dispatch the matching web notification events back into
the service worker.

#### Event: 'reply'

Returns:

* `details` [WebNotificationReplyEvent](#webnotificationreplyevent-object)

Emitted when the user submits text for a text action.

For persistent service worker notifications, this dispatches the web
`notificationclick` event to the service worker with the reply text.

#### Event: 'close'

Returns:

* `details` [WebNotificationCloseEvent](#webnotificationcloseevent-object)

Emitted when the notification is closed.

#### Event: 'failed'

Returns:

* `details` [WebNotificationFailedEvent](#webnotificationfailedevent-object)

Emitted when Electron fails to show the native notification.

### Instance Methods

#### `notification.show()`

Shows the notification using Electron's native notification presenter.

This can be used after `notification.suppress()` when the app wants to show the
original web notification later.

#### `notification.suppress()`

Prevents Electron from automatically showing the notification after the
`setWebNotificationHandler` callback returns.

Call this before the handler callback returns. Calling it later does not undo a
notification that Electron has already handed to the native presenter.

The notification remains valid and can still be controlled later with
`notification.click()`, `notification.clickAction(action)`,
`notification.reply(text[, action])`, and `notification.close([options])`.

#### `notification.close([options])`

* `options` Object (optional)
  * `byUser` boolean (optional) - Whether the close should be treated as a
    user-initiated close. Defaults to `true`.

Closes the notification. For persistent service worker notifications, this
dispatches `notificationclose` when `byUser` is `true`.

#### `notification.click()`

Dispatches a notification body click.

#### `notification.clickAction(action)`

* `action` Integer | string - The zero-based action index or the web
  notification action string.

Dispatches an action button click.

#### `notification.reply(text[, action])`

* `text` string
* `action` Integer | string (optional) - The zero-based action index or the web
  notification action string. If omitted, Electron uses the first text action.

Dispatches a text reply.

#### `notification.getServiceWorker()`

Returns `Promise<ServiceWorkerMain>` - Resolves with the service worker for this
persistent notification's scope.

This method is only available on persistent service worker notifications. Check
`notification.persistent` before calling it.

When the service worker is stopped, this method may start it in order to return
the `ServiceWorkerMain` object. For non-persistent notifications, use
`notification.frame` or `notification.webContents` when those properties are
available.

#### `notification.isDestroyed()`

Returns `boolean` - Whether the notification object has been destroyed.

### Instance Properties

#### `notification.id` _Readonly_

A `string` identifying this notification.

#### `notification.persistent` _Readonly_

A `boolean` indicating whether the notification was created by
`ServiceWorkerRegistration.showNotification()`.

In TypeScript this property discriminates persistent service worker
notifications from non-persistent notifications. Non-persistent notifications
can be created by a frame, dedicated worker, or shared worker with
`new Notification()`. Persistent notifications are created by service workers
with `ServiceWorkerRegistration.showNotification()`.

#### `notification.origin` _Readonly_

A `string` containing the notification origin.

#### `notification.title` _Readonly_

A `string` containing the notification title.

#### `notification.body` _Readonly_

A `string` containing the notification body.

#### `notification.tag` _Readonly_

A `string` containing the notification tag.

#### `notification.actions` _Readonly_

A [WebNotificationAction[]](#webnotificationaction-object) containing the web
notification actions.

#### `notification.frame` _Readonly_

A `WebFrameMain | undefined` identifying the frame associated with a
non-persistent notification.

This property is set for frame notifications and dedicated worker
notifications. It is `undefined` for shared worker notifications and persistent
service worker notifications.

#### `notification.webContents` _Readonly_

A `WebContents | undefined` identifying the `WebContents` associated with a
non-persistent notification.

This property is set for frame notifications and dedicated worker
notifications. It is `undefined` for shared worker notifications and persistent
service worker notifications.

#### `notification.documentUrl` _Readonly_

A `string | undefined` containing the document URL for a frame notification.

This property is `undefined` for worker notifications and persistent service
worker notifications.

#### `notification.serviceWorkerScope` _Readonly_

A `string | undefined` containing the service worker scope for a persistent
notification.

This property is `undefined` for non-persistent notifications.

#### `notification.serviceWorker` _Readonly_

A `ServiceWorkerMain | undefined` for the running service worker associated with
this persistent notification. This property is `undefined` when the service
worker is not currently running. Use `notification.getServiceWorker()` to start
and retrieve it.

## WebNotificationAction Object

* `action` string - The web notification action identifier.
* `title` string - The action button title.
* `type` string (optional) - The action type, for example `button` or `text`.
* `placeholder` string (optional) - Placeholder text for text actions.

## WebNotificationActionEvent Object

* `action` [WebNotificationAction](#webnotificationaction-object)

## WebNotificationReplyEvent Object

* `reply` string - The submitted text.
* `action` [WebNotificationAction](#webnotificationaction-object) (optional)

## WebNotificationCloseEvent Object

* `byUser` boolean - Whether the notification was closed by user action.
* `reason` string - The close reason.

## WebNotificationFailedEvent Object

* `error` string - The error encountered while showing the native notification.
