# Status Overlay

Put something other than the mascot on the panel — starting with a bar for the 5-hour
usage window — by compositing a layer *behind* the animation.

**Designed 2026-08-26, not built. No longer blocked** — [[Panel Colour Encoding]] landed
(and withdrew its own central idea; read its [[Analysis]] before trusting any colour
formula). The palette policy this shares with the mascot art is settled: `MIN_COLORS = 9`
padding stays, nudging red downward, and colours are chosen from photographs.

## The hardware precondition is met

Overlay legibility was the one thing that could have killed this outright, and it was
measured: a lit 1px line against the unlit row beside it reads at **4.2× to 13.7×**
contrast, gap rows at luma 7–22. The panel resolves single rows cleanly and does not smear
them — see [[Panel Quirks]] and [[Findings]].

## What the colour work settled, and what it means here

The 2026-08-26 colour run ([[Analysis]], [[Panel Quirks]]) was a prerequisite for this
task. Five things it produced change how the rail must be built:

- **No channel below 8.** Beside a saturated channel, anything under ~8 contributes
  nothing — the mixture floor that explains the old `B = 4` anomaly. **The rail's colour
  ramp must never generate a channel in 1–7**; clamp to 0 or to 8. A ramp computed by
  naive interpolation between two colours will land there constantly.
- **Colours come from the mixture table, formulas do not.** `panel_encode()` describes
  *brightness*, not hue, and applying it to art produced a red mascot. For the rail: use it
  for a **fill that fades or grows in brightness**, never to pick the ramp's colours.
  Those get measured, like `MASCOT` was.
- **Blue stays 0 in warm colours**, now for a measured reason: blue 24 beside a saturated
  red sends B/R past 0.8 and the result goes magenta. An amber or red rail with any blue in
  it will read pink.
- **1px is legible** — 4.2× to 13.7× contrast against the unlit row beside it, gap rows at
  luma 7–22. The row-0 rail works. This was the task's one hardware precondition.
- **The panel is scan-driven.** Verify the rail from **video**, never a still:
  per-pixel variation is 9.5% of level and moving banding 7.2%, invisible to the eye and
  ruinous to a single row in a photograph. `art/read_panel_photo.py` averages video frames.

**One open item that lands on this task directly:** `PROP` white `(255,255,255)` was
photographed at `(63,66,82)` — dim, and blue. That reading came from 2px sleep bubbles, so
bloom and size are mixed into it, but a white rail or a white marker pixel is likely to
read dim blue rather than white. **Measure a white swatch before choosing the pace
marker's colour**; a warm white will probably be needed. `art/testcards.py` is where that
card goes.

## Decisions reached

- **The overlay is the back layer; the mascot is drawn on top of it.** Not the other way
  round. The rail changes a few times an hour and the animation changes constantly, so the
  animation is what should occlude. Confetti crossing the bar is fine and self-correcting.
- **Alpha is authored, never inferred.** Colour-keying black fails on the eyes, on the
  flag, and on any black region that touches the canvas edge in one frame of a wave and
  not the next — measured: `done-flag` carries up to 22 enclosed black pixels per frame,
  `starting` 16, every clip at least the eyes. A flood fill from the border recovers the
  eyes and would flicker the flag. **`generate.py` knows which pixels are background** and
  emits real transparency; imported art gets it from the classification `_typing_recolour()`
  already performs. The app never guesses.
- **The app composites and re-encodes.** This contradicts [[BLE Protocol]]'s current "key
  simplification" — that the app never encodes GIFs — and that page must be rewritten, not
  patched. Decode clip → composite over the overlay → encode → existing BLE path unchanged.
- **Our own GIF writer, not ImageIO**, for exact palette control (the panel's palette and
  colour rules are unforgiving) and byte-stability under the golden-fixture discipline.
  **It must do inter-frame diffs**: `done-flag` is 12.8KB across 59 frames (~217 B/frame)
  because PIL emits bounding-box diffs with a transparent index; a full-frame encoder would
  3–4× that and turn every clip swap into a multi-second upload. This is the largest
  implementation risk in the task.
- **The rail is row 0**: fill from the left for usage, plus one contrasting pixel marking
  the clock's position in the window, so "am I burning faster than it resets" is answerable
  at a glance. Colour ramp authored through `panel_encode()` — unencoded, the green→amber→red
  steps bunch exactly as the naive ladders did.
- **A knockout halo is available and optional per clip**: dilate the clip's silhouette by
  1px and clear the overlay beneath it, so the mascot reads as being in front rather than
  merging into the bar.
- **Refresh is boundary-gated like every other swap.** The overlay is keyed on its
  *quantised* rendering (bar length + colour bucket), not the raw percentage, so it changes
  a handful of times an hour; a changed key marks the displayed clip stale and it re-uploads
  at the next seam. Restarting a loop mid-cycle would break the anchor contract.
- **The rail dies with the panel.** Idle escalation is unchanged — dark is dark.
- **Data arrives from a statusline wrapper** that tees Claude Code's stdin JSON to the
  existing socket and then execs the user's real statusline (`ccstatusline` today).
  `rate_limits.five_hour.used_percentage` and `resets_at` are already in that payload, so
  no credentials are needed. The app caches the snapshot and keeps the clock honest between
  sessions. **The first-run flow offers to install the wrapper**, the way it already offers
  the plugin, at the user's direction.
- **Build the full mechanism, ship one widget.** The layer stack, alpha, compositor,
  encoder and refresh rule are the hard part regardless; exactly one thing rides on them at
  first.

## Out of scope for the first build

A second widget of any kind (the 7-day window, context usage, session count). The
reserved-region budget — at most rows 0–1, one widget per row, everything else is the
mascot's stage — is a rule to write down, not to fill.

## Open before implementation

- **The graffiti experiment, first.** The iDotMatrix protocol has a single-pixel write. If
  it composites over a playing GIF, the encoder is unnecessary and the rail becomes 32 tiny
  writes. Almost certainly it switches the panel out of GIF mode instead — but it is twenty
  minutes against several days, so it goes first.
- **What the rail shows with no data** (statusline not installed, or no session ever run).
  Hiding it is the obvious answer and needs confirming.

## Specs

- [[BLE Protocol]] — its "the app never encodes GIFs" simplification is what this ends
- [[Art Pipeline]] — alpha becomes an authored output
- [[Menu Bar App]] — the new data-flow leg and the stale-overlay re-upload rule
- [[Claude Code Plugin]] — the statusline wrapper as a second input
- [[Panel Quirks]] — 1px legibility, and why the ramp must be encoded
