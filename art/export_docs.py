"""
Export viewable copies of every bundled animation for the [[Animation Catalogue]] spec.

The shipped art is 32x32 -- unreadably small in a document -- so each clip is scaled up
by an integer factor with NEAREST resampling, which reproduces every pixel exactly as a
block of pixels. No frame is added, dropped or retimed: the per-frame durations are
copied straight from the source GIF, so what the page plays is what the panel plays.

    venv/bin/python art/export_docs.py     # rewrites Docs/Specs/_animations/*.gif

Run it after art/generate.py, alongside art/export_golden.py. The catalogue page names
every clip, so a *new* clip needs a line adding there by hand; this script only keeps the
images honest.

Deliberately writes into Docs/ rather than committing a second hand-made copy of the art:
a duplicate that is updated by hand is a second, staler truth, which is exactly what the
repo's docs rule forbids. Regenerating from the bundled GIFs means the page cannot drift
from what ships.
"""

import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "Sources" / "ClaudeMascot" / "Resources" / "Animations"
OUT = ROOT / "Docs" / "Specs" / "_animations"

# 6x -> 192px. Big enough to read a 2px eye, small enough to sit several to a row.
SCALE = 6


def upscale(path: Path) -> list:
    """Every frame of `path`, scaled by SCALE with NEAREST, plus its duration."""
    im = Image.open(path)
    frames = []
    try:
        while True:
            big = im.convert("RGB").resize(
                (im.width * SCALE, im.height * SCALE), Image.NEAREST
            )
            frames.append((big, im.info.get("duration") or 100))
            im.seek(im.tell() + 1)
    except EOFError:
        pass
    return frames


def save(name: str, frames) -> Path:
    path = OUT / f"{name}.gif"
    images = [im for im, _ in frames]
    images[0].save(
        path,
        save_all=True,
        append_images=images[1:],
        duration=[ms for _, ms in frames],
        loop=0,
        disposal=2,
    )
    return path


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = json.loads((SRC / "clips.json").read_text())["clips"]

    # Drop anything left behind by a renamed or deleted clip, so the folder is
    # exactly the current manifest and never accumulates orphans.
    keep = {f"{name}.gif" for name in manifest}
    for stale in OUT.glob("*.gif"):
        if stale.name not in keep:
            stale.unlink()
            print(f"removed stale {stale.name}")

    for name in sorted(manifest):
        frames = upscale(SRC / manifest[name]["file"])
        path = save(name, frames)
        print(f"{path.name:22s} {len(frames):2d} frames  {path.stat().st_size:6d} bytes")

    print(f"\nwrote {len(manifest)} previews at {SCALE}x to {OUT.relative_to(ROOT)}")
