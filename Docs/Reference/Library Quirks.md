# Library Quirks

Sharp edges in `markusressel/idotmatrix-api-client` (the vendored Python library).

## No top-level re-exports

`idotmatrix/__init__.py` is only a docstring. `from idotmatrix import IDotMatrixClient`
raises ImportError. Import from submodules:

```python
from idotmatrix.client import IDotMatrixClient
from idotmatrix.screensize import ScreenSize
```

## A benign GATT error on every write

After each write the library optionally reads back a characteristic that CoreBluetooth
refuses, logging at ERROR:

```
error while reading response data: (2, 'GATT Protocol Error: Read Not Permitted')
```

The write itself succeeded. The library only silences this for BlueZ (`org.bluez.Error.NotPermitted`,
Linux); macOS raises a different exception class and falls through to the generic
handler — `connection_manager.py:287`. The daemon suppresses it by setting that
logger to CRITICAL.

## Repeated uploads can stick

`gif.py:168` carries an upstream TODO: some GIFs stop animating mid-upload, and a
second upload after a successful one sometimes leaves the previous GIF stuck.

In practice this has been fine — 7+ consecutive uploads succeeded. But when the panel
looks frozen, check for **two daemons** first (see below); that was the real cause
every time it was suspected here.

## SIGTERM does not kill the daemon

The daemon's BLE cleanup blocks `SIGTERM`, so `pkill -f mascot/daemon.py` reports
success while leaving the process alive. This silently produced two daemons running
for over an hour, interleaving uploads and leaving the panel showing half-written
GIFs.

Always `kill -9`, and always verify:

```bash
pgrep -fl 'mascot/daemon.py'
```

The Python daemon now takes a PID lock at `~/.idotmatrix/daemon.pid` to prevent this.
[[Menu Bar App]] gets it for free — a single app instance.

## Frame count

`_ensure_reasonable_frame_count` caps at 64 frames. The importer subsamples to 16 to
keep state-change uploads fast.
