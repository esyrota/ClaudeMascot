import Foundation
import Testing

@testable import ClaudeMascot

/// Mutable "now" the choreographer reads instead of `Date()`, matching the
/// pattern `PanelControllerTests.FakeClock` uses — every test advances it
/// explicitly, so epoch boundaries land exactly where the test expects.
@MainActor
private final class FakeClock {
  private(set) var now: TimeInterval = 0

  func advance(_ seconds: TimeInterval) {
    now += seconds
  }

  func callAsFunction() -> TimeInterval { now }
}

// MARK: - Synthetic clip builders

/// A looping variant clip in `group`, at `pose`.
private func loopClip(
  _ id: String, pose: Pose, group: String, weight: Double = 1.0, duration: TimeInterval = 1
)
  -> Clip
{
  Clip(
    id: id, file: "\(id).gif", frameCount: 1, duration: duration, motion: duration, loops: true,
    pose: pose, variantGroup: group, fidgetGroup: nil, weight: weight, fromPose: nil, toPose: nil,
    maxPerPhase: nil, maxRepeats: nil, interruptible: false)
}

/// A non-looping transition edge between two different poses.
private func edgeClip(
  _ id: String, from: Pose, to: Pose, motion: TimeInterval = 1, duration: TimeInterval = 5
)
  -> Clip
{
  Clip(
    id: id, file: "\(id).gif", frameCount: 1, duration: duration, motion: motion, loops: false,
    pose: nil, variantGroup: nil, fidgetGroup: nil, weight: 1, fromPose: from, toPose: to,
    maxPerPhase: nil, maxRepeats: nil, interruptible: false)
}

/// A non-looping self-edge at `pose` — the shape both `"<group>-enter"`
/// one-shots and fidgets have (`fromPose == toPose`). `fidgetGroup` is nil for a
/// fidget that suits any state at the pose, and set for one scoped to a single
/// state the way the wander fidgets are scoped to `idle`. `maxPerPhase` and
/// `maxRepeats` default to nil (unlimited), matching every shipped fidget but
/// `doze-dream` and `work-coffee`.
private func selfEdgeClip(
  _ id: String, pose: Pose, fidgetGroup: String? = nil, variantGroup: String? = nil,
  motion: TimeInterval = 1, duration: TimeInterval = 1, maxPerPhase: Int? = nil,
  maxRepeats: Int? = nil
) -> Clip {
  Clip(
    id: id, file: "\(id).gif", frameCount: 1, duration: duration, motion: motion, loops: false,
    pose: nil, variantGroup: variantGroup, fidgetGroup: fidgetGroup, weight: 1,
    fromPose: pose, toPose: pose, maxPerPhase: maxPerPhase, maxRepeats: maxRepeats,
    interruptible: false)
}

private func manifest(_ clips: [Clip]) -> ClipManifest {
  var byId: [String: Clip] = [:]
  for clip in clips { byId[clip.id] = clip }
  return ClipManifest(version: 1, clips: byId)
}

// MARK: - Pose derivation

@Test @MainActor
func poseOfLoopingClipIsItsPose() {
  let clock = FakeClock()
  let choreographer = Choreographer(manifest: manifest([]), clock: { clock() })
  let clip = loopClip("working", pose: .sitting, group: "working")
  #expect(choreographer.pose(of: clip) == .sitting)
}

@Test @MainActor
func poseOfTransitionClipIsItsToPose() {
  let clock = FakeClock()
  let choreographer = Choreographer(manifest: manifest([]), clock: { clock() })
  let clip = edgeClip("stand-sit", from: .standing, to: .sitting)
  #expect(choreographer.pose(of: clip) == .sitting)
}

@Test @MainActor
func poseOfNilDisplayedIsOffBottom() {
  let clock = FakeClock()
  let choreographer = Choreographer(manifest: manifest([]), clock: { clock() })
  #expect(choreographer.pose(of: nil) == .offBottom)
}

// MARK: - One edge at a time

