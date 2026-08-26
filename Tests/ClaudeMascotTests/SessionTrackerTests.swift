import Foundation
import Testing

@testable import ClaudeMascot

/// Fake clock the tracker reads instead of `Date()`. Every test advances it
/// explicitly, so tests involving `staleAfter`/`doneCountsFor`/`settleAfter`
/// (minutes of wall time) finish instantly. Mirrors `PanelControllerTests`'
/// `FakeClock`.
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
  let tracker = SessionTracker(clock: clock.callAsFunction, doneCountsFor: 30, settleAfter: 5)

  tracker.apply(hook("SessionStart", session: "A"))
  tracker.apply(hook("SessionStart", session: "B"))
  tracker.apply(hook("SessionStart", session: "C"))
  tracker.apply(hook("SessionStart", session: "D"))
  tracker.apply(hook("SessionStart", session: "E"))

  // idle, idle, idle, idle, idle -> idle
  #expect(tracker.derived == .idle)

  // A did real work before Stop, and enough time has passed to settle to done.
  tracker.apply(hook("UserPromptSubmit", session: "A"))
  tracker.apply(hook("PreToolUse", session: "A"))
  tracker.apply(hook("Stop", session: "A"))
  clock.advance(6)  // past settleAfter
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
@Test("a done session decays to idle after settleAfter + doneCountsFor")
func doneDecaysToIdle() {
  let clock = FakeClock()
  let tracker = SessionTracker(
    clock: clock.callAsFunction, doneCountsFor: 30, settleAfter: 5)

  tracker.apply(hook("SessionStart", session: "A"))
  tracker.apply(hook("UserPromptSubmit", session: "A"))
  tracker.apply(hook("PreToolUse", session: "A"))
  tracker.apply(hook("Stop", session: "A"))

  // Still within the settle window: reads as whatever it was doing
  // (working, from the seating rule), not done yet.
  #expect(tracker.derived == .working)

  clock.advance(5)  // now exactly at settleAfter
  #expect(tracker.derived == .done)

  clock.advance(29)  // 34s since pendingDoneAt, still < settleAfter + doneCountsFor (35)
  #expect(tracker.derived == .done)

  clock.advance(2)  // now 36s since pendingDoneAt
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
@Test("SessionEnd of the last session yields off once settled; a fresh SessionStart clears it")
func sessionEndYieldsOffUntilNewSessionStart() {
  let clock = FakeClock()
  let tracker = SessionTracker(clock: clock.callAsFunction, settleAfter: 5)

  tracker.apply(hook("SessionStart", session: "A"))
  tracker.apply(hook("SessionEnd", session: "A"))
  clock.advance(5)  // past settleAfter

  #expect(tracker.derived == .off)

  tracker.reap()
  #expect(tracker.sessionCount == 0)

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
  let tracker = SessionTracker(clock: clock.callAsFunction, settleAfter: 5)

  tracker.apply(hook("SessionStart", session: nil))
  tracker.apply(hook("UserPromptSubmit", session: nil))
  #expect(tracker.sessionCount == 1)
  #expect(tracker.derived == .thinking)

  tracker.apply(hook("PreToolUse", session: nil))
  tracker.apply(hook("Stop", session: nil))
  clock.advance(5)
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

// MARK: - Chunk 2: seating, done-debounce, and end-debounce

@MainActor
@Test("a prompt with no tool call yet derives thinking")
func promptWithNoToolCallDerivesThinking() {
  let clock = FakeClock()
  let tracker = SessionTracker(clock: clock.callAsFunction)

  tracker.apply(hook("SessionStart", session: "A"))
  tracker.apply(hook("UserPromptSubmit", session: "A"))

  #expect(tracker.derived == .thinking)
}

@MainActor
@Test("after one PreToolUse, PostToolUse still derives working — the seating case")
func postToolUseAfterWorkStaysWorking() {
  let clock = FakeClock()
  let tracker = SessionTracker(clock: clock.callAsFunction)

  tracker.apply(hook("SessionStart", session: "A"))
  tracker.apply(hook("UserPromptSubmit", session: "A"))
  tracker.apply(hook("PreToolUse", session: "A"))
  #expect(tracker.derived == .working)

  tracker.apply(hook("PostToolUse", session: "A"))
  #expect(tracker.derived == .working)
}

@MainActor
@Test("a new UserPromptSubmit returns to thinking — the per-turn flag resets")
func newPromptResetsSeatingFlag() {
  let clock = FakeClock()
  let tracker = SessionTracker(clock: clock.callAsFunction)

  tracker.apply(hook("SessionStart", session: "A"))
  tracker.apply(hook("UserPromptSubmit", session: "A"))
  tracker.apply(hook("PreToolUse", session: "A"))
  tracker.apply(hook("PostToolUse", session: "A"))
  #expect(tracker.derived == .working)

  tracker.apply(hook("UserPromptSubmit", session: "A"))
  #expect(tracker.derived == .thinking)
}

@MainActor
@Test("the 12:12:33 case: Stop mid-tool never resolves to done, even well past settleAfter")
func stopMidToolNeverBecomesDone() {
  let clock = FakeClock()
  let tracker = SessionTracker(clock: clock.callAsFunction, doneCountsFor: 30, settleAfter: 5)

  tracker.apply(hook("SessionStart", session: "1e27"))
  tracker.apply(hook("UserPromptSubmit", session: "1e27"))
  tracker.apply(hook("PreToolUse", session: "1e27"))
  tracker.apply(hook("Stop", session: "1e27"))
  tracker.apply(hook("PostToolUse", session: "1e27"))  // 0s later, contradicts the pending Stop

  clock.advance(120)  // well past settleAfter + doneCountsFor
  #expect(tracker.derived == .working)
  #expect(tracker.derived != .done)
}

@MainActor
@Test(
  "a Stop after real work derives done past settleAfter, and idle past settleAfter + doneCountsFor")
func stopAfterRealWorkEarnsDoneThenExpires() {
  let clock = FakeClock()
  let tracker = SessionTracker(clock: clock.callAsFunction, doneCountsFor: 30, settleAfter: 5)

  tracker.apply(hook("SessionStart", session: "A"))
  tracker.apply(hook("UserPromptSubmit", session: "A"))
  tracker.apply(hook("PreToolUse", session: "A"))
  tracker.apply(hook("Stop", session: "A"))

  clock.advance(4)  // still inside settleAfter
  #expect(tracker.derived != .done)

  clock.advance(1)  // now exactly at settleAfter (5s total)
  #expect(tracker.derived == .done)

  clock.advance(30)  // 35s since pendingDoneAt == settleAfter + doneCountsFor
  #expect(tracker.derived == .idle)
}

@MainActor
@Test("a work-free turn derives idle on Stop, never done")
func workFreeTurnNeverEarnsDone() {
  let clock = FakeClock()
  let tracker = SessionTracker(clock: clock.callAsFunction, doneCountsFor: 30, settleAfter: 5)

  tracker.apply(hook("SessionStart", session: "A"))
  tracker.apply(hook("UserPromptSubmit", session: "A"))
  tracker.apply(hook("Stop", session: "A"))

  clock.advance(5)
  #expect(tracker.derived == .idle)

  clock.advance(30)
  #expect(tracker.derived == .idle)
}

@MainActor
@Test("during the grace window the session still derives what it was doing")
func duringGraceWindowStateIsUnchanged() {
  let clock = FakeClock()
  let tracker = SessionTracker(clock: clock.callAsFunction, doneCountsFor: 30, settleAfter: 5)

  tracker.apply(hook("SessionStart", session: "A"))
  tracker.apply(hook("UserPromptSubmit", session: "A"))
  tracker.apply(hook("PreToolUse", session: "A"))
  #expect(tracker.derived == .working)

  tracker.apply(hook("Stop", session: "A"))
  // Immediately after Stop, still inside the grace window: the seating
  // rule still applies because didWorkThisTurn holds and state is
  // unchanged by Stop.
  #expect(tracker.derived == .working)

  clock.advance(4)
  #expect(tracker.derived == .working)
}

@MainActor
@Test("the 12:13:23 case: SessionEnd followed by PreToolUse never derives off")
func sessionEndFollowedByToolUseNeverGoesOff() {
  let clock = FakeClock()
  let tracker = SessionTracker(clock: clock.callAsFunction, settleAfter: 5)

  tracker.apply(hook("SessionStart", session: "1e27"))
  tracker.apply(hook("SessionEnd", session: "1e27"))
  tracker.apply(hook("PreToolUse", session: "1e27"))  // contradicts the pending end

  clock.advance(600)  // ten minutes, well past settleAfter
  #expect(tracker.derived == .working)
  #expect(tracker.derived != .off)
}

@MainActor
@Test(
  "a SessionEnd with nothing following derives off once past settleAfter, and reap empties the tracker"
)
func sessionEndAloneSettlesToOffAndReaps() {
  let clock = FakeClock()
  let tracker = SessionTracker(clock: clock.callAsFunction, settleAfter: 5)

  tracker.apply(hook("SessionStart", session: "A"))
  tracker.apply(hook("SessionEnd", session: "A"))

  clock.advance(4)
  #expect(tracker.derived != .off)

  clock.advance(1)  // now at settleAfter
  #expect(tracker.derived == .off)

  tracker.reap()
  #expect(tracker.sessionCount == 0)
  #expect(tracker.derived == .off)
}

@MainActor
@Test("a session sitting in a pending state is still reaped by staleAfter")
func pendingSessionIsStillReapedByStaleness() {
  let clock = FakeClock()
  let tracker = SessionTracker(clock: clock.callAsFunction, staleAfter: 60, settleAfter: 5)

  tracker.apply(hook("SessionStart", session: "A"))
  tracker.apply(hook("UserPromptSubmit", session: "A"))
  tracker.apply(hook("PreToolUse", session: "A"))
  tracker.apply(hook("Stop", session: "A"))  // pendingDoneAt set, never settles or contradicts

  clock.advance(61)  // past staleAfter
  tracker.reap()

  #expect(tracker.sessionCount == 0)
  #expect(tracker.derived == .idle)
}

@MainActor
@Test("multi-session priority reduction still holds with pending states in play")
func multiSessionPriorityReductionHoldsWithPendingStates() {
  let clock = FakeClock()
  let tracker = SessionTracker(clock: clock.callAsFunction, settleAfter: 5)

  tracker.apply(hook("SessionStart", session: "A"))
  tracker.apply(hook("SessionStart", session: "B"))

  tracker.apply(hook("PreToolUse", session: "A"))
  #expect(tracker.derived == .working)

  tracker.apply(hook("Notification", session: "B"))
  // waiting outranks working.
  #expect(tracker.derived == .waiting)
}

@MainActor
@Test("an AskUserQuestion round trip reaches waiting and then goes back to work")
func askUserQuestionDrivesWaitingEndToEnd() {
  let clock = FakeClock()
  let tracker = SessionTracker(clock: clock.callAsFunction)

  // The real 23:21:42 → 23:23:26 sequence from input.jsonl, which is the
  // evidence that `waiting` was reachable all along without a plugin change.
  tracker.apply(hook("SessionStart", session: "A"))
  tracker.apply(hook("UserPromptSubmit", session: "A"))
  tracker.apply(hook("PreToolUse", tool: "Bash", session: "A"))
  tracker.apply(hook("PostToolUse", tool: "Bash", session: "A"))
  #expect(tracker.derived == .working)

  tracker.apply(hook("PreToolUse", tool: "AskUserQuestion", session: "A"))
  #expect(tracker.derived == .waiting)

  // 104 seconds of a human reading the question. Nothing else arrives, and
  // the mascot must still be waving at the end of it.
  clock.advance(104)
  #expect(tracker.derived == .waiting)

  // Answered: `PostToolUse` maps to `.thinking`, which the seating rule
  // reads as `.working` because the turn has done real work.
  tracker.apply(hook("PostToolUse", tool: "AskUserQuestion", session: "A"))
  #expect(tracker.derived == .working)
}

@MainActor
@Test("a question in one session outranks another session's work")
func waitingOutranksAConcurrentWorkingSession() {
  let clock = FakeClock()
  let tracker = SessionTracker(clock: clock.callAsFunction)

  tracker.apply(hook("SessionStart", session: "A"))
  tracker.apply(hook("SessionStart", session: "B"))
  tracker.apply(hook("PreToolUse", tool: "Bash", session: "B"))
  #expect(tracker.derived == .working)

  tracker.apply(hook("PreToolUse", tool: "AskUserQuestion", session: "A"))
  #expect(tracker.derived == .waiting)
}

@MainActor
@Test("a turn whose only tool call was a question has nothing to celebrate")
func questionOnlyTurnDoesNotCelebrate() {
  let clock = FakeClock()
  let tracker = SessionTracker(clock: clock.callAsFunction, doneCountsFor: 30, settleAfter: 5)

  tracker.apply(hook("SessionStart", session: "A"))
  tracker.apply(hook("UserPromptSubmit", session: "A"))
  tracker.apply(hook("PreToolUse", tool: "AskUserQuestion", session: "A"))
  tracker.apply(hook("PostToolUse", tool: "AskUserQuestion", session: "A"))
  // Asking is the assistant *not* working, so the answer must not seat it at
  // a desk where nothing has been done.
  #expect(tracker.derived == .thinking)

  tracker.apply(hook("Stop", session: "A"))
  clock.advance(6)
  #expect(tracker.derived == .idle)
}

@MainActor
@Test("a question in the middle of real work still leaves the turn worth celebrating")
func questionDoesNotEraseEarlierWork() {
  let clock = FakeClock()
  let tracker = SessionTracker(clock: clock.callAsFunction, doneCountsFor: 30, settleAfter: 5)

  tracker.apply(hook("SessionStart", session: "A"))
  tracker.apply(hook("UserPromptSubmit", session: "A"))
  tracker.apply(hook("PreToolUse", tool: "Bash", session: "A"))
  tracker.apply(hook("PostToolUse", tool: "Bash", session: "A"))
  tracker.apply(hook("PreToolUse", tool: "AskUserQuestion", session: "A"))
  tracker.apply(hook("PostToolUse", tool: "AskUserQuestion", session: "A"))

  tracker.apply(hook("Stop", session: "A"))
  clock.advance(6)
  #expect(tracker.derived == .done)
}
