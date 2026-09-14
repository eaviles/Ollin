@testable import Ollin
import Testing
import CoreGraphics
import Foundation

/// The ink line around a mesh (`outline(width:color:)`, `Material.outlineWidth`).
///
/// What a sketch is being promised, in pixels: the line sits *outside* the silhouette
/// and never over the face (which is also the check that the hull culls the right
/// faces, since a hull culled the wrong way paints the whole disk); it is as many
/// pixels wide as asked, at any distance (a pen, not a world-space shell); a nearer
/// shape hides a farther one's line, because the hull takes the depth test; and a
/// width of zero draws the byte-identical frame.
@Suite
@MainActor
struct MeshOutlineTests {

    // MARK: The value

    @Test func theMaterialCarriesTheLine() {
        let m = Material.toon.outlined(3, color: .red)
        #expect(m.outlineWidth == 3)
        #expect(m.outlineColor == .red)
        #expect(m.shading == .toon)   // the finish under it is untouched
        let g = m.gpuMaterial()
        #expect(g.outline.w == 3)
        #expect(abs(Double(g.outline.x) - 1) < 1e-6 && g.outline.y == 0 && g.outline.z == 0)
        #expect(Material().gpuMaterial().outline.w == 0)          // the gate is off by default
        #expect(Material(outlineWidth: -4).outlineWidth == 0)     // never negative
        #expect(m.outlined(0).outlineWidth == 0)
    }

    @Test func theDrawingStateBreaksTheBatch() {
        // Two spheres in one material merge into one batch; a line on the second opens
        // its own, since the width rides the per-batch uniform.
        let d = Drawer()
        d.beginFrame()
        d.camera(Camera3D(eye: Vector3(0, 0, 5), target: .zero))
        d.drawMesh(.sphere(radius: 1))
        d.drawMesh(.sphere(radius: 1))
        #expect(d.batches.count == 1)
        d.outline(width: 3, color: .black)
        d.drawMesh(.sphere(radius: 1))
        #expect(d.batches.count == 2)
        #expect(d.batches[1].finish.outline.w == 3)
        d.noOutline()
        d.drawMesh(.sphere(radius: 1))
        #expect(d.batches.count == 3)
        #expect(d.batches[2].finish.outline.w == 0)
    }

    // MARK: In pixels

    private struct Frame {
        let width: Int, height: Int, data: [UInt8]
        func rgb(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
            let i = (y * width + x) * 4
            return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
        }
        /// The line's own color, red, against a white ground and a blue fill.
        func isInk(_ x: Int, _ y: Int) -> Bool {
            let c = rgb(x, y)
            return c.r > 140 && c.g < 110 && c.b < 110
        }
        func isFill(_ x: Int, _ y: Int) -> Bool {
            let c = rgb(x, y)
            return c.b > 140 && c.r < 110
        }
        /// Ink pixels along the middle row, left of the center and right of it.
        func inkRuns() -> (left: Int, right: Int) {
            let y = height / 2
            var left = 0, right = 0
            for x in 0 ..< width / 2 where isInk(x, y) { left += 1 }
            for x in width / 2 ..< width where isInk(x, y) { right += 1 }
            return (left, right)
        }
        func inkPixels(within radius: Int, of cx: Int, _ cy: Int) -> Int {
            var n = 0
            for y in max(0, cy - radius) ... min(height - 1, cy + radius) {
                for x in max(0, cx - radius) ... min(width - 1, cx + radius)
                where (x - cx) * (x - cx) + (y - cy) * (y - cy) <= radius * radius && isInk(x, y) {
                    n += 1
                }
            }
            return n
        }
    }

    private func outlined(_ width: Double?, distance: Double) -> Sketch {
        let probe = OutlineProbe()
        probe.lineWidth = width
        probe.distance = distance
        return probe
    }

    private func twoSpheres(nearSphere: Bool) -> Sketch {
        let probe = TwoSpheresProbe()
        probe.nearSphere = nearSphere
        return probe
    }

    private func frame(_ sketch: Sketch) throws -> Frame {
        let image = try #require(OllinApp.image(of: sketch, frame: 1))
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return Frame(width: w, height: h, data: data)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theLineRingsTheSilhouetteAndNeverTheFace() throws {
        let f = try frame(outlined(8, distance: 5))
        let runs = f.inkRuns()
        #expect((6 ... 11).contains(runs.left) && (6 ... 11).contains(runs.right),
                "an 8 px line reads \(runs.left) px on the left and \(runs.right) on the right")
        // The face is the fill, not the line: the hull culled the faces toward the eye.
        #expect(f.isFill(f.width / 2, f.height / 2))
        #expect(f.inkPixels(within: 30, of: f.width / 2, f.height / 2) == 0)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theLineHoldsItsWidthAtTwiceTheDistance() throws {
        let near = try frame(outlined(8, distance: 5)).inkRuns()
        let far = try frame(outlined(8, distance: 10)).inkRuns()
        #expect(abs(near.left - far.left) <= 2 && abs(near.right - far.right) <= 2,
                "the line reads \(near) px near and \(far) px at twice the distance")
        // And a different width is a different run, so the reading is the line.
        let thin = try frame(outlined(3, distance: 5)).inkRuns()
        #expect(thin.left < near.left - 2 && thin.right < near.right - 2,
                "a 3 px line reads \(thin) against the 8 px \(near)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aNearerShapeHidesAFartherLine() throws {
        // The far sphere's left silhouette crosses the near sphere's face on screen;
        // its line must not. With the near sphere taken out, the same pixels carry
        // the line, which is what makes the empty count mean something.
        let hidden = try frame(twoSpheres(nearSphere: true))
        let control = try frame(twoSpheres(nearSphere: false))
        let cx = hidden.width / 2, cy = hidden.height / 2
        #expect(hidden.isFill(cx, cy))
        #expect(hidden.inkPixels(within: 25, of: cx, cy) == 0)
        #expect(control.inkPixels(within: 25, of: cx, cy) > 20)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func noLineIsTheSameFrame() throws {
        let plain = try frame(outlined(nil, distance: 5))
        let zero = try frame(outlined(0, distance: 5))
        #expect(plain.data == zero.data)
        #expect(plain.inkRuns() == (0, 0))
    }
}

/// One blue sphere at the origin, unlit, with a red line of the given width (`nil`
/// never calls `outline`), seen straight on from `distance`.
private final class OutlineProbe: Sketch {
    var lineWidth: Double? = nil
    var distance = 5.0
    override var canvasSize: CanvasSize { .square(256) }
    override func draw() {
        background(.white)
        camera(.perspective(eye: Vector3(0, 0, distance)))
        noLights()
        fill(.blue)
        if let lineWidth { outline(width: lineWidth, color: .red) }
        drawSphere(radius: 1, segments: 96, rings: 64)
    }
}

/// A near sphere at the origin and a far one behind it to the right, both lined.
private final class TwoSpheresProbe: Sketch {
    var nearSphere = true
    override var canvasSize: CanvasSize { .square(256) }
    override func draw() {
        background(.white)
        camera(.perspective(eye: Vector3(0, 0, 5)))
        noLights()
        fill(.blue)
        outline(width: 8, color: .red)
        withState {
            translate(0.9, 0, -2.5)
            drawSphere(radius: 1, segments: 96, rings: 64)
        }
        if nearSphere { drawSphere(radius: 1, segments: 96, rings: 64) }
    }
}
