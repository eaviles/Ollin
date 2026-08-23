@testable import Ollin
import CoreGraphics
import Foundation
import Testing

/// View boxes: `withViewBox(_:fit:_:)`, which runs a block inside a rectangle as
/// if that rectangle were the whole canvas.
///
/// The render probes put two boxes side by side on a 240 square and give each one
/// its own `background`. That is the load-bearing case: a background belongs to
/// the frame, and one box wiping the frame would take every other box with it.
@Suite(.serialized)
@MainActor
struct ViewBoxTests {

    static let frameColor = Color(hex: 0x304050)

    final class Probe: Sketch {
        var fit: ImageFit = .contain
        /// What the mouse read inside each box, in the order they were entered.
        var mouseInside: [Vector2] = []
        var mouseAfter: Vector2 = .zero

        override var canvasSize: CanvasSize { .square(240) }

        static func make(_ fit: ImageFit, mouse: Vector2 = .zero) -> Probe {
            let p = Probe()
            p.fit = fit
            p.setCanvasSize(width: 240, height: 240)
            p.setMouse(x: mouse.x, y: mouse.y)
            return p
        }

        override func draw() {
            background(ViewBoxTests.frameColor)
            mouseInside = []
            withViewBox(Rectangle(x: 0, y: 0, width: 120, height: 240), fit: fit) {
                mouseInside.append(Vector2(mouseX, mouseY))
                background(.red)
                noStroke()
                fill(.green)
                drawCircle(width / 2, height / 2, 40)
            }
            withViewBox(Rectangle(x: 120, y: 0, width: 120, height: 240), fit: fit) {
                mouseInside.append(Vector2(mouseX, mouseY))
                background(.blue)
            }
            mouseAfter = Vector2(mouseX, mouseY)
        }
    }

    private func pixels(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    /// The mean of one channel over a fractional patch of the frame.
    private func patch(_ image: CGImage, x0: Double, x1: Double,
                       y0: Double, y1: Double, channel: Int) -> Double {
        let d = pixels(of: image)
        var sum = 0, count = 0
        for py in Int(Double(image.height) * y0)..<Int(Double(image.height) * y1) {
            for px in Int(Double(image.width) * x0)..<Int(Double(image.width) * x1) {
                sum += Int(d[(py * image.width + px) * 4 + channel]); count += 1
            }
        }
        return Double(sum) / Double(Swift.max(count, 1))
    }

    private func rgb(_ image: CGImage, x0: Double, x1: Double, y0: Double, y1: Double)
        -> (r: Double, g: Double, b: Double) {
        (patch(image, x0: x0, x1: x1, y0: y0, y1: y1, channel: 0),
         patch(image, x0: x0, x1: x1, y0: y0, y1: y1, channel: 1),
         patch(image, x0: x0, x1: x1, y0: y0, y1: y1, channel: 2))
    }

    // MARK: A background belongs to its box

    /// The deciding law. Two boxes wipe themselves in turn, and each keeps its
    /// own color. A wipe that reached the frame would leave the whole canvas
    /// whichever color went last.
    @Test(.enabled(if: Snapshot.hasMetal))
    func eachBoxKeepsItsOwnBackground() throws {
        let frame = try #require(OllinApp.image(of: Probe.make(.contain), frame: 1))
        // The virtual canvas is square and each box is half as wide as it is
        // tall, so a contained canvas lands as a band across the middle.
        let left = rgb(frame, x0: 0.02, x1: 0.12, y0: 0.30, y1: 0.45)
        let right = rgb(frame, x0: 0.88, x1: 0.98, y0: 0.30, y1: 0.45)
        #expect(left.r > 200 && left.b < 60, "the left box should be red: \(left)")
        #expect(right.b > 200 && right.r < 60, "the right box should be blue: \(right)")
    }

    /// And nothing outside the boxes moved: the letterbox bands above and below
    /// the contained canvases are still the frame's own color.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theFrameOutsideEveryBoxIsUntouched() throws {
        let frame = try #require(OllinApp.image(of: Probe.make(.contain), frame: 1))
        for band in [(0.02, 0.10), (0.90, 0.98)] {
            let strip = rgb(frame, x0: 0.1, x1: 0.9, y0: band.0, y1: band.1)
            #expect(strip.r > 30 && strip.r < 70, "band \(band) red: \(strip)")
            #expect(strip.b > 60 && strip.b < 110, "band \(band) blue: \(strip)")
        }
    }

