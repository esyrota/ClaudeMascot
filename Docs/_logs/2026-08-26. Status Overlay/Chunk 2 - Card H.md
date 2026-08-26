---
model: Haiku
estimated_time: 2
estimated_tools: 8
estimated_tokens: 35000
estimated_risk: low
actual_tokens: 132000
actual_tools: 29
actual_time: 4
outcome: success
---

# Chunk 2 — Card H: white and the ramp candidates

## Task

Add one more characterisation card to `art/testcards.py`, following the seven already there
exactly. The card is shot on the panel in chunk 5 and is what the status rail's four colours get
chosen from. It must show, in one frame beside the on-screen reference: a solid white swatch,
three warm-white candidates for the clock marker, and green/amber/red ramp candidates for the
fill — the ramp candidates drawn **as 1px rows**, because a 1px row is the geometry the rail
actually renders and a solid block would measure something else.

## Required reading (in order)

1. `art/testcards.py` — read the whole file (323 lines). `card_c_thin()` is your model for 1px
   rows; `card_g_body()` for a swatch-and-candidates layout; `CARDS`, `save_gif()`,
   `reference_html()` and `main()` at the bottom are the registration points.
2. `art/panel_colour.py` — 75 lines; `panel_encode()` exists but is **not** used to pick these
   colours (see Constraints).
3. `Docs/Reference/Panel Quirks.md` — read the sections **"Mixtures: the floor…"** and
   **"1px features are legible"**. These give you the floor rule and the contrast numbers.

## Deliverable

`art/testcards.py` only. Add:

- `card_h_overlay() -> Image.Image` — the card. Include, each in its own clearly separated band:
  - a solid white swatch `(255,255,255)` — the reference for "is white actually white here"
  - three warm-white candidates, e.g. progressively less blue, each ending well clear of the floor
  - the three ramp candidates (a green, an amber, a red) each drawn as a **1px row**
  - **both marker cases the rail renders**: a single warm-white pixel sitting on unlit
    background, and a single *unlit* pixel punched into the middle of each 1px ramp row
- an entry in `CARDS` with id `h-overlay`, following the existing tuple shape exactly
- landmarks for `read_panel_photo.py --card` in whatever form the other cards provide them
- inclusion in `reference.html` through the existing `reference_html()` path — do not special-case it

## Constraints

- **No channel in 1–7, on any colour on this card.** Beside a saturated channel, anything under
  ~8 contributes nothing (the measured mixture floor). Clamp to 0 or to 8 or above.
- **Warm colours end in `B = 0`.** Blue beside a saturated red drives the result magenta. The
  warm-white candidates are the *only* place blue is allowed above 0, and that is the point of
  measuring them.
- **Do not use `panel_encode()` to choose any colour on this card.** It describes brightness, not
  hue; applying it to colour choice is the mistake that shipped a red mascot. Colours here are
  candidates to be photographed, chosen by hand.
- **Add an assertion in the module** that every colour the card uses has no channel in 1–7, so a
  future edit cannot quietly reintroduce one.
- Follow the file's existing conventions: 4-space indent, the same docstring voice, the same
  `_fill()` / `_blank()` helpers. Do not reformat anything you did not write.
- **One Write or one MultiEdit on `art/testcards.py`. Hard rule.**
- Do NOT modify any file other than `art/testcards.py`.
- Do NOT run any git command.

## Verify before reporting

Run these and report the output:

```
venv/bin/python art/testcards.py
ls -l art/testcards/
```

- `art/testcards/h-overlay.gif` (or whatever name the existing convention produces) is written.
- `reference.html` is regenerated and mentions the new card.
- The floor assertion passes.
- Report the exact list of colours you chose, as RGB triples, in your Run Report — the next
  hardware gate needs them written down.

## When done

Return your Run Report as your final message. Do NOT write it to a file, do NOT modify this brief.

```
# Chunk 2 — Card H — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, MultiEdit=N, Bash=N, ...
- Edit-per-file count: art/testcards.py: N edits
- Colours placed on the card: <every RGB triple, labelled>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
