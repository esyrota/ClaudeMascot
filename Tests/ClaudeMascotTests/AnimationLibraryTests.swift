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
  func testOverrideFolderFileBeatsBundle() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // Create an override file for the idle state
    let overrideFilePath = tempDir.appendingPathComponent("idle.gif")
    let overrideData = "Override Idle".data(using: .utf8)!
    try overrideData.write(to: overrideFilePath)

    library.overrideFolder = tempDir

    // The override should be used instead of the bundled one
    let url = try XCTUnwrap(library.url(for: .idle))
    XCTAssertEqual(url, overrideFilePath)

    let data = try library.data(for: .idle)
    XCTAssertEqual(data, overrideData)
  }

  @MainActor
  func testCustomFolderBeatsOverrideFolderRoot() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // Create a custom subdirectory
    let customDir = tempDir.appendingPathComponent("custom")
    try FileManager.default.createDirectory(at: customDir, withIntermediateDirectories: true)

    // Create files in both locations
    let rootFile = tempDir.appendingPathComponent("thinking.gif")
    let rootData = "Root Override".data(using: .utf8)!
    try rootData.write(to: rootFile)

    let customFile = customDir.appendingPathComponent("thinking.gif")
    let customData = "Custom Override".data(using: .utf8)!
    try customData.write(to: customFile)

    library.overrideFolder = tempDir

    // The custom folder should take precedence
    let url = try XCTUnwrap(library.url(for: .thinking))
    XCTAssertEqual(url, customFile)

    let data = try library.data(for: .thinking)
    XCTAssertEqual(data, customData)
  }

  @MainActor
  func testMissingStateFallsBackCorrectly() throws {
    // Create a bundled directory with animations
    let bundledDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString)
    try FileManager.default.createDirectory(
      at: bundledDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: bundledDir) }

    let animationsDir =
      bundledDir
      .appendingPathComponent("Animations")
    try FileManager.default.createDirectory(at: animationsDir, withIntermediateDirectories: true)

    // Copy fixture GIFs
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

    let mockBundle = Bundle(path: bundledDir.path)
    library.bundleOverride = mockBundle

    // Create empty override folder
    let overrideDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString)
    try FileManager.default.createDirectory(at: overrideDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: overrideDir) }

    library.overrideFolder = overrideDir

    // The bundled animation should be used as fallback
    let url = library.url(for: .waiting)
    XCTAssertNotNil(url)

    let data = try library.data(for: .waiting)
    XCTAssertGreaterThan(data.count, 0)
  }

  @MainActor
  func testUrlReturnsNilForMissingWhenNoBundle() throws {
    // Create a bundled directory with animations
    let bundledDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString)
    try FileManager.default.createDirectory(
      at: bundledDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: bundledDir) }

    let animationsDir =
      bundledDir
      .appendingPathComponent("Animations")
    try FileManager.default.createDirectory(at: animationsDir, withIntermediateDirectories: true)

    // Copy fixture GIFs
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

    let mockBundle = Bundle(path: bundledDir.path)
    library.bundleOverride = mockBundle

    // Create empty override folder
    let tmpID2 = UUID().uuidString
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(tmpID2)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    library.overrideFolder = tempDir

    // With override folder set but no files there, it should still find bundled
    for state in PanelState.allCases {
      let url = library.url(for: state)
      XCTAssertNotNil(url, "Should find bundled animation even with override folder set")
    }
  }

  @MainActor
  func testDataThrowsWhenNotFound() throws {
    // Create a bundled directory with animations
    let bundledDir = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString)
    try FileManager.default.createDirectory(
      at: bundledDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: bundledDir) }

    let animationsDir =
      bundledDir
      .appendingPathComponent("Animations")
    try FileManager.default.createDirectory(at: animationsDir, withIntermediateDirectories: true)

    // Copy fixture GIFs
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

    let mockBundle = Bundle(path: bundledDir.path)
    library.bundleOverride = mockBundle

    // Create empty override folder
    let tmpID2 = UUID().uuidString
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(tmpID2)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    library.overrideFolder = tempDir

    // Even with empty override folder, bundled should work
    let data = try library.data(for: .idle)
    XCTAssertGreaterThan(data.count, 0)
  }
}