@Test @MainActor
func oneEdgeAtATimeTowardATwoHopTarget() {
  let clock = FakeClock()
  // A synthetic graph, not the shipped one: standing reaches sitting only by way
  // of offLeft, so `.working` is deliberately two hops away. (This used to route
  // to `.sleeping` at `.lying`; the mascot now sleeps standing and `lying` is
  // gone, so the two-hop target had to become a pose that still exists.)
  let idle = loopClip("idle", pose: .standing, group: "idle")
  let working = loopClip("working", pose: .sitting, group: "working")
  let standLeft = edgeClip("stand-left", from: .standing, to: .offLeft)
  let leftSit = edgeClip("left-sit", from: .offLeft, to: .sitting)
  let choreographer = Choreographer(
    manifest: manifest([idle, working, standLeft, leftSit]), clock: { clock() })

  // Standing, wants to be sitting: only the first edge comes back.
  let first = choreographer.clip(for: .working, displayed: idle, ledger: PhaseLedger())
  #expect(first?.id == "stand-left")

  // Same call again, nothing displayed yet: identical answer (idempotent).
  let firstAgain = choreographer.clip(for: .working, displayed: idle, ledger: PhaseLedger())
  #expect(firstAgain?.id == "stand-left")

  // Only once the first edge is actually displayed does the second appear.
  let second = choreographer.clip(for: .working, displayed: standLeft, ledger: PhaseLedger())
  #expect(second?.id == "left-sit")
}

@Test @MainActor
func targetFlippingMidJourneyIsSelfCorrecting() {
  let clock = FakeClock()
  // Same synthetic two-hop graph as above, plus the edge back.
  let idle = loopClip("idle", pose: .standing, group: "idle")
  let working = loopClip("working", pose: .sitting, group: "working")
  let standLeft = edgeClip("stand-left", from: .standing, to: .offLeft)
  let leftStand = edgeClip("left-stand", from: .offLeft, to: .standing)
  let leftSit = edgeClip("left-sit", from: .offLeft, to: .sitting)
  let choreographer = Choreographer(
    manifest: manifest([idle, working, standLeft, leftStand, leftSit]), clock: { clock() })

  // Walking toward .working: first edge lands us at offLeft.
  let firstEdge = choreographer.clip(for: .working, displayed: idle, ledger: PhaseLedger())
  #expect(firstEdge?.id == "stand-left")

  // The world changes its mind before the second edge plays: target flips
  // back to .idle (standing). From offLeft, that's a single edge back —
  // not a continuation of the walk toward sitting.
  let corrected = choreographer.clip(for: .idle, displayed: standLeft, ledger: PhaseLedger())
  #expect(corrected?.id == "left-stand")
}

// MARK: - Graceful degradation

@Test @MainActor
func noPathDegradesToADirectSwap() {
  let clock = FakeClock()
  let idle = loopClip("idle", pose: .standing, group: "idle")
  let working = loopClip("working", pose: .sitting, group: "working")
  // No edges at all in this manifest — today's real manifest, basically.
  let choreographer = Choreographer(manifest: manifest([idle, working]), clock: { clock() })

  let resolved = choreographer.clip(for: .working, displayed: idle, ledger: PhaseLedger())
  #expect(resolved?.id == "working")
}

// MARK: - Determinism

@Test @MainActor
func sameInputsReturnIdenticalClipWithinAnEpoch() {
  let clock = FakeClock()
  let a = loopClip("idle-a", pose: .standing, group: "idle", weight: 1)
  let b = loopClip("idle-b", pose: .standing, group: "idle", weight: 1)
  let choreographer = Choreographer(
    manifest: manifest([a, b]), clock: { clock() }, fidgetChance: 0)

  // The exact same (target, displayed, now) triple, called three times: no
  // stored state means no run of calls can see a different answer than the
  // first.
  let first = choreographer.clip(for: .idle, displayed: a, ledger: PhaseLedger())
  let second = choreographer.clip(for: .idle, displayed: a, ledger: PhaseLedger())
  let third = choreographer.clip(for: .idle, displayed: a, ledger: PhaseLedger())
  #expect(first?.id == second?.id)
  #expect(first?.id == third?.id)
}

// MARK: - Variant rotation

