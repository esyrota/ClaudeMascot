/// Where the mascot's body is. Loop clips live *at* a pose; transition clips
/// are the edges between two of them.
enum Pose: String, Codable, Sendable, CaseIterable {
  case standing, sitting, lying, offLeft, offRight, offBottom

  /// True when the panel is dark at this pose — the mascot has left the screen.
  var isOffscreen: Bool {
    switch self {
    case .offLeft, .offRight, .offBottom:
      return true
    case .standing, .sitting, .lying:
      return false
    }
  }
}
