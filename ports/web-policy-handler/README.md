# web-policy-handler

Adds `session.setWebPolicyHandler(handler)` so Electron applications can
observe and selectively override browser web policy checks from the main
process.

The handler covers policy gates that Chromium normally evaluates inside Blink:

- Content Security Policy directive checks, including `connect-src`,
  `script-src`, `style-src-*`, `worker-src`, Trusted Types directives, and WASM
  eval checks.
- Permissions Policy feature checks, including `sync-xhr`.
- Document Policy feature checks exposed by the current Chromium build.
- Runtime checks that are not represented by response headers, currently sync
  XHR and sync XHR during page dismissal.

The API returns one of `default`, `allow`, or `deny` for the specific policy
check that produced the callback. It does not grant unrelated browser
permissions, bypass CORS, or force a network request to succeed.

Target bundles live under `ports/web-policy-handler/<target>/`.
