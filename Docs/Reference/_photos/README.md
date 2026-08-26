# Panel photos

Reference photographs of the real panel, used to check authored colour against what the
LEDs actually do. See [[Panel Quirks]] for how to shoot one that can be trusted: the
on-screen reference in the same frame is the method, and **video beats a still** — the
panel is scan-driven.

Only decisive frames live here. The raw rounds stay local (`art/photos/`, gitignored);
their numbers are in [[Findings]].

| File | What it shows |
|---|---|
| `panel-card-a-ramps.jpg` | 2026-08-26. Card A on the panel beside `reference.html` on screen — the shot the tone curve was fitted to. The white 2×2 anchor is the alignment landmark; the bottom-right dark block is the value-0 patch. |
| `panel-card-e-gamma.jpg` | 2026-08-26. Card E, the falsification test: gamma-encoded ladders beside naive ones. The encoded ladders step evenly, the naive ones bunch. |
| `panel-work-idea.jpg` *(named by the old rule, never actually added)* | 2026-08-18. `work-idea`, the palette before the blue-channel fix: `MASCOT (255,68,4)` rendering pink, `MASCOT_DARK (255,24,0)` rendering vivid red, `LAPTOP_GREY` rendering blue. The photo the current colour rule is fitted to — see the shade bisection in [[Panel Quirks]] for the two later shots of `SHADE_SCALE` at 0.35 and 0.60. |
