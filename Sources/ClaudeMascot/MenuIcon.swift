import AppKit
import SwiftUI

/// The mascot silhouette, drawn from its 32-unit design grid (see
/// `Docs/Specs/Art Pipeline.md`): torso `x4-28, y7-23`, arms `x0-4` and
/// `x28-32` at `y15-19`, four legs at `x6-8`/`x10-12`/`x20-22`/`x24-26` at
/// `y23-27`, and two eyes at `x8-10` and `x22-24` at `y11-15`. The eyes are
/// punched out via the even-odd fill rule rather than drawn in a second
/// colour, since the menu bar render is a single-colour template.
struct MascotSilhouette: Shape {
  static let gridSize: CGFloat = 32

  func path(in rect: CGRect) -> Path {
    let scale = min(rect.width, rect.height) / Self.gridSize
    var path = Path()

    func unit(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) {
      path.addRect(CGRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale))
    }

    unit(4, 7, 24, 16)  // torso
    unit(0, 15, 4, 4)  // left arm
    unit(28, 15, 4, 4)  // right arm
    unit(6, 23, 2, 4)  // leg 1
    unit(10, 23, 2, 4)  // leg 2
    unit(20, 23, 2, 4)  // leg 3
    unit(24, 23, 2, 4)  // leg 4
    unit(8, 11, 2, 4)  // left eye (punched out)
    unit(22, 11, 2, 4)  // right eye (punched out)

    return path
  }
}

/// The silhouette rendered at menu bar size, filled with the even-odd rule
/// so the eye rectangles cut through the torso rather than adding to it.
private struct MascotSilhouetteView: View {
  var body: some View {
    MascotSilhouette()
      .fill(style: FillStyle(eoFill: true))
      .frame(width: MenuIcon.pointSize, height: MenuIcon.pointSize)
  }
}

/// Builds the mascot menu bar icon as a template `NSImage`-backed
/// `Image`, so AppKit tints it to match the light/dark menu bar the same
/// way SF Symbols are tinted. No PNG is shipped; this is pure vector
/// drawing, scaled down from the 32-unit design grid to menu bar size.
@MainActor
enum MenuIcon {
  static let pointSize: CGFloat = 18

  /// The rendered template image, built once and reused — the geometry
  /// never changes at runtime.
  static let image: Image = render()

  private static func render() -> Image {
    let renderer = ImageRenderer(content: MascotSilhouetteView())
    renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
    guard let nsImage = renderer.nsImage else {
      // Should be unreachable on any real display, but keep the menu bar
      // populated rather than crashing if rendering ever fails.
      return Image(systemName: "display")
    }
    nsImage.isTemplate = true
    return Image(nsImage: nsImage)
  }
}
