import CoreGraphics
import Foundation
import Ollin
import Testing

/// Behavioral probes for `Filter.antialias`, the post-process pass over a layer a
/// fragment shader wrote pixel by pixel. A pixel snapshot pins one sheet of it as a
/// picture; these pin the claims a mean difference averages away.
///
/// The measurement throughout is **edge wander**: read the sub-pixel row the edge sits
/// on in each column (the coverage a column carries, taken in linear light), fit the
/// straight line those rows should lie on, and report the RMS distance from it in
/// pixels. A staircase wanders by about a third of a pixel whatever it is made of,
/// which is the sawtooth a whole-pixel edge cannot avoid; a ramp wanders far less.
/// The number is a distance, so it is worth reading directly rather than as a ratio.
/// Metal-gated.
@Suite
@MainActor
struct AntialiasFilterTests {

    // MARK: The parameter is honest

    /// Zero amount hands the layer back byte for byte, so an A/B costs nothing. It has
    /// to hold on both paths through the fragment: the pixel that returns early with
    /// no edge in it, and the pixel that walks an edge and then blends by zero.
    @Test(.enabled(if: Snapshot.hasMetal))
    func zeroAmountIsIdentity() throws {
        let plain = try #require(OllinApp.image(of: StaircaseProbe.make(nil), frame: 1))
        let zero = try #require(OllinApp.image(
            of: StaircaseProbe.make(.antialias(amount: 0)), frame: 1))
        #expect(maxDifference(plain, zero) == 0)
    }

    /// A layer with nothing in it comes back untouched. The early return is what keeps
    /// the pass off the rest of a frame, and a flat field is the whole of that case.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aFlatLayerComesBackUntouched() throws {
        let plain = try #require(OllinApp.image(of: FlatFieldProbe.make(nil), frame: 1))
        let filtered = try #require(OllinApp.image(
            of: FlatFieldProbe.make(.antialias()), frame: 1))
        #expect(maxDifference(plain, filtered) == 0)
    }

    // MARK: What it is for

    /// The headline. A shallow hard edge written by a shader steps a whole pixel every
    /// eight columns, and the pass turns those steps into a ramp: measured here, the
    /// edge wanders 0.286 px before and 0.140 px after, half the distance. Half rather
    /// than none is what this family of pass buys, since it reads an image rather than
    /// the shape that made it; the steep, silhouette, and overbright probes below all
    /// land within a hundredth of the same figure.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aStairSteppedEdgeBecomesARamp() throws {
        let plain = try #require(OllinApp.image(of: StaircaseProbe.make(nil), frame: 1))
        let smoothed = try #require(OllinApp.image(
            of: StaircaseProbe.make(.antialias()), frame: 1))
        let before = edgeWander(plain), after = edgeWander(smoothed)
        #expect(before > 0.2, "the unfiltered edge should be a staircase (\(before) px)")
        #expect(after < before * 0.5,
                "the edge still wanders \(after) px against \(before) px unfiltered")
    }

    /// It reaches an edge at any angle, not only the shallow one it is easiest to show
    /// on. A steep edge steps sideways rather than downward, which is the other branch
    /// of the run-across / run-down test, and it has to improve too.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aSteepEdgeIsSmoothedByTheOtherBranch() throws {
        let plain = try #require(OllinApp.image(of: SteepEdgeProbe.make(nil), frame: 1))
        let smoothed = try #require(OllinApp.image(
            of: SteepEdgeProbe.make(.antialias()), frame: 1))
        let before = columnWander(plain), after = columnWander(smoothed)
        #expect(before > 0.2, "the unfiltered edge should be a staircase (\(before) px)")
        #expect(after < before * 0.5,
                "the edge still wanders \(after) px against \(before) px unfiltered")
    }

    /// Following an edge further is what a shallower one needs. At one step every 24
    /// columns a short walk reports the middle of the span for most of a tread, so it
    /// hardly moves the pixel; the long walk reaches the end and lands it. Measured:
    /// 0.250 px of wander on the short look against 0.112 px on the long one.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aLongerLookHelpsAShallowerEdge() throws {
        let plain = try #require(OllinApp.image(
            of: StaircaseProbe.make(nil, slope: 1.0 / 24.0), frame: 1))
        let short = try #require(OllinApp.image(
            of: StaircaseProbe.make(.antialias(quality: .performance), slope: 1.0 / 24.0),
            frame: 1))
        let long = try #require(OllinApp.image(
            of: StaircaseProbe.make(.antialias(quality: .detail), slope: 1.0 / 24.0),
            frame: 1))
        let (raw, near, far) = (edgeWander(plain), edgeWander(short), edgeWander(long))
        #expect(far < near, "the long look (\(far) px) should beat the short one (\(near) px)")
        #expect(far < raw * 0.5, "\(far) px against \(raw) px unfiltered")
    }

    // MARK: What the threshold decides

    /// The threshold is a contrast, so a faint edge is below it and a strong one is
    /// not. Raised past the step this layer carries, the layer comes back byte for
    /// byte; lowered under it, the step grows the in-between tones a ramp is made of.
    ///
    /// Counted rather than measured as wander, because the two sides here are only 25
    /// of 255 apart, and at that contrast a single quantization step is worth about a
    /// pixel of apparent position: the wander of a faint edge is mostly rounding. The
    /// count runs 0 to 157 pixels over the window.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aThresholdAboveTheEdgeLeavesItAlone() throws {
        let faint = { (f: Filter?) in StaircaseProbe.make(f, high: 0.55, low: 0.45) }
        let plain = try #require(OllinApp.image(of: faint(nil), frame: 1))
        let ignored = try #require(OllinApp.image(
            of: faint(.antialias(threshold: 0.5)), frame: 1))
        #expect(maxDifference(plain, ignored) == 0)

        let reached = try #require(OllinApp.image(
            of: faint(.antialias(threshold: 0.02)), frame: 1))
        let before = inBetweenTones(plain), after = inBetweenTones(reached)
        #expect(before < 40, "a hard edge should have almost no in-between tones (\(before))")
        #expect(after > before * 4, "\(after) in-between pixels against \(before)")
    }

    // MARK: The two decisions the layer's own shape forces

    /// A silhouette in a transparent layer is an edge even when the shape is black.
    /// Premultiplied color is 0 on both sides of it, so a pass reading color alone
    /// finds nothing there. Reading the layer over a backdrop is what makes the alpha
    /// step a brightness step, and this is the test that fails without it.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aBlackSilhouetteOnAClearLayerIsFound() throws {
        let plain = try #require(OllinApp.image(of: ClearLayerProbe.make(nil), frame: 1))
        let smoothed = try #require(OllinApp.image(
            of: ClearLayerProbe.make(.antialias()), frame: 1))
        let before = edgeWander(plain), after = edgeWander(smoothed)
        #expect(before > 0.2, "the unfiltered silhouette should be a staircase (\(before) px)")
        #expect(after < before * 0.6,
                "the silhouette still wanders \(after) px against \(before) px")
    }

    /// An edge between two values brighter than white is still an edge. A layer is
    /// linear and the tone map is at the present pass, so a pass whose brightness
    /// clamps at 1 reads a bright pair as flat and walks away. Measured by pushing the
    /// layer above 1, smoothing it there, and bringing it back down to look.
    @Test(.enabled(if: Snapshot.hasMetal))
    func anEdgeAboveWhiteIsStillAnEdge() throws {
        let plain = try #require(OllinApp.image(of: OverbrightProbe.make(nil), frame: 1))
        let smoothed = try #require(OllinApp.image(
            of: OverbrightProbe.make(.antialias()), frame: 1))
        let before = edgeWander(plain), after = edgeWander(smoothed)
        #expect(before > 0.2, "the unfiltered edge should be a staircase (\(before) px)")
        #expect(after < before * 0.6,
                "the overbright edge still wanders \(after) px against \(before) px")
    }

    // MARK: Readback helpers

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

    private func maxDifference(_ a: CGImage, _ b: CGImage) -> Int {
        let pa = pixels(of: a), pb = pixels(of: b)
        var worst = 0
        for i in 0 ..< min(pa.bytes.count, pb.bytes.count) {
            worst = max(worst, abs(Int(pa.bytes[i]) - Int(pb.bytes[i])))
        }
        return worst
    }

    /// The green channel of one pixel, back in linear light. The present pass encodes
    /// for display, and coverage only adds up to a distance in the space it was
    /// blended in.
    private func linearValue(_ px: (bytes: [UInt8], width: Int, height: Int),
                             x: Int, y: Int) -> Double {
        let v = Double(px.bytes[(y * px.width + x) * 4 + 1]) / 255
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    /// How far the edge strays from the straight line it should lie on, in pixels
    /// (RMS). Each column's coverage down the window is the sub-pixel row the edge
    /// crosses it at; a least-squares line through those rows is where they should be.
    private func edgeWander(_ image: CGImage, window: ClosedRange<Int> = 40 ... 215,
                            columns: ClosedRange<Int> = 36 ... 220) -> Double {
        let px = pixels(of: image)
        let rows = columns.map { x in
            window.reduce(0.0) { $0 + linearValue(px, x: x, y: $1) }
        }
        return residual(of: rows)
    }

    /// The same for an edge that runs down the frame rather than across it: each row's
    /// coverage across the window is the sub-pixel column the edge crosses it at.
    private func columnWander(_ image: CGImage, window: ClosedRange<Int> = 40 ... 215,
                              rows: ClosedRange<Int> = 36 ... 220) -> Double {
        let px = pixels(of: image)
        let cols = rows.map { y in
            window.reduce(0.0) { $0 + linearValue(px, x: $1, y: y) }
        }
        return residual(of: cols)
    }

    /// How many pixels sit clear of both plateaus a two-value layer is made of: the
    /// tones a ramp has and a staircase does not. The plateaus are the two ends of the
    /// image's own tone range, so the count needs no knowledge of the colors used.
    private func inBetweenTones(_ image: CGImage) -> Int {
        let px = pixels(of: image)
        var lowest = 255, highest = 0
        for y in 40 ... 215 {
            for x in 36 ... 220 {
                let v = Int(px.bytes[(y * px.width + x) * 4 + 1])
                lowest = min(lowest, v); highest = max(highest, v)
            }
        }
        guard highest - lowest > 8 else { return 0 }
        var count = 0
        for y in 40 ... 215 {
            for x in 36 ... 220 {
                let v = Int(px.bytes[(y * px.width + x) * 4 + 1])
                if v > lowest + 3 && v < highest - 3 { count += 1 }
            }
        }
        return count
    }

    /// RMS distance from the least-squares straight line through a run of positions.
    private func residual(of positions: [Double]) -> Double {
        let n = Double(positions.count)
        guard n > 2 else { return 0 }
        let meanX = (n - 1) / 2
        let meanY = positions.reduce(0, +) / n
        var sxy = 0.0, sxx = 0.0
        for (i, y) in positions.enumerated() {
            let dx = Double(i) - meanX
            sxy += dx * (y - meanY)
            sxx += dx * dx
        }
        let slope = sxx > 0 ? sxy / sxx : 0
        var sum = 0.0
        for (i, y) in positions.enumerated() {
            let fit = meanY + slope * (Double(i) - meanX)
            sum += (y - fit) * (y - fit)
        }
        return (sum / n).squareRoot()
    }
}

