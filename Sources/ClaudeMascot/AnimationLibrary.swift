import Foundation

/// Resolves animation GIFs for panel states, respecting user overrides.
@MainActor final class AnimationLibrary {
  /// Optional user folder that overrides the bundled art.
  var overrideFolder: URL?

  /// For testing: allows overriding the bundle to load animations from.
  var bundleOverride: Bundle?

  /// Resolves the URL for an animation in this precedence order:
  /// 1. `<overrideFolder>/custom/<state>.gif`
  /// 2. `<overrideFolder>/<state>.gif`
  /// 3. bundled `Animations/<state>.gif`
  /// Returns `nil` if nothing is found.
  func url(for state: PanelState) -> URL? {
    let filename = "\(state.rawValue).gif"

    // Check override folder custom subdirectory
    if let override = overrideFolder {
      let customPath = override.appendingPathComponent("custom").appendingPathComponent(filename)
      if fileExists(at: customPath) {
        return customPath
      }
    }

    // Check override folder root
    if let override = overrideFolder {
      let overridePath = override.appendingPathComponent(filename)
      if fileExists(at: overridePath) {
        return overridePath
      }
    }

    // Check bundled animations
    if let bundledURL = bundledURL(for: filename) {
      return bundledURL
    }

    return nil
  }

  /// Returns the data for an animation, following the same resolution order as `url(for:)`.
  /// Throws if the file cannot be read.
  func data(for state: PanelState) throws -> Data {
    guard let url = url(for: state) else {
      throw AnimationLibraryError.notFound(state)
    }
    return try Data(contentsOf: url)
  }

  // MARK: - Private

  private func fileExists(at url: URL) -> Bool {
    FileManager.default.fileExists(atPath: url.path)
  }

  private func bundledURL(for filename: String) -> URL? {
    // Try the injected bundle first (for testing)
    if let bundle = bundleOverride {
      if let bundlePath = bundle.path(forResource: "Animations", ofType: nil) {
        let bundleURL = URL(fileURLWithPath: bundlePath)
        let fileURL = bundleURL.appendingPathComponent(filename)
        if fileExists(at: fileURL) {
          return fileURL
        }
      }
    }

    // Try Bundle.main. Hand-imported art in Animations/custom/ wins over the
    // generated art beside it, mirroring the override-folder precedence above
    // and the Python tooling, which writes imports into that subfolder.
    if let bundlePath = Bundle.main.path(forResource: "Animations", ofType: nil) {
      let bundleURL = URL(fileURLWithPath: bundlePath)
      for candidate in [
        bundleURL.appendingPathComponent("custom").appendingPathComponent(filename),
        bundleURL.appendingPathComponent(filename),
      ] where fileExists(at: candidate) {
        return candidate
      }
    }

    // Fallback: look for animations relative to the executable or in development
    // This handles cases like tests where resources may be in alternate locations
    if let bundleResourcePath = Bundle.main.bundlePath as String? {
      let bundleURL = URL(fileURLWithPath: bundleResourcePath)
      let candidates = [
        bundleURL.appendingPathComponent("Contents/Resources/Animations"),
        bundleURL.appendingPathComponent("Resources/Animations"),
        bundleURL.deletingLastPathComponent().appendingPathComponent("Resources/Animations"),
      ]

      for candidateURL in candidates {
        let fileURL = candidateURL.appendingPathComponent(filename)
        if fileExists(at: fileURL) {
          return fileURL
        }
      }
    }

    return nil
  }
}

enum AnimationLibraryError: LocalizedError {
  case notFound(PanelState)

  var errorDescription: String? {
    switch self {
    case .notFound(let state):
      return "Animation not found for state: \(state.rawValue)"
    }
  }
}
