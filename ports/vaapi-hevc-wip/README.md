# vaapi-hevc-wip

Reusable port bundle for managing VAAPI/HEVC WIP Chromium changes through
Electron's Chromium patch stack.

After apply, the Electron repo receives a patch-stack registration commit, and
the Chromium patches added by that commit are also materialized in the Chromium
`src` working tree with `git am -3`.

```text
src/electron/patches/chromium/*.patch
src/electron/patches/chromium/.patches
```

In other words, one `apply vaapi-hevc-wip --target <target>` call keeps both the
Electron repo's management record and the current Chromium working tree aligned.
