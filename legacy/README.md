# legacy

The Python daemon this app replaced, kept only as a record of how the system worked
before the native port.

**It will not run as-is.** `daemon.py` imports the `idotmatrix` Python library, which
was vendored in the old `idotmatrix-api-client` checkout and is no longer part of this
repository. Reviving it would mean re-cloning
<https://github.com/markusressel/idotmatrix-api-client>.

`ensure.sh` and `start.sh` launched the daemon through Terminal.app to borrow its
Bluetooth permission — the workaround the menu bar app exists to eliminate. See
`Docs/Reference/macOS Bluetooth TCC.md`.

The protocol itself is not lost with the library: `art/export_golden.py` contains a
self-contained port of the packet framing, and `Tests/Fixtures/` pins it byte-for-byte.
