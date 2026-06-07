# widevine-cdm

Reusable port bundle for Chromium and Electron Widevine/CDM integration changes.

The Chromium-side CDM renderer visibility change is stored in Electron's
`src/electron/patches/chromium` stack to match Electron's distribution model.
`chromium-direct` keeps the original Chromium patch as reference/archive
material.

This bundle enables Widevine support code by default in Electron builds:

```gn
enable_widevine = true
```

It does not set `bundle_widevine_cdm = true` by default. Until CDM binary
redistribution rights are confirmed, runtime CDM files must be supplied
separately according to the product's distribution policy.

Package builds that include CDM files must provide an explicit CDM source
directory and license acknowledgement:

```bash
ELECTRON_PACKAGE_INCLUDE_WIDEVINE_CDM=1 \
ELECTRON_PACKAGE_WIDEVINE_LICENSE_ACK=1 \
ELECTRON_PACKAGE_WIDEVINE_CDM_DIR=/path/to/WidevineCdm \
scripts/build-dev-electron-npm.sh --target 42
```

On Linux, prepare a CDM directory compatible with the target Chromium version:

```bash
scripts/resolve-widevine-cdm.sh \
  --target 42 \
  --license-ack \
  --download-if-missing \
  --prefer-download \
  --require-chrome-major-match \
  --force \
  --print-environment
```

If packaging requests Widevine and no CDM path is provided, the Linux build
script runs the resolver automatically:

```bash
scripts/build-dev-electron-npm.sh \
  --target 42 \
  --include-widevine-cdm \
  --widevine-license-ack
```

Packaging scripts do not auto-discover or copy CDM files from an installed
Chrome.

## CDM Resolver Behavior

Widevine CDM packaging must be tied to the target Chromium version, not the
Electron package version. The resolver reads Chromium version information from:

```text
<target>/src/chrome/VERSION
```

If that file is unavailable, it falls back to Electron `DEPS` and its
`chromium_version` entry.

The Widevine component id is:

```text
oimompecagnajdejgnnjijobebaeigek
```

When downloading is requested, the resolver queries Google update2 instead of
blindly copying a local Chrome installation:

```text
https://update.googleapis.com/service/update2/json
```

The app entry uses `version: 0.0.0.0` so the request asks for a fresh component
compatible with the target Chromium version. The request also follows
Chromium's component updater shape by adding a CUP query and update headers:

```text
cup2key=16:<base64url_nonce>&cup2hreq=<sha256_request_body_hex>
X-Goog-Update-Updater: chrome-<chromium_version>
X-Goog-Update-Interactivity: fg
X-Goog-Update-AppId: oimompecagnajdejgnnjijobebaeigek
```

The CUP values are protocol freshness / verification data, not a secret token.
Without this updater-shaped request, update2 can return `error-inexpressible`
even when the component app status is otherwise `ok`.

Successful responses may expose downloads through
`response.apps[0].updatecheck.pipelines[*].operations[*]` entries whose
operation type is `download`. Prefer HTTPS URLs. The downloaded artifact is a
CRX3 package; the resolver checks the `Cr24` header, skips the CRX header, and
extracts the ZIP payload.

Before copying a CDM directory, the resolver verifies:

- `manifest.json` parses as JSON
- `LICENSE` exists
- the current platform library exists
- the manifest advertises the current platform, such as `win_x64`
- `minimum_chrome_version` is not higher than the target Chromium version
- `x-cdm-host-versions` overlaps Chromium's supported range from
  `media/cdm/supported_cdm_versions.h`

The resolver's preferred flow is:

1. With `--prefer-download`, try Google update2 first.
2. If update2 fails, try Chrome for Testing exact-version archives.
3. Without `--prefer-download`, check local candidates first, then fall back to
   downloads when `--download-if-missing` is set.

Windows packaging invokes the resolver with equivalent behavior to:

```text
-DownloadIfMissing -PreferDownload -RequireChromeMajorMatch
```

This avoids selecting an installed Chrome CDM whose major version does not match
the Electron target's Chromium major.

Widevine license acknowledgement remains a hard boundary. The resolver and
package scripts refuse download, copy, and packaging work unless the caller
passes the acknowledgement flag or environment variable:

```text
--widevine-license-ack
ELECTRON_PACKAGE_WIDEVINE_LICENSE_ACK=1
```

Static manifest and host-version checks do not prove DRM playback. Runtime
playback still needs product-level testing with the relevant license server.
