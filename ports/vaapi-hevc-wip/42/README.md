# vaapi-hevc-wip / 42

Reusable Electron target bundle.

Patch directories:

- `electron/*.patch`: apply in `src/electron`; adds and refreshes Electron
  `patches/chromium` patch-stack entries.

There are no direct Chromium archive files in this target bundle.

Target notes:

- `0003-patches-gate-Intel-HEVC-tuning-to-Intel-VAAPI.patch` keeps the Intel
  iHD HEVC stabilization parameters behind Intel VAAPI implementation checks.
  Non-Intel implementations, including NVIDIA, keep the original `fix/vaapi`
  HEVC parameter path.

Use:

```bash
scripts/port-bundle.sh apply vaapi-hevc-wip --target 42 --src-root /path/to/src
scripts/port-bundle.sh undo vaapi-hevc-wip --target 42 --src-root /path/to/src
```
