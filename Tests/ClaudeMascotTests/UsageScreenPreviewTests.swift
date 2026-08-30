import Foundation
import XCTest

@testable import ClaudeMascot

/// Not an assertion — a darkroom. Writes the generated screen out as a real
/// GIF so it can be looked at, which is the only check this project trusts
/// for anything visual (see `Docs/_logs/2026-08-27. Dozing Dream/Analysis.md`,
/// where every test passed while the art was broken). Skipped unless
/// `USAGE_SCREEN_PREVIEW` names an output path.
final class UsageScreenPreviewTests: XCTestCase {
  func testWritePreview() throws {
    guard let path = ProcessInfo.processInfo.environment["USAGE_SCREEN_PREVIEW"] else {
      throw XCTSkip("set USAGE_SCREEN_PREVIEW to a path to write the preview")
    }
    let now = Date(timeIntervalSince1970: 1_756_400_000)
    let snapshot = UsageSnapshot(
      usedPercent: 34, resetsAt: now.addingTimeInterval(3 * 3600 + 2400), receivedAt: now,
      weekUsedPercent: 66, weekResetsAt: now.addingTimeInterval(2 * 86400 + 14 * 3600))
    let image = try XCTUnwrap(UsageScreen.render(snapshot, at: now))
    try GifEncoder.encode(image).write(to: URL(fileURLWithPath: path))
    print("wrote \(image.frames.count) frames to \(path)")
  }
}
