# User Agent Override Design

## Goal

Provide a native Electron API that applies a coherent browser identity before
navigation starts. The API must cover the legacy `User-Agent` string,
UA Client Hints metadata, `Sec-CH-UA*` request headers, and early
`navigator.userAgentData` reads without relying on DevTools Protocol attach
timing.

The feature does not generate browser profiles. Callers are responsible for
passing a `userAgent` and matching `userAgentMetadata`. A separate library can
build those values from higher-level browser profile data.

## API Shape

Add object-based override APIs:

```ts
app.setUserAgentOverride({
  userAgent,
  userAgentMetadata
})

session.setUserAgentOverride({
  userAgent,
  userAgentMetadata,
  acceptLanguages?
})

webContents.setUserAgentOverride({
  userAgent,
  userAgentMetadata,
  inheritToNewWindows?
})
```

Add matching clear APIs:

```ts
app.clearUserAgentOverride()
session.clearUserAgentOverride()
webContents.clearUserAgentOverride()
```

Existing `setUserAgent()` APIs remain for compatibility. They do not guarantee
that UA Client Hints metadata matches the legacy UA string.

`navigator.platform` is intentionally out of scope for the first implementation.
It is controlled through Blink page settings rather than Chromium's
`UserAgentOverride` and would require a separate renderer preference path.

## UserAgentMetadata

The metadata shape follows Chromium DevTools Protocol's
`Emulation.UserAgentMetadata` model:

```ts
interface UserAgentMetadata {
  brands?: Array<{ brand: string; version: string }>;
  fullVersionList?: Array<{ brand: string; version: string }>;
  fullVersion?: string;
  platform: string;
  platformVersion: string;
  architecture: string;
  model: string;
  mobile: boolean;
  bitness?: string;
  wow64?: boolean;
  formFactors?: string[];
}
```

`brands` drives `Sec-CH-UA`. `mobile` drives `Sec-CH-UA-Mobile`.
`platform` drives `Sec-CH-UA-Platform`. High entropy fields are used when
Chromium policy allows the corresponding high entropy hints.

## Precedence

For frames and dedicated workers:

```text
webContents override > session override > app override > Chromium default
```

For shared workers and service workers:

```text
session override > app override > Chromium default
```

Shared workers and service workers are scoped to a storage partition/session,
not to an individual WebContents. A WebContents-specific override therefore does
not apply to them by default.

## Navigation Timing

Overrides are guaranteed for the first request only when set before navigation
starts.

- `app.setUserAgentOverride()` should be called before creating windows or
  sessions.
- `session.setUserAgentOverride()` should be called before creating/loading
  WebContents that use that session.
- `webContents.setUserAgentOverride()` should be called before `loadURL()` to
  affect the first navigation.

Calling an override while a worker or navigation is already running is a future
navigation/creation setting. Existing shared workers and service workers are not
retroactively updated.

## Child Windows

Session and app overrides naturally apply to child windows because child
WebContents use the same BrowserContext/session by default.

WebContents-specific overrides are not inherited by child windows unless
`inheritToNewWindows` is true. This avoids leaking a tab-specific identity into
new windows unexpectedly.

## Client Hints Policy

Electron should feed Chromium's native Client Hints pipeline rather than
manually injecting `Sec-CH-UA*` headers. This means:

- Low entropy hints are emitted according to Chromium policy.
- High entropy hints still require normal Chromium `Accept-CH`/policy flow.
- Secure/trustworthy origin and permissions policy checks remain Chromium's
  responsibility.

Electron must provide a `ClientHintsControllerDelegate`; returning `nullptr`
prevents navigation requests from receiving native UA Client Hints headers.

## Validation

The implementation should reject invalid header values, invalid brand/version
strings, and invalid form factors. Validation should mirror the DevTools
Protocol `Emulation.setUserAgentOverride` behavior where practical.
