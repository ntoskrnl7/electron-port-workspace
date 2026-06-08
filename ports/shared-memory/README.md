# shared-memory

Reusable Electron shared-memory channel APIs.

This port adds main-process shared-memory pool and channel APIs so Electron
applications can move larger binary payloads through named shared memory rather
than copying everything through regular IPC messages.

Target bundles live under:

```text
ports/shared-memory/<target>/
```
