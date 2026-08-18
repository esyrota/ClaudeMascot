"""
Import an arbitrary GIF for use as a mascot state on the 32x32 panel.

Handles the things a naive resize gets wrong:

  * coalescing -- GIF frames are deltas with disposal methods; each frame is
    composited onto a running canvas, then flattened onto black
  * cropping   -- crops to the union bounding box of actual content across all
    frames, so a small figure in a big empty canvas still fills the panel
  * framerate  -- subsamples to at most MAX_FRAMES so a state change uploads fast
  * palette    -- guarantees >= MIN_COLORS so the panel doesn't garble the
    colors (see the note in generate.py)

Imported gifs land in mascot/custom/, which the daemon prefers over the
generated art, so re-running generate.py never clobbers them.

    python mascot/import_gif.py gifs/claude-claude-code.gif idle
    python mascot/import_gif.py gifs/claude-claude-code-1.gif working --preview
"""

import argparse
from pathlib import Path

from PIL import Image, ImageSequence

from generate import EYE, MASCOT, MIN_COLORS, SIZE, pad_palette as _pad  # noqa: E402

CUSTOM_DIR = (Path(__file__).resolve().parent.parent
              / "Sources" / "ClaudeMascot" / "Resources" / "Animations" / "custom")
MAX_FRAMES = 16
PAD = 1  # pixels of margin to leave around the cropped content


def coalesce(path: Path):
    """
    Return [(RGBA frame, duration_ms)].

    PIL already applies GIF disposal while iterating sequentially, so each frame
    it yields is complete. Compositing them onto a running canvas as well makes
    every frame accumulate on the last and smears the animation into a trail --
    so take PIL's frames as-is.
    """
    from PIL import GifImagePlugin
    GifImagePlugin.LOADING_STRATEGY = GifImagePlugin.LoadingStrategy.RGB_AFTER_FIRST

    im = Image.open(path)
    return [
        (raw.convert("RGBA"), raw.info.get("duration") or 100)
        for raw in ImageSequence.Iterator(im)
    ]


def detect_native_grid(frame, lo=8, hi=64):
    """
    Find the source art's native pixel resolution.

    These gifs are small pixel-art canvases blown up to 200x200 at a non-integer
    scale (claude-claude-code-1 is ~19x19 at 10.53px per pixel), and the blown-up
    export carries anti-aliased edges -- 53 distinct colors in one frame. Resizing
    200->32 straddles those boundaries and smears them.

    Brute force it: for each candidate N, sample cell centers, blow back up to the
    source size, and keep the N that reproduces the original most closely. Sampling
    centers also sidesteps the anti-aliased edge pixels, which only live at the
    boundaries between native cells.
    """
    rgb = frame.convert("RGB")
    w, h = rgb.size
    best, best_err = None, None
    for n in range(lo, hi + 1):
        small = rgb.resize((n, n), Image.NEAREST)
        back = small.resize((w, h), Image.NEAREST)
        # Mean absolute error against the original.
        err = sum(abs(a - b) for a, b in zip(rgb.tobytes(), back.tobytes())) / (w * h * 3)
        if best_err is None or err < best_err - 1e-9:
            best, best_err = n, err
    return best, best_err


def to_native(frames, n):
    """Resample every frame down to the native n x n grid, no interpolation."""
    return [(f.resize((n, n), Image.NEAREST), d) for f, d in frames]


def power_of_two_window(box, size, options=(128, 256)):
    """
    Pick the smallest power-of-two window that contains the content, centered on it.

    128 -> 32 is exactly 4:1 and 256 -> 32 exactly 8:1, so every output pixel is a
    whole number of source pixels and no edge gets split. Which one fits depends on
    the art: the blacksmith's content is 108px (fits 128, and filling more of the
    window means a bigger mascot on the panel), the walker's is 182px (needs 256).
    The window is clamped to the canvas and any overhang is filled with black.
    """
    l, t, r, b = box
    need = max(r - l, b - t)
    side = next((o for o in sorted(options) if o >= need), max(options))
    cx, cy = (l + r) / 2, (t + b) / 2
    return int(round(cx - side / 2)), int(round(cy - side / 2)), side


def window_crop(frame, left, top, side, background=(0, 0, 0)):
    """Crop a side x side window, padding with black where it runs off canvas."""
    out = Image.new("RGBA", (side, side), (*background, 255))
    out.alpha_composite(frame, dest=(max(0, -left), max(0, -top)),
                        source=(max(0, left), max(0, top)))
    return out


def flatten(im, mascot, dark_threshold=96, background=(0, 0, 0)):
    """
    Reduce every pixel to exactly one of: mascot colour, pure black, background.

    The source art carries a highlight, a mid tone, a shadow and white props -- and
    the blacksmith frame has 53 distinct colours from anti-aliasing baked into the
    200x200 export. Collapsing to a single colour is both the look we want and, as
    a side effect, the cleanest possible de-anti-aliasing: every blend pixel snaps
    to one side of the threshold instead of surviving as a halo.
    """
    out = im.copy()
    px = out.load()
    w, h = out.size
    for y in range(h):
        for x in range(w):
            c = px[x, y][:3]
            if c == background:
                continue                      # empty space stays empty
            px[x, y] = EYE if max(c) < dark_threshold else mascot
    return out


