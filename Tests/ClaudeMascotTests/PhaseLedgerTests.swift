import Foundation
import Testing

@testable import ClaudeMascot

/// A non-looping self-edge fidget at `.sitting`, with the two caps this
/// ledger enforces. Matches the shape `ChoreographerTests.selfEdgeClip`
/// builds, kept local here since this file must not touch existing tests.
private func fidgetClip(
  _ id: String, maxPerPhase: Int? = nil, maxRepeats: Int? = nil
) -> Clip {
  Clip(
    id: id, file: "\(id).gif", frameCount: 1, duration: 1, motion: 1, loops: false,
    pose: nil, variantGroup: nil, fidgetGroup: nil, weight: 1,
    fromPose: .sitting, toPose: .sitting, maxPerPhase: maxPerPhase, maxRepeats: maxRepeats,
    interruptible: false, minCycles: nil)
}

/// A looping clip at `.sitting` — the group's own variant, used to prove a
/// loop in between two fidget plays does not break the fidget's run.
private func loopingClip(_ id: String) -> Clip {
  Clip(
    id: id, file: "\(id).gif", frameCount: 1, duration: 1, motion: 1, loops: true,
    pose: .sitting, variantGroup: "sitting", fidgetGroup: nil, weight: 1,
    fromPose: nil, toPose: nil, maxPerPhase: nil, maxRepeats: nil, interruptible: false,
    minCycles: nil)
}

@Test("a fresh ledger allows everything, including capped clips")
func freshLedgerAllowsEverything() {
  let ledger = PhaseLedger()
  let capped = fidgetClip("dream", maxPerPhase: 1, maxRepeats: 1)
  #expect(ledger.allows(capped))
}

@Test("maxPerPhase: 1 refuses after one play, until a different group starts a new phase")
func maxPerPhaseGatesOncePerPhase() {
  var ledger = PhaseLedger()
  ledger.enterPhase("dozing")
  let dream = fidgetClip("doze-dream", maxPerPhase: 1)

  #expect(ledger.allows(dream))
  ledger.record(dream)
  #expect(!ledger.allows(dream))

  // Same group again: the phase does not restart, so it stays refused.
  ledger.enterPhase("dozing")
  #expect(!ledger.allows(dream))

  // A different group: a new phase, ledger cleared, allowed again.
  ledger.enterPhase("sitting")
  #expect(ledger.allows(dream))
}

@Test("maxRepeats: 1 refuses immediately after playing, allowed again after a different fidget")
func maxRepeatsGatesConsecutivePlays() {
  var ledger = PhaseLedger()
  ledger.enterPhase("sitting")
  let coffee = fidgetClip("work-coffee", maxRepeats: 1)
  let stretch = fidgetClip("fidget-stretch")

  ledger.record(coffee)
  #expect(!ledger.allows(coffee))

  ledger.record(stretch)
  #expect(ledger.allows(coffee))
}

@Test("a loop clip recorded between two fidget plays does not reset the run")
func loopBetweenFidgetsDoesNotBreakTheRun() {
  var ledger = PhaseLedger()
  ledger.enterPhase("sitting")
  let coffee = fidgetClip("work-coffee", maxRepeats: 1)
  let sittingLoop = loopingClip("sitting")

  ledger.record(coffee)
  #expect(!ledger.allows(coffee))

  ledger.record(sittingLoop)
  #expect(!ledger.allows(coffee))
}

@Test("a clip with neither cap is never refused, however many times it is recorded")
func uncappedClipIsNeverRefused() {
  var ledger = PhaseLedger()
  ledger.enterPhase("sitting")
  let plain = fidgetClip("fidget-look")

  for _ in 0..<5 {
    #expect(ledger.allows(plain))
    ledger.record(plain)
  }
  #expect(ledger.allows(plain))
}
