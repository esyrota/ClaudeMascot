"""
Colour-characterisation test cards for the iDotMatrix panel.

`testcard.py` answers one question — the channel permutation — with four
saturated quadrants. These four cards answer the questions left open by
`Docs/_tasks/Recheck the Panel Colour Rule.md`:

    A  ramps      per-channel transfer curve, densest at the dark end
    B  halftones  can the panel hold a dither, or does it smear?
    C  thin       is a 1px line legible, and how far does a lit pixel bloom?
    D  hues       the unexplained pink, and the specific colours the docs claim

Each card is a 32x32 two-frame GIF (the panel's GIF path expects an
animation). `reference.html` renders all four at 12x on screen: hold the panel
beside the monitor and photograph both in one frame, so whatever the camera
does to colour it does to the reference too. That relative comparison is the
only trustworthy reading — see Docs/Reference/Panel Quirks.md.

    venv/bin/python art/testcards.py        # writes art/testcards/

Send a card with the app's menu bar → "Send Test Image…"; nothing else can
talk to the panel (the Python daemon in legacy/ is retired).
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image

OUT = Path(__file__).parent / "testcards"
SIZE = 32

# The art's own colours, so the halftone card asks the question that matters:
# whether the *mascot* palette can carry a dither.
MASCOT = (255, 68, 0)
MASCOT_DARK = (153, 41, 0)  # MASCOT * SHADE_SCALE (0.60), as generate.py ships it

# Dense at the bottom: the whole claim on Panel Quirks is that the panel
# over-drives low values, so that is where the samples belong.
RAMP_STEPS = [0, 8, 16, 32, 64, 96, 160, 255]

# Card C / D palettes, kept as (name, rgb) so reference.html can label them.
THIN_COLOURS = [
    ("white", (255, 255, 255)),
    ("red", (255, 0, 0)),
    ("green", (0, 255, 0)),
    ("mascot", MASCOT),
    ("amber", (255, 180, 0)),
    ("dim green", (0, 96, 0)),
    ("dim red", (96, 0, 0)),
    ("blue", (0, 0, 255)),
]

HUE_SWEEP = [
    ("h0", (255, 0, 0)),
    ("h15", (255, 64, 0)),
    ("h20", (255, 85, 0)),
    ("h30", (255, 128, 0)),
    ("h40", (255, 170, 0)),
    ("h50", (255, 213, 0)),
    ("h60", (255, 255, 0)),
    ("h90", (128, 255, 0)),
]

CLAIMED = [
    ("mascot B=0", (255, 68, 0)),
    ("mascot B=4", (255, 68, 4)),
    ("mascot dark", MASCOT_DARK),
    ("laptop grey", (134, 134, 134)),
    ("mid grey", (64, 64, 64)),
    ("white", (255, 255, 255)),
    ("prop red", (255, 0, 0)),
    ("prop green", (0, 255, 0)),
]


def _blank() -> Image.Image:
    return Image.new("RGB", (SIZE, SIZE), (0, 0, 0))


def _fill(im: Image.Image, x0: int, y0: int, x1: int, y1: int, rgb) -> None:
    """Inclusive rectangle fill, written pixel-wise so nothing is left to a
    draw library's edge conventions."""
    px = im.load()
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            px[x, y] = rgb


def card_a_ramps() -> Image.Image:
    """Four 8-row bands (R, G, B, grey), each eight 4px steps, dark to bright
    left to right. The 2x2 white block at top-left sits inside the value-0
    patch, where it costs no sample, and fixes the orientation of the photo."""
    im = _blank()
    bands = [
        lambda v: (v, 0, 0),
        lambda v: (0, v, 0),
        lambda v: (0, 0, v),
        lambda v: (v, v, v),
    ]
    for row, make in enumerate(bands):
        for col, v in enumerate(RAMP_STEPS):
            _fill(im, col * 4, row * 8, col * 4 + 3, row * 8 + 7, make(v))
    _fill(im, 0, 0, 1, 1, (255, 255, 255))
    return im


