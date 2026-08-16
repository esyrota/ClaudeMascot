/// Where the mascot's body is. Loop clips live *at* a pose; transition clips
/// are the edges between two of them.
enum Pose: String, Codable, Sendable, CaseIterable {
  // `dozing` was `lying` until the mascot stopped sleeping as a blob on the floor.
  // It sleeps on its feet now, but the slumped shape — arms down on the legs, eyes
  // shut — is still a resting place of its own rather than a dressed-up `standing`,
  // which is what lets `stand-to-doze` and `doze-to-stand` be real edges.
  case standing, sitting, dozing, offLeft, offRight, offBottom

  /// True when the panel is dark at this pose — the mascot has left the screen.
  var isOffscreen: Bool {
    switch self {
    case .offLeft, .offRight, .offBottom:
      return true
    case .standing, .sitting, .dozing:
      return false
    }
  }
}
