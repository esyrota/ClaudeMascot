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
  func testBundledFallbackResolvesForAllManifestClips() throws {
    // Create a mock bundled directory with every clip the real manifest
    // lists, using the same fixture GIFs the old per-state test used
    // (fixture filenames match `PanelState.rawValue`, which lines up with
    // every non-transition clip id in the shipped manifest).
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

    // Every state's clip (a synthetic one, id == file == "<state>.gif") should resolve.
    for state in PanelState.allCases {
      let clip = Clip(
        id: state.rawValue,
        file: "\(state.rawValue).gif",
        frameCount: 1,
        duration: 1,
        motion: 1,
        loops: true,
        pose: nil,
        variantGroup: nil,
        fidgetGroup: nil,
        weight: 1,
        fromPose: nil,
        toPose: nil
      )
      let data = try library.data(for: clip)
      XCTAssertGreaterThan(
        data.count, 0, "Animation data should not be empty for clip: \(clip.id)")
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

    let clip = Clip(
      id: "idle", file: "idle.gif", frameCount: 1, duration: 1, motion: 1, loops: true,
      pose: nil, variantGroup: nil, fidgetGroup: nil, weight: 1, fromPose: nil, toPose: nil)

    XCTAssertThrowsError(try library.data(for: clip)) { error in
      guard case AnimationLibraryError.clipNotFound("idle") = error else {
        XCTFail("Expected AnimationLibraryError.clipNotFound(\"idle\"), got \(error)")
        return
      }
    }
  }

  @MainActor
  func testRealBundledManifestLoadsAndReportsStartingMotion() throws {
    // Point straight at the source resources directory the same way
    // `fixturesDirectory` above points at the fixtures, since `swift test`
    // does not put the package's own bundled resources on `Bundle.main`.
    let resourcesDir = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Sources/ClaudeMascot/Resources")
    library.bundleOverride = Bundle(path: resourcesDir.path)

    let manifest = try XCTUnwrap(library.manifest)
    XCTAssertEqual(manifest.version, 1)

    // 3.36s since appear.gif was split: `starting` is now the rise out of the floor
    // alone, and the sway that used to follow it ships as the `dancing` idle variant.
    let starting = try XCTUnwrap(library.clip(id: "starting"))
    XCTAssertEqual(starting.motion, 3.36, accuracy: 0.0001)
  }
}
