# Glossary

## Main Process

The Electron process that runs application startup code, owns `app`, creates
windows, and controls browser-side objects such as `Session`, `WebContents`,
`WebFrameMain`, and worker runtime handles.

## Renderer Process

The Chromium renderer process that runs web page, preload, frame, worker, and
service worker JavaScript.
