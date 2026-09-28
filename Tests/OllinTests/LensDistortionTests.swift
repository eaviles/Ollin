import CoreGraphics
import Testing
@testable import Ollin

/// Lens distortion: the Brown-Conrady radial model run over a layer. Zero
/// coefficients have to change no byte, whatever the center and whether or not
/// the frame is asked to stay full; a grid of dots has to land where the CPU's
/// own reading of the model puts it, for a barrel, a pincushion, and a filled
/// barrel with its scale; and a barrel has to leave its corners empty until it
/// is asked to fill the frame, while a pincushion never does.
@Suite
@MainActor
struct LensDistortionTests {

    // MARK: Identity

    @Test(.enabled(if: Snapshot.hasMetal))
    func zeroCoefficientsChangeNoByte() throws {
        let plain = try #require(OllinApp.image(of: DotsProbe.make(nil), frame: 1))
        let zeros: [Filter] = [
            .lensDistortion(amount: 0),
            .lensDistortion(amount: 0, quartic: 0, fillsFrame: true),
            .lensDistortion(amount: 0, center: Vector2(0.3, 0.7)),
            .lensDistortion(amount: 0, center: Vector2(0.3, 0.7), fillsFrame: true),
        ]
        for filter in zeros {
            let filtered = try #require(OllinApp.image(of: DotsProbe.make(filter), frame: 1))
            #expect(maxDifference(plain, filtered) == 0, "\(filter.kind) moved at zero")
        }
        // The gate can fail: a real barrel moves the dots.
        let bent = try #require(OllinApp.image(of: DotsProbe.make(.lensDistortion(amount: 0.3)), frame: 1))
        #expect(maxDifference(plain, bent) > 100)
    }

    // MARK: The model, against the CPU

