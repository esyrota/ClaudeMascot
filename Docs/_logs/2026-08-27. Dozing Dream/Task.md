# Dozing Dream

A set-piece animation for the sleeping mascot — a nightmare in which Pac-Man chases him off
the panel — and the three scheduling fields it needs to exist without wearing out its welcome.

## Why now

`work-coffee` had never once been seen. The cause was measurable: `fidgetChance` 0.15 per
20s epoch, `work-coffee` at 0.15 of a 1.3 total, ≈19 minutes of continuous `working` between
sips. That was fixed by raising both numbers — but the investigation surfaced two facts about
the fidget machinery that a long set piece cannot live with:

- **A fidget is not a one-shot.** Once picked it is re-picked for the rest of its epoch, and
  `driveTowards` skips the re-upload because the id is unchanged, so the panel simply loops the
  GIF. A 8-second dream would play, restart, and be guillotined mid-way at the epoch boundary.
- **Weight cannot make a clip rare.** It is a *relative* number. There are no other `dozing`
  fidgets, so a dream would be the only candidate and fire on every due roll — a dream a minute.

Both are scheduling gaps, not art problems, and neither is specific to the dream:
`work-coffee` has the same repeat-within-an-epoch behaviour today.

## The dream, as scripted

1. He sleeps. The `sleeping` bubbles drift up as they always do.
2. The largest bubble does not pop — it keeps growing, and fills the panel.
3. Dark screen.
4. `walk-in-left`.
5. He looks back over his left shoulder — the implied body turn `dancing` uses.
6. He startles — `starting` frames 4–5, **without** the rise; he stays on the ground.
7. `walk-off-right`.
8. A large yellow Pac-Man crosses left to right, chasing him.
9. Dark screen, and he is asleep again.

## Decisions reached

- **Three new `Clip` fields**, two of them sharing one mechanism:
  - `maxPerPhase` — how many times a clip may play in one phase. The dream sets `1`.
  - `maxRepeats` — how many times a clip may play consecutively. `work-coffee` sets `1`.
  - `interruptible` — the clip may be cut mid-motion. The dream sets `true`.
- **The dream needs only `maxPerPhase: 1`** — once per phase already implies never twice in
  a row.
- **A *phase* is a maximal run where the resolved group is unchanged.** Leave `dozing` and
  come back later and it is a new sleep, ledger cleared — which is exactly "max one dream per
  sleep". For `work-coffee` a phase is a whole working stretch, possibly hours, so only
  `maxRepeats` is meaningful there.
- **This replaces rarity-by-weight.** The companion `doze-peek` fidget considered during
  design is not needed: with the dream excluded after its one showing, `selectFidget` finds no
  other `dozing` candidate, returns nil, and falls through to the `sleeping` loop.
- **`maxRepeats` is set on `work-coffee` and nothing else.** Making it a default for all
  fidgets was considered and rejected: with five `sitting` candidates each excluding only
  itself, every due epoch would fill with a rotating chain of four or five distinct fidgets and
  the typing loop would only appear in non-due epochs. Today's epoch-hold behaviour stays for
  every fidget that does not opt out.
- **The ledger is an explicit fourth input to `Choreographer`, not internal state.**
  `PanelController` owns it and writes it in exactly one place — `attemptUpload`'s success
  branch, beside `displayed`. The statelessness contract in `Choreographer`'s doc comment
  becomes a four-input purity contract; the reason it exists (speculative calls on every tick
  must not advance bookkeeping) survives intact, because the only write happens on a real
  upload.
- **The dream excludes `doze-to-stand` and `stand-to-doze`.** It ends on the dark screen and
  the `sleeping` loop resumes. Keeping them inside would duplicate 5.4s of existing art inside
  a clip that has to travel over BLE.
- **Interruption:** a wake cuts in at any frame. The pose bookkeeping already supports it —
  the dream is a self-edge, so `pose(of:)` reads `toPose == dozing` at every moment inside it
  and a wake resolves to `doze-to-stand` from any frame with no graph confusion. `wave-off` is
  existing precedent for bypassing the seam when the beat matters more.

## Out of scope

- **Making fidgets discrete beats generally** (a "one fidget per epoch" gate). Considered and
  deferred; the epoch-hold behaviour is now documented in [[Menu Bar App]] rather than fixed.
- **Revisiting `fidgetChance`.** Just raised to 0.3; leave it a while and judge it on the panel.
- **Dreams for any other pose.** `dozing` only.

## Specs

- [[Menu Bar App]] — the fidget section: the three fields, the phase ledger, the four-input contract
- [[Animation Catalogue]] — the new clip, its numbers, and its place as a `dozing` self-edge
- [[Panel Quirks]] — the full-panel white bloom is the brightest frame this project has drawn