    // MARK: The coordinates are remapped

    /// A circle drawn at the canvas center inside a box lands at that box's
    /// center, at the box's scale. The block is written as though it owned the
    /// window, and that is the whole point.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theCanvasCenterLandsAtTheBoxCenter() throws {
        let frame = try #require(OllinApp.image(of: Probe.make(.contain), frame: 1))
        let middle = rgb(frame, x0: 0.20, x1: 0.30, y0: 0.45, y1: 0.55)
        #expect(middle.g > 200 && middle.r < 60, "the left box's center should be green: \(middle)")
        // Half the canvas away, the same box is still its own background.
        let edge = rgb(frame, x0: 0.02, x1: 0.06, y0: 0.45, y1: 0.55)
        #expect(edge.r > 200 && edge.g < 90, "the box edge should be red: \(edge)")
    }

    /// `.stretch` gives the box the whole rectangle, so the same drawing fills it
    /// top to bottom and the letterbox bands are gone.
    @Test(.enabled(if: Snapshot.hasMetal))
    func stretchFillsTheWholeBox() throws {
        let frame = try #require(OllinApp.image(of: Probe.make(.stretch), frame: 1))
        let top = rgb(frame, x0: 0.1, x1: 0.4, y0: 0.02, y1: 0.08)
        #expect(top.r > 200 && top.b < 60, "a stretched box reaches the top: \(top)")
    }

    // MARK: The mouse

    /// Inside a box the mouse arrives in that box's coordinates, so an
    /// interactive piece works in each box on its own.
    @Test func theMouseArrivesInEachBoxOwnCoordinates() {
        // The canvas center. Contained in the left box, that is (120, 120) again;
        // in the right box it is the left edge of a canvas that starts at x 120.
        let probe = Probe.make(.contain, mouse: Vector2(120, 120))
        probe.draw()
        #expect(probe.mouseInside.count == 2)
        #expect(abs(probe.mouseInside[0].x - 240) < 1e-9, "left box: \(probe.mouseInside[0])")
        #expect(abs(probe.mouseInside[0].y - 120) < 1e-9)
        #expect(abs(probe.mouseInside[1].x - 0) < 1e-9, "right box: \(probe.mouseInside[1])")
    }

    /// And it is put back on the way out, so code after a box is not left reading
    /// somebody else's coordinates.
    @Test func theMouseIsRestoredOnTheWayOut() {
        let probe = Probe.make(.contain, mouse: Vector2(37, 91))
        probe.draw()
        #expect(probe.mouseAfter == Vector2(37, 91))
    }

    /// Boxes nest, and the mapping composes: a box inside a box halves the scale
    /// twice, and the mouse follows both steps.
    @Test func boxesNestAndTheirMappingsCompose() {
        final class Nested: Sketch {
            var inner = Vector2.zero
            override func draw() {
                withViewBox(Rectangle(x: 0, y: 0, width: width / 2, height: height / 2),
                            fit: .stretch) {
                    withViewBox(Rectangle(x: 0, y: 0, width: width / 2, height: height / 2),
                                fit: .stretch) {
                        inner = Vector2(mouseX, mouseY)
                    }
                }
            }
        }
        let sketch = Nested()
        sketch.setCanvasSize(width: 400, height: 400)
        sketch.setMouse(x: 50, y: 50)
        sketch.draw()
        // Two halvings: a point 50 in from the corner reads 200 in.
        #expect(abs(sketch.inner.x - 200) < 1e-9, "\(sketch.inner)")
        #expect(abs(sketch.inner.y - 200) < 1e-9)
    }

    /// A box with no area draws nothing rather than dividing by zero.
    @Test func aBoxWithNoAreaDrawsNothing() {
        final class Empty: Sketch {
            var ran = false
            override func draw() {
                withViewBox(Rectangle(x: 10, y: 10, width: 0, height: 50)) { ran = true }
            }
        }
        let sketch = Empty()
        sketch.setCanvasSize(width: 200, height: 200)
        sketch.draw()
        #expect(!sketch.ran)
    }
}
