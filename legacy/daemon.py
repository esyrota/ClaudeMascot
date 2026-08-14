"""
Mascot daemon: holds one BLE connection to the iDotMatrix display and mirrors
whatever state word is in the state file.

Why a daemon instead of doing this straight from the hooks:

  1. macOS TCC kills any process that touches Bluetooth unless the *responsible*
     app declares NSBluetoothAlwaysUsageDescription. Hooks are spawned by `claude`,
     which doesn't -- they'd die with SIGABRT. This daemon is launched from
     Terminal.app, which does.
  2. A BLE connect takes ~7s. Far too slow to do per hook.

So hooks only ever `echo <state> > ~/.idotmatrix/state`, which is instant and
cannot fail. This process does all the radio work.

    python mascot/daemon.py          # run it from Terminal, or use start.sh
"""

import asyncio
import logging
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from idotmatrix.client import IDotMatrixClient
from idotmatrix.screensize import ScreenSize

STATE_DIR = Path.home() / ".idotmatrix"
STATE_FILE = STATE_DIR / "state"
LOCK_FILE = STATE_DIR / "daemon.pid"
GIF_DIR = Path(__file__).resolve().parent

# Paste your display's address here to skip the ~5s discovery scan on startup.
DISPLAY_MAC = "95FFE74B-E5D9-125E-E136-8D25E959FA39"

VALID_STATES = {"idle", "thinking", "working", "waiting", "done", "sleeping"}

# Panel brightness, 5-100. Low is much easier on the eyes in a dim room, and it is
# the right way to make things look darker -- dimming the ART shifts colours blue.
BRIGHTNESS = int(os.environ.get("MASCOT_BRIGHTNESS", 35))

# After a stretch of idling, doze off; after longer, blank the panel entirely.
# Overridable so the behaviour can be exercised without waiting ten minutes.
SLEEP_AFTER = float(os.environ.get("MASCOT_SLEEP_AFTER", 5 * 60))
OFF_AFTER = float(os.environ.get("MASCOT_OFF_AFTER", 10 * 60))
# ...and after longer still, quit entirely and release the BLE connection. The
# hooks restart us on demand via ensure.sh, so there is no reason to sit on the
# radio while nobody is using the panel.
QUIT_AFTER = float(os.environ.get("MASCOT_QUIT_AFTER", 15 * 60))
OFF = "__off__"          # sentinel: panel powered down, not an animation

# "done" is a celebration, not a resting state -- fall back to idle afterwards.
# It holds for a good while so the confetti is actually seen: the Stop hook fires
# the moment a turn ends, which is often exactly when you look away. This is a
# floor, not a ceiling -- sending another prompt switches to "thinking" at once.
DONE_SECONDS = float(os.environ.get("MASCOT_DONE_SECONDS", 30))
AUTO_REVERT = {"done": ("idle", DONE_SECONDS)}

POLL_SECONDS = 0.25

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s :: %(levelname)s :: %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger("mascot")
logging.getLogger("bleak").setLevel(logging.WARNING)
# The library logs an ERROR for an optional post-write GATT read that CoreBluetooth
# refuses. The write itself succeeds, so don't let it spam the console.
logging.getLogger("idotmatrix.connection_manager").setLevel(logging.CRITICAL)


def acquire_lock() -> None:
    """
    Refuse to start if another daemon is already running.

    Two daemons both polling the state file will both upload to the panel, and the
    interleaved transfers leave it showing a stuck, half-written GIF. Worse, the
    daemon's BLE cleanup blocks SIGTERM, so a plain `pkill` can silently leave one
    alive -- which is exactly how a stale instance from an earlier run survived.
    """
    if LOCK_FILE.exists():
        try:
            pid = int(LOCK_FILE.read_text().strip())
        except (ValueError, OSError):
            pid = None
        if pid and pid != os.getpid():
            try:
                os.kill(pid, 0)          # signal 0 just tests for existence
            except ProcessLookupError:
                pass                     # stale lock, fall through and take it
            except PermissionError:
                raise SystemExit(f"another mascot daemon is running (pid {pid})")
            else:
                raise SystemExit(
                    f"another mascot daemon is already running (pid {pid}).\n"
                    f"Stop it first:  kill -9 {pid}"
                )
    LOCK_FILE.write_text(str(os.getpid()))


