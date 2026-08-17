---
model: 'Sonnet'
estimated_time: 20
estimated_tools: 30
estimated_tokens: 70000
estimated_risk: 'medium'
---

# Chunk 7 — Final verification

## Task

Bring the catalogue in line with what actually shipped, fix the specific stale sentences the
earlier chunks deliberately left behind, and run the expensive gates once against the
finished tree.

**Promoted to Sonnet on purpose** (the plan had this as Haiku): the numbers are
transcription, but the prose corrections below are edits to the document CLAUDE.md calls the
single source of truth for the art, and a wrong one there becomes the staler truth the whole
docs rule exists to prevent.

## Required reading (in order)

1. `CLAUDE.md` — the "Specs come first" rules and the regeneration command order.
2. `Docs/Specs/Animation Catalogue.md` — the whole file. This is your main deliverable.
3. `Sources/ClaudeMascot/Resources/Animations/clips.json` — the generated manifest. **This is
   the authority for every number you write.** Read the real values; never carry a number
   over from the old table or from a chunk report.
4. `Docs/Specs/Menu Bar App.md`, the "Event handling and session tracking" section only —
   one sentence to tighten.

## Deliverable

Modified: `Docs/Specs/Animation Catalogue.md`, `Docs/Specs/Menu Bar App.md`,
`Tests/ClaudeMascotTests/PanelControllerTests.swift` (one comment).
Plus the regenerated `Docs/Specs/_animations/*.gif`.

### 1. Regenerate first, in CLAUDE.md's order

```bash
venv/bin/python art/generate.py
venv/bin/python art/export_golden.py
venv/bin/python art/export_docs.py
```

`export_docs.py` only keeps *existing* images honest — a **new clip needs its line added to
the catalogue by hand**, which is most of your job below. Confirm every clip in `clips.json`
has a corresponding `Docs/Specs/_animations/<id>.gif` afterwards, and that no orphan image
remains for a retired clip (`working-alt`); delete such an orphan if it exists.

### 2. The four stale things earlier chunks left for you

Each was left deliberately, with a note saying so. All four must go:

1. **The `sitting` section's interim note** — a paragraph beginning roughly *"The table above
   is still today's shipped pair … regenerating it is a later pass, not this one."* Delete
   the note and replace the table it apologises for with the real one.
2. **The pose-graph interim note** — a paragraph beginning roughly *"The diagram and table
   above still show the shipped manifest, without `stand-to-sit` / `sit-to-stand`."* Delete
   it, and update the ASCII diagram and the From/To edge table so `sitting` is genuinely
   connected: `standing → sitting` is `stand-to-sit`, `sitting → standing` is
   `sit-to-stand`, and the other `sitting` cells stay ❌. `standing` remains the hub.
3. **The turned-head claim about the seated beats is wrong.** The `sitting` section says
   `work-coffee` and `work-look` *"turn the mascot to face the viewer, so both are drawn to
   the turned-head rule above"*, and describes each as turning. **Neither turns.** This
   mascot is drawn front-on in every clip, so there is no away-facing pose to turn from; the
   attention shift in both is drawn as **looking up from the screen** — the eyes rise within
   the head, `thinking-alt`'s paint-over-and-redraw technique, symmetric in `work-look` to
   keep it distinct from the single-eye quizzical lift `work-idea` and `thinking-alt` use.
   Rewrite the two clip descriptions and drop the false turned-head attribution. **Keep the
   turned-head rule itself** near the top of the file — it still governs `dancing` and the
   sweep.
4. **`Menu Bar App.md`** says *"Sessions are reaped on `SessionEnd` and on a staleness
   timeout"*. Reaping on `SessionEnd` is now deferred by the debounce a few paragraphs below,
   so tighten that clause to stay true without duplicating the debounce's own explanation.

### 3. The `sitting` section's real inventory

Write the tables the way the rest of the page does it — an image row and a
`**id** · Nf · N.NNs · w N.N` row for loops, `**id**<br>from → to<br>Nf · motion N.NNs` for
transitions — with **every number read from `clips.json`**:

- The `working` loop (drawn seated art now, not the broom).
- `stand-to-sit` and `sit-to-stand`, as pose edges. They may go in the Transitions section
  next to `stand-to-doze`/`doze-to-stand` if that reads better — your call, say which you
  chose and why.
- The four fidgets `work-idea`, `work-coffee`, `work-look`, `work-think`, with their
  `fidgetGroup: "working"` scoping explained once, not four times.
- `working-alt` gone from the page entirely except where its retirement is the point.

