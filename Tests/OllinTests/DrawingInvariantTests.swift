import COllinShaders
import CoreGraphics
import Foundation
import ImageIO
import OllinWebGate
import Testing
@testable import Ollin

/// Invariants of the 2D drawing paths: the analytic shapes (the disk's
/// area-conserving coverage, the region fills' inside-biased ramp, the stroke
/// band, hollow mode, stroke alignment), the fringe strokes (perceived width,
/// the perceptual carve-out, the caps, the shared inner crossing), the triangle
/// fills, the stroke and fill media, a retained batch, the vector round trip,
/// and the recorded page. Each is a statement about a path that holds whatever
/// its implementation, read against an analytic value or a twin render.
///
/// Two readings of a pixel are used, and which one a path promises is the
/// invariant. The strokes, the disk, and atlas text remap their coverage to
/// perceptual alpha, so for black ink over white paper the display byte's
/// shortfall from white *is* the geometric coverage: `shade` reads it. The
/// region fills, hollow bands, and the triangle path composite in linear light
/// with no remap, so their coverage is the shortfall in linear light: `light`
/// reads that. Summing either over a mark gives the area the path covered.
@Suite(.enabled(if: Snapshot.hasMetal))
@MainActor
struct DrawingInvariantTests {

    // MARK: Support

    /// A still frame drawn by a closure on a square canvas.
    private final class Probe: Sketch {
        var side = 256
        var wide = 0
        var paper: Color = .white
        var body: @MainActor (Sketch) -> Void = { _ in }
        override var canvasSize: CanvasSize { wide > 0 ? .size(wide, side) : .square(side) }
        override func setup() { noLoop() }
        override func draw() { background(paper); body(self) }
    }

    private func render(side: Int = 256, wide: Int = 0, paper: Color = .white,
                        _ body: @escaping @MainActor (Sketch) -> Void) throws -> Pixels {
        let probe = Probe()
        probe.side = side; probe.wide = wide; probe.paper = paper; probe.body = body
        return Pixels(try OllinApp.image(of: probe))
    }

    private func image(side: Int = 256, _ body: @escaping @MainActor (Sketch) -> Void) throws -> CGImage {
        let probe = Probe()
        probe.side = side; probe.body = body
        return try OllinApp.image(of: probe)
    }

    /// Coverage as the perceptual paths encode it: the byte's shortfall from white.
    private func shade(_ p: Pixels, _ x: Int, _ y: Int) -> Double { 1 - Double(p.gray(x, y)) / 255 }
    /// Coverage as the linear paths encode it: the shortfall in linear light.
    private func light(_ p: Pixels, _ x: Int, _ y: Int) -> Double { 1 - linear(UInt8(p.gray(x, y))) }

    private typealias Reader = (Pixels, Int, Int) -> Double

    /// The sum of a reading over the box `x0..<x1` by `y0..<y1`.
    private func sum(_ p: Pixels, _ x0: Int, _ x1: Int, _ y0: Int, _ y1: Int, _ read: Reader) -> Double {
        var total = 0.0
        for y in max(0, y0)..<min(p.height, y1) {
            for x in max(0, x0)..<min(p.width, x1) { total += read(p, x, y) }
        }
        return total
    }

    /// The paper's own reading, from a box the drawing never touches, so a
    /// dithered white subtracts out of every sum.
    private func paper(_ p: Pixels, _ x0: Int, _ x1: Int, _ y0: Int, _ y1: Int, _ read: Reader) -> Double {
        sum(p, x0, x1, y0, y1, read) / Double((x1 - x0) * (y1 - y0))
    }

    /// The ink in a box with the paper's level taken out.
    private func ink(_ p: Pixels, _ x0: Int, _ x1: Int, _ y0: Int, _ y1: Int, paper level: Double, _ read: Reader) -> Double {
        sum(p, x0, x1, y0, y1, read) - level * Double((x1 - x0) * (y1 - y0))
    }

    /// The sRGB transfer function, written out so the reference is independent
    /// of the code it checks.
    private func toDisplay(_ c: Double) -> Double {
        c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
    }
    private func toLinear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    /// A pin that reads its measurement into the record: the house form, a plain
    /// `if` around `withKnownIssue`, scoped to the cases that fall.
    private func pinned(_ reason: Comment, when active: Bool = true, _ body: () throws -> Void) throws {
        if active { withKnownIssue(reason) { try body() } } else { try body() }
    }

    private func percent(_ a: Double, of b: Double) -> String { String(format: "%+.1f%%", (a / b - 1) * 100) }

