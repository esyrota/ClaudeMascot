# Library Quirks

Sharp edges found in `markusressel/idotmatrix-api-client`, the Python library this
project was originally built on. The library is gone — [[BLE Protocol]] is a
self-contained port — but these are properties of **the panel**, not of the library, so
they still apply to the Swift client.

## Never read back after a write

The library optionally read back a characteristic after each write, which CoreBluetooth
refuses outright:

```
error while reading response data: (2, 'GATT Protocol Error: Read Not Permitted')
```

The write itself succeeds. `BLEClient` writes with response and never reads back, so
this cannot resurface — but any future "confirm the write" idea will hit it.

## Repeated uploads can stick

An upstream TODO (`gif.py:168`) reported GIFs stopping mid-upload, and a second upload
sometimes leaving the previous one stuck. Never reproduced here in normal use.

Every time it *was* suspected, the real cause was **two processes uploading at once**,
interleaving their writes. That failure mode is now designed out — see the
single-instance guard in [[Menu Bar App]] — but it is the first thing to rule out if the
panel ever looks frozen or half-written.

Historical note: the retired Python daemon needed a PID lock to get there, because its
BLE cleanup blocked `SIGTERM` and `pkill` reported success while leaving it running. The
app does **not** get single-instance behaviour for free either; assuming it did is how
two copies ended up fighting over the panel for a day.

## Frame count

The library capped uploads at 64 frames, and `art/import_gif.py` still subsamples to 16
so state changes upload fast. Neither limit applies to hand-authored native art: the
entrance is 44 source frames, imported whole (see [[Art Pipeline]]), and uploads fine.
