import Foundation
import XCTest

@testable import ClaudeMascot

final class ClipManifestTests: XCTestCase {
  private func data(_ json: String) -> Data {
    Data(json.utf8)
  }

  func testDecodesMsToSecondsAndAttachesId() throws {
    let manifest = try ClipManifest.decode(
      data(
        """
        {
          "version": 1,
          "clips": {
            "idle": {
              "file": "idle.gif",
              "frameCount": 7,
              "durationMs": 2560,
              "motionMs": 2560,
              "loops": true,
              "pose": "standing",
              "variantGroup": "idle",
              "weight": 1.0
            }
          }
        }
        """))

    XCTAssertEqual(manifest.version, 1)
    let clip = try XCTUnwrap(manifest["idle"])
    XCTAssertEqual(clip.id, "idle")
    XCTAssertEqual(clip.file, "idle.gif")
    XCTAssertEqual(clip.frameCount, 7)
    XCTAssertEqual(clip.duration, 2.56, accuracy: 0.0001)
    XCTAssertEqual(clip.motion, 2.56, accuracy: 0.0001)
    XCTAssertTrue(clip.loops)
    XCTAssertEqual(clip.pose, .standing)
    XCTAssertEqual(clip.variantGroup, "idle")
  }

  func testWeightDefaultsToOneWhenAbsent() throws {
    let manifest = try ClipManifest.decode(
      data(
        """
        {
          "version": 1,
          "clips": {
            "starting": {
              "file": "starting.gif",
              "frameCount": 32,
              "durationMs": 8520,
              "motionMs": 5600,
              "loops": false,
              "fromPose": "offBottom",
              "toPose": "standing"
            }
          }
        }
        """))

    let clip = try XCTUnwrap(manifest["starting"])
    XCTAssertEqual(clip.weight, 1.0)
    XCTAssertNil(clip.pose)
    XCTAssertEqual(clip.fromPose, .offBottom)
    XCTAssertEqual(clip.toPose, .standing)
    XCTAssertEqual(clip.motion, 5.6, accuracy: 0.0001)
  }

  func testClipsInGroupSortedById() throws {
    let manifest = try ClipManifest.decode(
      data(
        """
        {
          "version": 1,
          "clips": {
            "idleC": {
              "file": "idleC.gif", "frameCount": 1, "durationMs": 100, "motionMs": 100,
              "loops": true, "pose": "standing", "variantGroup": "idle", "weight": 1.0
            },
            "idleA": {
              "file": "idleA.gif", "frameCount": 1, "durationMs": 100, "motionMs": 100,
              "loops": true, "pose": "standing", "variantGroup": "idle", "weight": 1.0
            },
            "idleB": {
              "file": "idleB.gif", "frameCount": 1, "durationMs": 100, "motionMs": 100,
              "loops": true, "pose": "standing", "variantGroup": "idle", "weight": 1.0
            },
            "working": {
              "file": "working.gif", "frameCount": 1, "durationMs": 100, "motionMs": 100,
              "loops": true, "pose": "sitting", "variantGroup": "working", "weight": 1.0
            }
          }
        }
        """))

    let ids = manifest.clips(inGroup: "idle").map(\.id)
    XCTAssertEqual(ids, ["idleA", "idleB", "idleC"])
  }

  func testTransitionLookup() throws {
    let manifest = try ClipManifest.decode(
      data(
        """
        {
          "version": 1,
          "clips": {
            "starting": {
              "file": "starting.gif", "frameCount": 32, "durationMs": 8520, "motionMs": 5600,
              "loops": false, "fromPose": "offBottom", "toPose": "standing"
            }
          }
        }
        """))

    let transition = manifest.transition(from: .offBottom, to: .standing)
    XCTAssertEqual(transition?.id, "starting")
    XCTAssertNil(manifest.transition(from: .standing, to: .offBottom))
  }

  func testMalformedJSONThrows() {
    XCTAssertThrowsError(try ClipManifest.decode(data("not json")))
  }

  func testMissingRequiredFieldThrows() {
    XCTAssertThrowsError(
      try ClipManifest.decode(
        data(
          """
          {
            "version": 1,
            "clips": {
              "idle": {
                "file": "idle.gif",
                "frameCount": 7,
                "motionMs": 2560,
                "loops": true,
                "pose": "standing",
                "variantGroup": "idle"
              }
            }
          }
          """)))
  }

  func testUnknownPoseThrows() {
    XCTAssertThrowsError(
      try ClipManifest.decode(
        data(
          """
          {
            "version": 1,
            "clips": {
              "idle": {
                "file": "idle.gif",
                "frameCount": 7,
                "durationMs": 2560,
                "motionMs": 2560,
                "loops": true,
                "pose": "levitating",
                "variantGroup": "idle",
                "weight": 1.0
              }
            }
          }
          """)))
  }
}
