"""
Colour test card for the iDotMatrix panel.

Sends four known, fully-saturated quadrants with NO channel juggling at all.
Photograph the panel and the mapping falls out directly:

    top-left     RED    (255,   0,   0)
    top-right    GREEN  (  0, 255,   0)
    bottom-left  BLUE   (  0,   0, 255)
    bottom-right WHITE  (255, 255, 255)   <- orientation anchor

Whatever colour each quadrant actually shows tells us the panel's real channel
permutation, instead of inferring it from a photo of a mid-tone like #DD775B.

    python mascot/testcard.py
"""

from pathlib import Path

from PIL import Image, ImageDraw

OUT = Path(__file__).parent
SIZE = 32
H = SIZE // 2

QUADRANTS = [
    ((0, 0), (255, 0, 0), "top-left     RED"),
    ((H, 0), (0, 255, 0), "top-right    GREEN"),
    ((0, H), (0, 0, 255), "bottom-left  BLUE"),
    ((H, H), (255, 255, 255), "bottom-right WHITE"),
]


def build() -> Image.Image:
    im = Image.new("RGB", (SIZE, SIZE), (0, 0, 0))
    d = ImageDraw.Draw(im)
    for (x, y), color, _ in QUADRANTS:
        d.rectangle([x, y, x + H - 1, y + H - 1], fill=color)
    # A one-pixel black cross keeps the quadrant edges legible on the panel.
    d.line([H - 1, 0, H - 1, SIZE], fill=(0, 0, 0))
    d.line([0, H - 1, SIZE, H - 1], fill=(0, 0, 0))
    return im


if __name__ == "__main__":
    im = build()
    path = OUT / "testcard.gif"
    # Two identical frames: the device's GIF path expects an animation.
    im.save(path, save_all=True, append_images=[im], duration=[500, 500], loop=0)
    print(f"wrote {path}")
    for _, color, label in QUADRANTS:
        print(f"  {label:22s} sent as RGB{color}")