    /// Each dot of a grid comes out centered where the CPU's inversion of the
    /// model puts it, within a pixel: the barrel pulls the outer dots in, the
    /// pincushion pushes them out, and the filled barrel pulls them in by less,
    /// since its scale reads the whole frame from inside the layer.
    @Test(.enabled(if: Snapshot.hasMetal))
    func dotsLandWhereTheModelSays() throws {
        let cases: [(amount: Double, quartic: Double, fills: Bool)] = [
            (0.25, 0.1, false), (-0.2, 0, false), (0.25, 0.1, true), (0.3, -0.1, true),
        ]
        for c in cases {
            let filter = Filter.lensDistortion(amount: c.amount, quartic: c.quartic, fillsFrame: c.fills)
            let image = try #require(OllinApp.image(of: DotsProbe.make(filter), frame: 1))
            let px = pixels(of: image)
            // The scale the pass worked out, read off the same packing the GPU got.
            let pass = try #require(filter.singlePass(width: 256, height: 256, resolve: { $0 }))
            let scale = Double(pass.params[0].w), far = Double(pass.params[1].z)
            var worst = 0.0
            for dot in DotsProbe.dots {
                let predicted = outputPoint(ofSource: dot, amount: c.amount, quartic: c.quartic,
                                            scale: scale, far: far)
                let found = try #require(centroid(px, near: predicted, within: 9),
                                         "no dot near \(predicted) for \(c)")
                worst = max(worst, (found - predicted).length)
            }
            #expect(worst < 1.0, "dots landed \(worst) px from the model for \(c)")
        }
    }

    /// Where the source point `s` (canvas pixels) shows up in the output: the
    /// output point `o` reads the source at `o + (o - c)(factor(|o|) - 1)`, so
    /// along the ray from the center the radius solves `r * factor(r) = r_s`.
    private func outputPoint(ofSource s: Vector2, amount: Double, quartic: Double,
                             scale: Double, far: Double) -> Vector2 {
        let center = Vector2(128, 128)
        let fraction = 1.0 / 256   // canvas pixels to layer fractions (square, so aspect 1)
        let p = (s - center) * fraction
        let rs = p.length
        guard rs > 1e-9 else { return s }
        func factor(_ r: Double) -> Double {
            let t = (r / far) * (r / far)
            return (1 + amount * t + quartic * t * t) * scale
        }
        // Bisection on the monotonic r * factor(r).
        var low = 0.0, high = rs * 2
        for _ in 0 ..< 80 {
            let mid = (low + high) / 2
            if mid * factor(mid) < rs { low = mid } else { high = mid }
        }
        let ro = (low + high) / 2
        return center + p * (ro / rs) / fraction
    }

    // MARK: The empty corners

    /// The field is a flat color over black, so an empty pixel reads black and a
    /// whole one reads the field.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aBarrelLeavesTheCornersEmptyUntilAskedToFill() throws {
        let field = Int((0.6 * 255).rounded())   // the field's green, as drawn
        func cornerIsEmpty(_ filter: Filter) throws -> Bool {
            let image = try #require(OllinApp.image(of: FieldProbe.make(filter), frame: 1))
            // The present pass dithers, so a black pixel reads 0 or 1.
            return green(pixels(of: image), x: 1, y: 1) <= 1
        }
        func borderIsWhole(_ filter: Filter) throws -> Bool {
            let px = pixels(of: try #require(OllinApp.image(of: FieldProbe.make(filter), frame: 1)))
            for i in 0 ..< 128 {
                for (x, y) in [(i, 0), (i, 127), (0, i), (127, i)]
                where abs(green(px, x: x, y: y) - field) > 2 {
                    return false
                }
            }
            return true
        }
        #expect(try cornerIsEmpty(.lensDistortion(amount: 0.3)))
        #expect(try borderIsWhole(.lensDistortion(amount: 0.3, fillsFrame: true)))
        #expect(try borderIsWhole(.lensDistortion(amount: -0.3)))
        #expect(try borderIsWhole(.lensDistortion(amount: -0.3, fillsFrame: true)))
        // A quartic term alone bends only the corners, and the fill covers it too.
        #expect(try cornerIsEmpty(.lensDistortion(amount: 0, quartic: 0.4)))
        #expect(try borderIsWhole(.lensDistortion(amount: 0, quartic: 0.4, fillsFrame: true)))
        // The filled barrel keeps the middle of the picture: the fill is a
        // scale, not a crop to nothing.
        let filled = pixels(of: try #require(OllinApp.image(
            of: FieldProbe.make(.lensDistortion(amount: 0.3, fillsFrame: true)), frame: 1)))
        #expect(abs(green(filled, x: 64, y: 64) - field) <= 2)
    }

    // MARK: Pixels

    private func pixels(of image: CGImage) -> (bytes: [UInt8], width: Int, height: Int) {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        if let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                               bytesPerRow: w * 4, space: space, bitmapInfo: info) {
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return (data, w, h)
    }

    private func green(_ px: (bytes: [UInt8], width: Int, height: Int), x: Int, y: Int) -> Int {
        Int(px.bytes[(y * px.width + x) * 4 + 1])
    }

    /// The brightness-weighted centroid of the pixels within `radius` of `point`,
    /// or nil when nothing bright is there.
    private func centroid(_ px: (bytes: [UInt8], width: Int, height: Int),
                          near point: Vector2, within radius: Int) -> Vector2? {
        var sum = Vector2(0, 0), weight = 0.0
        let cx = Int(point.x.rounded()), cy = Int(point.y.rounded())
        for y in max(0, cy - radius) ... min(px.height - 1, cy + radius) {
            for x in max(0, cx - radius) ... min(px.width - 1, cx + radius) {
                let w = Double(px.bytes[(y * px.width + x) * 4 + 1])   // green
                sum = sum + Vector2(Double(x) + 0.5, Double(y) + 0.5) * w
                weight += w
            }
        }
        return weight > 0 ? sum / weight : nil
    }

    private func maxDifference(_ a: CGImage, _ b: CGImage) -> Int {
        let pa = pixels(of: a), pb = pixels(of: b)
        var worst = 0
        for i in 0 ..< min(pa.bytes.count, pb.bytes.count) {
            worst = max(worst, abs(Int(pa.bytes[i]) - Int(pb.bytes[i])))
        }
        return worst
    }
}

/// A grid of small green dots in a black opaque layer, at positions well inside
/// the frame so the warped dots never touch its edge.
private final class DotsProbe: Sketch {
    var filter: Filter?
    static func make(_ filter: Filter?) -> DotsProbe {
        let s = DotsProbe(); s.filter = filter; return s
    }
    /// The dot centers, in canvas pixels.
    static let dots: [Vector2] = {
        var points: [Vector2] = []
        for row in 0 ..< 5 {
            for column in 0 ..< 5 {
                points.append(Vector2(48 + Double(column) * 40, 48 + Double(row) * 40))
            }
        }
        return points
    }()
    override var canvasSize: CanvasSize { .square(256) }
    override func draw() {
        background(.black)
        let layer = makeRenderTarget()
        withTarget(layer) {
            background(.black)
            noStroke(); fill(Color(red: 0.2, green: 1, blue: 0.3))
            for dot in Self.dots { drawCircle(dot.x, dot.y, 4) }
        }
        drawImage((filter.map { layer.filtered($0) } ?? layer).image, 0, 0)
    }
}

/// An opaque field filling the whole layer, laid over black, so a pixel the
/// warp left empty reads black and one it covered reads the field.
private final class FieldProbe: Sketch {
    var filter: Filter?
    static func make(_ filter: Filter?) -> FieldProbe {
        let s = FieldProbe(); s.filter = filter; return s
    }
    override var canvasSize: CanvasSize { .square(128) }
    override func draw() {
        background(.black)
        let layer = makeRenderTarget()
        withTarget(layer) { background(Color(red: 0.4, green: 0.6, blue: 0.9)) }
        drawImage((filter.map { layer.filtered($0) } ?? layer).image, 0, 0)
    }
}