@Test @MainActor
func variantsRotateAcrossEpochsWithoutImmediateRepeat() {
  let clock = FakeClock()
  let a = loopClip("idle-a", pose: .standing, group: "idle", weight: 1)
  let b = loopClip("idle-b", pose: .standing, group: "idle", weight: 1)
  let rotationPeriod: TimeInterval = 20
  let choreographer = Choreographer(
    manifest: manifest([a, b]), clock: { clock() }, rotationPeriod: rotationPeriod, fidgetChance: 0)

  var previousId: String?
  var sawBoth = Set<String>()
  for _ in 0..<12 {
    let displayed = previousId.map { $0 == "idle-a" ? a : b } ?? a
    let picked = choreographer.clip(for: .idle, displayed: displayed, ledger: PhaseLedger())
    #expect(picked != nil)
    if let picked {
      if let previousId {
        #expect(picked.id != previousId, "immediate repeat with 2 candidates")
      }
      sawBoth.insert(picked.id)
      previousId = picked.id
    }
    clock.advance(rotationPeriod)
  }
  #expect(sawBoth == ["idle-a", "idle-b"])
}

@Test @MainActor
func heavilyWeightedVariantDominatesAcrossManyEpochs() {
  let clock = FakeClock()
  // Three candidates so excluding the previous epoch's pick still leaves a
  // real weighted choice (with only two, exclusion would force strict
  // alternation regardless of weight).
  let common = loopClip("idle-common", pose: .standing, group: "idle", weight: 20)
  let rare1 = loopClip("idle-rare1", pose: .standing, group: "idle", weight: 1)
  let rare2 = loopClip("idle-rare2", pose: .standing, group: "idle", weight: 1)
  let rotationPeriod: TimeInterval = 20
  let choreographer = Choreographer(
    manifest: manifest([common, rare1, rare2]), clock: { clock() }, rotationPeriod: rotationPeriod,
    fidgetChance: 0)

  var counts: [String: Int] = [:]
  var displayed = common
  for _ in 0..<300 {
    let picked = choreographer.clip(for: .idle, displayed: displayed, ledger: PhaseLedger())!
    counts[picked.id, default: 0] += 1
    displayed = picked
    clock.advance(rotationPeriod)
  }

  // "No immediate repeat" caps any single candidate's share at under half of
  // all picks (it can never follow itself, so it must alternate with
  // something else at least every other epoch) — so the fair comparison
  // for "dominates" is against each *individual* rare, not their sum, which
  // a heavy weight cannot mathematically outweigh once there is more than
  // one alternative to split the remainder with.
  let commonCount = counts["idle-common", default: 0]
  let rare1Count = counts["idle-rare1", default: 0]
  let rare2Count = counts["idle-rare2", default: 0]
  #expect(commonCount > rare1Count)
  #expect(commonCount > rare2Count)
}

// MARK: - Enter one-shot

@Test @MainActor
func enterOneShotPlaysOnArrivalAndIsNotRepeatedOnceSettled() {
  let clock = FakeClock()
  let idle = loopClip("idle", pose: .standing, group: "idle")
  let done = loopClip("done", pose: .standing, group: "done")
  let doneEnter = selfEdgeClip("done-enter", pose: .standing)
  let choreographer = Choreographer(
    manifest: manifest([idle, done, doneEnter]), clock: { clock() }, fidgetChance: 0)

  // Arriving at .done straight from a different group's loop clip (same
  // pose, no edge to walk): the one-shot entrance plays.
  let onArrival = choreographer.clip(for: .done, displayed: idle, ledger: PhaseLedger())
  #expect(onArrival?.id == "done-enter")

  // Once the entrance itself is what's displayed, asking again must not
  // replay it — it falls through to the settled loop.
  let settled = choreographer.clip(for: .done, displayed: doneEnter, ledger: PhaseLedger())
  #expect(settled?.id == "done")

  // And it stays settled on subsequent calls.
  let stillSettled = choreographer.clip(for: .done, displayed: settled, ledger: PhaseLedger())
  #expect(stillSettled?.id == "done")
}

// MARK: - Fidgets

