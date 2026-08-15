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
}
