"""
Build the app's .icns from art/sources/logo.gif.

The logo is the mascot as a 32x32 silhouette with its eyes knocked out as
transparency, drawn 1.5x the size of the on-panel geometry. It sits on a dark rounded
plate, which is doing real work rather than decoration: the mascot's own colour is the
only colour in the artwork, so without a ground the icon would be a floating shape
that vanishes against a light Finder background.

Scaling honours the art rather than the canvas. At 128px and up the mascot is blown up
by a whole number of pixels with NEAREST, so its edges stay square; at 64px and below
a 32px-wide figure has more detail than the icon can hold, so it is filtered down
instead and the softness is the point.

    python art/make_icon.py     # writes Sources/ClaudeMascot/Resources/AppIcon.icns
"""

import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "art" / "sources" / "logo.gif"
OUT = ROOT / "Sources" / "ClaudeMascot" / "Resources" / "AppIcon.icns"

PLATE = (28, 28, 32)        # near-black, but not black: the panel, powered down
MASCOT = (215, 118, 87)     # the logo's own terracotta, flattened from its few AA pixels
GLYPH = 0.75                # fraction of the icon the mascot spans
RADIUS = 0.22               # corner radius as a fraction of the icon, macOS-ish
SUPERSAMPLE = 4             # the plate is a curve, so it is drawn big and filtered down

# Every size `iconutil` wants, as (pixels, [iconset names]).
SIZES = [
    (16, ["icon_16x16.png"]),
    (32, ["icon_16x16@2x.png", "icon_32x32.png"]),
    (64, ["icon_32x32@2x.png"]),
    (128, ["icon_128x128.png"]),
    (256, ["icon_128x128@2x.png", "icon_256x256.png"]),
    (512, ["icon_256x256@2x.png", "icon_512x512.png"]),
    (1024, ["icon_512x512@2x.png"]),
]


def mascot_art() -> Image.Image:
    """The logo as flat MASCOT-on-transparent, cropped to the figure and centred."""
    src = Image.open(SRC).convert("RGBA")
    art = Image.new("RGBA", src.size, (0, 0, 0, 0))
    px, out = src.load(), art.load()
    for y in range(src.size[1]):
        for x in range(src.size[0]):
            if px[x, y][3]:
                out[x, y] = (*MASCOT, 255)
    # The figure is drawn standing on the bottom edge; an icon wants it centred.
    return art.crop(art.getbbox())


def plate(size: int) -> Image.Image:
    big = size * SUPERSAMPLE
    im = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    ImageDraw.Draw(im).rounded_rectangle(
        [0, 0, big - 1, big - 1], radius=int(big * RADIUS), fill=(*PLATE, 255))
    return im.resize((size, size), Image.LANCZOS)


def icon(size: int, art: Image.Image) -> Image.Image:
    aw, ah = art.size
    if size >= 128:
        # Whole-pixel blow-up: the figure keeps hard square edges.
        scale = max(1, int(size * GLYPH) // aw)
        glyph = art.resize((aw * scale, ah * scale), Image.NEAREST)
    else:
        width = max(1, round(size * GLYPH))
        glyph = art.resize((width, max(1, round(ah * width / aw))), Image.LANCZOS)

    im = plate(size)
    im.alpha_composite(glyph, dest=((size - glyph.size[0]) // 2,
                                    (size - glyph.size[1]) // 2))
    return im


if __name__ == "__main__":
    if shutil.which("iconutil") is None:
        raise SystemExit("iconutil not found -- .icns can only be built on macOS")

    art = mascot_art()
    with tempfile.TemporaryDirectory() as tmp:
        iconset = Path(tmp) / "AppIcon.iconset"
        iconset.mkdir()
        for size, names in SIZES:
            im = icon(size, art)
            for name in names:
                im.save(iconset / name)
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(OUT)], check=True)

    print(f"{SRC.name} {art.size[0]}x{art.size[1]} -> {OUT.name}  "
          f"{len(SIZES)} sizes, {OUT.stat().st_size} bytes")