@Test @MainActor
func fidgetInjectedWhenDueAndAbsentFidgetsFallThroughCleanly() {
  let clock = FakeClock()
  let idle = loopClip("idle", pose: .standing, group: "idle")
  let blink = selfEdgeClip("blink", pose: .standing)
  let rotationPeriod: TimeInterval = 20

  // fidgetChance: 1 forces "due" on every epoch, isolating the "is a fidget
  // ever returned at all" behaviour from the roll itself.
  let withFidget = Choreographer(
    manifest: manifest([idle, blink]), clock: { clock() }, rotationPeriod: rotationPeriod,
    fidgetChance: 1)
  let picked = withFidget.clip(for: .idle, displayed: idle, ledger: PhaseLedger())
  #expect(picked?.id == "blink")

  // No fidget clips in the manifest at all (today's real manifest): falls
  // through cleanly to the settled loop instead of stalling or crashing.
  let withoutFidgets = Choreographer(
    manifest: manifest([idle]), clock: { clock() }, rotationPeriod: rotationPeriod, fidgetChance: 1)
  let fallenThrough = withoutFidgets.clip(for: .idle, displayed: idle, ledger: PhaseLedger())
  #expect(fallenThrough?.id == "idle")
}

@Test @MainActor
func neverFidgetsDuringATransitionOrForOff() {
  let clock = FakeClock()
  let idle = loopClip("idle", pose: .standing, group: "idle")
  let sitStand = edgeClip("sit-stand", from: .sitting, to: .standing)
  let standingBlink = selfEdgeClip("blink", pose: .standing)
  let offLoop = loopClip("off", pose: .offBottom, group: "off")
  let choreographer = Choreographer(
    manifest: manifest([idle, sitStand, standingBlink, offLoop]), clock: { clock() },
    fidgetChance: 1)

  // Just walked the edge in: displayed is the transition itself, whose
  // `toPose` matches the target's pose. Even though a fidget for this pose
  // exists and fidgetChance forces it "due", arriving must not be mistaken
  // for a fidget opportunity.
  let justArrivedAtStanding = choreographer.clip(
    for: .idle, displayed: sitStand, ledger: PhaseLedger())
  #expect(justArrivedAtStanding?.id != "blink")

  // `.off` never fidgets, even with a matching pose and a forced-due roll.
  let offTarget = choreographer.clip(for: .off, displayed: offLoop, ledger: PhaseLedger())
  #expect(offTarget?.id != "blink")
}

@Test @MainActor
func aGroupedFidgetOnlyFiresForItsOwnGroup() {
  let clock = FakeClock()
  let idle = loopClip("idle", pose: .standing, group: "idle")
  let waiting = loopClip("waiting", pose: .standing, group: "waiting")
  // The shape of a wander clip: a standing self-edge scoped to `idle`. It is the
  // only fidget in the manifest, so whichever state does not get it gets no
  // fidget at all — which is the point. Walking off the panel is fine while
  // idling and wrong while `waiting` is asking the user for something.
  let wander = selfEdgeClip("wander-off-left-in-right", pose: .standing, fidgetGroup: "idle")
  let choreographer = Choreographer(
    manifest: manifest([idle, waiting, wander]), clock: { clock() }, fidgetChance: 1)

  #expect(
    choreographer.clip(for: .idle, displayed: idle, ledger: PhaseLedger())?.id
      == "wander-off-left-in-right")
  #expect(
    choreographer.clip(for: .waiting, displayed: waiting, ledger: PhaseLedger())?.id == "waiting")
}

@Test @MainActor
func aGroupedFidgetIsNeverPickedAsAVariant() {
  let clock = FakeClock()
  let idle = loopClip("idle", pose: .standing, group: "idle")
  // A non-looping clip that declares a variantGroup. Nothing in the shipped
  // manifest does this — fidget scoping is its own field — but `clips(inGroup:)`
  // has to make it impossible rather than merely unused: returning a one-shot as
  // a variant would leave it on screen and the panel would hold its last frame
  // forever.
  let wander = selfEdgeClip("wander-sink-rise", pose: .standing, variantGroup: "idle")
  let choreographer = Choreographer(
    manifest: manifest([idle, wander]), clock: { clock() }, fidgetChance: 0)

  for _ in 0..<8 {
    #expect(choreographer.clip(for: .idle, displayed: idle, ledger: PhaseLedger())?.id == "idle")
    clock.advance(30)
  }
}