def vivify(im, threshold=96, sat_boost=1.4):
    """
    Drive each color to full brightness and deepen it, preserving hue.

    Two reasons, and they compound:

    * The panel over-drives low channel values, hardest on blue, so any real
      amount of blue turns a warm colour blue-violet -- #DD775B and this art's
      (216,112,80) both came out blue. Driving value to 1.0 is one way to squeeze
      blue out; zeroing it directly is the rule the palette follows now (see
      [[Panel Quirks]]).
    * Value alone turns (216,112,80) into a pale salmon (255,132,94). Boosting
      saturation as well lands it near (255,92,38) -- an actually vivid orange,
      which is the look we're after on an LED panel.

    Colors darker than `threshold` are left alone so eyes, outlines and shadows
    stay dark instead of blowing out to orange.
    """
    import colorsys

    out = im.copy()
    px = out.load()
    w, h = out.size
    cache = {}
    for y in range(h):
        for x in range(w):
            c = px[x, y]
            if c not in cache:
                if max(c) >= threshold:
                    hh, ss, _ = colorsys.rgb_to_hsv(*(v / 255 for v in c))
                    rr, gg, bb = colorsys.hsv_to_rgb(hh, min(1.0, ss * sat_boost), 1.0)
                    cache[c] = (round(rr * 255), round(gg * 255), round(bb * 255))
                else:
                    cache[c] = c
            px[x, y] = cache[c]
    return out


def content_bbox(frames):
    """Union bounding box of non-transparent, non-background content."""
    box = None
    for frame, _ in frames:
        alpha = frame.getchannel("A")
        b = alpha.getbbox()
        if b is None:
            continue
        box = b if box is None else (
            min(box[0], b[0]), min(box[1], b[1]),
            max(box[2], b[2]), max(box[3], b[3]),
        )
    return box


def squarify(box, size):
    """Expand a bbox to a padded square, clamped to the image."""
    l, t, r, b = box
    l, t = max(0, l - PAD), max(0, t - PAD)
    r, b = min(size[0], r + PAD), min(size[1], b + PAD)
    w, h = r - l, b - t
    side = max(w, h)
    cx, cy = l + w / 2, t + h / 2
    l = int(max(0, min(size[0] - side, cx - side / 2)))
    t = int(max(0, min(size[1] - side, cy - side / 2)))
    return (l, t, l + side, t + side)


def subsample(frames, limit):
    if len(frames) <= limit:
        return frames
    step = len(frames) / limit
    picked = []
    for i in range(limit):
        frame, duration = frames[int(i * step)]
        picked.append((frame, int(duration * step)))
    return picked


def pad_palette(frames):
    """Apply generate.pad_palette to every frame."""
    return [_pad(f) for f in frames]


def convert(src: Path, background=(0, 0, 0), mascot=MASCOT, window=None):
    frames = coalesce(src)

    box = content_bbox(frames)
    if box is None:
        raise SystemExit(f"{src}: no visible content")

    left, top, side = power_of_two_window(box, frames[0][0].size,
                                          (window,) if window else (128, 256))
    ratio = side // SIZE
    frames = subsample(frames, MAX_FRAMES)

    rgb, durations = [], []
    for frame, duration in frames:
        cropped = window_crop(frame, left, top, side, background)
        # Exact integer downscale: each output pixel is a whole ratio x ratio block.
        small = cropped.resize((SIZE, SIZE), Image.NEAREST)
        flat = Image.new("RGBA", (SIZE, SIZE), (*background, 255))
        flat = Image.alpha_composite(flat, small)
        rgb.append(flatten(flat.convert("RGB"), mascot, background=background))
        durations.append(duration)
    return pad_palette(rgb), durations, (side, ratio, box)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("source")
    ap.add_argument("state", help="idle | thinking | working | waiting | done")
    ap.add_argument("--preview", action="store_true", help="write a contact sheet too")
    ap.add_argument("--window", type=int, choices=(128, 256), default=None,
                    help="force the crop window instead of picking the smallest that fits")
    args = ap.parse_args()

    src = Path(args.source)
    frames, durations, box = convert(src, window=args.window)

    CUSTOM_DIR.mkdir(parents=True, exist_ok=True)
    out = CUSTOM_DIR / f"{args.state}.gif"
    frames[0].save(out, save_all=True, append_images=frames[1:],
                   duration=durations, loop=0, disposal=2)

    side, ratio, content = box
    colors = min(len(f.getcolors(maxcolors=1 << 20)) for f in frames)
    content_px = max(content[2] - content[0], content[3] - content[1])
    print(f"{src.name} -> {out}")
    print(f"  content {content_px}px -> {side}px window -> {SIZE}px ({ratio}:1 exact)")
    print(f"  {len(frames)} frames, {colors} colors, {out.stat().st_size} bytes")

    if args.preview:
        scale = 5
        sheet = Image.new("RGB", (len(frames) * SIZE * scale, SIZE * scale), (18, 18, 20))
        for i, f in enumerate(frames):
            sheet.paste(f.resize((SIZE * scale, SIZE * scale), Image.NEAREST), (i * SIZE * scale, 0))
        p = CUSTOM_DIR / f"{args.state}_preview.png"
        sheet.save(p)
        print(f"  preview -> {p}")


if __name__ == "__main__":
    main()