Also: **`sweeping` needs its line in the `standing`/**idle** variant table** — it is an idle
variant now, so it belongs in that table with the other four, and the idle intro sentence
saying how many variants there are must match reality.

### 3b. The turned-head rule is wrong as written — correct it

Chunk 6 attempted the trim and it was **deliberately reverted** after investigation. The
rule near the top of the catalogue currently reads as if it applies to any turn and is
mechanically satisfiable. Neither is true, and the file must say what was actually found:

- **It only means anything for a turn that still shows both eyes.** `dancing`'s two deep
  turns (its frames 6 and 15, the ones carrying 43 shaded pixels against 46–47 for the
  shallow ones) and the sweep's own deep turns (coalesced frames 12 and 21) present a single
  eye with the full 16-wide torso behind it. There, "no body outboard of the far eye" would
  mean trimming eight of sixteen columns — halving the head rather than turning it.
- **Even on the shallow turns it cannot be applied to this art.** In `dancing` frame 1 the
  eyes sit at x13–14 and x21–22 with exactly one body column at x23. Erasing that column
  leaves the far eye opening into the background — it stops reading as an eye and becomes a
  notch in the outline — and narrows the head from 16 columns to 13 across most of the sway.
  That is the shrinking silhouette this page already records as the reason `idle-think` was
  cut and `working-alt` retired.

So rewrite the rule as a **constraint on newly drawn art** — which is how the seated set was
built and why it has no such defect — and record the existing violation as a known gap
rather than a rule the shipped clips satisfy. The honest fix is re-authoring the sway's
turned frames (shifting the eyes and narrowing the head together, so the silhouette stays
one width), not a repair pass, and that is a separate task.

### 4. Known gaps

Re-check the list against the finished tree. `sitting` now has fidgets and edges, `working`
is drawn at full scale, and the laptop has shape — so if any surviving gap entry is now
false or partly false, fix it. Do not invent new gaps; if the art review turns up something,
that is the user's call, not a gap you add unilaterally.

**One gap you MUST add**: the turned-head violation in `dancing` and the sweep, with the
diagnosis from section 3b — one stray column past the far eye on the shallow turns, a
single-eye head on the deep ones, and why a trim makes both worse. This is the defect the
user originally reported, so the page must carry it as known and unfixed rather than let the
rule imply it is solved.

Two further items you MAY record, because they are known and real, if you judge the gap list
the right home for them (say either way in your report):

- `work-idea`'s spark sits ~6 rows above the seated head with nothing bridging the gap,
  where `thinking-alt`'s bubble has a puff tail — it may read as floating rather than as his.
- `work-coffee`'s mug occupies the far arm's position rather than being held at the end of
  it, so "holding" is implied by adjacency.

### 5. `PanelControllerTests.swift`

`departureIsAbandonedIfTheMascotCannotLeave`'s comment says a missing `.away` edge is *"true
of `sitting` in the shipped manifest today"*. No longer true. **The test must keep working
unchanged** — it uses a synthetic resolver to prove graceful degradation. Reword the comment
only.

## Constraints

- **Every number comes from `clips.json`.** Not from a chunk report, not from the old table,
  not from arithmetic on frame counts. If a number in the file disagrees with `clips.json`
  after you finish, that is a failure of this chunk.
- Do NOT edit `art/generate.py` or any Swift file other than the one comment above. If a
  number looks wrong, report it — do not fix art here.
- Match the page's house voice. You are also allowed to **delete** prose the change makes
  stale; that is part of the job.
- One write operation per file. If `MultiEdit` is not registered in your session, apply each
  file's change as ONE `Write`, or a single uniqueness-checked patch script via Bash — say
  which you used.
- Do NOT run any git command. Do NOT install anything into `/Applications`.

### Verify before reporting

1. The three regeneration commands, in order, all clean.
2. `swift build 2>&1 | tail -10` — zero warnings, zero errors.
3. `swift test 2>&1 | tail -20` — the full suite green; report the test count.
4. `./make-app.sh 2>&1 | tail -15` — must succeed. Do **not** install or launch it; BLE can
   only be exercised from the installed bundle and that is the user's step.
5. **Cross-check every number you wrote**: for each clip id mentioned in the catalogue, print
   `clips.json`'s `frameCount`, `durationMs` and `motionMs` and confirm the page agrees.
   Paste that comparison into your report.
6. `grep -rn "working-alt" Docs/Specs/ Sources/ Tests/ art/` — report every remaining hit and
   why each is correct.
7. Confirm no interim note survives: `grep -n "later pass\|still show\|still today's" "Docs/Specs/Animation Catalogue.md"`
   must come back empty.

If a gate fails and the cause is outside your deliverables, STOP and report `blocked` with
the full error list — never a truncated head.

## When done

Report by **returning your Run Report as your final message** — do NOT write it to a file,
and do NOT modify this brief. Every field is required; use `none` or `n/a`.

```
# Chunk 7 — Final verification — Run Report

- Outcome: success | partial | blocked
- Files created/modified/deleted: <paths>
- Files read: <paths>
- Tool calls (by tool, count): Read=N, Write=N, Edit=N, Bash=N, ...
- Edit-per-file count: <file>: N edits
- Regeneration (all three commands): <pass/fail each>
- swift build: <pass/fail + tail>
- swift test: <pass/fail, test count, + tail>
- make-app.sh: <pass/fail + tail>
- Number cross-check (clip → clips.json vs page): <table; every row must agree>
- The four stale things: <one line each confirming it is gone>
- Where the sit edges were documented, and why: <...>
- Gap list changes: <what you changed, and whether you recorded the two known art items>
- working-alt grep results: <every hit + why correct>
- Interim-note grep: <empty? y/n>
- Deviations from spec: <bullets or "none">
- Risks / open questions: <bullets or "none">
- Notes for the orchestrator: <anything needing a human, especially anything only the panel can settle>
```