/// Seam guard: `wave-off` is a standing self-edge shaped exactly like an
/// ordinary fidget, and would be drawn as one for any standing state if it
/// ever shipped without a `fidgetGroup`. That failure is silent everywhere
/// but hardware — a departure clip stealing a beat from `.idle`,
/// `.thinking`, `.waiting`, or `.done` looks like a slightly odd fidget, not
/// a bug. Selection is seeded by epoch, so a single clock value proves
/// nothing; this sweeps several hundred to make the guard mean something.
@Test @MainActor
func waveOffNeverLeaksIntoAStandingFidget() {
  let clock = FakeClock()
  let rotationPeriod: TimeInterval = 20
  let idle = loopClip("idle", pose: .standing, group: "idle")
  let thinking = loopClip("thinking", pose: .standing, group: "thinking")
  let waiting = loopClip("waiting", pose: .standing, group: "waiting")
  let done = loopClip("done", pose: .standing, group: "done")
  let waveOff = selfEdgeClip("wave-off", pose: .standing, fidgetGroup: "away")
  let choreographer = Choreographer(
    manifest: manifest([idle, thinking, waiting, done, waveOff]), clock: { clock() },
    rotationPeriod: rotationPeriod, fidgetChance: 1)

  let targets: [(PanelState, Clip)] = [
    (.idle, idle), (.thinking, thinking), (.waiting, waiting), (.done, done),
  ]
  for _ in 0..<400 {
    for (state, displayed) in targets {
      #expect(
        choreographer.clip(for: state, displayed: displayed, ledger: PhaseLedger())?.id
          != "wave-off")
    }
    clock.advance(rotationPeriod)
  }
}

// MARK: - Phase ledger: maxPerPhase, maxRepeats, interruptible

@Test @MainActor
func maxPerPhaseExcludesAfterOnePlayAndFallsThroughToTheLoop() {
  let clock = FakeClock()
  let sleeping = loopClip("sleeping", pose: .dozing, group: "sleeping")
  // The dream: the only fidget candidate at `.dozing`, capped to one play
  // per phase. Once it is excluded there is nothing else for `selectFidget`
  // to return, so the fall-through to the group's loop variant is the whole
  // point of the field -- not nil.
  let dream = selfEdgeClip("doze-dream", pose: .dozing, maxPerPhase: 1)
  let choreographer = Choreographer(
    manifest: manifest([sleeping, dream]), clock: { clock() }, fidgetChance: 1)

  var ledger = PhaseLedger()
  ledger.enterPhase("sleeping")

  let first = choreographer.clip(for: .sleeping, displayed: sleeping, ledger: ledger)
  #expect(first?.id == "doze-dream")
  ledger.record(first!)

  // Same epoch, ledger now has the one play recorded: the dream is excluded
  // and the only other candidate is the loop itself.
  let second = choreographer.clip(for: .sleeping, displayed: first, ledger: ledger)
  #expect(second?.id == "sleeping")
}

@Test @MainActor
func aNewPhaseClearsTheLedgerAndReallowsTheCappedClip() {
  let clock = FakeClock()
  let sleeping = loopClip("sleeping", pose: .dozing, group: "sleeping")
  let dream = selfEdgeClip("doze-dream", pose: .dozing, maxPerPhase: 1)
  let choreographer = Choreographer(
    manifest: manifest([sleeping, dream]), clock: { clock() }, fidgetChance: 1)

  var ledger = PhaseLedger()
  ledger.enterPhase("sleeping")
  let first = choreographer.clip(for: .sleeping, displayed: sleeping, ledger: ledger)
  #expect(first?.id == "doze-dream")
  ledger.record(first!)
  #expect(choreographer.clip(for: .sleeping, displayed: first, ledger: ledger)?.id == "sleeping")

  // Leave the phase and come back: a new sleep, ledger cleared, one dream
  // available again.
  ledger.enterPhase("idle")
  ledger.enterPhase("sleeping")
  let again = choreographer.clip(for: .sleeping, displayed: sleeping, ledger: ledger)
  #expect(again?.id == "doze-dream")
}

