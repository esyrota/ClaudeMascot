import Foundation
import Testing

@testable import ClaudeMascot

/// Fake clock the tracker reads instead of `Date()`. Every test advances it
/// explicitly, so tests involving `staleAfter`/`doneCountsFor` (minutes of
/// wall time) finish instantly. Mirrors `PanelControllerTests`' `FakeClock`.
@MainActor
private final class FakeClock {
  private(set) var now: TimeInterval = 1_000

  func advance(_ seconds: TimeInterval) {
    now += seconds
  }

  func callAsFunction() -> TimeInterval { now }
}

private func hook(_ event: String, tool: String? = nil, session: String? = nil) -> HookEvent {
  HookEvent(event: event, tool: tool, session: session, mode: nil)
}

@MainActor
@Test("A's Stop does not cancel B's thinking — the multi-session bug this chunk fixes")
func stopFromOneSessionDoesNotCancelAnothersThinking() {
  let clock = FakeClock()
  let tracker = SessionTracker(clock: clock.callAsFunction)

  tracker.apply(hook("SessionStart", session: "A"))
  tracker.apply(hook("SessionStart", session: "B"))
  tracker.apply(hook("UserPromptSubmit", session: "B"))
  #expect(tracker.derived == .thinking)

  tracker.apply(hook("Stop", session: "A"))

  #expect(tracker.derived == .thinking)
}

@MainActor
@Test("derived reduces across concurrent sessions by full precedence order")
func fullPrecedenceOrdering() {
  let clock = FakeClock()
  let tracker = SessionTracker(clock: clock.callAsFunction)

  tracker.apply(hook("SessionStart", session: "A"))
  tracker.apply(hook("SessionStart", session: "B"))
  tracker.apply(hook("SessionStart", session: "C"))
  tracker.apply(hook("SessionStart", session: "D"))
  tracker.apply(hook("SessionStart", session: "E"))

  // idle, idle, idle, idle, idle -> idle
  #expect(tracker.derived == .idle)

  tracker.apply(hook("Stop", session: "A"))
  // done, idle, idle, idle, idle -> done
  #expect(tracker.derived == .done)

  tracker.apply(hook("UserPromptSubmit", session: "B"))
  // done, thinking -> thinking
  #expect(tracker.derived == .thinking)

  tracker.apply(hook("PreToolUse", session: "C"))
  // done, thinking, working -> working
  #expect(tracker.derived == .working)

  tracker.apply(hook("Notification", session: "D"))
  // done, thinking, working, waiting -> waiting
  #expect(tracker.derived == .waiting)

  // Adding another working/thinking/done session must not unseat waiting.
  tracker.apply(hook("PreToolUse", session: "E"))
  #expect(tracker.derived == .waiting)
}

@MainActor
@Test("a done session decays to idle after doneCountsFor")
func doneDecaysToIdle() {
  let clock = FakeClock()
  let tracker = SessionTracker(clock: clock.callAsFunction, doneCountsFor: 30)

  tracker.apply(hook("SessionStart", session: "A"))
  tracker.apply(hook("Stop", session: "A"))
  #expect(tracker.derived == .done)

  clock.advance(29)
  #expect(tracker.derived == .done)

  clock.advance(2)  // now 31s since doneAt
  #expect(tracker.derived == .idle)
}

@MainActor
@Test("reaping a stuck thinking session past staleAfter restores idle, not off")
func reapingStaleSessionRestoresIdle() {
  let clock = FakeClock()
  let tracker = SessionTracker(clock: clock.callAsFunction, staleAfter: 60)

  tracker.apply(hook("SessionStart", session: "A"))
  tracker.apply(hook("UserPromptSubmit", session: "A"))
  #expect(tracker.derived == .thinking)

  clock.advance(61)
  tracker.reap()

  #expect(tracker.sessionCount == 0)
  #expect(tracker.derived == .idle)
}

@MainActor
@Test("subagent depth increments on Task spawn, decrements on SubagentStop, clamps at zero")
func subagentDepthTracking() {
  let clock = FakeClock()
  let tracker = SessionTracker(clock: clock.callAsFunction)

  tracker.apply(hook("SessionStart", session: "A"))
  #expect(tracker.subagentCount == 0)

  tracker.apply(hook("PreToolUse", tool: "Task", session: "A"))
  tracker.apply(hook("PreToolUse", tool: "Task", session: "A"))
  #expect(tracker.subagentCount == 2)

  tracker.apply(hook("SubagentStop", session: "A"))
  #expect(tracker.subagentCount == 1)

  // Clamp at zero: more stops than spawns must never go negative.
  tracker.apply(hook("SubagentStop", session: "A"))
  tracker.apply(hook("SubagentStop", session: "A"))
  #expect(tracker.subagentCount == 0)
}

@MainActor
@Test("SubagentStop alone does not change the session's state")
func subagentStopDoesNotChangeState() {
  let clock = FakeClock()
  let tracker = SessionTracker(clock: clock.callAsFunction)

  tracker.apply(hook("SessionStart", session: "A"))
  tracker.apply(hook("PreToolUse", tool: "Task", session: "A"))
  #expect(tracker.derived == .working)

  tracker.apply(hook("SubagentStop", session: "A"))
  #expect(tracker.derived == .working)
}

@MainActor
@Test("SessionEnd of the last session yields off; a fresh SessionStart clears it")
func sessionEndYieldsOffUntilNewSessionStart() {
  let clock = FakeClock()
  let tracker = SessionTracker(clock: clock.callAsFunction)

  tracker.apply(hook("SessionStart", session: "A"))
  tracker.apply(hook("SessionEnd", session: "A"))

  #expect(tracker.derived == .off)

  tracker.apply(hook("SessionStart", session: "A"))
  #expect(tracker.derived == .idle)
}

@MainActor
@Test("a tracker that has never seen a session reads idle, not off")
func neverHadASessionReadsIdle() {
  let clock = FakeClock()
  let tracker = SessionTracker(clock: clock.callAsFunction)

  #expect(tracker.derived == .idle)
  #expect(tracker.sessionCount == 0)
}

@MainActor
@Test("nil session ids collapse to one implicit session")
func nilSessionIdsCollapseToOneImplicitSession() {
  let clock = FakeClock()
  let tracker = SessionTracker(clock: clock.callAsFunction)

  tracker.apply(hook("SessionStart", session: nil))
  tracker.apply(hook("UserPromptSubmit", session: nil))
  #expect(tracker.sessionCount == 1)
  #expect(tracker.derived == .thinking)

  tracker.apply(hook("Stop", session: nil))
  #expect(tracker.sessionCount == 1)
  #expect(tracker.derived == .done)
}

@MainActor
@Test("the entrance pulse is consumed exactly once")
func entrancePulseConsumedOnce() {
  let clock = FakeClock()
  let tracker = SessionTracker(clock: clock.callAsFunction)

  #expect(tracker.takeEntranceRequest() == false)

  tracker.apply(hook("SessionStart", session: "A"))
  #expect(tracker.takeEntranceRequest() == true)
  #expect(tracker.takeEntranceRequest() == false)
}

@MainActor
@Test("unknown event names change nothing and return false")
func unknownEventIsNotMeaningful() {
  let clock = FakeClock()
  let tracker = SessionTracker(clock: clock.callAsFunction)

  let meaningful = tracker.apply(hook("Bogus", session: "A"))

  #expect(meaningful == false)
  #expect(tracker.sessionCount == 0)
  #expect(tracker.derived == .idle)
}