def release_lock() -> None:
    try:
        if LOCK_FILE.exists() and LOCK_FILE.read_text().strip() == str(os.getpid()):
            LOCK_FILE.unlink()
    except OSError:
        pass


def read_state() -> str:
    try:
        value = STATE_FILE.read_text().strip()
    except FileNotFoundError:
        return "idle"
    return value if value in VALID_STATES else "idle"


def gif_for(state: str) -> Path:
    """
    Hand-imported art in mascot/custom/ wins over the generated art, so
    re-running generate.py never clobbers a gif brought in via import_gif.py.
    """
    custom = GIF_DIR / "custom" / f"{state}.gif"
    return custom if custom.exists() else GIF_DIR / f"{state}.gif"


async def show(client: IDotMatrixClient, state: str) -> bool:
    path = gif_for(state)
    if not path.exists():
        log.error(f"no animation for state {state!r} ({path})")
        return False
    try:
        await client.gif.upload_gif_file(file_path=str(path))
        log.info(f"showing {state} ({path.parent.name}/{path.name})")
        return True
    except Exception as e:
        log.warning(f"upload failed for {state}: {e!r}")
        return False


async def main() -> None:
    STATE_DIR.mkdir(exist_ok=True)
    acquire_lock()
    if not STATE_FILE.exists():
        STATE_FILE.write_text("idle")

    client = IDotMatrixClient(
        screen_size=ScreenSize.SIZE_32x32,
        mac_address=DISPLAY_MAC,
    )
    client.set_auto_reconnect(True)

    log.info("connecting...")
    await client.connect()
    await client.set_brightness(BRIGHTNESS)
    log.info("connected -- watching %s", STATE_FILE)

    current = None
    pending_revert = None
    last_seen = None
    idle_since = None

    def now() -> float:
        return asyncio.get_event_loop().time()

    try:
        while True:
            desired = read_state()
            t = now()

            # Track how long we have been continuously idle.
            if desired != last_seen:
                last_seen = desired
                idle_since = t if desired == "idle" else None

            # An auto-revert timer fires only if nothing else changed meanwhile.
            if pending_revert is not None:
                revert_to, deadline = pending_revert
                if desired == current and t >= deadline:
                    desired = revert_to
                    STATE_FILE.write_text(revert_to)
                    last_seen, idle_since = revert_to, t
                    pending_revert = None

            # Idling long enough escalates: awake -> sleeping -> panel off.
            effective = desired
            if desired == "idle" and idle_since is not None:
                elapsed = t - idle_since
                if elapsed >= QUIT_AFTER:
                    log.info("idle %.0fs -- shutting down (hooks will restart me)",
                             elapsed)
                    return
                if elapsed >= OFF_AFTER:
                    effective = OFF
                elif elapsed >= SLEEP_AFTER:
                    effective = "sleeping"

            if effective != current:
                if effective == OFF:
                    await client.turn_off()
                    log.info("idle %.0fs -- panel off", t - idle_since)
                    current = OFF
                    pending_revert = None
                else:
                    # Coming back from a powered-down panel needs a wake first.
                    if current == OFF:
                        await client.turn_on()
                        await client.set_brightness(BRIGHTNESS)
                        log.info("waking panel")
                    if await show(client, effective):
                        current = effective
                        if effective in AUTO_REVERT:
                            revert_to, delay = AUTO_REVERT[effective]
                            pending_revert = (revert_to, t + delay)
                        else:
                            pending_revert = None
                    else:
                        # Failed upload: back off rather than hammering the radio.
                        await asyncio.sleep(1.0)

            await asyncio.sleep(POLL_SECONDS)
    finally:
        log.info("disconnecting...")
        await client.disconnect()
        release_lock()


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nmascot daemon stopped.")
