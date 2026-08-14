import Foundation
import Testing

@testable import ClaudeMascot

@Test(
  "all nine Claude Code events map to the documented PanelState",
  arguments: [
    ("SessionStart", PanelState.idle),
    ("UserPromptSubmit", .thinking),
    ("PreToolUse", .working),
    ("PostToolUse", .thinking),
    ("Notification", .waiting),
    ("Stop", .done),
    ("PreCompact", .working),
    ("SessionEnd", .off),
  ]
)
func eventMapsToExpectedState(name: String, expected: PanelState) {
  let event = HookEvent(event: name, tool: nil, session: nil, mode: nil)
  #expect(EventPolicy.state(for: event) == expected)
}

@Test("SubagentStop is deliberately ignored, not a bug")
func subagentStopMapsToNil() {
  let event = HookEvent(event: "SubagentStop", tool: nil, session: nil, mode: nil)
  #expect(EventPolicy.state(for: event) == nil)
}

@Test("an unrecognised event name maps to nil, never a fallback state")
func unknownEventMapsToNil() {
  let event = HookEvent(event: "Bogus", tool: nil, session: nil, mode: nil)
  #expect(EventPolicy.state(for: event) == nil)
}

@Test("a full payload decodes every field")
func decodeFullPayload() {
  let json = Data(
    #"{"event":"PreToolUse","tool":"Bash","session":"abc-123","mode":"ask"}"#.utf8)
  let event = HookEvent.decode(line: json)
  #expect(
    event
      == HookEvent(event: "PreToolUse", tool: "Bash", session: "abc-123", mode: "ask"))
}

@Test("a minimal payload with only the required key decodes fine")
func decodeMinimalPayload() {
  let json = Data(#"{"event":"Stop"}"#.utf8)
  let event = HookEvent.decode(line: json)
  #expect(event == HookEvent(event: "Stop", tool: nil, session: nil, mode: nil))
}

@Test("malformed JSON decodes to nil rather than throwing")
func decodeMalformedJSON() {
  let json = Data(#"{"event":"#.utf8)
  #expect(HookEvent.decode(line: json) == nil)
}

@Test("JSON missing the required event key decodes to nil")
func decodeMissingEventKey() {
  let json = Data(#"{"tool":"Bash"}"#.utf8)
  #expect(HookEvent.decode(line: json) == nil)
}

@Test("unknown extra keys are ignored, not an error")
func decodeUnknownExtraKeys() {
  let json = Data(#"{"event":"Stop","surprise":true,"nested":{"a":1}}"#.utf8)
  let event = HookEvent.decode(line: json)
  #expect(event == HookEvent(event: "Stop", tool: nil, session: nil, mode: nil))
}
