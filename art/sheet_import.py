"""
Slice a hand-authored sprite-sheet screenshot into 32x32 mascot frames.

`art/import_gif.py` imports a single animated GIF; this handles the other shape of
hand-drawn source the mascot has -- a contact sheet exported as a PNG screenshot from
a sprite-sheet tool, several frames arranged in a grid, one PNG per animation.

A screenshot, not a clean atlas, is the whole complication here. It carries a grey
page background outside the frames, uneven gaps between them, and a frame-number
label strip under each row -- so THE GRID HAS NO FIXED PITCH. Measured across the two
sheets this pipeline was built for, column runs are 161-176px wide and row runs
166-195px tall despite a nominal 9x4 grid of "the same" tile. Any code that slices by
`col * pitch_x, row * pitch_y` will silently misalign by up to fifteen pixels on some
tiles and land clean on others, which is a much worse failure than an exception --
the next person to touch this file needs no fixed-pitch assumption to un-learn, so it
does not exist here.

Detection instead works the way a screenshot invites: each tile is a near-black
rectangle (its own drawing canvas, exported at the source's own background colour)
sitting on a lighter grey page. Threshold on `r+g+b < DARK_THRESHOLD`, project onto
each axis to find the column and row runs, intersect them into 36 candidate cells,
then -- because a run's width is the union across every tile in that column/row, not
any one tile's actual extent -- trim each candidate down to the dark bounding box
that lives inside it. That per-tile bbox is what gets resampled.

The second complication: the pixel art inside a tile is upscaled to the screenshot
by a NON-INTEGER factor (measured ~5.3x -- a 32x32 native canvas exported at
161-196px). `Image.resize` would blend across native-pixel boundaries at a
non-integer ratio and blur the flat colour fields the panel needs crisp. Instead,
`resample_tile` samples the centre of each of the 32x32 destination cells against a
sub-grid computed from the tile's own measured width and height -- nearest-neighbour,
but on a per-tile scale rather than a fixed one. Landing exactly on native-pixel
centres is also the cleanest de-anti-aliasing available, the same trick
`art/import_gif.py`'s `detect_native_grid` and `generate.py`'s `imported()` both rely
on: blend pixels only ever live on cell boundaries, so sampling centres skips them.

    python art/sheet_import.py art/sources/<sheet>.png            # dump a preview
    python art/sheet_import.py art/sources/<sheet>.png --out x.png
"""

import argparse
from pathlib import Path

from PIL import Image

SIZE = 32
COLS, ROWS = 9, 4
# A tile's own drawing canvas (background + art) sits well below the screenshot's
# grey page background; a pixel is "tile" when the sum of its channels is under
# this. Comfortably below the page grey (which sums well over 300) and comfortably
# above the tile canvas's own near-black noise (which sums under 10 in practice).
DARK_THRESHOLD = 40


def _dark_runs(occupied: list) -> list:
    """Contiguous True-runs in a 1D occupancy list, as inclusive (start, end) pairs."""
    runs = []
    start = None
    for i, v in enumerate(occupied):
        if v and start is None:
            start = i
        elif not v and start is not None:
            runs.append((start, i - 1))
            start = None
    if start is not None:
        runs.append((start, len(occupied) - 1))
    return runs


