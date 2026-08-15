import Foundation
import XCTest

@testable import ClaudeMascot

private let fixturesDirectory: URL = {
  URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures")
}()

final class AnimationLibraryTests: XCTestCase {
  var library: AnimationLibrary!

  override func setUp() {
    super.setUp()
    library = AnimationLibrary()
  }

  override func tearDown() {
    library = nil
    super.tearDown()
  }

  @MainActor
  func testBundledFallbackResolvesForAllStates() throws {
    // Create a mock bundled directory with all states
    let tmpID = UUID().uuidString
    let bundledDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(tmpID)
    try FileManager.default.createDirectory(
      at: bundledDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: bundledDir) }

    let animationsDir =
      bundledDir
      .appendingPathComponent("Animations")
    try FileManager.default.createDirectory(at: animationsDir, withIntermediateDirectories: true)

    // Copy fixture GIFs to the mock bundled directory
    for state in PanelState.allCases {
      let sourceURL = fixturesDirectory.appendingPathComponent("\(state.rawValue).gif")
      let destURL =
        animationsDir
        .appendingPathComponent("\(state.rawValue).gif")
      if FileManager.default.fileExists(atPath: sourceURL.path) {
        try FileManager.default.copyItem(
          at: sourceURL, to: destURL)
      }
    }

    // Inject the mock bundle
    let mockBundle = Bundle(path: bundledDir.path)
    library.bundleOverride = mockBundle

    // All states should resolve
    for state in PanelState.allCases {
      let url = library.url(for: state)
      XCTAssertNotNil(url, "Should find animation for state: \(state.rawValue)")

      // Verify we can read the data
      let data = try library.data(for: state)
      XCTAssertGreaterThan(
        data.count, 0, "Animation data should not be empty for state: \(state.rawValue)")
    }
  }

  @MainActor
  func testUrlReturnsNilForMissingWhenNoBundle() throws {
    // No bundleOverride is set, and the test target bundles no Animations
    // resource of its own, so nothing can resolve for any state.
    for state in PanelState.allCases {
      XCTAssertNil(library.url(for: state), "Should not find animation for state: \(state)")
    }
  }

  @MainActor
  func testDataThrowsWhenNotFound() throws {
    // Inject a bundle with an Animations folder that holds no GIFs.
    let bundledDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString)
    let animationsDir = bundledDir.appendingPathComponent("Animations")
    try FileManager.default.createDirectory(at: animationsDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: bundledDir) }

    library.bundleOverride = Bundle(path: bundledDir.path)

    XCTAssertThrowsError(try library.data(for: .idle)) { error in
      guard case AnimationLibraryError.notFound(.idle) = error else {
        XCTFail("Expected AnimationLibraryError.notFound(.idle), got \(error)")
        return
      }
    }
  }
}
