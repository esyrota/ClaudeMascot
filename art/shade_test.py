"""
Test card for SHADE_SCALE candidates.

The card shows the mascot's silhouette three times side by side, each shaded at
a different candidate value. Leftmost is SHADE_SCALE=0.85. Photograph at brightness
30 and 100 and shoot video, not a still (the panel is scan-driven; art/read_panel_photo.py
averages frames).
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image

from panel_colour import panel_encode
from testcards import save_gif

OUT = Path(__file__).parent / "testcards"
SIZE = 32
MASCOT = (255, 68, 0)

CANDIDATES = [0.85, 0.75, 0.65]


def make_shade_test() -> Image.Image:
    """Build a 32x32 image with three sections side by side showing different
    shade candidates. Each section has a body block and a shade block."""
    im = Image.new("RGB", (SIZE, SIZE), (0, 0, 0))
    px = im.load()

    # Layout: three 10px-wide sections with 1px gutters between them
    # x ranges: [0-9], [11-20], [22-31]
    # Each section: 6px body + 4px shade
    # y range: [6-25] for the 20px block (6px top/bottom padding)

    for section_idx, candidate in enumerate(CANDIDATES):
        section_x = section_idx * 11  # 0, 11, 22

        # Compute the shade color
        shade_rgb = tuple(round(c * candidate) for c in MASCOT)

        # Encode both colors through panel_encode
        body_encoded = panel_encode(MASCOT)
        shade_encoded = panel_encode(shade_rgb)

        # Draw body block (6px wide, 20px tall)
        for y in range(6, 26):  # 6-25 inclusive = 20px
            for x in range(section_x, section_x + 6):
                px[x, y] = body_encoded

        # Draw shade block (4px wide, 20px tall)
        for y in range(6, 26):  # 6-25 inclusive = 20px
            for x in range(section_x + 6, section_x + 10):
                px[x, y] = shade_encoded

    return im


if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    im = make_shade_test()
    save_gif(im, OUT / "shade-test.gif")
    print(f"Wrote {OUT / 'shade-test.gif'}")
