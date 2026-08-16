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
private func loopClip(_ id: String, pose: Pose, group: String, weight: Double = 1.0, duration: TimeInterval = 1)
  -> Clip
{
  Clip(
    id: id, file: "\(id).gif", frameCount: 1, duration: duration, motion: duration, loops: true,
    pose: pose, variantGroup: group, weight: weight, fromPose: nil, toPose: nil)
}

/// A non-looping transition edge between two different poses.
private func edgeClip(_ id: String, from: Pose, to: Pose, motion: TimeInterval = 1, duration: TimeInterval = 5)
  -> Clip
{
  Clip(
    id: id, file: "\(id).gif", frameCount: 1, duration: duration, motion: motion, loops: false,
    pose: nil, variantGroup: nil, weight: 1, fromPose: from, toPose: to)
}

/// A non-looping self-edge at `pose` — the shape both `"<group>-enter"`
/// one-shots and fidgets have (`fromPose == toPose`).
private func selfEdgeClip(_ id: String, pose: Pose, motion: TimeInterval = 1, duration: TimeInterval = 1) -> Clip {
  Clip(
    id: id, file: "\(id).gif", frameCount: 1, duration: duration, motion: motion, loops: false,
    pose: nil, variantGroup: nil, weight: 1, fromPose: pose, toPose: pose)
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
  let idle = loopClip("idle", pose: .standing, group: "idle")
  let sleeping = loopClip("sleeping", pose: .lying, group: "sleeping")
  let standSit = edgeClip("stand-sit", from: .standing, to: .sitting)
  let sitLie = edgeClip("sit-lie", from: .sitting, to: .lying)
  let choreographer = Choreographer(
    manifest: manifest([idle, sleeping, standSit, sitLie]), clock: { clock() })

  // Standing, wants to be lying: only the first edge comes back.
  let first = choreographer.clip(for: .sleeping, displayed: idle)
  #expect(first?.id == "stand-sit")

  // Same call again, nothing displayed yet: identical answer (idempotent).
  let firstAgain = choreographer.clip(for: .sleeping, displayed: idle)
  #expect(firstAgain?.id == "stand-sit")

  // Only once the first edge is actually displayed does the second appear.
  let second = choreographer.clip(for: .sleeping, displayed: standSit)
  #expect(second?.id == "sit-lie")
}

@Test @MainActor
func targetFlippingMidJourneyIsSelfCorrecting() {
  let clock = FakeClock()
  let idle = loopClip("idle", pose: .standing, group: "idle")
  let sleeping = loopClip("sleeping", pose: .lying, group: "sleeping")
  let standSit = edgeClip("stand-sit", from: .standing, to: .sitting)
  let sitStand = edgeClip("sit-stand", from: .sitting, to: .standing)
  let sitLie = edgeClip("sit-lie", from: .sitting, to: .lying)
  let choreographer = Choreographer(
    manifest: manifest([idle, sleeping, standSit, sitStand, sitLie]), clock: { clock() })

  // Walking toward .sleeping: first edge lands us at sitting.
  let firstEdge = choreographer.clip(for: .sleeping, displayed: idle)
  #expect(firstEdge?.id == "stand-sit")

  // The world changes its mind before the second edge plays: target flips
  // back to .idle (standing). From sitting, that's a single edge back —
  // not a continuation of the walk toward lying.
  let corrected = choreographer.clip(for: .idle, displayed: standSit)
  #expect(corrected?.id == "sit-stand")
}

// MARK: - Graceful degradation

@Test @MainActor
func noPathDegradesToADirectSwap() {
  let clock = FakeClock()
  let idle = loopClip("idle", pose: .standing, group: "idle")
  let working = loopClip("working", pose: .sitting, group: "working")
  // No edges at all in this manifest — today's real manifest, basically.
  let choreographer = Choreographer(manifest: manifest([idle, working]), clock: { clock() })

  let resolved = choreographer.clip(for: .working, displayed: idle)
  #expect(resolved?.id == "working")
}

// MARK: - Determinism

@Test @MainActor
func sameInputsReturnIdenticalClipWithinAnEpoch() {
  let clock = FakeClock()
  let a = loopClip("idle-a", pose: .standing, group: "idle", weight: 1)
  let b = loopClip("idle-b", pose: .standing, group: "idle", weight: 1)
  let choreographer = Choreographer(manifest: manifest([a, b]), clock: { clock() }, fidgetChance: 0)

  // The exact same (target, displayed, now) triple, called three times: no
  // stored state means no run of calls can see a different answer than the
  // first.
  let first = choreographer.clip(for: .idle, displayed: a)
  let second = choreographer.clip(for: .idle, displayed: a)
  let third = choreographer.clip(for: .idle, displayed: a)
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
    let picked = choreographer.clip(for: .idle, displayed: displayed)
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
    let picked = choreographer.clip(for: .idle, displayed: displayed)!
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
  let onArrival = choreographer.clip(for: .done, displayed: idle)
  #expect(onArrival?.id == "done-enter")

  // Once the entrance itself is what's displayed, asking again must not
  // replay it — it falls through to the settled loop.
  let settled = choreographer.clip(for: .done, displayed: doneEnter)
  #expect(settled?.id == "done")

  // And it stays settled on subsequent calls.
  let stillSettled = choreographer.clip(for: .done, displayed: settled)
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
    manifest: manifest([idle, blink]), clock: { clock() }, rotationPeriod: rotationPeriod, fidgetChance: 1)
  let picked = withFidget.clip(for: .idle, displayed: idle)
  #expect(picked?.id == "blink")

  // No fidget clips in the manifest at all (today's real manifest): falls
  // through cleanly to the settled loop instead of stalling or crashing.
  let withoutFidgets = Choreographer(
    manifest: manifest([idle]), clock: { clock() }, rotationPeriod: rotationPeriod, fidgetChance: 1)
  let fallenThrough = withoutFidgets.clip(for: .idle, displayed: idle)
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
  let justArrivedAtStanding = choreographer.clip(for: .idle, displayed: sitStand)
  #expect(justArrivedAtStanding?.id != "blink")

  // `.off` never fidgets, even with a matching pose and a forced-due roll.
  let offTarget = choreographer.clip(for: .off, displayed: offLoop)
  #expect(offTarget?.id != "blink")
}
