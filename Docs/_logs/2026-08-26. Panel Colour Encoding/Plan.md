# Panel Colour Encoding — Implementation Plan

**Source:** [[_logs/2026-08-26. Panel Colour Encoding/Task]]
**Touches:** [[Art Pipeline]], [[Animation Catalogue]], [[Panel Quirks]], [[BLE Protocol]]

## Scope

1. `panel_encode()` and `panel_preview()` in `art/generate.py`, with the constant sourced
   in one place rather than copied from `art/testcards.py`.
2. Every authored colour in `generate.py` passing through the encode at the point it is
   written, so the module's constants read as ordinary display colours.
3. `SHADE_SCALE` restated in display terms, with three candidates carried into a
   hardware test clip and the winner chosen from a video.
4. `MIN_COLORS` padding re-examined against the encoded palette and either justified,
   changed, or removed — with the reason recorded.
5. Full art regeneration, golden fixtures regenerated in the same run, catalogue images
   refreshed through `panel_preview()`.

## Architecture decisions

- **Encode at the point of writing, not at the point of drawing.** The drawing code keeps
  passing named constants around; the conversion happens once, where pixels become file
  bytes. Encoding inside `mascot()` and its callers would mean every helper had to know
  whether its input was display or panel space, and a single missed call site would be an
  invisible one-clip colour bug.
- **One source for the constant.** `art/testcards.py` already defines `PANEL_GAMMA` and a
  working `panel_encode()`. The cards and the generator must never drift, so the
  definition moves into a module both import — a two-function `art/panel_colour.py` — and
  `testcards.py` imports it rather than keeping its copy.
- **`panel_preview()` is the inverse, not a second fit.** `display = 255·(v/255)^(1/2.96)`.
  Deriving it from the same constant is what keeps the catalogue honest when the constant
  is retuned.
- **The hardware gate carries candidates, not a single guess.** The shade choice is the
  one judgement the arithmetic cannot make, so the test clip shows 0.85 / 0.75 / 0.65 side
  by side. A second photograph to re-decide is far more expensive than three swatches in
  the first one.
- **Blue stays out.** `panel_encode` of a zero is zero, so `B = 0` survives the transform
  untouched. **Correction to the task's premise:** `pad_palette()` no longer nudges blue —
  it already moved to nudging *red* downward (247–254), for exactly the reason the curve
  now confirms, and its docstring says so. So chunk 5 is not "stop using blue"; it is
  "does the padding still do anything once colours are encoded, and do its values stay
  distinct through the transform".
- **Pad first, encode second.** `pad_palette()` and `body_pixel_count()` compare pixels
  against `MASCOT` **by exact equality**. Encoding before they run would break both
  silently. The order inside `save()` is: pad in display space, then encode, then write.

## Integration seams

Colour does not stay in `generate.py`. Every site below reads or reproduces a palette
value and must be checked in the chunk that touches it:

| Seam | Who else depends on it |
|---|---|
| `MASCOT` / `MASCOT_DARK` | `_typing_recolour()` and `_shade_of()` classify *imported* art into these constants by threshold — the thresholds are compared against **source** pixel values and must NOT be encoded |
| `PROP` / `LAPTOP_GREY` | same import path; `LAPTOP_GREY` ships knowing it renders blue |
| `BG = (0,0,0)` | encodes to itself; the black-background contract is unaffected |
| `Tests/Fixtures/` | every GIF's bytes move → `export_golden.py` is mandatory, same run |
| `Docs/Specs/Animation Catalogue.md` | 39 images regenerate; with `panel_preview()` they change meaning as well as content |
| `art/make_icon.py` | reads `art/sources/logo.gif`, not these constants — unaffected, confirm only |

**The threshold constants are the trap.** `TYPING_BODY_MIN = 252`, `TYPING_LOGO_MIN = 200`,
`TYPING_DARK = 40`, `TYPING_CHROMA_MIN = 64`, `SHADED_BODY_MIN`, `BODY_MIN` all compare
against pixels in the *hand-drawn sources*, which are authored in display space and never
pass through the panel. Encoding them would silently reclassify the seated pose.

## File map