// MARK: - Probes

/// A hard edge written per pixel by a shader, so it carries no coverage of its own and
/// steps a whole pixel at a time: white above, black below, rising one row every
/// `1 / slope` columns. The shape every claim here is measured on.
private final class StaircaseProbe: Sketch {
    var filter: Filter?
    var slope = 1.0 / 8.0
    var high = 1.0
    var low = 0.0

    static func make(_ filter: Filter?, slope: Double = 1.0 / 8.0,
                     high: Double = 1, low: Double = 0) -> StaircaseProbe {
        let s = StaircaseProbe()
        s.filter = filter; s.slope = slope; s.high = high; s.low = low
        return s
    }

    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        let shader = Shader("""
        float4 shade(float2 uv, ShaderInfo info) {
            float edge = 0.25 + uv.x * \(slope);
            float v = uv.y < edge ? \(high) : \(low);
            return float4(v, v, v, 1.0);
        }
        """)
        let layer = generate(shader)
        drawImage((filter.map { layer.filtered($0) } ?? layer).image, 0, 0)
    }
}

/// The same edge turned a quarter: it runs down the frame and steps sideways, which
/// takes the other branch of the run-across / run-down test.
private final class SteepEdgeProbe: Sketch {
    var filter: Filter?
    static func make(_ filter: Filter?) -> SteepEdgeProbe {
        let s = SteepEdgeProbe(); s.filter = filter; return s
    }
    override var canvasSize: CanvasSize { .square(256) }
    override func draw() {
        let shader = Shader("""
        float4 shade(float2 uv, ShaderInfo info) {
            float edge = 0.25 + uv.y * 0.125;
            float v = uv.x < edge ? 1.0 : 0.0;
            return float4(v, v, v, 1.0);
        }
        """)
        let layer = generate(shader)
        drawImage((filter.map { layer.filtered($0) } ?? layer).image, 0, 0)
    }
}