@Test @MainActor
func maxRepeatsExcludesTheClipUntilADifferentFidgetPlays() {
  let clock = FakeClock()
  let working = loopClip("working", pose: .sitting, group: "working")
  // The only fidget candidate in this manifest, capped to one play in a row.
  // `work-other` below is never a candidate `selectFidget` could return
  // (it is not in the manifest at all) -- it stands in for "some other
  // fidget played", recorded directly the way `PanelController` would
  // record whatever it actually uploaded.
  let coffee = selfEdgeClip("work-coffee", pose: .sitting, maxRepeats: 1)
  // Same pose as `coffee` -- `pose(of:)` reads `displayed` to derive the
  // mascot's current pose, and a mismatched pose here would route the next
  // call through the edge-graph branch instead of the fidget branch this
  // test is about.
  let otherFidget = selfEdgeClip("work-other", pose: .sitting)
  let choreographer = Choreographer(
    manifest: manifest([working, coffee]), clock: { clock() }, fidgetChance: 1)

  var ledger = PhaseLedger()
  ledger.enterPhase("working")
  ledger.record(coffee)

  // Just played once: not picked again while it is the last fidget played.
  let excluded = choreographer.clip(for: .working, displayed: coffee, ledger: ledger)
  #expect(excluded?.id == "working")

  // A different fidget plays in between, breaking the run.
  ledger.record(otherFidget)
  let reallowed = choreographer.clip(for: .working, displayed: otherFidget, ledger: ledger)
  #expect(reallowed?.id == "work-coffee")
}

@Test @MainActor
func aLoopClipBetweenTwoFidgetsDoesNotResetTheMaxRepeatsRun() {
  let clock = FakeClock()
  let working = loopClip("working", pose: .sitting, group: "working")
  let coffee = selfEdgeClip("work-coffee", pose: .sitting, maxRepeats: 1)
  let choreographer = Choreographer(
    manifest: manifest([working, coffee]), clock: { clock() }, fidgetChance: 1)

  var ledger = PhaseLedger()
  ledger.enterPhase("working")
  ledger.record(coffee)
  // The group's own loop clip lands between two fidgets across an epoch
  // boundary -- recording it must not count as "a different fidget" and
  // must not clear the run `work-coffee` is still serving.
  ledger.record(working)

  let stillExcluded = choreographer.clip(for: .working, displayed: working, ledger: ledger)
  #expect(stillExcluded?.id == "working")
}

@Test @MainActor
func uncappedFidgetsIgnoreTheLedger() {
  let clock = FakeClock()
  let idle = loopClip("idle", pose: .standing, group: "idle")
  // Neither field set: a manifest with no caps must produce exactly today's
  // selections no matter how many plays land in the ledger.
  let blink = selfEdgeClip("blink", pose: .standing)
  let choreographer = Choreographer(
    manifest: manifest([idle, blink]), clock: { clock() }, fidgetChance: 1)

  var ledger = PhaseLedger()
  ledger.enterPhase("idle")
  for _ in 0..<5 {
    let picked = choreographer.clip(for: .idle, displayed: idle, ledger: ledger)
    #expect(picked?.id == "blink")
    ledger.record(picked!)
  }
}

// MARK: - Arriving and leaving

@Test @MainActor
func theEntranceIsSuppressedWhenTheMascotIsAlreadyOnScreen() {
  let clock = FakeClock()
  let idle = loopClip("idle", pose: .standing, group: "idle")
  let starting = edgeClip("starting", from: .offBottom, to: .standing)
  // The wander is the trap this regression is about: it is a standing
  // self-edge, so `transition(from: .standing, to: .standing)` matches it, and
  // the mascot answered a `SessionStart` by walking off the panel.
  let wander = selfEdgeClip("wander-off-left-in-right", pose: .standing, fidgetGroup: "idle")
  let choreographer = Choreographer(
    manifest: manifest([idle, starting, wander]), clock: { clock() }, fidgetChance: 0)

  // Standing there already: the arrival has nothing to do, so it settles into
  // the standing loop rather than removing the mascot in order to bring it back.
  #expect(choreographer.clip(for: .starting, displayed: idle, ledger: PhaseLedger())?.id == "idle")
}

@Test @MainActor
func theEntranceStillPlaysFromOffScreen() {
  let clock = FakeClock()
  let idle = loopClip("idle", pose: .standing, group: "idle")
  let starting = edgeClip("starting", from: .offBottom, to: .standing)
  let walkInLeft = edgeClip("walk-in-left", from: .offLeft, to: .standing)
  let walkOffLeft = edgeClip("walk-off-left", from: .standing, to: .offLeft)
  let choreographer = Choreographer(
    manifest: manifest([idle, starting, walkInLeft, walkOffLeft]), clock: { clock() })

  // Nothing on screen at all (a dark panel, or a fresh launch): rise.
  #expect(
    choreographer.clip(for: .starting, displayed: nil, ledger: PhaseLedger())?.id == "starting")
  // Off to one side, because it walked off: come back the way it went, not up
  // through the floor.
  #expect(
    choreographer.clip(for: .starting, displayed: walkOffLeft, ledger: PhaseLedger())?.id
      == "walk-in-left")
}

