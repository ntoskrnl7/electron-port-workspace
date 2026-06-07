# window-prompt-dialog

Reusable Electron feature port that enables `window.prompt()` to use Electron's
existing JavaScript dialog path instead of throwing `prompt() is not supported.`

This is intentionally minimal. It does not add a public JavaScript dialog API;
apps that need interception can still use the internal `-run-dialog` path until
a supported API is added.

Target bundles live under:

```text
ports/window-prompt-dialog/<target>/
```
