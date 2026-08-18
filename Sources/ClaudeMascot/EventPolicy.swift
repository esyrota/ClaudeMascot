import Foundation

/// Maps a decoded `HookEvent` to the `PanelState` it should drive, so the
/// plugin never has to encode meaning — it only forwards raw Claude Code
/// hook names, and this is the single place that interprets them.
enum EventPolicy {
  /// Resolves the `PanelState` for `event`, or `nil` if the event is not
  /// ours to act on.
  ///
  /// `nil` means "ignore this event" — it must NOT fall back to `.idle`.
  /// The retired state file had to resolve malformed contents to *some*
  /// state, so it fell back to `.idle`; an event stream has no such
  /// obligation. An unrecognised event (including `SubagentStop`, which is
  /// real but deliberately unhandled, and any name Claude Code has not yet
  /// defined) simply carries no signal for the panel, and a fallback here
  /// would let it reset the panel mid-turn.
  ///
  /// `event.mode` (`permission_mode`) is intentionally never consulted
  /// here. It reports the session's *configured* mode (`ask`/`allow`), not
  /// whether Claude is currently waiting on a prompt — keying `.waiting`
  /// off it would show `waiting` on every tool call in the default `ask`
  /// mode. `Notification` is the only event that means the panel should
  /// wait.
  static func state(for event: HookEvent) -> PanelState? {
    switch event.event {
    // The entrance, not `.idle`: a new session is the mascot arriving, and
    // `PanelController` settles it into `.idle` once the animation finishes.
    case "SessionStart": return .starting
    case "UserPromptSubmit": return .thinking
    case "PreToolUse": return .working
    case "PostToolUse": return .thinking
    case "Notification": return .waiting
    case "Stop": return .done
    case "SubagentStop": return nil
    case "PreCompact": return .working
    case "SessionEnd": return .off
    default: return nil
    }
  }

  /// Whether `event` announces a new session. `SessionTracker` treats this
  /// as a lifecycle transition — reset the session to `.idle` and raise the
  /// entrance pulse — rather than taking `state(for:)`'s `.starting` at face
  /// value, since `.starting` is never a state a *session* sits in, only a
  /// transition `PanelController` plays (see `PanelState`'s doc comment).
  static func isSessionStart(_ event: HookEvent) -> Bool {
    event.event == "SessionStart"
  }

  /// Whether `event` ends a session. `SessionTracker` removes the session
  /// entirely rather than storing `state(for:)`'s `.off`, since `.off` is a
  /// panel-wide power state, not something one session among several can be
  /// in — the panel only goes `.off` once *every* session has ended this
  /// way.
  static func isSessionEnd(_ event: HookEvent) -> Bool {
    event.event == "SessionEnd"
  }

  /// Whether `event` is a subagent finishing. Unlike every other recognised
  /// event it carries no `PanelState` of its own (see `state(for:)`, which
  /// deliberately maps it to `nil`) — it only decrements the session's
  /// subagent depth, which feeds panel *intensity*, not state.
  static func isSubagentStop(_ event: HookEvent) -> Bool {
    event.event == "SubagentStop"
  }

  /// Whether `event` is a subagent spawning: a `PreToolUse` whose tool is
  /// `Task`. This rides alongside `state(for:)`'s `.working` mapping for the
  /// same event rather than replacing it — a subagent launch is still a
  /// tool call — and increments the session's subagent depth.
  static func isSubagentSpawn(_ event: HookEvent) -> Bool {
    event.event == "PreToolUse" && event.tool == "Task"
  }

  /// Whether `event` ends the assistant's turn. Unlike every other
  /// recognised event, `SessionTracker` cannot take `state(for:)`'s `.done`
  /// at face value here: a `Stop` must not resolve to `.done` until a grace
  /// window has passed with no contradicting activity, so `SessionTracker`
  /// needs to recognise the event itself in order to record a pending done
  /// instead of storing the state this file would otherwise hand it.
  static func isTurnEnd(_ event: HookEvent) -> Bool {
    event.event == "Stop"
  }

  /// Whether `event` starts a new turn. `SessionTracker` resets its
  /// per-turn "did this session do real work" flag on this event rather
  /// than on `state(for:)`'s `.thinking` mapping, since `PostToolUse` maps
  /// to `.thinking` too and must not reset that flag mid-turn.
  static func isTurnStart(_ event: HookEvent) -> Bool {
    event.event == "UserPromptSubmit"
  }

  /// Whether `event` is a tool call, i.e. real work happened. `SessionTracker`
  /// sets its per-turn work flag on this event, separately from `state(for:)`'s
  /// `.working` mapping, because the flag needs to survive past the tool call
  /// itself (through the following `PostToolUse`'s `.thinking`) for as long as
  /// the turn lasts, not just for as long as this one event's state does.
  static func isToolCall(_ event: HookEvent) -> Bool {
    event.event == "PreToolUse"
  }
}