def card_b_halftones() -> Image.Image:
    """Dithers against the solids they should average to. If the panel holds
    them, half-tone pixel art is available and the art's one-flat-colour rule
    is an artistic choice rather than a hardware limit."""
    im = _blank()
    px = im.load()

    def checker(y0: int, y1: int, a, b, cell: int) -> None:
        for y in range(y0, y1 + 1):
            for x in range(SIZE):
                px[x, y] = a if ((x // cell) + (y // cell)) % 2 == 0 else b

    checker(0, 5, MASCOT, MASCOT_DARK, 1)  # 1px, two body tones
    checker(6, 11, MASCOT, (0, 0, 0), 1)  # 1px, body against unlit
    checker(12, 17, MASCOT, MASCOT_DARK, 2)  # 2px, same two tones
    # An eight-step blend between the two tones: how many are distinguishable?
    for col in range(8):
        t = col / 7
        blend = tuple(round(MASCOT[i] + (MASCOT_DARK[i] - MASCOT[i]) * t) for i in range(3))
        _fill(im, col * 4, 18, col * 4 + 3, 23, blend)
    _fill(im, 0, 24, SIZE - 1, 27, MASCOT)  # the solids the dithers sit against
    _fill(im, 0, 28, SIZE - 1, 31, MASCOT_DARK)
    return im


def card_c_thin() -> Image.Image:
    """1px lines both ways, then isolated pixels beside 2x2 blocks of the same
    colour. The block/pixel pair is the bloom measurement: if a single lit
    pixel photographs as bright as four, the panel is spreading light and a
    1px rail will not read as one row."""
    im = _blank()
    px = im.load()
    for i, (_, rgb) in enumerate(THIN_COLOURS):
        y = i * 2  # rows 0..14, every other row lit
        for x in range(SIZE):
            px[x, y] = rgb
    for i, (_, rgb) in enumerate(THIN_COLOURS):
        x = i * 2  # columns 0..14, bottom half only
        for y in range(16, SIZE):
            px[x, y] = rgb
    for i, (_, rgb) in enumerate(THIN_COLOURS[:4]):
        x = 18 + i * 3
        px[x, 18] = rgb  # single pixel
        _fill(im, x, 22, x + 1, 23, rgb)  # 2x2 of the same colour
        _fill(im, x, 27, x + 1, 30, rgb)  # 2x4, one more step of area
    return im


def card_d_hues() -> Image.Image:
    """Top: a saturated sweep from red to chartreuse, to find where the body
    colour actually lands. Bottom: the exact colours Panel Quirks makes claims
    about, so each claim is confirmed or killed by one photograph."""
    im = _blank()
    for col, (_, rgb) in enumerate(HUE_SWEEP):
        _fill(im, col * 4, 0, col * 4 + 3, 15, rgb)
    for col, (_, rgb) in enumerate(CLAIMED):
        _fill(im, col * 4, 16, col * 4 + 3, 31, rgb)
    return im


# Measured 2026-08-26 from IMG_2777: the panel's tone curve is roughly three
# times more compressive than a display's under the same camera (exponent 0.24
# against 0.71). PANEL_GAMMA is the ratio; card E exists to falsify it.
PANEL_GAMMA = 2.96


def panel_encode(rgb, gamma: float = PANEL_GAMMA):
    """Map a colour authored in ordinary display terms to the value the panel
    needs to *show* that colour. Pure hypothesis until card E is photographed."""
    return tuple(round(255 * (c / 255) ** gamma) for c in rgb)


def card_e_gamma() -> Image.Image:
    """The falsification test for `panel_encode`. Two pairs of eight-step
    ladders, encoded above naive:

        rows  0-7   grey, gamma-encoded   -> should photograph as an even ramp
        rows  8-15  grey, naive           -> should photograph bunched bright
        rows 16-23  mascot hue, encoded   -> the shade ladder we would ship
        rows 24-31  mascot hue, naive     -> today's ladder, the control

    If the encoded bands are even and the naive ones are not, the model holds
    and `SHADE_SCALE` becomes arithmetic instead of bisection. If both look the
    same, the model is wrong and nothing has been built on it yet."""
    im = _blank()
    fractions = [(i + 1) / 8 for i in range(8)]
    ladders = [
        [panel_encode((round(255 * f),) * 3) for f in fractions],
        [(round(255 * f),) * 3 for f in fractions],
        [panel_encode(tuple(round(c * f) for c in MASCOT)) for f in fractions],
        [tuple(round(c * f) for c in MASCOT) for f in fractions],
    ]
    for row, ladder in enumerate(ladders):
        for col, rgb in enumerate(ladder):
            _fill(im, col * 4, row * 8, col * 4 + 3, row * 8 + 7, rgb)
    return im


CARDS = [
    ("a-ramps", card_a_ramps, "per-channel transfer curve (R, G, B, grey; dark → bright)"),
    ("b-halftones", card_b_halftones, "1px and 2px dithers against the solids they average to"),
    ("c-thin", card_c_thin, "1px lines, isolated pixels vs 2x2 and 2x4 blocks (bloom)"),
    ("d-hues", card_d_hues, "saturated hue sweep, and the colours Panel Quirks claims"),
    ("e-gamma", card_e_gamma, "gamma-encoded ladders above naive ones — the model's falsification test"),
]


def save_gif(im: Image.Image, path: Path) -> None:
    """Two identical frames, no `optimize`. Optimising re-quantises the
    palette — the one thing a colour test card must not let happen."""
    quantised = im.convert("P", palette=Image.ADAPTIVE, colors=256)
    if quantised.convert("RGB").tobytes() != im.tobytes():
        raise SystemExit(f"{path.name}: quantisation changed a pixel; card is not measurable")
    quantised.save(path, save_all=True, append_images=[quantised], duration=[500, 500], loop=0)


def reference_html(path: Path) -> None:
    """The on-screen half of the measurement. Same pixels, 12x, side by side,
    with every authored value printed beside its card."""
    cells = []
    for name, build, caption in CARDS:
        im = build()
        px = im.load()
        rows = "".join(
            "".join(
                f'<i style="background:rgb{px[x, y]}"></i>' for x in range(SIZE)
            )
            for y in range(SIZE)
        )
        cells.append(
            f'<figure><figcaption><b>{name}</b><br>{caption}</figcaption>'
            f'<div class="card">{rows}</div></figure>'
        )
    legend = "<br>".join(
        f"{label}: rgb{rgb}" for label, rgb in (
            [("ramp steps", tuple(RAMP_STEPS))] + CLAIMED
        )
    )
    path.write_text(
        "<!doctype html><meta charset=utf-8><title>panel test cards</title>"
        "<style>"
        "body{background:#000;color:#bbb;font:13px/1.5 -apple-system,sans-serif;margin:24px}"
        "main{display:flex;gap:24px;flex-wrap:wrap}"
        "figure{margin:0}figcaption{margin-bottom:8px;max-width:384px}"
        ".card{width:384px;height:384px;display:grid;"
        "grid-template-columns:repeat(32,12px);grid-template-rows:repeat(32,12px)}"
        "i{display:block}"
        "footer{margin-top:24px;color:#777}"
        "</style>"
        f"<main>{''.join(cells)}</main><footer>{legend}</footer>",
        encoding="utf-8",
    )


def main() -> None:
    OUT.mkdir(exist_ok=True)
    for name, build, _ in CARDS:
        path = OUT / f"{name}.gif"
        save_gif(build(), path)
        print(f"wrote {path}")
    reference_html(OUT / "reference.html")
    print(f"wrote {OUT / 'reference.html'}")


if __name__ == "__main__":
    main()
