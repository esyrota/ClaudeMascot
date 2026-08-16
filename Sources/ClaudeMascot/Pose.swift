/// Where the mascot's body is. Loop clips live *at* a pose; transition clips
/// are the edges between two of them.
enum Pose: String, Codable, Sendable, CaseIterable {
  // `lying` used to be here, for a mascot that slept as a blob on the floor. It
  // sleeps standing now, so no clip declared it and no state resolved to it — a
  // pose nothing can be at is a node the pathfinder can only ever fail to reach.
  case standing, sitting, offLeft, offRight, offBottom

  /// True when the panel is dark at this pose — the mascot has left the screen.
  var isOffscreen: Bool {
    switch self {
    case .offLeft, .offRight, .offBottom:
      return true
    case .standing, .sitting:
      return false
    }
  }
}