@Test @MainActor
func leavingWalksOffThePanel() {
  let clock = FakeClock()
  let idle = loopClip("idle", pose: .standing, group: "idle")
  let walkOffLeft = edgeClip("walk-off-left", from: .standing, to: .offLeft)
  let walkOffRight = edgeClip("walk-off-right", from: .standing, to: .offRight)
  let choreographer = Choreographer(
    manifest: manifest([idle, walkOffLeft, walkOffRight]), clock: { clock() })

  let exit = choreographer.clip(for: .away, displayed: idle, ledger: PhaseLedger())
  #expect(exit?.id == "walk-off-left" || exit?.id == "walk-off-right")
  #expect(exit?.toPose?.isOffscreen == true)
}

@Test @MainActor
func leavingFromDozingStandsUpFirst() {
  let clock = FakeClock()
  let sleeping = loopClip("sleeping", pose: .dozing, group: "sleeping")
  let dozeToStand = edgeClip("doze-to-stand", from: .dozing, to: .standing)
  let walkOffLeft = edgeClip("walk-off-left", from: .standing, to: .offLeft)
  let walkOffRight = edgeClip("walk-off-right", from: .standing, to: .offRight)
  let choreographer = Choreographer(
    manifest: manifest([sleeping, dozeToStand, walkOffLeft, walkOffRight]), clock: { clock() })

  // One edge at a time: the mascot has to get up before it can walk anywhere,
  // and the route is found without anything spelling it out.
  #expect(
    choreographer.clip(for: .away, displayed: sleeping, ledger: PhaseLedger())?.id
      == "doze-to-stand")
}

@Test @MainActor
func leavingResolvesToNothingOnceAlreadyGone() {
  let clock = FakeClock()
  let walkOffLeft = edgeClip("walk-off-left", from: .standing, to: .offLeft)
  let choreographer = Choreographer(
    manifest: manifest([walkOffLeft]), clock: { clock() })

  // Already off screen: there is no clip for "gone", and `PanelController`
  // reads the arrival off `displayed` rather than expecting one.
  #expect(choreographer.clip(for: .away, displayed: walkOffLeft, ledger: PhaseLedger()) == nil)
}

@Test @MainActor
func leavingResolvesToNothingWhenNoExitExists() {
  let clock = FakeClock()
  // A synthetic manifest, not the shipped one: `sitting` has no edge back to
  // `standing` here, so this proves the graceful-degradation path rather than
  // anything about what the real manifest ships.
  let working = loopClip("working", pose: .sitting, group: "working")
  let walkOffLeft = edgeClip("walk-off-left", from: .standing, to: .offLeft)
  let choreographer = Choreographer(
    manifest: manifest([working, walkOffLeft]), clock: { clock() })

  #expect(choreographer.clip(for: .away, displayed: working, ledger: PhaseLedger()) == nil)
}

@Test @MainActor
func sitAndStandRouteThroughTheSitEdges() {
  let clock = FakeClock()
  let idle = loopClip("idle", pose: .standing, group: "idle")
  let working = loopClip("working", pose: .sitting, group: "working")
  let standToSit = edgeClip("stand-to-sit", from: .standing, to: .sitting)
  let sitToStand = edgeClip("sit-to-stand", from: .sitting, to: .standing)
  let choreographer = Choreographer(
    manifest: manifest([idle, working, standToSit, sitToStand]), clock: { clock() })

  // Standing, wants to be sitting: the drawn sit edge, not a direct swap onto `working`.
  #expect(
    choreographer.clip(for: .working, displayed: idle, ledger: PhaseLedger())?.id == "stand-to-sit")

  // Seated, wants to be standing: the reverse edge.
  #expect(
    choreographer.clip(for: .idle, displayed: working, ledger: PhaseLedger())?.id == "sit-to-stand")
}
