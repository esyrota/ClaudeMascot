import Foundation

/// A single decoded hook payload sent by the plugin relay over the app's
/// Unix domain socket, one JSON object per connection, newline-terminated.
///
/// The wire keys are short (`event`, `tool`, `session`, `mode`) rather than
/// the Claude Code hook field names (`hook_event_name`, `tool_name`,
/// `session_id`, `permission_mode`) because the relay shell script writes
/// them by hand; short keys keep that script simple. `event` is the only
/// required key — everything else is optional and decodes to `nil` when the
/// relay omits it. Unknown or extra keys in the payload are ignored, never
/// an error.
struct HookEvent: Codable, Sendable, Equatable {
  let event: String
  let tool: String?
  let session: String?
  let mode: String?
}

extension HookEvent {
  /// Decodes one line of relay JSON, or `nil` if it is malformed or missing
  /// the required `event` key. Never throws: the relay is a shell script
  /// talking to a socket, and callers should be able to drop a bad line
  /// without reasoning about a decoding error.
  static func decode(line: Data) -> HookEvent? {
    try? JSONDecoder().decode(HookEvent.self, from: line)
  }
}