| File | Change |
|---|---|
| `art/panel_colour.py` | **NEW** — `PANEL_GAMMA`, `panel_encode()`, `panel_preview()`, with the measurement's provenance in the docstring |
| `art/generate.py` | constants restated in display terms; encode applied where pixels are written; `SHADE_SCALE` semantics changed |
| `art/testcards.py` | imports from `panel_colour`, drops its local copy |
| `art/export_docs.py` | renders catalogue images through `panel_preview()` |
| `art/shade_test.py` | **NEW** — the three-candidate verification clip |
| `Docs/Specs/Art Pipeline.md` | style rules rewritten: colours are authored in display terms |
| `Docs/Specs/Animation Catalogue.md` | images regenerate; the preview's meaning is stated once |
| `Sources/ClaudeMascot/Resources/Animations/*` | regenerated |
| `Tests/Fixtures/*` | regenerated |

## Chunks

**1 — Specs first.** Rewrite [[Art Pipeline]]'s *Style rules* around authoring in display
terms: what `panel_encode` is, that constants are now display colours, that the import
thresholds are deliberately exempt, and that `SHADE_SCALE` is a display ratio pending the
photograph. Add the one-line statement to [[Animation Catalogue]] that its images are
`panel_preview()` predictions, not file contents. Prose only — no Python.
**Verify:** the two pages read correctly and every claim traces to [[Panel Quirks]] or
[[Findings]]; no numbers invented here.

**2 — `art/panel_colour.py`.** The new module: `PANEL_GAMMA = 2.96`, `panel_encode()`,
`panel_preview()`, docstring naming the measurement and its log. Repoint `testcards.py`
at it and delete its local copy.
**Verify:** `venv/bin/python -c "from art.panel_colour import *"` round-trips —
`panel_preview(panel_encode(v)) ≈ v` for v in 0…255 within 1 — and
`venv/bin/python art/testcards.py` writes byte-identical cards to the committed ones.

**3 — Encode at the write path.** Apply the encode where `generate.py` turns pixels into
saved files, leaving drawing code untouched. Restate `MASCOT`, `PROP`, `LAPTOP_GREY` as
display colours. **Leave every `*_MIN` threshold alone** and add a comment at each saying
why.
**Verify:** regenerate one drawn clip (`idle`) and one imported clip (`working`); assert
`idle`'s body pixels are the encoded value, and that `working`'s recolour still classifies
into exactly the same four families it does today (compare the *set* of colours, not the
values).

**4 — `SHADE_SCALE` in display terms + the candidate clip.** Restate the constant as a
display ratio, default 0.85 (today's appearance). Add `art/shade_test.py`: a 32×32 clip
showing the mascot silhouette three times, shaded at 0.85 / 0.75 / 0.65, labelled by
position, written to `art/testcards/shade-test.gif`.
**Verify:** the clip's three shade regions carry three distinct encoded values; typecheck
the module by running it.

**5 — `MIN_COLORS` decision.** Measure rather than assume. Two questions: (a) how many
distinct colours does each clip carry *after* encoding and before padding, and (b) do
`pad_palette`'s red nudges (247–254) survive the encode as distinct palette entries, or
do some collapse onto each other? Encoding compresses the top of the range —
`encode(255)=255`, `encode(254)≈252`, `encode(253)≈249` — so they should stay distinct at
roughly 3× the spacing, but that is a prediction to check, not an assumption. Decide keep
/ shrink / drop and write the reason into [[Art Pipeline]] and [[Panel Quirks]]'s
*Palette* section.
**Verify:** every generated GIF still lands on a ≥16-entry palette (or the decision is
recorded with the count that justifies it).

**6 — HARDWARE GATE. Stop here.** Regenerate everything, then put `shade-test.gif` and one
re-encoded clip on the panel via the menu bar's **Send Test Image…**, at brightness 30 and
100. **Shoot video, not stills** — the panel is scan-driven and a still catches one
arbitrary phase; `art/read_panel_photo.py` averages frames. Read the result back and pick
the shade. **Do not proceed on a preview alone**: the previews are supposed to look wrong.
**Verify:** a chosen `SHADE_SCALE` with a video behind it, recorded in [[Findings]].

**7 — Final verification.** With the shade set: `venv/bin/python art/generate.py`, then
`art/export_golden.py` (mandatory — the GIFs are `GifPacketizerTests`' inputs), then
`art/export_docs.py`. Then `swift build` warning-free and `swift test` green (112 tests).
Confirm `art/make_icon.py` is unaffected. Update [[Home]]'s art row.
**Verify:** all four commands clean, 112/112, and `git status` shows exactly the expected
set — 39 animations, `clips.json`, `preview.png`, the fixtures, and the catalogue images.

## Out of scope

- The status overlay and its layering — planned separately once this lands.
- White-balance correction; greys still render blue and `LAPTOP_GREY` ships that way.
- The `B = 0` vs `B = 4` anomaly, and the unmeasured mixture/current-limiting behaviour.
