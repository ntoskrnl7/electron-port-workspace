# vaapi-hevc-wip / 41

Electron 41 target bundle for VAAPI/HEVC WIP.

## Contents

- `electron/*.patch`: Electron repo commit that adds eight VAAPI/HEVC Chromium
  patches to `src/electron/patches/chromium`
- `chromium-direct/*.patch`: archived source Chromium commits that can also be
  applied directly

The primary apply target is `electron/*.patch`. `chromium-direct` is archived
source material.

## Apply

```bash
scripts/port-bundle.sh apply vaapi-hevc-wip --target 41 --src-root /path/to/src
```

After apply, the Electron repo receives a patch-stack commit, and the Chromium
patches added by that commit are also applied to Chromium `src` with
`git am -3`.

## Undo

```bash
scripts/port-bundle.sh undo vaapi-hevc-wip --target 41 --src-root /path/to/src
```

To remove the bundle without preserving revert commits:

```bash
scripts/port-bundle.sh drop vaapi-hevc-wip --target 41 --src-root /path/to/src
```
