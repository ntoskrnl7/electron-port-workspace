# Preload / 41

Electron 41 target bundle for session-managed preload injection across frames
and workers.

Patch directories:

- `electron/*.patch`: apply in `src/electron`

There are no direct Chromium patches in this target bundle.

Included patches:

- `feat: extend session preload scripts to frames and workers`
- `fix: delay subframe preload init after early script execution`
- `fix: disable sandbox by default for subframe node integration`
- `fix: skip PDF viewer extension preload`
- `fix: disable DOM storage in PDF renderers`

Use:

```bash
scripts/port-bundle.sh apply preload \
  --target 41 \
  --src-root /path/to/src

scripts/port-bundle.sh undo preload \
  --target 41 \
  --src-root /path/to/src
```

Useful checks after applying:

```bash
cd /path/to/src/electron
python3 script/run-clang-format.py -c shell/renderer/electron_render_frame_observer.cc
git diff --check
```
