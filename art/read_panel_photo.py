"""Read a photographed test card back into numbers.

The panel and the on-screen reference are photographed together (see
Docs/Reference/Panel Quirks.md), so each half is measured the same way and the
comparison survives whatever the camera did to colour.

    venv/bin/python art/read_panel_photo.py photo.png \
        --corners 899,251 1358,231 1360,709 917,716 --card a-ramps [--flip]

Corners are the four corners of the *lit* area, clockwise from the top-left as
it appears in the photo, in photo pixels. Read them off the image; `--fit` then
hill-climbs from there. **Always check the reported landmark**: card A's white
2×2 anchor must land on cells (0,0)-(1,1) with a dark neighbour. A fit that
looks plausible and misses the anchor is off by a cell, which silently shifts
every ramp step by one — that happened once and inverted the reading.
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

CARDS = Path(__file__).parent / "testcards"
S = 16  # samples per cell edge


def load(path: str) -> Image.Image:
    """A still, or the average of every frame of a video.

    **Prefer the video.** The panel is scan-driven: a 2026-08-26 clip measured
    per-pixel temporal variation at 9.5% of level against a monitor's 2.9% in
    the same frame, and moving horizontal banding at 7.2% (worst frame, 50
    luma) — invisible to the eye, which integrates, but a still catches one
    arbitrary phase of it. Averaging 42 frames averages the scan out. The
    whole-patch level is stable to 0.36%, so nothing is lost by averaging.
    """
    if Path(path).suffix.lower() not in (".mov", ".mp4", ".m4v"):
        return Image.open(path).convert("RGB")
    if not shutil.which("ffmpeg"):
        raise SystemExit("ffmpeg is needed to average a video; brew install ffmpeg")
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(
            ["ffmpeg", "-v", "error", "-i", path, "-vsync", "0", f"{tmp}/f%04d.png"],
            check=True,
        )
        frames = sorted(Path(tmp).glob("f*.png"))
        if not frames:
            raise SystemExit(f"no frames decoded from {path}")
        acc = None
        for f in frames:
            a = np.asarray(Image.open(f).convert("RGB"), dtype=float)
            acc = a if acc is None else acc + a
        print(f"averaged {len(frames)} frames")
        return Image.fromarray((acc / len(frames)).round().clip(0, 255).astype("uint8"))


def cells(im: Image.Image, corners) -> np.ndarray:
    """Warp the quad to a 32×32 grid and average the centre half of each cell.
    The centre half, not the whole cell: the panel's LEDs have visible gaps and
    the edges carry a neighbour's bloom."""
    tl, tr, br, bl = corners
    quad = (tl[0], tl[1], bl[0], bl[1], br[0], br[1], tr[0], tr[1])
    a = np.asarray(
        im.transform((32 * S, 32 * S), Image.QUAD, data=quad, resample=Image.BILINEAR),
        dtype=float,
    )
    return a.reshape(32, S, 32, S, 3)[:, S // 4 : 3 * S // 4, :, S // 4 : 3 * S // 4, :].mean(
        axis=(1, 3)
    )


def luma(c):
    return c[..., 0] * 0.299 + c[..., 1] * 0.587 + c[..., 2] * 0.114


def _rank(v):
    order = v.argsort()
    r = np.empty_like(order, dtype=float)
    r[order] = np.arange(v.size)
    return (r - r.mean()) / (r.std() + 1e-6)


def fit(im, corners, target_rank, span=20):
    """Hill-climb the corners against the authored card.

    Rank correlation, never Pearson: the panel's response curve is the thing
    being measured, so the objective has to be invariant to any monotonic
    distortion of it — otherwise the fit bends the geometry to explain the
    physics.
    """
    best = float((_rank(luma(cells(im, corners)).ravel()) * target_rank).mean())
    corners = [list(c) for c in corners]
    while span >= 1:
        moved = True
        while moved:
            moved = False
            for i in range(4):
                for dx, dy in ((span, 0), (-span, 0), (0, span), (0, -span)):
                    trial = [list(c) for c in corners]
                    trial[i][0] += dx
                    trial[i][1] += dy
                    s = float((_rank(luma(cells(im, trial)).ravel()) * target_rank).mean())
                    if s > best + 1e-5:
                        best, corners, moved = s, trial, True
        span //= 2
    return [tuple(c) for c in corners], best


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("photo", help="a still, or a video whose frames are averaged (preferred)")
    ap.add_argument("--corners", nargs=4, required=True, metavar="X,Y")
    ap.add_argument("--card", default=None, help="card id in art/testcards, enables --fit and landmarks")
    ap.add_argument("--flip", action="store_true", help="photo is 180° rotated")
    ap.add_argument("--fit", action="store_true")
    ap.add_argument("--patches", type=int, default=0, help="report N×1 patch columns instead of cells")
    args = ap.parse_args()

    im = load(args.photo)
    corners = [tuple(int(v) for v in c.split(",")) for c in args.corners]
    if args.fit and args.card:
        authored = Image.open(CARDS / f"{args.card}.gif").convert("RGB")
        if args.flip:
            authored = authored.rotate(180)
        corners, score = fit(im, corners, _rank(luma(np.asarray(authored, float)).ravel()))
        print(f"fitted corners {corners}  rank-corr {score:+.3f}")

    grid = cells(im, corners)
    if args.flip:
        grid = grid[::-1, ::-1, :]

    if args.card == "a-ramps":
        anchor = luma(grid[0:2, 0:2]).mean()
        print(f"landmark: anchor {anchor:.0f} vs neighbour {luma(grid[2, 2]):.0f}"
              f"  {'OK' if anchor > 3 * luma(grid[2, 2]) else 'MISALIGNED — do not trust the numbers'}")

    if args.patches:
        step = 32 // args.patches
        for p in range(args.patches):
            col = grid[:, p * step + 1 : p * step + 3, :]
            for band in range(4):
                v = col[band * 8 + 3 : band * 8 + 7].reshape(-1, 3).mean(axis=0)
                print(f"  patch {p} band {band}: ({v[0]:3.0f},{v[1]:3.0f},{v[2]:3.0f})")
    else:
        for y in range(32):
            print(" ".join(f"{luma(grid[y, x]):3.0f}" for x in range(32)))


if __name__ == "__main__":
    main()