/// One flat color, edge to edge: the case the pass has to walk away from.
private final class FlatFieldProbe: Sketch {
    var filter: Filter?
    static func make(_ filter: Filter?) -> FlatFieldProbe {
        let s = FlatFieldProbe(); s.filter = filter; return s
    }
    override var canvasSize: CanvasSize { .square(256) }
    override func draw() {
        let shader = Shader("""
        float4 shade(float2 uv, ShaderInfo info) { return float4(0.6, 0.4, 0.2, 1.0); }
        """)
        let layer = generate(shader)
        drawImage((filter.map { layer.filtered($0) } ?? layer).image, 0, 0)
    }
}

/// A black shape on a layer that is otherwise clear, drawn over a white canvas. The
/// layer's premultiplied color is 0 on both sides of the silhouette, so only the alpha
/// step says an edge is there.
private final class ClearLayerProbe: Sketch {
    var filter: Filter?
    static func make(_ filter: Filter?) -> ClearLayerProbe {
        let s = ClearLayerProbe(); s.filter = filter; return s
    }
    override var canvasSize: CanvasSize { .square(256) }
    override func draw() {
        background(.white)
        let shader = Shader("""
        float4 shade(float2 uv, ShaderInfo info) {
            float edge = 0.25 + uv.x * 0.125;
            return float4(0.0, 0.0, 0.0, uv.y < edge ? 1.0 : 0.0);
        }
        """)
        let layer = generate(shader)
        drawImage((filter.map { layer.filtered($0) } ?? layer).image, 0, 0)
    }
}

/// The staircase pushed well past white, smoothed up there, and brought back down to
/// be looked at. Both sides of the edge are brighter than 1 when the pass runs.
private final class OverbrightProbe: Sketch {
    var filter: Filter?
    static func make(_ filter: Filter?) -> OverbrightProbe {
        let s = OverbrightProbe(); s.filter = filter; return s
    }
    override var canvasSize: CanvasSize { .square(256) }
    override func draw() {
        let shader = Shader("""
        float4 shade(float2 uv, ShaderInfo info) {
            float edge = 0.25 + uv.x * 0.125;
            float v = uv.y < edge ? 1.0 : 0.5;
            return float4(v, v, v, 1.0);
        }
        """)
        var layer = generate(shader).filtered(.exposure(stops: 3))
        if let filter { layer = layer.filtered(filter) }
        drawImage(layer.filtered(.exposure(stops: -3)).image, 0, 0)
    }
}
