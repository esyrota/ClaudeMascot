import Foundation

/// Draws an `Overlay` behind a clip's own art, frame by frame.
///
/// A pure value type: no actor isolation, no I/O. It only ever touches the
/// `Overlay.reservedRows` rows at the top of the canvas — everything below
/// is the frame's own pixels, untouched.
///
/// ## Where the background mask comes from
///
/// There is no authored alpha to read: `art/generate.py` uses its `BG`
/// constant as both "the background" and "black art" (`_paste_over`'s
/// `transparent=BG`, and the recolour functions returning `BG` for
/// "background, and the eyes"), so nothing in the pipeline distinguishes the
/// two today, and telling them apart would mean rewriting the 2052 lines
/// that draw every clip rather than adding a mask export to them. Instead
/// the mask is *inferred* per frame: a pixel is background if it is
/// `RGB(0,0,0)` and reachable from the canvas edge through other black
/// pixels (4-connectivity, flood fill from the border). Everything else —
/// including a black pixel enclosed by non-black art, like the mascot's
/// eyes — is the mascot.
///
/// This is wrong in exactly one direction: black art that itself touches the
/// border reads as background. `done-flag`'s flagpole is the shipped
/// example. That is precisely what the knockout halo below exists to cover.
enum Compositor {
  /// Composites `overlay` behind `image`'s frames and returns the result.
  /// Returns `image` unchanged when `overlay` is `nil` — callers rely on
  /// this to keep the no-overlay path a plain passthrough.
  static func composite(_ image: GifImage, under overlay: Overlay?) -> GifImage {
    guard let overlay else { return image }

    // A `nil` overlay pixel means "draw nothing here" — the base layer for
    // every reserved-row position starts black and either stays black or is
    // drawn over below.
    let baseOverlay: [RGB] = overlay.pixels.map { $0 ?? Self.black }

    let frames = image.frames.map { frame in
      composite(frame, width: image.width, height: image.height, baseOverlay: baseOverlay)
    }
    return GifImage(width: image.width, height: image.height, frames: frames)
  }

  private static let black = RGB(r: 0, g: 0, b: 0)
  private static let neighbourOffsets = [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)]

  private static func composite(
    _ frame: GifFrame, width: Int, height: Int, baseOverlay: [RGB]
  ) -> GifFrame {
    let reservedRows = Overlay.reservedRows
    let background = backgroundMask(frame.pixels, width: width, height: height)

    // The knockout halo: mandatory, not optional. It is what makes the
    // inferred mask above exact wherever border-connected black abuts lit
    // art in the reserved rows (`done-flag`'s flagpole among them), and it
    // separately keeps the overlay's warm ramp from fusing into
    // `MASCOT = (255,64,0)`, a hue neighbour of the ramp's red end.
    var overlayLayer = baseOverlay
    for y in 0..<height {
      for x in 0..<width where !background[y * width + x] {
        for (dx, dy) in neighbourOffsets {
          let nx = x + dx
          let ny = y + dy
          guard nx >= 0, nx < width, ny >= 0, ny < reservedRows else { continue }
          overlayLayer[ny * width + nx] = black
        }
      }
    }

    // The mascot always wins: its non-background pixels are drawn last,
    // over the overlay. Rows outside the reserved region are already the
    // frame's own pixels, untouched by anything above.
    var pixels = frame.pixels
    for y in 0..<reservedRows {
      for x in 0..<width {
        let index = y * width + x
        if background[index] {
          pixels[index] = overlayLayer[index]
        }
      }
    }

    return GifFrame(pixels: pixels, delayMilliseconds: frame.delayMilliseconds)
  }

  /// Border flood fill over `RGB(0,0,0)`, 4-connectivity. `true` means
  /// background. See the type doc comment for why this is inferred rather
  /// than authored, and in which direction it is wrong.
  private static func backgroundMask(_ pixels: [RGB], width: Int, height: Int) -> [Bool] {
    guard width > 0, height > 0 else { return [] }

    var background = [Bool](repeating: false, count: pixels.count)
    var queue: [Int] = []

    func seed(_ x: Int, _ y: Int) {
      let index = y * width + x
      guard pixels[index] == black, !background[index] else { return }
      background[index] = true
      queue.append(index)
    }

    for x in 0..<width {
      seed(x, 0)
      seed(x, height - 1)
    }
    for y in 0..<height {
      seed(0, y)
      seed(width - 1, y)
    }

    var head = 0
    while head < queue.count {
      let index = queue[head]
      head += 1
      let x = index % width
      let y = index / width
      for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
        let nx = x + dx
        let ny = y + dy
        guard nx >= 0, nx < width, ny >= 0, ny < height else { continue }
        seed(nx, ny)
      }
    }

    return background
  }
}