def find_grid(im: Image.Image, cols: int = COLS, rows: int = ROWS,
              dark_threshold: int = DARK_THRESHOLD) -> list:
    """
    Detect each tile's own bounding box in a contact-sheet screenshot.

    Returns `cols * rows` (left, top, right, bottom) boxes, inclusive, in row-major
    order. See the module docstring for why this is detected per tile rather than
    assumed from a fixed pitch -- a screenshot's tiles are not evenly spaced.
    """
    w, h = im.size
    px = im.load()

    def is_dark(c) -> bool:
        return sum(c) < dark_threshold

    col_occ = [any(is_dark(px[x, y]) for y in range(h)) for x in range(w)]
    row_occ = [any(is_dark(px[x, y]) for x in range(w)) for y in range(h)]
    col_runs = _dark_runs(col_occ)
    row_runs = _dark_runs(row_occ)
    if len(col_runs) != cols or len(row_runs) != rows:
        raise SystemExit(
            f"find_grid: expected a {cols}x{rows} grid, found "
            f"{len(col_runs)} column run(s) and {len(row_runs)} row run(s) at "
            f"threshold {dark_threshold} -- the sheet's layout or export changed, "
            f"re-measure DARK_THRESHOLD before trusting the slice")

    boxes = []
    for ry0, ry1 in row_runs:
        for cx0, cx1 in col_runs:
            # Trim the candidate cell (the union footprint of every tile in this
            # column/row) down to this one tile's own dark pixels -- see the
            # module docstring for why the candidate alone is not tight enough.
            minx = maxx = miny = maxy = None
            for y in range(ry0, ry1 + 1):
                for x in range(cx0, cx1 + 1):
                    if is_dark(px[x, y]):
                        if minx is None or x < minx:
                            minx = x
                        if maxx is None or x > maxx:
                            maxx = x
                        if miny is None or y < miny:
                            miny = y
                        if maxy is None or y > maxy:
                            maxy = y
            if minx is None:
                raise SystemExit(
                    f"find_grid: candidate cell ({cx0},{ry0})-({cx1},{ry1}) has no "
                    f"dark pixels -- the grid detection above is out of sync with "
                    f"the sheet")
            boxes.append((minx, miny, maxx, maxy))
    return boxes


def resample_tile(im: Image.Image, box, size: int = SIZE) -> Image.Image:
    """
    Resample one tile down to `size` x `size` by sampling destination-cell centres.

    The tile's native art is upscaled by a non-integer factor (see the module
    docstring), so this computes a fresh sub-grid from the tile's own measured
    width and height rather than assuming any fixed ratio -- `Image.resize` would
    blur across native-pixel boundaries at a non-integer scale.
    """
    left, top, right, bottom = box
    tile_w, tile_h = right - left + 1, bottom - top + 1
    src = im.load()
    out = Image.new("RGB", (size, size))
    dst = out.load()
    for oy in range(size):
        sy = top + int((oy + 0.5) * tile_h / size)
        sy = min(bottom, max(top, sy))
        for ox in range(size):
            sx = left + int((ox + 0.5) * tile_w / size)
            sx = min(right, max(left, sx))
            dst[ox, oy] = src[sx, sy]
    return out


def slice_sheet(path: Path, cols: int = COLS, rows: int = ROWS, size: int = SIZE,
                 dark_threshold: int = DARK_THRESHOLD) -> list:
    """Load a contact-sheet screenshot and return `cols * rows` size x size RGB
    frames, row-major (left to right, top to bottom -- matches the sheets'
    frame-number labels)."""
    im = Image.open(path).convert("RGB")
    boxes = find_grid(im, cols, rows, dark_threshold)
    return [resample_tile(im, box, size) for box in boxes]


def preview(tiles: list, cols: int, path: Path, scale: int = 6, size: int = SIZE) -> Path:
    """Contact-sheet dump of sliced (and optionally recoloured) tiles, for eyeballing."""
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * size * scale, rows * size * scale), (18, 18, 20))
    for i, tile in enumerate(tiles):
        row, col = divmod(i, cols)
        big = tile.resize((size * scale, size * scale), Image.NEAREST)
        sheet.paste(big, (col * size * scale, row * size * scale))
    sheet.save(path)
    return path


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__,
                                  formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("sheet", type=Path, help="contact-sheet screenshot PNG")
    ap.add_argument("--cols", type=int, default=COLS)
    ap.add_argument("--rows", type=int, default=ROWS)
    ap.add_argument("--out", type=Path, default=None,
                    help="preview path (default: <sheet>.sliced.png next to the source)")
    args = ap.parse_args()

    frames = slice_sheet(args.sheet, args.cols, args.rows)
    out = args.out or args.sheet.with_suffix(".sliced.png")
    preview(frames, args.cols, out)
    print(f"{args.sheet.name}: {len(frames)} tiles -> {out}")
