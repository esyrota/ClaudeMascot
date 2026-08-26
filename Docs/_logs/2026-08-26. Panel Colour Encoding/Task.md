# Panel Colour Encoding

Author the art in ordinary display colours and let the pipeline convert them to what the
panel needs, so the mascot on the panel looks like the mascot in the preview.

## Why now

The panel's tone curve was measured on 2026-08-26 — see
[[Findings]] and [[Panel Quirks]]. It is roughly three times more compressive than a
display's: an authored `8` already reaches 42% of full brightness, and everything above
`96` lands within 20% of maximum. Every colour surprise in this project's history is that
one fact:

- `MASCOT`'s green of 68 sits at ~72% of full green rather than a quarter of it, which is
  why the body photographs pink rather than orange.
- Shades vanished, and `SHADE_SCALE = 0.60` was found by bisecting three photographs. The
  curve reproduces all three of those photographs arithmetically.
- Tonal steps got crushed, which is what made half-tones look like a hardware limit rather
  than the artistic choice they actually were.

The correction is one function, and it has already survived a card built to falsify it
(`e-gamma.gif`, at brightness 30 and 100). It also buys back *range*, and buys more of it
the dimmer the panel runs: at brightness 30 the naive grey ladder spans 51 luma where the
encoded one keeps 115.

## Decisions reached

- **`panel_encode()` moves into `art/generate.py`** and every authored colour goes through
  it: `panel_value = 255 · (display_value/255) ^ 2.96`. A working implementation and the
  constant already exist in `art/testcards.py`.
- **Colours are authored in display terms from now on.** `MASCOT` stays `(255,68,0)` as
  *written*; what reaches the GIF is roughly `(255,5,0)`. The previews will look alarming
  and the panel will look right — that inversion is the whole point.
- **`SHADE_SCALE` is chosen from a photograph, not restated.** It stops being a
  panel-value ratio and becomes a display-space one, which changes what the number means:
  today's 0.60 is ≈0.85 in display terms. Three candidates (0.85, 0.75, 0.65) ship in the
  verification clip and the winner is picked from the video. This is now a choice between
  known appearances rather than a blind bisection.
- **`panel_preview()` — the inverse — lands in the same change**, so
  [[Animation Catalogue]] can show predicted on-panel appearance. This is the dependency
  [[Docs GIFs as the Art Source]] has been waiting on.
- **`MIN_COLORS = 9` padding is re-examined, not assumed.** It pads the palette by nudging
  blue by 1–8 on body pixels; the measured curve says a small blue is never free here, and
  the encode may make the padding unnecessary or actively harmful.
- **One clip is photographed before the catalogue follows.** Via the menu bar's
  **Send Test Image…**, and as **video, not a still** — the panel is scan-driven (9.5%
  per-pixel variation against a monitor's 2.9%), and `art/read_panel_photo.py` averages
  video frames for exactly this reason.
- **Specs first**, per CLAUDE.md: [[Art Pipeline]]'s style rules are rewritten before any
  Python changes.

## Out of scope

- **The status overlay and its layering.** Settled in design (overlay behind, mascot in
  front, real authored alpha, own GIF writer, 1px rail on row 0) and planned separately
  once this lands — the encode may retire the `MIN_COLORS` padding and change the palette
  policy both pieces share, so planning it first would bake in assumptions.
- **White-balance correction.** Greys will still render blue after this change; that is a
  channel-balance effect, not a tone-curve one, and the mixture behaviour it depends on is
  unmeasured (pure red at 255 photographs R=232, but the red inside white photographs 131,
  which looks like current limiting). `LAPTOP_GREY` ships blue by prior decision anyway.
- **The `B = 0` vs `B = 4` anomaly.** Still unexplained. The encode must not quietly
  reintroduce small blue values on the strength of a curve that does not predict it.

## Specs

- [[Art Pipeline]] — style rules, the encode, and the preview
- [[Animation Catalogue]] — every image regenerates
- [[Panel Quirks]] — the measured curve this implements
- [[BLE Protocol]] — golden fixtures are regenerated, framing is untouched
