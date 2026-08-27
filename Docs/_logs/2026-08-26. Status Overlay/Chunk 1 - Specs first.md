---
model: Sonnet
estimated_time: 5
estimated_tools: 10
estimated_tokens: 70000
estimated_risk: medium
actual_tokens: 128000
actual_tools: 23
actual_time: 7
outcome: success
---

# Chunk 1 — Specs first

## Task

Per CLAUDE.md, a behaviour change that is not in a spec is not finished, and the spec leads the
code. This chunk writes the Status Overlay into the specs **before any of it is built**. Four
pages change. The largest is [[BLE Protocol]], whose "Key simplification: the app never
*encodes* GIFs" is now false and must be **rewritten, not patched**.

Read `Plan.md` in this folder first — its *Architecture decisions* and *Integration seams*
sections are the source for everything below. Do not invent behaviour that is not in it.

## Required reading (in order)

1. `Docs/_logs/2026-08-26. Status Overlay/Plan.md` — the whole plan; this is your source
2. `Docs/_logs/2026-08-26. Status Overlay/Task.md` — the decisions and why
3. `Docs/Specs/BLE Protocol.md` — 74 lines, read whole; the page you rewrite most
4. `Docs/Specs/Art Pipeline.md` — read the **Style rules** section only
5. `Docs/Specs/Claude Code Plugin.md` — read **Transport** and **Installation** only
6. `Docs/Specs/Menu Bar App.md` — read **Architecture** (the data-flow diagram + file table),
   **Boundary scheduling**, and **Holding a diagnostic image**. Do NOT read the whole file.
7. `CLAUDE.md` — the "Specs come first" rules you are working under

## Deliverable

Edit exactly these four files. No source files, no new pages.

**`Docs/Specs/BLE Protocol.md`** — replace the *Key simplification* paragraph. What is true now:
- The app passes bundled GIF bytes through **untouched** when no overlay is present. That is the
  common path and the golden fixtures still pin it.
- When an overlay *is* present the app decodes the clip, composites, and re-encodes with its own
  writer (`GifImage.swift` / `GifEncoder.swift`), because the panel's palette rules are
  unforgiving and ImageIO applies colour management this project cannot tolerate.
- The uploaded GIF is always fully opaque and full-frame; the framing contract below is unchanged.
- State that every shipped GIF is already full-frame at ~190–226 B/frame, so re-encoding does not
  grow uploads.

**`Docs/Specs/Menu Bar App.md`** — add an **overlay** subsection covering: the overlay is the back
layer and the mascot occludes it; the reserved-region budget (at most rows 0–1, one widget per
row, the rest is the mascot's stage); the staleness rule (the overlay's *quantised* rendering is
part of what is on the panel, and a changed key re-uploads at the next seam, never mid-loop);
the rail dies with the panel; and `sendDiagnosticImage` is never composited over. Add the
`UsageSnapshot` leg to the data-flow diagram and the new files to the file table.

**`Docs/Specs/Art Pipeline.md`** — add to *Style rules* (or a short new section) that the
background mask is **inferred in the app** by flood fill from the border, not authored in the
art, and that the 1px knockout halo is what makes that exact in the overlay's rows — it is
load-bearing, not cosmetic. Say plainly that authored transparency was considered and deferred,
and why (the drawing code uses `BG` as both background and black art — `_paste_over`'s
`transparent=BG`, and recolour functions returning `BG` for "background, and the eyes").

**`Docs/Specs/Claude Code Plugin.md`** — add the statusline wrapper as a second, independent
input: what it sends (`{"event":"Usage","usedPercent":…,"resetsAt":…}`), that it **extracts
rather than forwards** under the same privacy rule that keeps `tool_input` off the wire, that it
`exec`s the user's real statusline and must pass its output through unchanged on every failure
path, and that it is offered separately from the plugin and independently declinable.

## Constraints

- **Prose only.** No Python, no Swift, no code blocks other than the one JSON payload example.
- **Invent no numbers.** The rail's colours do not exist yet — they are measured in chunk 5. Do
  not write a colour value, a bucket threshold, or a percentage into any spec.
- **Do not claim the art carries authored transparency.** It does not, and will not in this build.
- Specs reference source files, never duplicate their logic (CLAUDE.md rule 3). Name the file
  that implements a thing rather than restating it.
- Keep them lean (CLAUDE.md rule 4). You are adding maybe 60–80 lines across four files, not 300.
- Match each page's existing voice — these pages argue from measurement and name the failure that
  taught each rule. Do not write marketing prose.
- **One Write or one MultiEdit per file. Hard rule.** Plan all edits to a page, then apply them
  in a single call. If MultiEdit is unavailable, use one full-file Write per file.
- Do NOT modify any file other than the four named above.
- Do NOT run any git command.

## Verify before reporting

- Re-read each edited section once. Every factual claim must trace to `Plan.md`, `Task.md`, or
  `Docs/Reference/Panel Quirks.md`.
- `grep -n "authored transparen\|authored alpha" Docs/Specs/*.md` returns nothing that claims the
  art carries it.
- No colour triple or bucket threshold appears in your additions.

## When done

Return your Run Report as your final message. Do NOT write it to a file, do NOT modify this brief.

```
# Chunk 1 — Specs first — Run Report

- Outcome: success | partial | blocked
- Files created/modified: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, MultiEdit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for next chunk: <bullets or "none">
```
