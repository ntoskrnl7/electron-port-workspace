# window-prompt-dialog / 42

Reusable Electron 42 target bundle for enabling `window.prompt()`.

Patch sequence:

- `electron/0001-feat-allow-window-prompt-dialogs.patch`

Behavior:

- Removes Electron's renderer-side `window.prompt` override that threw
  `prompt() is not supported.`
- Lets Chromium route prompt dialogs through Electron's existing
  `-run-dialog` path with `dialogType: 'prompt'`.
- Allows a custom `-run-dialog` handler to return prompt text through the
  callback.
- Keeps the built-in Electron message box path minimal: OK returns
  `defaultPromptText`; Cancel returns `null` through Chromium's normal prompt
  cancel behavior. It does not add a native text-entry UI yet.

Export source:

- Electron base: `5bdcbff09733d0d6177c74e6d1fb5835b41dc727`
- Electron head: `4be57ca72d08e49011d1a6f9980e337da5d06a86`

Use:

```bash
scripts/port-bundle.sh apply window-prompt-dialog --target 42
scripts/port-bundle.sh undo window-prompt-dialog --target 42
```

```powershell
.\scripts\port-bundle.ps1 apply window-prompt-dialog -Target 42 -SrcRoot C:\path\to\src
.\scripts\port-bundle.ps1 undo window-prompt-dialog -Target 42 -SrcRoot C:\path\to\src
```

Validation performed before export:

- `e --config=42-release build -local_jobs 16 -t electron:electron`
- `env -u ELECTRON_RUN_AS_NODE npm run test -- --skipYarnInstall --runners=main --grep "window.prompt"`
- `env -u ELECTRON_RUN_AS_NODE npm run test -- --skipYarnInstall --runners=main --grep "synchronous prompts"`
- `scripts/build-dev-electron-npm.sh --target 42 --include-widevine-cdm --widevine-license-ack`

Built package:

- `/path/to/workspace/42/src/out/electron-npm/electron-linux-x64-42.1.0-dev.10.tgz`
