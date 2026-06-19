# Web Policy

Process: [Main](../glossary.md#main-process)

Port: `web-policy-handler`

`session.setWebPolicyHandler(handler)` lets the main process observe and
selectively override browser web policy checks that Chromium normally evaluates
inside Blink.

The handler covers:

- Content Security Policy directive checks such as `connect-src`, `script-src`,
  `style-src-*`, `worker-src`, Trusted Types directives, and WASM eval checks.
- Permissions Policy feature checks such as `sync-xhr`.
- Document Policy feature checks exposed by the current Chromium build.
- Runtime browser checks that are not represented by response headers, currently
  sync XHR and sync XHR during page dismissal.

The API returns one of `default`, `allow`, or `deny` for the specific policy
check that produced the callback. It does not grant unrelated browser
permissions, bypass CORS, or force a network request to succeed.

```js
const { session } = require('electron')

session.defaultSession.setWebPolicyHandler(details => {
  if (details.policy === 'browser-runtime' &&
      details.name === 'sync-xhr-page-dismissal') {
    return { action: 'deny' }
  }

  return { action: 'default' }
})
```

## WebPolicyHandlerDetails Object

The generated TypeScript definition models details as a discriminated union:

```ts
type WebPolicyHandlerDetails =
  | WebContentSecurityPolicyHandlerDetails
  | WebPermissionsPolicyHandlerDetails
  | WebDocumentPolicyHandlerDetails
  | WebBrowserRuntimePolicyHandlerDetails
```

Common fields:

* `policy` string - `content-security-policy`, `permissions-policy`,
  `document-policy`, or `browser-runtime`.
* `name` string - The checked directive, feature, or runtime gate.
* `disposition` string - `enforce` or `report`.
* `source` string - Currently `runtime`.
* `resourceUrl` string (optional) - The resource URL involved in the check.
* `documentUrl` string (optional) - The document URL associated with the check.
* `contextType` string - `frame`, `dedicated-worker`, `shared-worker`,
  `service-worker`, or `unknown`.
* `message` string (optional) - Chromium's policy message when available.

## WebPolicyHandlerResponse Object

* `action` string - `default`, `allow`, or `deny`.

Use `default` to preserve Chromium's original policy result for the current
check.
