# web-notification-handler / 42

Electron 42 port of the Web Notification handler API.

## Contents

- `electron/0001-feat-add-web-notification-handler.patch`
  - Adds `session.setWebNotificationHandler(handler)`.
  - Adds the internal `WebNotification` main-process object.
  - Wires frame, subframe, dedicated worker, shared worker, and persistent
    service worker notifications into the same handler path.
  - Adds docs, structures, runtime specs, and TypeScript smoke coverage.

## Type Shape

Generated `electron.d.ts` is post-processed by
`script/fix-web-notification-typescript-definitions.mjs` so
`Electron.WebNotification` is a discriminated union:

```ts
type WebNotification =
  | WebFrameNotification
  | WebWorkerNotification
  | WebServiceWorkerNotification;
```

Use `notification.persistent === true` to narrow to persistent service worker
notifications. For non-persistent notifications, `documentUrl` distinguishes
document/frame notifications from worker notifications.

## Validation

Validated on Electron 42.3.3 with:

```bash
npm run create-typescript-definitions
env -u ELECTRON_RUN_AS_NODE npm run test -- --skipYarnInstall --runners=main --grep "setWebNotificationHandler"
e build --no-remote -t electron -local_jobs 20
ELECTRON_BUILD_NO_REMOTE=1 ELECTRON_BUILD_REMOTE_JOBS=0 ./scripts/build-dev-electron-npm.sh --target 42
```

The package artifact is written under the selected target's Electron npm output
directory, for example:

```text
<workspace>/<target>/src/out/electron-npm/electron-linux-x64-<version>.tgz
```