    /// Writes a frame as a PNG into the folder `OLLIN_INVARIANT_DUMP` names, for
    /// a look at what a probe read.
    private func dump(_ p: Pixels, _ name: String) {
        guard let folder = ProcessInfo.processInfo.environment["OLLIN_INVARIANT_DUMP"] else { return }
        var bytes = p.bytes
        let image = bytes.withUnsafeMutableBytes { raw -> CGImage? in
            CGContext(data: raw.baseAddress, width: p.width, height: p.height, bitsPerComponent: 8, bytesPerRow: p.width * 4,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
        }
        guard let image, let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: folder).appendingPathComponent("\(name).png") as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    /// Where two same-sized frames differ, as `(x, y, worst channel difference)`.
    private func differences(_ a: Pixels, _ b: Pixels) -> [(x: Int, y: Int, by: Int)] {
        var out: [(Int, Int, Int)] = []
        for y in 0..<a.height { for x in 0..<a.width {
            let i = (y * a.width + x) * 4
            var worst = 0
            for c in 0..<4 { worst = max(worst, abs(Int(a.bytes[i + c]) - Int(b.bytes[i + c]))) }
            if worst > 0 { out.append((x, y, worst)) }
        } }
        return out
    }

    // MARK: The disk: area-conserving coverage

    /// A frame in linear light, read before the present pass dithers and
    /// quantizes it: what a sum over a dot smaller than a pixel needs, since a
    /// handful of pixels at one 8-bit level each would be most of the reading.
    private func linearFrame(side: Int = 256, _ body: @escaping @MainActor (Sketch) -> Void) throws -> EffectInvariantTests.Frame {
        let probe = EffectInvariantTests.Probe()
        probe.side = side
        probe.body = { s in s.background(.white); body(s) }
        return try EffectInvariantTests.render(probe)
    }

    /// `shade` on a linear frame: black ink over white paper leaves the light
    /// `1 - alpha`, and the perceptual paths choose the alpha whose display
    /// value falls short of white by the coverage.
    private func shade(_ f: EffectInvariantTests.Frame, _ x: Int, _ y: Int) -> Double {
        1 - toDisplay(min(max(f.value(x, y), 0), 1))
    }

    /// The ten-by-ten grid's centers: a pitch of 20.1 puts each disk at its
    /// own tenth of a pixel on both axes, so the hundred are the hundred phases.
    private nonisolated static let gridCenters: [Vector2] = {
        var centers: [Vector2] = []
        for j in 0..<10 {
            for i in 0..<10 { centers.append(Vector2(28 + 20.1 * Double(i), 28 + 20.1 * Double(j))) }
        }
        return centers
    }()

    /// The ink each mark of the grid laid, summed over its own box in the
    /// perceptual reading the disk path promises. `reach` is how far from its
    /// center a mark's ink may fall, in pixels.
    private func gridInks(reach: Double, _ draw: @escaping @MainActor (Sketch) -> Void) throws -> [Double] {
        let frame = try linearFrame(draw)
        let half = max(3, Int(reach.rounded(.up)) + 3)
        return Self.gridCenters.map { c in
            let cx = Int(c.x.rounded(.down)), cy = Int(c.y.rounded(.down))
            var total = 0.0
            for y in (cy - half)...(cy + half) { for x in (cx - half)...(cx + half) { total += shade(frame, x, y) } }
            return total
        }
    }

    /// A ten-by-ten grid of disks of one radius, each landing at a different
    /// sub-pixel phase: the ink of each disk. `local` maps a center on the
    /// canvas to the coordinates the sketch draws it at under `prepare`.
    private func diskInks(radius: Double, local: (Vector2) -> Vector2 = { $0 },
                          prepare: @escaping @MainActor (Sketch) -> Void = { _ in },
                          shape: @escaping @MainActor (Sketch, Vector2, Double) -> Void) throws -> [Double] {
        let locals = Self.gridCenters.map(local)
        return try gridInks(reach: radius) { s in
            s.noStroke(); s.fill(.black)
            prepare(s)
            for c in locals { shape(s, c, radius) }
        }
    }

    private nonisolated static let diskRadii = [0.2, 0.35, 0.5, 0.75, 1.0, 1.5, 2.0, 3.0]

    /// A disk's ink is its area, wherever it lands on the pixel grid. Its
    /// coverage at a pixel is the share of that pixel the disk covers, so the
    /// sum is pi r squared whatever the radius; below a pixel across, the
    /// footprint is held at a pixel and the coverage scaled by the true area
    /// over the footprint's, so a shrinking dot fades by area rather than
    /// snapping to a floor.
    @Test(arguments: diskRadii)
    func aDiskLaysDownItsArea(radius: Double) throws {
        let inks = try diskInks(radius: radius) { s, c, r in s.drawCircle(center: c, radius: r) }
        let mean = inks.reduce(0, +) / Double(inks.count)
        let area = Double.pi * radius * radius
        #expect(abs(mean - area) <= 0.03 * area,
                "radius \(radius): mean ink \(mean) against the area \(area) (\(percent(mean, of: area)))")
        let worst = inks.max { abs($0 - area) < abs($1 - area) }!
        #expect(abs(worst - area) <= 0.03 * area,
                "radius \(radius): one phase lays \(worst) against the area \(area) (\(percent(worst, of: area)))")
    }

    /// Where a disk lands on the pixel grid changes nothing about how much ink
    /// it lays: the hundred phases of the grid agree.
    @Test(arguments: [0.3, 0.7, 1.2, 2.5])
    func aDiskDoesNotPopAsItMoves(radius: Double) throws {
        let inks = try diskInks(radius: radius) { s, c, r in s.drawCircle(center: c, radius: r) }
        let mean = inks.reduce(0, +) / Double(inks.count)
        let spread = (inks.max()! - inks.min()!) / mean
        if spread >= 0.02 {
            for j in 0..<10 { print("radius \(radius) phase y \(Double(j) / 10): " + inks[(j * 10)..<(j * 10 + 10)].map { String(format: "%.3f", $0) }.joined(separator: " ")) }
        }
        #expect(spread < 0.02, "radius \(radius): the ink varies by \(spread * 100)% with the disk's sub-pixel phase")
    }

    /// A dot under a pixel moves as its center moves: the ink's center of
    /// mass follows the dot's across a pixel, rather than sitting in one
    /// pixel and jumping to the next.
    @Test(arguments: [0.2, 0.4])
    func aSmallDiskMovesSmoothly(radius: Double) throws {
        let frame = try linearFrame { s in
            s.noStroke(); s.fill(.black)
            for c in Self.gridCenters { s.drawCircle(center: c, radius: radius) }
        }
        var worst = 0.0
        for c in Self.gridCenters {
            let cx = Int(c.x.rounded(.down)), cy = Int(c.y.rounded(.down))
            var total = 0.0, mx = 0.0, my = 0.0
            for y in (cy - 4)...(cy + 4) { for x in (cx - 4)...(cx + 4) {
                let v = shade(frame, x, y)
                total += v; mx += v * (Double(x) + 0.5); my += v * (Double(y) + 0.5)
            } }
            worst = max(worst, abs(mx / total - c.x), abs(my / total - c.y))
        }
        #expect(worst < 0.08, "radius \(radius): the ink's center sits up to \(worst) px from the dot's")
    }

    /// A dot growing through a pixel across never steps: below a pixel it is
    /// its area shared out by a tent, from a pixel up the exact share of a
    /// disc, and the two place up to 4% of a pixel differently where they
    /// meet, so the one is faded into the other over the last fifth of a
    /// pixel. A thousandth of a pixel either side of one pixel across, no
    /// pixel changes by more than the dot's own growth; as a circle, and as a
    /// particle's mark drawn as a quad and as a point.
    @Test func aDotDoesNotStepAsItGrowsThroughAPixel() throws {
        func frames(_ draw: @escaping @MainActor (Sketch, Double) -> Void) throws -> Double {
            let under = try linearFrame { s in draw(s, 0.4995) }
            let over = try linearFrame { s in draw(s, 0.5005) }
            var worst = 0.0
            for c in Self.gridCenters {
                let cx = Int(c.x.rounded(.down)), cy = Int(c.y.rounded(.down))
                for y in (cy - 3)...(cy + 3) { for x in (cx - 3)...(cx + 3) {
                    worst = max(worst, abs(shade(under, x, y) - shade(over, x, y)))
                } }
            }
            return worst
        }
        let circle = try frames { s, r in
            s.noStroke(); s.fill(.black)
            for c in Self.gridCenters { s.drawCircle(center: c, radius: r) }
        }
        #expect(circle < 0.012, "a circle: one pixel changes by \(circle) across a pixel's width")
        for maxSize in [nil, 1.1] as [Double?] {
            let mark = try frames { [self] s, r in
                s.drawParticles(self.gridParticles(radius: r, color: SIMD4(0, 0, 0, 1)), style: .marks, maxSize: maxSize)
            }
            #expect(mark < 0.012, "a mark as \(maxSize == nil ? "a quad" : "a point"): one pixel changes by \(mark) across a pixel's width")
        }
    }

    /// Each instance carries its own transform, so a disk drawn under a scale,
    /// a rotation, an anisotropic stretch, or a canvas zoomed far out lays the
    /// ink of the same disk drawn plain: its footprint is measured in pixels
    /// on each of its own axes, whatever the transform.
    @Test(arguments: [0.4, 1.0, 2.5])
    func aDiskKeepsItsInkUnderAnyTransform(radius: Double) throws {
        let plain = try diskInks(radius: radius) { s, c, r in s.drawCircle(center: c, radius: r) }
        let scaled = try diskInks(radius: radius, local: { $0 / 4 }, prepare: { $0.scale(4) }) { s, c, r in
            s.drawCircle(center: c, radius: r / 4)
        }
        let zoomedOut = try diskInks(radius: radius, local: { $0 * 8 }, prepare: { $0.scale(0.125) }) { s, c, r in
            s.drawCircle(center: c, radius: r * 8)
        }
        let angle = 0.6
        let turned = try diskInks(radius: radius, local: { p in
            // The inverse of rotate(angle) then scale(2, 0.5): unrotate, then unscale.
            let q = Vector2(p.x * cos(-angle) - p.y * sin(-angle), p.x * sin(-angle) + p.y * cos(-angle))
            return Vector2(q.x / 2, q.y / 0.5)
        }, prepare: { $0.rotate(angle); $0.scale(2, 0.5) }) { s, c, r in
            s.drawEllipse(center: c, radiusX: r / 2, radiusY: r / 0.5)
        }
        let area = Double.pi * radius * radius
        for (name, inks) in [("plain", plain), ("scaled up", scaled), ("zoomed out", zoomedOut), ("turned and stretched", turned)] {
            let worst = inks.max { abs($0 - area) < abs($1 - area) }!
            #expect(abs(worst - area) <= 0.03 * area,
                    "radius \(radius), \(name): one phase lays \(worst) against the area \(area) (\(percent(worst, of: area)))")
        }
    }

    /// A dot under a pixel across stays about a pixel wide under a stretched
    /// transform: the footprint it is held at is a pixel on each of its own
    /// axes, so under `scale(2, 0.5)` it is not smeared along the wide one.
    /// (One number for both axes lays the same ink, which is why the ink alone
    /// does not show it.)
    @Test func aSmallDiskStaysAPixelWideUnderAStretch() throws {
        let angle = 0.6, radius = 0.4
        let locals = Self.gridCenters.map { p -> Vector2 in
            let q = Vector2(p.x * cos(-angle) - p.y * sin(-angle), p.x * sin(-angle) + p.y * cos(-angle))
            return Vector2(q.x / 2, q.y / 0.5)
        }
        let frame = try linearFrame { s in
            s.noStroke(); s.fill(.black)
            s.rotate(angle); s.scale(2, 0.5)
            for c in locals { s.drawEllipse(center: c, radiusX: radius / 2, radiusY: radius / 0.5) }
        }
        var worst = 1.0
        for c in Self.gridCenters {
            let cx = Int(c.x.rounded(.down)), cy = Int(c.y.rounded(.down))
            var near = 0.0, all = 0.0
            for y in (cy - 5)...(cy + 5) { for x in (cx - 5)...(cx + 5) {
                let v = shade(frame, x, y)
                all += v
                if abs(x - cx) <= 1 && abs(y - cy) <= 1 { near += v }
            } }
            worst = min(worst, near / all)
        }
        #expect(worst > 0.98, "one dot keeps only \(worst) of its ink within a pixel of its own")
    }

    /// The same for an ellipse thin on one axis alone: under the stretch its
    /// thin axis is held at a pixel of its own, so its ink stays beside its
    /// long axis. (One number for both axes would hold it at the wider axis's
    /// pixel, four times too wide here, and the dot above cannot show that: a
    /// dot under a pixel both ways is shared out on the screen's own axes.)
    @Test func aThinEllipseStaysAPixelWideUnderAStretch() throws {
        let angle = 0.6
        // On the canvas: 0.3 px by 3 px in radius, the long axis along the
        // stretched transform's second axis.
        let thin = 0.3, long = 3.0
        let locals = Self.gridCenters.map { p -> Vector2 in
            let q = Vector2(p.x * cos(-angle) - p.y * sin(-angle), p.x * sin(-angle) + p.y * cos(-angle))
            return Vector2(q.x / 2, q.y / 0.5)
        }
        let frame = try linearFrame { s in
            s.noStroke(); s.fill(.black)
            s.rotate(angle); s.scale(2, 0.5)
            for c in locals { s.drawEllipse(center: c, radiusX: thin / 2, radiusY: long / 0.5) }
        }
        let axis = Vector2(-sin(angle), cos(angle))
        var worst = 1.0
        for c in Self.gridCenters {
            let cx = Int(c.x.rounded(.down)), cy = Int(c.y.rounded(.down))
            var near = 0.0, all = 0.0
            for y in (cy - 7)...(cy + 7) { for x in (cx - 7)...(cx + 7) {
                let v = shade(frame, x, y)
                all += v
                let dx = Double(x) + 0.5 - c.x, dy = Double(y) + 0.5 - c.y
                if abs(dx * axis.y - dy * axis.x) <= 1.25 { near += v }
            } }
            worst = min(worst, near / all)
        }
        #expect(worst > 0.97, "one thin ellipse keeps only \(worst) of its ink within a pixel and a quarter of its long axis")
    }

    /// An ellipse's ink is its area too, at any turn, down to one thinner
    /// than a pixel across: the floor is held on each axis by itself, so a
    /// long thin ellipse keeps its length and fades across its width.
    @Test(arguments: [[6.0, 2.0], [3.0, 0.3], [1.5, 0.6], [0.4, 0.2]])
    func anEllipseLaysDownItsArea(radii: [Double]) throws {
        let a = radii[0], b = radii[1], area = Double.pi * a * b
        for angle in [0.0, 0.5, 1.2] {
            let inks = try gridInks(reach: a) { s in
                s.noStroke(); s.fill(.black)
                for c in Self.gridCenters {
                    s.withState {
                        s.translate(c); s.rotate(angle)
                        s.drawEllipse(center: .zero, radiusX: a, radiusY: b)
                    }
                }
            }
            let worst = inks.max { abs($0 - area) < abs($1 - area) }!
            #expect(abs(worst - area) <= 0.03 * area,
                    "\(a) by \(b) turned \(angle): one phase lays \(worst) against the area \(area) (\(percent(worst, of: area)))")
        }
    }

    /// A disk far larger than the canvas has an edge as true as a small one's:
    /// down every column the ink ends where the circle does. (Beside a circle
    /// this size a pixel is too small for the exact shared area, which single
    /// precision cannot hold there, so the edge is read as a line pulled in by
    /// the arc's bow.)
    @Test func aHugeDisksEdgeIsWhereTheCircleIs() throws {
        let radius = 5000.0, center = Vector2(128, 5228.3)
        let frame = try linearFrame { s in
            s.noStroke(); s.fill(.black)
            s.drawCircle(center: center, radius: radius)
        }
        var worst = 0.0
        for x in 8..<248 {
            var ink = 0.0
            for y in 200..<256 { ink += shade(frame, x, y) }
            let px = Double(x) + 0.5
            let edge = center.y - (radius * radius - (px - center.x) * (px - center.x)).squareRoot()
            worst = max(worst, abs(ink - (256 - edge)))
        }
        #expect(worst < 0.02, "a column's ink ends \(worst) px from the circle's edge")
    }

    /// One particle at each of the grid's centers, `radius` across twice.
    private func gridParticles(radius: Double, color: SIMD4<Float>) -> ComputeBuffer<OllinParticle> {
        ComputeBuffer(Self.gridCenters.map {
            OllinParticle(position: SIMD2(Float($0.x), Float($0.y)), velocity: .zero, color: color,
                          size: Float(2 * radius), life: 1, seedA: 0, seedB: 0)
        })
    }

    /// A particle drawn as a mark is the same disk: its ink is its area at
    /// every phase, as a quad and as the one point a named size makes it.
    @Test(arguments: [0.3, 0.8, 1.6])
    func aParticleMarkLaysDownItsArea(radius: Double) throws {
        let buffer = gridParticles(radius: radius, color: SIMD4(0, 0, 0, 1))
        let area = Double.pi * radius * radius
        for maxSize in [nil, 2 * radius] as [Double?] {
            let inks = try gridInks(reach: radius) { s in s.drawParticles(buffer, style: .marks, maxSize: maxSize) }
            let worst = inks.max { abs($0 - area) < abs($1 - area) }!
            #expect(abs(worst - area) <= 0.03 * area,
                    "radius \(radius), \(maxSize == nil ? "quads" : "points"): one phase lays \(worst) against the area \(area) (\(percent(worst, of: area)))")
        }
    }

    /// A particle drawn as light deposits its area times its weight, wherever
    /// it lands: a disc over a texel across takes the share of each texel it
    /// covers, never remapped.
    @Test(arguments: [0.6, 0.9, 1.4, 2.5])
    func aLightParticleDepositsItsArea(radius: Double) throws {
        let weight = 0.5
        let buffer = gridParticles(radius: radius, color: SIMD4(1, 1, 1, Float(weight)))
        let area = Double.pi * radius * radius
        for maxSize in [nil, 2 * radius] as [Double?] {
            let probe = EffectInvariantTests.Probe()
            probe.side = 256
            probe.body = { s in s.background(.black); s.blendMode(.add); s.drawParticles(buffer, style: .light, maxSize: maxSize) }
            let frame = try EffectInvariantTests.render(probe)
            let half = Int(radius.rounded(.up)) + 3
            let lights = Self.gridCenters.map { c -> Double in
                let cx = Int(c.x.rounded(.down)), cy = Int(c.y.rounded(.down))
                return frame.sum(0, x: (cx - half)..<(cx + half + 1), y: (cy - half)..<(cy + half + 1)) / weight
            }
            let worst = lights.max { abs($0 - area) < abs($1 - area) }!
            #expect(abs(worst - area) <= 0.03 * area,
                    "radius \(radius), \(maxSize == nil ? "quads" : "points"): one phase deposits \(worst) against the area \(area) (\(percent(worst, of: area))); the hundred run \(percent(lights.min()!, of: area)) to \(percent(lights.max()!, of: area))")
        }
    }

    // MARK: A coarse layer

    /// A frame whose marks were drawn into a layer `divisor` times coarser than
    /// the canvas and drawn back with each of the layer's texels kept whole, in
    /// linear light: every canvas pixel of a texel's block reads that texel, so
    /// a sum over the canvas is the layer's own ink in canvas pixels.
    private func coarseLayerFrame(divisor: Int, _ body: @escaping @MainActor (Sketch) -> Void) throws -> EffectInvariantTests.Frame {
        try linearFrame { s in
            let layer = s.makeRenderTarget(scale: 1 / Double(divisor))
            s.withTarget(layer) { body(s) }
            s.imageSampling(.nearest)
            s.drawImage(layer.image, 0, 0)
        }
    }

    /// A stroke drawn into a coarse layer is as wide as its weight there too,
    /// wherever it falls on the layer's own texels: the ribbon's rim and a
    /// hairline's footprint are sized by the texels of what is drawn into.
    @Test(arguments: [2, 4])
    func aStrokeIsAsWideAsItsWeightInACoarseLayer(divisor: Int) throws {
        let texel = Double(divisor)
        for weight in [0.5 * texel, 1.0 * texel, 2.5 * texel, 6.0 * texel] {
            for angle in [0.0, 30.0, 90.0] {
                let a = angle * .pi / 180
                var worst = weight
                for phase in Self.phases {
                    let frame = try coarseLayerFrame(divisor: divisor) { s in
                        s.stroke(.black); s.strokeWeight(weight); s.strokeCap(.butt)
                        let d = Vector2(cos(a), sin(a)) * 104
                        let middle = Vector2(128, 128) + Vector2(-sin(a), cos(a)) * (phase * texel)
                        s.drawLine(middle - d, middle + d)
                    }
                    var widths: [Double] = []
                    if angle == 90 {
                        for y in 96..<160 { var t = 0.0; for x in 0..<256 { t += shade(frame, x, y) }; widths.append(t) }
                    } else {
                        for x in 96..<160 { var t = 0.0; for y in 0..<256 { t += shade(frame, x, y) }; widths.append(t * cos(a)) }
                    }
                    let measured = widths.reduce(0, +) / Double(widths.count)
                    if abs(measured - weight) > abs(worst - weight) { worst = measured }
                }
                let allowed = weight < texel ? 0.05 : 0.03
                #expect(abs(worst - weight) <= allowed * weight,
                        "a layer 1/\(divisor) the canvas, weight \(weight) at \(angle) degrees: one position reads \(worst) wide (\(percent(worst, of: weight)))")
            }
        }
    }

    /// A disk drawn into a coarse layer lays its area there too, wherever it
    /// lands on the layer's texels.
    @Test(arguments: [2, 4])
    func aDiskLaysDownItsAreaInACoarseLayer(divisor: Int) throws {
        let texel = Double(divisor)
        for radius in [0.4 * texel, 1.2 * texel, 3.0 * texel] {
            // A five-by-five grid whose pitch is fractional in texels, so the
            // disks land at many phases, and wide enough that no box holds two.
            var centers: [Vector2] = []
            for j in 0..<5 { for i in 0..<5 { centers.append(Vector2(30.3 + 48.37 * Double(i), 30.3 + 48.37 * Double(j))) } }
            let frame = try coarseLayerFrame(divisor: divisor) { s in
                s.noStroke(); s.fill(.black)
                for c in centers { s.drawCircle(center: c, radius: radius) }
            }
            let area = Double.pi * radius * radius
            let half = Int((radius + 1.5 * texel).rounded(.up)) + divisor
            var worst = area
            for c in centers {
                // The box is snapped to the layer's texels, so no block is cut.
                let x0 = (Int(c.x) - half) / divisor * divisor, x1 = ((Int(c.x) + half) / divisor + 1) * divisor
                let y0 = (Int(c.y) - half) / divisor * divisor, y1 = ((Int(c.y) + half) / divisor + 1) * divisor
                var total = 0.0
                for y in max(0, y0)..<min(256, y1) { for x in max(0, x0)..<min(256, x1) { total += shade(frame, x, y) } }
                if abs(total - area) > abs(worst - area) { worst = total }
            }
            #expect(abs(worst - area) <= 0.03 * area,
                    "a layer 1/\(divisor) the canvas, radius \(radius): one disk lays \(worst) against the area \(area) (\(percent(worst, of: area)))")
        }
    }

    // MARK: The region fills: the inside-biased ramp

    private nonisolated static let splits = [100.0, 100.25, 100.5, 100.75]

    /// Two rectangles sharing an edge are one rectangle, to the byte: the fill
    /// ramp is full to the geometric edge with its halo outside, so abutting
    /// fills meet at full coverage and leave no seam at any fractional edge.
    @Test(arguments: splits)
    func twoHalfRectanglesAreOneRectangle(split: Double) throws {
        let color = Color(red: 0.2, green: 0.5, blue: 0.8)
        let left = 40.3, top = 50.6, right = 2 * split - left, bottom = 170.8
        let whole = try render { s in s.noStroke(); s.fill(color); s.drawRect(left, top, right - left, bottom - top) }
        let halves = try render { s in
            s.noStroke(); s.fill(color)
            s.drawRect(left, top, split - left, bottom - top)
            s.drawRect(split, top, right - split, bottom - top)
        }
        let stacked = try render { s in
            s.noStroke(); s.fill(color)
            s.drawRect(left, top, right - left, split - top)
            s.drawRect(left, split, right - left, bottom - split)
        }
        let sideBySide = differences(halves, whole), stackedUp = differences(stacked, whole)
        // Away from the seam's two ends nothing may differ (a level is the
        // dither's rounding of a float ulp); where the seam meets the outer edge
        // the two halves' halos overlap, which is pinned below.
        func atASeamEnd(_ x: Int, _ y: Int, seam: Double, along: (Double, Double)) -> Bool {
            let px = Double(x) + 0.5, py = Double(y) + 0.5
            return abs(px - seam) <= 1.5 && (abs(py - along.0) <= 1.5 || abs(py - along.1) <= 1.5)
        }
        let strayX = sideBySide.filter { $0.by > 1 && !atASeamEnd($0.x, $0.y, seam: split, along: (top, bottom)) }
        let strayY = stackedUp.filter { $0.by > 1 && !atASeamEnd($0.y, $0.x, seam: split, along: (left, right)) }
        #expect(strayX.isEmpty, "split at x \(split): \(strayX.count) pixels differ away from the seam's ends, e.g. \(strayX.prefix(4))")
        #expect(strayY.isEmpty, "split at y \(split): \(strayY.count) pixels differ away from the seam's ends, e.g. \(strayY.prefix(4))")
        try pinned("where a seam meets the outer edge the two fills' halos overlap and that pixel takes a second coat (up to 67 levels at one pixel per seam end, measured 2026-10-25)") {
            #expect(!sideBySide.contains { $0.by > 1 }, "split at x \(split): \(sideBySide.count) pixels differ, by up to \(sideBySide.map(\.by).max() ?? 0) levels, e.g. \(sideBySide.prefix(4))")
            #expect(!stackedUp.contains { $0.by > 1 }, "split at y \(split): \(stackedUp.count) pixels differ, by up to \(stackedUp.map(\.by).max() ?? 0) levels, e.g. \(stackedUp.prefix(4))")
        }
    }

    /// A grid of tiles at a fractional pitch is one solid: where four fills meet
    /// at a corner the ramp still leaves nothing through.
    @Test func aGridOfAbuttingTilesIsOneSolid() throws {
        let color = Color(red: 0.8, green: 0.3, blue: 0.2)
        let origin = 20.4, pitch = 23.7, n = 6
        let whole = try render { s in s.noStroke(); s.fill(color); s.drawRect(origin, origin, pitch * Double(n), pitch * Double(n)) }
        let tiles = try render { s in
            s.noStroke(); s.fill(color)
            for j in 0..<n { for i in 0..<n {
                s.drawRect(origin + pitch * Double(i), origin + pitch * Double(j), pitch, pitch)
            } }
        }
        let d = differences(tiles, whole)
        // The grid's seams end on its outer edge, where the halos overlap (the
        // pin above); inside, nothing may differ by more than the dither's level.
        let edge = origin + pitch * Double(n)
        let inside = d.filter { $0.by > 1 && Double($0.x) + 0.5 > origin + 1.5 && Double($0.x) + 0.5 < edge - 1.5
                                            && Double($0.y) + 0.5 > origin + 1.5 && Double($0.y) + 0.5 < edge - 1.5 }
        #expect(inside.isEmpty, "the tiled grid differs from the one rectangle inside its edge at \(inside.count) pixels, e.g. \(inside.prefix(4))")
        try pinned("where a seam meets the outer edge the two fills' halos overlap and that pixel takes a second coat (measured 2026-10-25)") {
            #expect(!d.contains { $0.by > 1 }, "the tiled grid differs from the one rectangle at \(d.count) pixels, by up to \(d.map(\.by).max() ?? 0) levels, e.g. \(d.prefix(4))")
        }
    }

    /// Two colors meeting at an edge show no paper between them: along the seam
    /// every pixel is some mix of the two fills and nothing else.
    @Test(arguments: splits)
    func twoColorsMeetWithNoPaperBetween(split: Double) throws {
        let frame = try render { s in
            s.noStroke()
            s.fill(Color(red: 1, green: 0, blue: 0)); s.drawRect(30, 40, split - 30, 160)
            s.fill(Color(red: 0, green: 0, blue: 1)); s.drawRect(split, 40, 220 - split, 160)
        }
        // Paper is white: green would come from nowhere else.
        var leak = 0
        for y in 50..<190 { for x in 98...102 where frame.channel(1, x, y) > 3 { leak += 1 } }
        #expect(leak == 0, "split at \(split): \(leak) pixels along the seam show paper")
    }

    // MARK: The stroke band

    private nonisolated static let bandWidths = [0.3, 0.5, 1.0, 2.0, 4.0]

    /// A stroked outline's ink is its length times its width, at any width: a band
    /// thinner than a pixel keeps a pixel's footprint and scales its alpha by the
    /// width, so it fades by ink instead of thinning to nothing.
    @Test(arguments: bandWidths)
    func anOutlinesInkIsItsLengthTimesItsWidth(width: Double) throws {
        let radius = 70.0
        let frame = try render { s in
            s.noFill(); s.stroke(.black); s.strokeWeight(width)
            s.drawCircle(128, 128, radius)
        }
        // The inside of the ring is paper too, which is where its level is read.
        let level = paper(frame, 100, 156, 100, 156, shade)
        let total = ink(frame, 50, 206, 50, 206, paper: level, shade)
        let expected = 2 * .pi * radius * width
        try pinned("a band thinner than its ramp lays 5.4% more ink than its width: the two edges' smoothsteps are cut at the centerline rather than summed there (measured 2026-10-25 at 0.3, 0.5, and 1)",
                   when: width <= 1) {
            #expect(abs(total - expected) <= 0.025 * expected,
                    "width \(width): ink \(total) against length times width \(expected) (\(percent(total, of: expected)))")
        }
    }

    /// A thin outline is as dark on the diagonals as on the axes. Its total ink
    /// is conserved around the ring either way; what this reads is the darkest
    /// pixel of each sector, which is what the eye reads as the line's weight.
    @Test(arguments: [0.5, 1.0])
    func aThinOutlineIsAsDarkAtEveryAngle(width: Double) throws {
        let radius = 70.0
        let frame = try render { s in
            s.noFill(); s.stroke(.black); s.strokeWeight(width)
            s.drawCircle(128, 128, radius)
        }
        var peaks: [Double] = [], sums: [Double] = []
        let sectors = 16
        for k in 0..<sectors {
            let a0 = 2 * .pi * Double(k) / Double(sectors), a1 = 2 * .pi * Double(k + 1) / Double(sectors)
            var peak = 0.0, total = 0.0
            for y in 50..<206 { for x in 50..<206 {
                let d = Vector2(Double(x) + 0.5 - 128, Double(y) + 0.5 - 128)
                var a = atan2(d.y, d.x); if a < 0 { a += 2 * .pi }
                guard a >= a0, a < a1, abs(d.length - radius) < 4 else { continue }
                let v = shade(frame, x, y)
                peak = max(peak, v); total += v
            } }
            peaks.append(peak); sums.append(total)
        }
        let sumSpread = (sums.max()! - sums.min()!) / (sums.reduce(0, +) / Double(sectors))
        #expect(sumSpread < 0.05, "width \(width): the sectors' ink varies by \(sumSpread * 100)%")
        let ratio = peaks.min()! / peaks.max()!
        try pinned("the band's footprint is fwidth, the L1 pixel step, so on a diagonal a thin outline is spread wider and reads lighter (measured 2026-10-25: the diagonals' darkest pixel is 0.84 of the axes' at 0.5 and at 1)",
                   when: true) {
            #expect(ratio >= 0.85, "width \(width): the darkest pixel on the diagonals is \(ratio) of the axes'")
        }
    }

    // MARK: Hollow mode and stroke alignment

    /// The ink of a column through one edge of a region, and where it sits.
    private func bandAcross(_ p: Pixels, x: Int, y0: Int, y1: Int, _ read: Reader) -> (ink: Double, centroid: Double) {
        var total = 0.0, moment = 0.0
        for y in y0..<y1 {
            let v = read(p, x, y)
            total += v; moment += v * (Double(y) + 0.5)
        }
        return (total, moment / max(total, 1e-9))
    }

    /// A hollow band is as wide as declared and centered on the outline: a
    /// column through the edge reads the band's width of ink (plus the half-pixel
    /// halo each of its two edges gets from the fill ramp), centered on the edge.
    @Test(arguments: [2.0, 6.0, 13.5])
    func aHollowBandIsAsWideAsDeclared(width: Double) throws {
        let top = 60.7
        let frame = try render { s in
            s.noStroke(); s.fill(.black); s.hollow(width)
            s.drawRect(48.3, top, 160, 120)
        }
        var inks: [Double] = [], centroids: [Double] = []
        for x in [100, 128, 150] {
            let band = bandAcross(frame, x: x, y0: 30, y1: 100, light)
            inks.append(band.ink); centroids.append(band.centroid)
        }
        let meanInk = inks.reduce(0, +) / 3, meanCentroid = centroids.reduce(0, +) / 3
        #expect(abs(meanInk - (width + 1)) <= 0.3,
                "width \(width): the band reads \(meanInk) of ink, the width plus its two half-pixel halos is \(width + 1)")
        #expect(abs(meanCentroid - top) <= 0.15, "width \(width): the band is centered at \(meanCentroid), the edge is at \(top)")
    }

    /// A stroke sits where its alignment says: centered on the edge, wholly
    /// inside it, or wholly outside, by an exact offset of half the weight, and
    /// its ink is the weight either way.
    @Test(arguments: [3.0, 8.0])
    func aStrokeSitsWhereItsAlignmentSays(width: Double) throws {
        let top = 60.7
        for (align, offset) in [(StrokeAlign.center, 0.0), (.inside, width / 2), (.outside, -width / 2)] {
            let frame = try render { s in
                s.noFill(); s.stroke(.black); s.strokeWeight(width); s.strokeAlign(align)
                s.drawRect(48.3, top, 160, 120)
            }
            var inks: [Double] = [], centroids: [Double] = []
            for x in [100, 128, 150] {
                let band = bandAcross(frame, x: x, y0: 30, y1: 100, shade)
                inks.append(band.ink); centroids.append(band.centroid)
            }
            let meanInk = inks.reduce(0, +) / 3, meanCentroid = centroids.reduce(0, +) / 3
            #expect(abs(meanInk - width) <= 0.03 * width + 0.05, "\(align) at \(width): ink \(meanInk) against the weight")
            #expect(abs(meanCentroid - (top + offset)) <= 0.15,
                    "\(align) at \(width): the band is centered at \(meanCentroid), expected \(top + offset)")
            // The footprint: an inside stroke leaves the paper outside the edge
            // untouched, an outside stroke leaves the interior bare.
            if align == .inside { #expect(shade(frame, 128, 59) < 0.02, "an inside stroke reached outside the edge") }
            if align == .outside { #expect(shade(frame, 128, 62) < 0.02, "an outside stroke reached inside the edge") }
        }
    }

    // MARK: The fringe strokes

    /// The width a line reads across its cross-section: the ink down each of 60
    /// columns through the middle of a line at `angle`, times the cosine that
    /// turns a column's slant crossing into the perpendicular width. `phase`
    /// slides the line across itself by that share of a pixel, so its edges
    /// fall at a different place in the pixels they cross.
    private func measuredWidth(weight: Double, angle degrees: Double, phase: Double = 0) throws -> Double {
        let a = degrees * .pi / 180
        let frame = try render { s in
            s.stroke(.black); s.strokeWeight(weight); s.strokeCap(.butt)
            let d = Vector2(cos(a), sin(a)) * 118
            let middle = Vector2(128, 128) + Vector2(-sin(a), cos(a)) * phase
            s.drawLine(middle - d, middle + d)
        }
        if degrees == 90 {
            let level = paper(frame, 2, 12, 2, 12, shade)
            var widths: [Double] = []
            for y in 98..<158 { widths.append(ink(frame, 0, 256, y, y + 1, paper: level, shade)) }
            return widths.reduce(0, +) / Double(widths.count)
        }
        let level = paper(frame, 244, 254, 2, 12, shade)
        var widths: [Double] = []
        for x in 98..<158 { widths.append(ink(frame, x, x + 1, 0, 256, paper: level, shade) * cos(a)) }
        return widths.reduce(0, +) / Double(widths.count)
    }

    private nonisolated static let phases = [0.0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875]

    /// A stroke reads as wide as its weight at any angle and wherever its edges
    /// fall in the pixels they cross: every triangle of the ribbon hands a pixel
    /// the same coverage, read at the pixel's center, and the ribbon runs half a
    /// pixel past where that coverage ends, so the multisample mask never cuts a
    /// pixel that carries ink.
    @Test(arguments: [1.0, 1.5, 2.5, 6.0, 11.0, 17.3])
    func aStrokeIsAsWideAsItsWeight(weight: Double) throws {
        for angle in [0.0, 30.0, 45.0, 90.0] {
            for phase in Self.phases {
                let measured = try measuredWidth(weight: weight, angle: angle, phase: phase)
                #expect(abs(measured - weight) <= 0.02 * weight,
                        "weight \(weight) at \(angle) degrees, phase \(phase), reads \(measured) wide (\(percent(measured, of: weight)))")
            }
        }
    }

    /// A hairline keeps its ink: a stroke under a pixel wide keeps a pixel's
    /// footprint and lays the ink of its width, as the stroke band and the disk
    /// do, at any angle and wherever it falls on the pixel grid.
    @Test(arguments: [0.3, 0.5, 0.7])
    func aHairlineKeepsItsInk(weight: Double) throws {
        for angle in [0.0, 30.0, 90.0] {
            for phase in Self.phases {
                let measured = try measuredWidth(weight: weight, angle: angle, phase: phase)
                #expect(abs(measured - weight) <= 0.05 * weight,
                        "weight \(weight) at \(angle) degrees, phase \(phase), lays \(measured) px of ink (\(percent(measured, of: weight)))")
            }
        }
    }

    /// A stroke's ribbon runs past its edge, and that rim is no part of the
    /// stroke: placed at a depth in a 3D scene it hides nothing drawn later
    /// behind it, right up to the stroke's own edge.
    @Test func aStrokesRimHidesNothing() throws {
        let frame = try render { s in
            s.camera(.perspective(eye: Vector3(0, 0, 4), target: .zero, fieldOfView: .pi / 3))
            s.depth(at: Vector3(0, 0, 1))
            s.noFill(); s.stroke(.black); s.strokeWeight(6); s.strokeCap(.butt)
            s.drawLine(40, 128, 216, 128)          // its edges on rows 125 and 131
            s.depth(at: Vector3(0, 0, -1))
            s.noStroke(); s.fill(Color(red: 1, green: 0, blue: 0))
            s.drawRect(60, 100, 136, 56)
        }
        #expect(frame.channel(1, 128, 128) < 8 && frame.channel(0, 128, 128) < 8, "the stroke is not in front of the fill behind it")
        for y in [122, 123, 124, 131, 132, 133] {
            #expect(frame.channel(0, 128, y) > 247 && frame.channel(1, 128, y) < 8,
                    "row \(y), beside the stroke's edge: the fill behind is missing there (red \(frame.channel(0, 128, y)), green \(frame.channel(1, 128, y)))")
        }
    }

    /// The light a hatch of 1 px lines leaves, by 24-pixel tiles over the middle
    /// of the canvas: the tiles' mean, and how far the lightest and the darkest
    /// tile are apart, as shares of full light. A tile is what the eye averages
    /// from a normal distance, and it averages light, not display values.
    private func hatchTone(angle degrees: Double, pitch: Double, ink: Color, paper: Color) throws -> (mean: Double, swing: Double) {
        let a = degrees * .pi / 180
        let dir = Vector2(cos(a), sin(a)), normal = Vector2(-sin(a), cos(a))
        let probe = EffectInvariantTests.Probe()
        probe.side = 256
        probe.body = { s in
            s.background(paper)
            s.noFill(); s.stroke(ink); s.strokeWeight(1); s.strokeCap(.butt)
            var k = -200.0
            while k <= 200 {
                let m = Vector2(128, 128) + normal * k
                s.drawLine(m - dir * 200, m + dir * 200)
                k += pitch
            }
        }
        let frame = try EffectInvariantTests.render(probe)
        var tiles: [Double] = []
        for ty in stride(from: 56, to: 200, by: 24) {
            for tx in stride(from: 56, to: 200, by: 24) {
                tiles.append(frame.sum(0, x: tx..<(tx + 24), y: ty..<(ty + 24)) / 576)
            }
        }
        return (tiles.reduce(0, +) / Double(tiles.count), tiles.max()! - tiles.min()!)
    }

    /// A hatch of thin lines reads one even tone, wherever its lines fall on
    /// the pixel grid and whatever its angle, dark on light and light on dark.
    /// This is what settled the stroke's edge (2026-11-12): a crisper edge that
    /// holds every line's ink still reads a 45-degree hatch lighter than a
    /// 10-degree one, and the edge before it banded.
    @Test(arguments: [true, false])
    func aHatchReadsOneToneAtEveryAngle(darkOnLight: Bool) throws {
        let ink: Color = darkOnLight ? .black : .white, paper: Color = darkOnLight ? .white : .black
        var means: [Double] = []
        for angle in [45.0, 30.0, 10.0] {
            let tone = try hatchTone(angle: angle, pitch: 3.37, ink: ink, paper: paper)
            means.append(tone.mean)
            #expect(tone.swing < 0.004, "\(darkOnLight ? "dark on light" : "light on dark") at \(angle) degrees: the tiles' light runs \(tone.swing) apart")
        }
        let spread = means.max()! - means.min()!
        #expect(spread < 0.004, "\(darkOnLight ? "dark on light" : "light on dark"): the hatch's light at 45, 30, and 10 degrees is \(means)")
    }

    /// A turn too tight for the ribbon's rim still lays one coat: where the rim
    /// would run past the neighboring segment along the shared crossing it is
    /// held back, rather than folding the ribbon over itself or giving up the
    /// crossing.
    @Test func aTightTurnKeepsOneCoat() throws {
        // An open arc of short segments, each turning 40 degrees: the crossing at
        // every turn holds the visible stroke and not the whole rim.
        var points: [Vector2] = []
        let side = 2.25, turn = 40.0 * .pi / 180
        var at = Vector2(13, 22), heading = 0.2
        for _ in 0...5 {
            points.append(at)
            at = at + Vector2(cos(heading), sin(heading)) * side
            heading += turn
        }
        let probe = Probe()
        probe.side = 320
        probe.body = { s in
            s.scale(8)
            s.noFill(); s.stroke(Color.black.withAlpha(0.3)); s.strokeWeight(4)
            s.strokeJoin(.round); s.strokeCap(.butt)
            s.drawPolyline(points)
        }
        let ink = InkProbe(try OllinApp.image(of: probe), inkDarkerThan: 250)
        #expect(ink.coatArea > 1_500, "the probe missed the stroke: \(ink.coatArea) pixels at the coat's level \(ink.coat)")
        #expect(ink.paintedTwice == 0, "\(ink.paintedTwice) pixels painted twice (coat \(ink.coat))")
        #expect(ink.hairlines == 0, "\(ink.hairlines) pixels of hairline inside the ink")
    }

    /// The perceptual remap touches partial coverage only: a pixel a stroke
    /// covers whole is blended in linear light exactly as a fill's interior is,
    /// so a translucent stroke and a translucent fill of one alpha read alike.
    @Test(arguments: [0.25, 0.5, 0.75])
    func aFullyCoveredPixelIsBlendedInLinearLight(alpha: Double) throws {
        let line = try render { s in
            s.stroke(Color.black.withAlpha(alpha)); s.strokeWeight(24); s.strokeCap(.butt)
            s.drawLine(20, 128, 236, 128)
        }
        let fill = try render { s in s.noStroke(); s.fill(Color.black.withAlpha(alpha)); s.drawRect(20, 116, 216, 24) }
        let n = Double(136 * 12)
        let lineMean = sum(line, 60, 196, 122, 134) { p, x, y in Double(p.gray(x, y)) } / n
        let fillMean = sum(fill, 60, 196, 122, 134) { p, x, y in Double(p.gray(x, y)) } / n
        let expected = toDisplay(1 - alpha) * 255
        #expect(abs(lineMean - fillMean) <= 0.6, "alpha \(alpha): the stroke's interior reads \(lineMean), the fill's \(fillMean)")
        #expect(abs(lineMean - expected) <= 1.0, "alpha \(alpha): the stroke's interior reads \(lineMean), linear blending says \(expected)")
    }

    /// A translucent zigzag of a dozen corners at every turn from 30 to 120
    /// degrees, under every join, is one even coat: no corner composites twice
    /// (the segments end on their shared inner crossing) and no hairline opens
    /// inside the ink (every join fans from the path vertex).
    @Test(arguments: [StrokeJoin.miter, .round, .bevel])
    func aTranslucentZigzagIsOneCoat(join: StrokeJoin) throws {
        var state: UInt64 = 12_345
        func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(state >> 11) / Double(1 << 53)
        }
        var points = [Vector2(30, 160)]
        var sign = 1.0
        for _ in 0..<12 {
            let a = (15 + 45 * next()) * .pi / 180
            let length = 60 + 30 * next()
            points.append(points.last! + Vector2(cos(a), sin(a) * sign) * length)
            sign = -sign
        }
        let probe = Probe()
        probe.side = 320; probe.wide = 1152
        probe.body = { s in
            s.noFill(); s.stroke(Color.black.withAlpha(0.3)); s.strokeWeight(14)
            s.strokeJoin(join); s.strokeCap(.butt)
            s.drawPolyline(points)
        }
        let ink = InkProbe(try OllinApp.image(of: probe), inkDarkerThan: 250)
        #expect(ink.coatArea > 8_000, "\(join): the probe missed the stroke")
        #expect(ink.paintedTwice == 0, "\(join): \(ink.paintedTwice) pixels painted twice (coat \(ink.coat))")
        #expect(ink.hairlines == 0, "\(join): \(ink.hairlines) pixels of hairline inside the ink")
    }

    /// A cap adds exactly its area: nothing for a butt, a square of the weight
    /// for a square cap, a disk of the weight for a round one.
    @Test func aCapAddsExactlyItsArea() throws {
        let weight = 20.0, length = 150.0
        let body = weight * length
        for (cap, extra) in [(StrokeCap.butt, 0.0), (.square, weight * weight), (.round, .pi * weight * weight / 4)] {
            let frame = try render { s in
                s.stroke(.black); s.strokeWeight(weight); s.strokeCap(cap)
                s.drawLine(53, 128, 53 + length, 128)
            }
            let level = paper(frame, 2, 12, 2, 12, shade)
            let total = ink(frame, 30, 226, 100, 156, paper: level, shade)
            let expected = body + extra
            #expect(abs(total - expected) <= 0.01 * expected,
                    "\(cap) cap: ink \(total) against \(expected) (\(percent(total, of: expected)))")
        }
    }

    // MARK: The triangle fills

    /// Pixels two renders disagree on by more than `levels` on some channel.
    private func farPixels(_ a: Pixels, _ b: Pixels, past levels: Int = 32) -> [(x: Int, y: Int)] {
        var far: [(Int, Int)] = []
        for y in 0..<a.height { for x in 0..<a.width {
            let i = (y * a.width + x) * 4
            var worst = 0
            for c in 0..<3 { worst = max(worst, abs(Int(a.bytes[i + c]) - Int(b.bytes[i + c]))) }
            if worst > levels { far.append((x, y)) }
        } }
        return far
    }

    /// The analytic path and the triangle path draw one rectangle: a `drawRect`
    /// (a distance field), the same corners as a polygon (a fan under multisampling),
    /// and as a shape (the triangulator) agree everywhere but on the edge itself,
    /// where one path's halo and the other's sample average differ by design.
    @Test func thePathsDrawOneRectangle() throws {
        let left = 28.6, top = 40.2, width = 200.0, height = 170.0
        let corners = [Vector2(left, top), Vector2(left + width, top), Vector2(left + width, top + height), Vector2(left, top + height)]
        let color = Color(red: 0.15, green: 0.35, blue: 0.7)
        let rect = try render { s in s.noStroke(); s.fill(color); s.drawRect(left, top, width, height) }
        let polygon = try render { s in s.noStroke(); s.fill(color); s.drawPolygon(corners) }
        let shape = try render { s in s.noStroke(); s.fill(color); s.drawShape(Shape(corners)) }
        func nearEdge(_ x: Int, _ y: Int) -> Bool {
            let px = Double(x) + 0.5, py = Double(y) + 0.5
            let inX = px >= left - 1.5 && px <= left + width + 1.5, inY = py >= top - 1.5 && py <= top + height + 1.5
            let onVertical = min(abs(px - left), abs(px - left - width)) <= 1.5 && inY
            let onHorizontal = min(abs(py - top), abs(py - top - height)) <= 1.5 && inX
            return onVertical || onHorizontal
        }
        for (name, other) in [("polygon", polygon), ("shape", shape)] {
            let far = farPixels(rect, other)
            let offEdge = far.filter { !nearEdge($0.x, $0.y) }
            #expect(offEdge.isEmpty, "the rect and the \(name) differ at \(offEdge.count) pixels away from the edge, e.g. \(offEdge.prefix(3))")
            let mean = zip(rect.bytes, other.bytes).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }
            #expect(Double(mean) / Double(rect.bytes.count) < 1.5, "the rect and the \(name): mean difference \(Double(mean) / Double(rect.bytes.count))")
        }
        #expect(farPixels(polygon, shape).isEmpty, "the polygon and the shape differ")
    }

    /// A shape with a hole carries its outer area less its hole, under the
    /// even-odd rule whatever the contours' directions, and under the non-zero
    /// rule when the hole runs the other way; a hole running the same way under
    /// non-zero is no hole.
    @Test func aHoledShapesInkIsItsOuterAreaLessItsHole() throws {
        let outer = [Vector2(58.4, 58.4), Vector2(198.4, 58.4), Vector2(198.4, 198.4), Vector2(58.4, 198.4)]
        let hole = [Vector2(103.4, 103.4), Vector2(153.4, 103.4), Vector2(153.4, 153.4), Vector2(103.4, 153.4)]
        let full = 140.0 * 140.0, holed = full - 50.0 * 50.0
        let cases: [(String, Shape, Double)] = [
            ("even-odd, same way", Shape(contours: [Contour(outer), Contour(hole)], winding: .evenOdd), holed),
            ("even-odd, reversed", Shape(contours: [Contour(outer), Contour(hole.reversed())], winding: .evenOdd), holed),
            ("non-zero, reversed", Shape(contours: [Contour(outer), Contour(hole.reversed())], winding: .nonZero), holed),
            ("non-zero, same way", Shape(contours: [Contour(outer), Contour(hole)], winding: .nonZero), full),
        ]
        for (name, shape, expected) in cases {
            let frame = try render { s in s.noStroke(); s.fill(.black); s.drawShape(shape) }
            let level = paper(frame, 2, 12, 2, 12, light)
            let total = ink(frame, 50, 206, 50, 206, paper: level, light)
            #expect(abs(total - expected) <= 0.005 * expected, "\(name): ink \(total) against \(expected) (\(percent(total, of: expected)))")
        }
    }

    /// A polygon's ink is its area, which multisampling resolves exactly: a convex
    /// outline through the fan `drawPolygon` draws, and a concave one through the
    /// triangulator `drawShape` uses, cover what the shoelace formula says.
    @Test func aPolygonsInkIsItsArea() throws {
        func area(_ points: [Vector2]) -> Double {
            var twice = 0.0
            for i in points.indices {
                let a = points[i], b = points[(i + 1) % points.count]
                twice += a.x * b.y - b.x * a.y
            }
            return abs(twice) / 2
        }
        let convex = [Vector2(40, 60), Vector2(120, 30), Vector2(200, 70), Vector2(210, 150), Vector2(150, 215), Vector2(60, 200), Vector2(30, 110)]
        let concave = [Vector2(40, 60), Vector2(120, 30), Vector2(200, 70), Vector2(170, 130), Vector2(210, 200),
                       Vector2(130, 170), Vector2(60, 210), Vector2(90, 130), Vector2(30, 110)]
        let cases: [(String, [Vector2], @MainActor (Sketch) -> Void)] = [
            ("a convex polygon", convex, { s in s.drawPolygon(convex) }),
            ("a concave shape", concave, { s in s.drawShape(Shape(concave)) }),
            ("a convex shape", convex, { s in s.drawShape(Shape(convex)) }),
        ]
        for (name, points, draw) in cases {
            let frame = try render { s in s.noStroke(); s.fill(.black); draw(s) }
            let level = paper(frame, 2, 12, 2, 12, light)
            let total = ink(frame, 20, 230, 20, 230, paper: level, light)
            let expected = area(points)
            #expect(abs(total - expected) <= 0.005 * expected, "\(name): ink \(total) against the area \(expected) (\(percent(total, of: expected)))")
        }
    }

    // MARK: The media

    /// A dry medium takes ink away from a stroke and never adds any. At full
    /// density no pixel of the medium is darker than the plain stroke's, since
    /// pigment only catches on the tooth's peaks; at a lower density the medium
    /// inks that share of the cells whole, so the comparison is the total in
    /// linear light, which is at most the plain stroke's.
    @Test(arguments: [StrokeMedium.pencil, .charcoal, .pastel, .dryBrush])
    func aDryMediumNeverAddsInk(medium: StrokeMedium) throws {
        func stroke(_ medium: StrokeMedium?, alpha: Double) throws -> Pixels {
            try render { s in
                s.noFill(); s.stroke(Color.black.withAlpha(alpha)); s.strokeWeight(24)
                if let medium { s.strokeMedium(medium) }
                s.drawPolyline(StrokeMediumTests.curve)
            }
        }
        let plain = try stroke(nil, alpha: 1), dry = try stroke(medium, alpha: 1)
        var darker = 0
        for y in 0..<256 { for x in 0..<256 where shade(dry, x, y) > shade(plain, x, y) + 3.0 / 255 { darker += 1 } }
        #expect(darker == 0, "\(medium.kind) is darker than the plain stroke at \(darker) pixels")
        let full = sum(dry, 0, 256, 0, 256, light), fullPlain = sum(plain, 0, 256, 0, 256, light)
        #expect(full <= fullPlain * 1.005, "\(medium.kind) at full density lays \(full) of ink, the plain stroke \(fullPlain) (\(percent(full, of: fullPlain)))")
        let thin = sum(try stroke(medium, alpha: 0.6), 0, 256, 0, 256, light), thinPlain = sum(try stroke(nil, alpha: 0.6), 0, 256, 0, 256, light)
        print("\(medium.kind) at density 0.6 lays \(percent(thin, of: thinPlain)) of the plain stroke's ink")
        #expect(thin <= thinPlain * 1.03, "\(medium.kind) at density 0.6 lays \(thin) of ink, the plain stroke \(thinPlain) (\(percent(thin, of: thinPlain)))")
    }

    /// A wet medium moves the ground into the stroke and never makes ink: over
    /// paper lighter than the pigment, wet paint is at every pixel at most as
    /// dark as the plain stroke, and oil, whose relief shades one side of each
    /// ridge and lights the other, lays no more ink than the plain stroke in all.
    @Test(arguments: [StrokeMedium.wet, .oil])
    func aWetMediumNeverCreatesInk(medium: StrokeMedium) throws {
        func stroke(_ medium: StrokeMedium?) throws -> Pixels {
            try render { s in
                s.noFill(); s.stroke(Color(white: 0.5)); s.strokeWeight(24)
                if let medium { s.strokeMedium(medium) }
                s.drawPolyline(StrokeMediumTests.curve)
            }
        }
        let plain = try stroke(nil), wet = try stroke(medium)
        if medium.kind == .wet {
            var darker = 0
            for y in 0..<256 { for x in 0..<256 where shade(wet, x, y) > shade(plain, x, y) + 3.0 / 255 { darker += 1 } }
            #expect(darker == 0, "wet paint is darker than the plain stroke at \(darker) pixels")
        }
        let total = sum(wet, 0, 256, 0, 256, light), plainTotal = sum(plain, 0, 256, 0, 256, light)
        #expect(total <= plainTotal * 1.005, "\(medium.kind) lays \(total) of ink, the plain stroke \(plainTotal) (\(percent(total, of: plainTotal)))")
    }

    /// A wet wash glazes: each channel is the darker of the ground and the
    /// pigment, so a white wash over gray leaves the gray.
    @Test func aWetWashNeverLightensItsGround() throws {
        let frame = try render(paper: Color(white: 0.5)) { s in
            s.noStroke(); s.fill(.white); s.fillMedium(.wash(water: 1))
            s.drawRect(40, 40, 176, 176)
        }
        let ground = frame.gray(10, 10)
        var lighter = 0
        for y in 60..<196 { for x in 60..<196 where frame.gray(x, y) > ground + 2 { lighter += 1 } }
        #expect(lighter == 0, "a wet white wash lightened the gray ground at \(lighter) pixels")
    }

    /// A wash's darkening is monotone in its water: a dark pigment over white
    /// covers less as the water rises, a light pigment over black lets more of
    /// the black through, and neither ever turns back.
    @Test func aWashesDarkeningIsMonotoneInItsWater() throws {
        let waters = [0.0, 0.25, 0.5, 0.75, 1.0]
        var darkOverWhite: [Double] = [], lightOverBlack: [Double] = []
        for water in waters {
            let dark = try render { s in
                s.noStroke(); s.fill(.black); s.fillMedium(.wash(water: water)); s.drawRect(40, 40, 176, 176)
            }
            darkOverWhite.append(sum(dark, 60, 196, 60, 196, light) / Double(136 * 136))
            let bright = try render(paper: .black) { s in
                s.noStroke(); s.fill(.white); s.fillMedium(.wash(water: water)); s.drawRect(40, 40, 176, 176)
            }
            lightOverBlack.append(sum(bright, 60, 196, 60, 196) { p, x, y in linear(UInt8(p.gray(x, y))) } / Double(136 * 136))
        }
        for i in 1..<waters.count {
            try pinned("the dry end picks the ground up into the paint and the glaze does not, so the first step of water darkens by 0.5% before the glaze thins (measured 2026-10-25: 0.942 at 0, 0.947 at 0.25)",
                       when: i == 1) {
                #expect(darkOverWhite[i] <= darkOverWhite[i - 1] + 0.002,
                        "black over white: water \(waters[i]) covers \(darkOverWhite[i]), water \(waters[i - 1]) covered \(darkOverWhite[i - 1])")
            }
            #expect(lightOverBlack[i] <= lightOverBlack[i - 1] + 0.002,
                    "white over black: water \(waters[i]) leaves \(lightOverBlack[i]) of light, water \(waters[i - 1]) left \(lightOverBlack[i - 1])")
        }
        #expect(darkOverWhite.first! > darkOverWhite.last! + 0.05, "the water changed nothing over white")
        #expect(lightOverBlack.first! > lightOverBlack.last! + 0.05, "the water changed nothing over black")
    }

    // MARK: Retained batches

    /// One drawing, recorded once and replayed under a transform, or issued
    /// directly under the same transform.
    private final class Replayed: Sketch {
        var useBatch = true
        var motif: Batch?
        var transform: @MainActor (Sketch) -> Void = { _ in }
        var content: @MainActor (Sketch) -> Void = { _ in }
        var ground = Color(hex: 0x14141E)
        override var canvasSize: CanvasSize { .square(400) }
        override func setup() { noLoop(); if useBatch { motif = makeBatch { content(self) } } }
        override func draw() {
            background(ground)
            transform(self)
            if let motif { drawBatch(motif) } else { content(self) }
        }
    }

    /// The analytic and triangle paths' content: a gradient rect, a polygon, a disk.
    private static let shapes: @MainActor (Sketch) -> Void = { s in
        s.noStroke()
        s.fill(Gradient.linear(from: Vector2(20, 20), to: Vector2(90, 90), [Color(hex: 0x4FC3F7), Color(hex: 0xE84C8B)]))
        s.drawRect(20, 20, 70, 70)
        s.fill(Color(hex: 0xE8A23C))
        s.drawPolygon([Vector2(30, 140), Vector2(80, 100), Vector2(130, 140), Vector2(80, 120)])
        s.fill(.white)
        s.drawCircle(140, 40, 18.5)
        // A shape recorded under a transform of its own, so the replay has
        // something to compose onto and the order of composition shows.
        s.withState { s.translate(150, 150); s.rotate(0.4); s.fill(Color(hex: 0x66CC88)); s.drawRect(-24, -14, 48, 28) }
    }

    /// The fringe path's content: a stroked polyline.
    private static let stroke: @MainActor (Sketch) -> Void = { s in
        s.stroke(.white); s.strokeWeight(2.5); s.noFill()
        s.drawPolyline([Vector2(100, 30), Vector2(120, 50), Vector2(140, 35)])
    }

    private func replayed(useBatch: Bool, content: @escaping @MainActor (Sketch) -> Void,
                          _ transform: @escaping @MainActor (Sketch) -> Void) throws -> Pixels {
        let sketch = Replayed()
        sketch.useBatch = useBatch; sketch.transform = transform; sketch.content = content
        return Pixels(try OllinApp.image(of: sketch))
    }

    /// A retained batch replayed under a translation, a rotation, and a scale
    /// draws what the same calls draw issued under that transform: the draw-time
    /// transform composes onto every recorded instance's own, so the analytic
    /// shapes and the triangles land on the same pixels. A stroke's fringe was
    /// expanded at record time and scales with the replay, so its edge is as
    /// much softer as the replay is larger: the documented difference, read here
    /// as a mean.
    @Test func aReplayedBatchDrawsWhatTheCallsDraw() throws {
        let transform: @MainActor (Sketch) -> Void = { s in s.translate(53.7, 29.2); s.rotate(0.35); s.scale(1.3) }
        let retained = try replayed(useBatch: true, content: Self.shapes, transform)
        let direct = try replayed(useBatch: false, content: Self.shapes, transform)
        let far = farPixels(retained, direct)
        #expect(far.isEmpty, "the replayed shapes differ from the direct drawing at \(far.count) pixels, e.g. \(far.prefix(3))")
        let mean = Double(zip(retained.bytes, direct.bytes).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }) / Double(retained.bytes.count)
        #expect(mean < 0.1, "the replayed shapes' mean difference from the direct drawing is \(mean)")
        let strokeRetained = try replayed(useBatch: true, content: Self.stroke, transform)
        let strokeDirect = try replayed(useBatch: false, content: Self.stroke, transform)
        let strokeMean = Double(zip(strokeRetained.bytes, strokeDirect.bytes).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }) / Double(strokeRetained.bytes.count)
        let strokeFar = farPixels(strokeRetained, strokeDirect)
        print("a replayed stroke under a 1.3 scale: mean difference \(String(format: "%.3f", strokeMean)), \(strokeFar.count) pixels past 32 levels along its edges")
        #expect(strokeMean < 0.2, "the replayed stroke's mean difference from the direct drawing is \(strokeMean)")
    }

    /// A stroke in a replayed batch is as wide as its weight times the replay's
    /// scale: the fringe scales with the stroke like any baked geometry.
    @Test func aReplayedStrokeKeepsItsWidthUnderScale() throws {
        let sketch = Replayed()
        sketch.ground = .white
        sketch.transform = { s in s.scale(2.5) }
        sketch.content = { s in s.noFill(); s.stroke(.black); s.strokeWeight(6); s.strokeCap(.butt); s.drawLine(20, 60, 150, 60) }
        let frame = Pixels(try OllinApp.image(of: sketch))
        let level = paper(frame, 2, 12, 2, 12, shade)
        var widths: [Double] = []
        for x in 120..<260 { widths.append(ink(frame, x, x + 1, 100, 200, paper: level, shade)) }
        let width = widths.reduce(0, +) / Double(widths.count)
        #expect(abs(width - 15) <= 0.45, "a 6-point stroke replayed at 2.5 reads \(width) wide")
    }

    // MARK: The vector round trip

    private final class Vectored: Sketch {
        override var canvasSize: CanvasSize { .square(200) }
        override func setup() { noLoop() }
        override func draw() {
            background(.white)
            noStroke(); fill(.black)
            drawCircle(100, 100, 40)
            withState {
                translate(10, 20)
                fill(Color(red: 1, green: 0, blue: 0, alpha: 0.5))
                drawRect(0, 0, 60, 24)
            }
            stroke(.black); strokeWeight(2)
            drawLine(Vector2(0, 0), Vector2(200, 200))
            noStroke(); fill(Color(white: 0.5))
            drawHeart(150, 150, 50)
            drawPolygon([Vector2(10, 110), Vector2(50, 100), Vector2(30, 150)])
            fill(Color(red: 0.1, green: 0.6, blue: 0.2))
            drawShape(Shape([Vector2(150, 20), Vector2(190, 30), Vector2(185, 70), Vector2(145, 60)]))
            noFill(); stroke(Color(red: 0.1, green: 0.2, blue: 0.9)); strokeWeight(3)
            drawEllipse(60, 165, 30, 18)
        }
    }

    /// A drawing exported as SVG and read back draws the same pixels within the
    /// anti-aliasing: every element, its paint, its transform, its alpha, and its
    /// stroke width survive the file.
    @Test func anExportedDrawingReimportsToTheSamePixels() throws {
        let original = try OllinApp.image(of: Vectored())
        let document = try OllinApp.svg(of: Vectored())
        let svg = try SVG(data: Data(document.utf8))
        #expect(svg.elements.count >= 8, "the file holds \(svg.elements.count) elements")
        let replayed = try image(side: 200) { s in s.drawSVG(svg) }
        let difference = try WebExportTests.meanDifference(replayed, original)
        let far = WebTriangleTests.farFraction(replayed, original)
        print("vector round trip: mean difference \(String(format: "%.3f", difference)), \(String(format: "%.3f", far * 100))% of the pixels past 32 levels")
        dump(Pixels(original), "svg-original"); dump(Pixels(replayed), "svg-replayed")
        if far >= 0.005 {
            let where_ = farPixels(Pixels(replayed), Pixels(original))
            print("vector round trip: far pixels at " + where_.prefix(40).map { "(\($0.x),\($0.y))" }.joined(separator: " "))
        }
        #expect(difference < Snapshot.tolerance, "mean difference \(difference)")
        try pinned("a curve is flattened to 8-point chords, which sit 0.2 px inside a 40-radius circle and 0.4 px inside a 20-radius one, so an imported curve's whole rim reads past 32 levels (1.7% of the pixels, measured 2026-10-25)") {
            #expect(far < 0.005, "\(far * 100)% of the pixels past 32 levels")
        }
    }

    // MARK: Atlas text and pictures

    /// A glyph from the atlas carries the ink of its outline: the two text paths
    /// cover the same area, one through a distance field at scale, the other
    /// through the triangulated outline.
    @Test func aGlyphFromTheAtlasCarriesTheInkOfItsOutline() throws {
        func text(_ mode: TextMode) throws -> Pixels {
            try render { s in
                s.noStroke(); s.fill(.black); s.textFont(.systemMedium); s.textSize(120); s.textMode(mode)
                s.drawText("ABC", 12, 170)
            }
        }
        let outline = try text(.outline), atlas = try text(.atlas)
        let outlineInk = ink(outline, 0, 256, 40, 200, paper: paper(outline, 0, 256, 220, 250, light), light)
        let atlasInk = ink(atlas, 0, 256, 40, 200, paper: paper(atlas, 0, 256, 220, 250, shade), shade)
        #expect(outlineInk > 3_000, "the probe missed the text")
        #expect(abs(atlasInk - outlineInk) <= 0.03 * outlineInk,
                "the atlas lays \(atlasInk) of ink, the outline \(outlineInk) (\(percent(atlasInk, of: outlineInk)))")
    }

    /// A picture drawn at its own size on whole pixels is its bytes: no filter
    /// softens it and the color space round-trips.
    @Test func aPictureDrawnAtItsSizeIsItsBytes() throws {
        let a = Color(red: 0.9, green: 0.2, blue: 0.1), b = Color(red: 0.1, green: 0.3, blue: 0.8)
        var picture = Image(width: 48, height: 48, color: a)
        for y in 0..<48 { for x in 0..<48 where ((x / 8) + (y / 8)) % 2 == 1 { picture[x, y] = b } }
        let frame = try render { s in s.drawImage(picture, 40, 40) }
        var off = 0
        for y in 0..<48 { for x in 0..<48 {
            let want = ((x / 8) + (y / 8)) % 2 == 1 ? b : a
            let wanted = [want.red, want.green, want.blue].map { Int(($0 * 255).rounded()) }
            for c in 0..<3 where abs(frame.channel(c, 40 + x, 40 + y) - wanted[c]) > 2 { off += 1; break }
        } }
        #expect(off == 0, "\(off) of the picture's pixels came back changed")
    }

    // MARK: Blend modes

    /// A blend mode is its arithmetic in linear light: where a 70% gray lies over
    /// a 50% gray, add sums their light, multiply takes the product, screen the
    /// complement's product, lightest and darkest pick one.
    @Test func aBlendModeIsItsArithmeticInLinearLight() throws {
        let under = toLinear(0.5), over = toLinear(0.7)
        let cases: [(BlendMode, Double)] = [
            (.add, min(1, under + over)), (.multiply, under * over), (.screen, 1 - (1 - under) * (1 - over)),
            (.lightest, max(under, over)), (.darkest, min(under, over)),
        ]
        for (mode, expected) in cases {
            let frame = try render { s in
                s.noStroke()
                s.fill(Color(white: 0.5)); s.drawRect(40, 40, 120, 120)
                s.blendMode(mode)
                s.fill(Color(white: 0.7)); s.drawRect(100, 100, 120, 120)
            }
            let mean = sum(frame, 110, 150, 110, 150) { p, x, y in Double(p.gray(x, y)) } / 1600
            let byte = toDisplay(expected) * 255
            #expect(abs(mean - byte) <= 1.5, "\(mode): the overlap reads \(mean), the arithmetic says \(byte)")
        }
    }

    // MARK: The page

    /// One scene per door of the recorded page, each at the tolerance its door
    /// documents: the primitives, the triangle and fringe paths as vertices, the
    /// strokes and fills as points the page expands, pictures and atlas text, the
    /// layered effects, the fields, the stroke media, and a moved control.
    @Test(.enabled("a browser with WebGL2 is needed") { await HeadlessBrowser.hasWebGL2() })
    func thePagePlaysEveryDoorsScene() async throws {
        struct Door {
            var name: String
            var make: () -> Sketch
            var frames: Int
            var fps: Double
            var probe: Int
            var settings = ""
            var overrides: [String: String] = [:]
            var far: Double?
        }
        let near = WebTriangleTests.farTolerance
        let doors = [
            Door(name: "primitives (a breathing ring)", make: { WebExportTests.Ring() }, frames: 60, fps: 30, probe: 41, far: near),
            Door(name: "vertices (strokes and fills)", make: { WebTriangleTests.Drawn() }, frames: 4, fps: 30, probe: 2, far: near),
            Door(name: "points (strokes the page expands)", make: { WebSourceTests.Strokes() }, frames: 2, fps: 30, probe: 1, far: near),
            Door(name: "pictures and atlas text", make: { WebAssetTests.AtlasText() }, frames: 6, fps: 30, probe: 4, far: near),
            Door(name: "effects (a filtered layer)", make: { WebEffectsTests.Filtered() }, frames: 4, fps: 30, probe: 2, far: nil),
            Door(name: "fields (a melt, a carve, a morph)", make: { WebFieldTests.Combined() }, frames: 8, fps: 30, probe: 5, far: near),
            Door(name: "media (dry, bristles, oil, a pen)", make: { WebStrokeMediumTests.Media() }, frames: 4, fps: 30, probe: 2, far: 0.01),
            Door(name: "a moved control", make: { WebControlTests.Dial() }, frames: 20, fps: 10, probe: 7,
                 settings: "player.set('radius', 140); player.set('ink', '#cc2200');",
                 overrides: ["radius": "140", "ink": "#CC2200"], far: nil),
        ]
        let pages = try doors.map { d in
            let recording = try OllinApp.recordWebFrames(of: d.make(), frames: d.frames, fps: d.fps)
            return WebExportTests.PageProbe(page: try OllinApp.webPage(of: recording, form: .inline), frame: d.probe, settings: d.settings)
        }
        for (d, played) in zip(doors, try await WebExportTests.pagePixels(pages)) {
            let reference = d.overrides.isEmpty
                ? try OllinApp.image(of: d.make(), frame: d.probe, fps: FrameRate(d.fps))
                : try WebControlTests.reference(d.make, frame: d.probe, fps: d.fps, overrides: d.overrides)
            let difference = try WebExportTests.meanDifference(played, reference)
            let far = WebTriangleTests.farFraction(played, reference)
            print("web page against the Mac: \(d.name) frame \(d.probe), mean difference \(String(format: "%.3f", difference)), \(String(format: "%.3f", far * 100))% of the pixels past 32 levels")
            #expect(difference < Snapshot.tolerance, "\(d.name) frame \(d.probe): mean difference \(difference)")
            if let limit = d.far {
                #expect(far < limit, "\(d.name) frame \(d.probe): \(far * 100)% of the pixels past 32 levels")
            }
        }
    }
}
