import CoreGraphics
import Testing
@testable import Ollin

/// Stroke dynamics is an interactive feature, so a pixel snapshot cannot cover
/// it: nothing in a headless render moves a pointer. These pin it the way the
/// width profiles are pinned instead, with unit tests over the measurement and
/// the mapping, plus a few rendered probes driven by a synthetic hand.
///
/// The load-bearing one is `recordingIsFrameRateIndependent`. A mark measures
/// speed from how far the pointer moved per frame, and the whole feature is
/// worthless if the same gesture comes out fatter on a 60 Hz display than on a
/// 120 Hz one.
@Suite
@MainActor
struct StrokeDynamicsTests {

    // MARK: The mapping

    @Test
    func uniformAsksForNothing() {
        #expect(StrokeDynamics.uniform.isUniform)
        let m = StrokeDynamics.uniform.multipliers(for: StrokeInput())
        #expect(m.width == 1)
        #expect(m.opacity == 1)
        // Everything else takes the varying path, even when it happens to be flat.
        #expect(!StrokeDynamics.speed().isUniform)
        #expect(!StrokeDynamics(opacity: .pressure(light: 1)).isUniform)
        // An axis left out stays neutral, so nothing is driven by accident.
        #expect(StrokeDynamics(width: .speed(fast: 0.1))
                    .multipliers(for: StrokeInput(speed: 5000)).opacity == 1)
    }

    @Test
    func speedThinsAsTheHandHurries() {
        let d = StrokeDynamics(width: .speed(reference: 1000, slow: 1, fast: 0.2))
        #expect(abs(d.multipliers(for: StrokeInput(speed: 0)).width - 1) < 1e-12)
        #expect(abs(d.multipliers(for: StrokeInput(speed: 500)).width - 0.6) < 1e-12)
        #expect(abs(d.multipliers(for: StrokeInput(speed: 1000)).width - 0.2) < 1e-12)
        // Past the reference it holds, rather than thinning away to nothing.
        #expect(abs(d.multipliers(for: StrokeInput(speed: 9000)).width - 0.2) < 1e-12)
    }

    /// Swapping the two ends reverses the mapping, for a mark that swells as it
    /// speeds up. This is why they are two arguments and not a range.
    @Test
    func speedCanBeMappedEitherWay() {
        let d = StrokeDynamics(width: .speed(reference: 1000, slow: 0.2, fast: 1))
        #expect(abs(d.multipliers(for: StrokeInput(speed: 0)).width - 0.2) < 1e-12)
        #expect(abs(d.multipliers(for: StrokeInput(speed: 1000)).width - 1) < 1e-12)
    }

    @Test
    func pressureSwellsUnderForce() {
        let d = StrokeDynamics(width: .pressure(light: 0.1),
                               opacity: .pressure(light: 0.4))
        let light = d.multipliers(for: StrokeInput(pressure: 0))
        let heavy = d.multipliers(for: StrokeInput(pressure: 1))
        #expect(abs(light.width - 0.1) < 1e-12)
        #expect(abs(light.opacity - 0.4) < 1e-12)
        #expect(abs(heavy.width - 1) < 1e-12)
        #expect(abs(heavy.opacity - 1) < 1e-12)
        // A device that cannot measure pressure reports 1, so it draws at `heavy`
        // rather than not drawing at all.
        #expect(abs(d.multipliers(for: StrokeInput()).width - 1) < 1e-12)
    }

    @Test
    func multipliersAreClamped() {
        let d = StrokeDynamics(width: StrokeResponse { _ in -5 },
                               opacity: StrokeResponse { _ in 4 })
        let m = d.multipliers(for: StrokeInput())
        #expect(m.width == 0)
        #expect(m.opacity == 1)
    }

    // MARK: Measuring the hand

    /// The same gesture at two frame rates records the same mark. A mark measures
    /// distance per frame, so without dividing by the real elapsed time a 120 Hz
    /// display would read every stroke as half as fast and lay down a fatter mark.
    @Test
    func recordingIsFrameRateIndependent() {
        /// Walk 400 points to the right at a steady 600 points per second.
        func walk(fps: Double) -> StrokeMark {
            var mark = StrokeMark(.speed(reference: 1200, fast: 0.1), smoothing: 0.5)
            let dt = 1 / fps, step = 600 / fps
            for i in 0...Int(fps) {   // one second of travel either way
                mark.record(Vector2(20 + step * Double(i), 50), dt: dt)
            }
            return mark
        }
        let slow = walk(fps: 60), fast = walk(fps: 120)
        #expect(!slow.isEmpty && !fast.isEmpty)
        // Both hands moved at 600 points per second, so both marks settle on the
        // same width: 1 - 600/1200 * (1 - 0.1) = 0.55.
        let a = slow.samples.last!.width, b = fast.samples.last!.width
        #expect(abs(a - 0.55) < 0.02)
        #expect(abs(a - b) < 0.01)
        // And they cover the same ground.
        #expect(abs(slow.length - fast.length) < 1e-6)
    }

    /// A hand held still adds nothing. Without this a paused pointer would pile
    /// hundreds of coincident points into one spot every second.
    @Test
    func aStillHandRecordsNothing() {
        var mark = StrokeMark()
        for _ in 0..<200 { mark.record(Vector2(40, 40), dt: 1.0 / 60) }
        #expect(mark.count == 0)
        #expect(mark.isEmpty)
    }

    /// Frames whose motion falls under `minimumSpacing` bank their time rather
    /// than dropping it, so the point that finally lands measures its speed over
    /// the whole interval. Spending only the last frame's time instead would read
    /// a slow, finely-sampled hand as a fast one.
    @Test
    func skippedFramesBankTheirTime() {
        var mark = StrokeMark(StrokeDynamics(width: .speed(reference: 1000, fast: 0)),
                              smoothing: 0)
        mark.minimumSpacing = 5
        // One point per frame, 1 point apart, at 60 fps: a true 60 points/second.
        for i in 0...120 { mark.record(Vector2(Double(i), 0), dt: 1.0 / 60) }
        #expect(mark.count > 2)
        // 60 of 1000 leaves the width at 0.94. Reading 5 points against a single
        // frame's 1/60 s would give 300 points/second and a width of 0.7.
        #expect(abs(mark.samples.last!.width - 0.94) < 0.03)
    }

    /// The first point is held back until a second one gives it a heading, so a
    /// direction-driven brush starts with an honest direction rather than a
    /// made-up one. A one-point mark draws nothing anyway.
    @Test
    func theFirstPointWaitsForItsHeading() {
        var mark = StrokeMark(StrokeDynamics(width: StrokeResponse { $0.direction.y }))
        mark.record(Vector2(0, 0), dt: 1.0 / 60)
        #expect(mark.count == 0)
        mark.record(Vector2(0, 30), dt: 1.0 / 60)      // heading straight down
        #expect(mark.count == 2)
        #expect(abs(mark.samples[0].width - 1) < 1e-9) // and the held point got it
    }

    @Test
    func clearResetsTheMeasurement() {
        var mark = StrokeMark()
        for i in 0...30 { mark.record(Vector2(Double(i) * 10, 0), dt: 1.0 / 60) }
        #expect(mark.count > 2)
        mark.clear()
        #expect(mark.count == 0)
        #expect(mark.length == 0)
        #expect(mark.bounds == nil)
        // A fresh first point is held again, which means the filters really reset.
        mark.record(Vector2(500, 500), dt: 1.0 / 60)
        #expect(mark.count == 0)
    }

    @Test
    func appendedSamplesBypassTheDynamics() {
        var mark = StrokeMark(.speed(fast: 0))
        mark.append(StrokeMark.Sample(position: Vector2(0, 0), width: 0.3, opacity: 0.5))
        mark.append(StrokeMark.Sample(position: Vector2(100, 0), width: 0.7, opacity: 0.9))
        #expect(mark.samples.map(\.width) == [0.3, 0.7])
        #expect(abs(mark.length - 100) < 1e-12)
    }

    /// Opacity averaged for vector export is weighted by distance, not by point
    /// count, so a spot the hand lingered over does not outvote the sweep.
    @Test
    func averageOpacityIsWeightedByDistance() {
        var mark = StrokeMark()
        // Three points clustered at 0 (opacity 0) then one far point (opacity 1).
        mark.append(StrokeMark.Sample(position: Vector2(0, 0), opacity: 0))
        mark.append(StrokeMark.Sample(position: Vector2(1, 0), opacity: 0))
        mark.append(StrokeMark.Sample(position: Vector2(101, 0), opacity: 1))
        // The 100-long span at a mean of 0.5 dominates the 1-long span at 0.
        #expect(abs(mark.averageOpacity - 0.4950) < 0.001)
    }

    // MARK: Widths at their real positions

    /// A mark's widths reach the stroke expander at the fractions where they were
    /// measured. A recorded hand slows and hurries, so its points are not evenly
    /// spaced, and spreading the widths evenly would slide every one of them off
    /// the place it belongs.
    @Test
    func pathFractionsFollowDistanceNotIndex() {
        var mark = StrokeMark()
        // Three points bunched in the first tenth, one at the far end.
        for (x, w) in [(0.0, 1.0), (5.0, 0.9), (10.0, 0.8), (100.0, 0.2)] {
            mark.append(StrokeMark.Sample(position: Vector2(x, 0), width: w))
        }
        let f = mark.pathFractions
        #expect(f == [0, 0.05, 0.1, 1])
        // Evenly spaced they would be [0, 1/3, 2/3, 1], which would put the 0.8
        // sample two thirds of the way along a mark it barely started.
        let profile = StrokeProfile.values(mark.samples.map(\.width), at: f)
        #expect(abs(profile(0.1) - 0.8) < 1e-12)
        #expect(abs(profile(0.55) - 0.5) < 1e-12)     // halfway between 0.8 and 0.2
    }

    @Test
    func valuesAtPositionsHoldTheirEnds() {
        let p = StrokeProfile.values([0.2, 1], at: [0.25, 0.75])
        #expect(abs(p(0) - 0.2) < 1e-12)              // before the first sample
        #expect(abs(p(0.25) - 0.2) < 1e-12)
        #expect(abs(p(0.5) - 0.6) < 1e-12)
        #expect(abs(p(1) - 1) < 1e-12)                // after the last
        // Degenerate inputs stay well defined.
        #expect(StrokeProfile.values([], at: [])(0.5) == 1)
        #expect(abs(StrokeProfile.values([0.3], at: [0.5])(0.9) - 0.3) < 1e-12)
        // Mismatched lengths take the shorter, rather than trapping.
        #expect(abs(StrokeProfile.values([0, 1, 2], at: [0, 1])(1) - 1) < 1e-12)
    }

    // MARK: Rendered behaviour

    /// A mark whose dynamics ask for nothing is a plain polyline, drawn through
    /// the same expander with the same state. This is the guarantee that the
    /// feature costs the rest of the framework nothing: it is the byte-identical
    /// promise, in one test.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aNeutralMarkDrawsExactlyLikeAPolyline() throws {
        let markProbe = NeutralMarkProbe(), lineProbe = NeutralMarkProbe()
        lineProbe.drawsMark = false
        let mark = try #require(OllinApp.image(of: markProbe))
        let line = try #require(OllinApp.image(of: lineProbe))
        #expect(pixels(of: mark).bytes == pixels(of: line).bytes)
    }

    /// The headline behaviour: ink follows the hand. The probe's mark is walked
    /// slowly down its left half and quickly down its right, so the left carries
    /// visibly more ink than the right even though the path and the stroke weight
    /// are the same all the way across.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aFastStrokeLaysDownLessInk() throws {
        let image = try #require(OllinApp.image(of: PacedMarkProbe()))
        let px = pixels(of: image)
        // Ink in a column, summed: a thick mark is saturated in the middle, so a
        // peak reading cannot see it thinning.
        func ink(_ x: Int) -> Int { (0..<128).reduce(0) { $0 + 255 - px.gray(x, $1) } }
        // The hand ends about twice as fast as it started, and the mark carries
        // about half the ink to show for it.
        #expect(Double(ink(30)) > Double(ink(225)) * 1.7)
        // And it thins steadily across the whole run rather than stepping.
        #expect(ink(60) > ink(120))
        #expect(ink(120) > ink(180))
    }

    /// Opacity-driven dynamics fade the mark without narrowing it. The two axes
    /// are separate, and a sketch that asks for one must not silently get both.
    @Test(.enabled(if: Snapshot.hasMetal))
    func opacityDynamicsFadeWithoutThinning() throws {
        let probe = PacedMarkProbe()
        probe.fadesOpacity = true
        let image = try #require(OllinApp.image(of: probe))
        let px = pixels(of: image)
        func darkest(_ x: Int) -> Int { (0..<128).map { px.gray(x, $0) }.min() ?? 255 }
        /// The mark's width at a column, measured at half its own darkness. A
        /// plain "any ink at all" count would shrink as the mark fades, since a
        /// faint mark's anti-aliased edge is indistinguishable from paper: it
        /// would report thinning that is not there.
        func widthAtHalfMax(_ x: Int) -> Int {
            let half = (255 + darkest(x)) / 2
            return (0..<128).count { px.gray(x, $0) < half }
        }
        // The fast end is markedly lighter...
        #expect(darkest(225) > darkest(30) + 60)
        // ...while staying just as wide (a pixel of anti-aliasing aside).
        #expect(abs(widthAtHalfMax(225) - widthAtHalfMax(30)) <= 1)
    }

    // MARK: Vector export

    /// A profiled mark exports as the region it covers, so a plotter draws the
    /// mark rather than a line of one width. Opacity has nowhere to live in a
    /// single filled path, so it flattens to the mark's average, which for the
    /// plotter case (one pen, one ink) costs nothing.
    @Test
    func vectorExportKeepsWidthAndFlattensOpacity() {
        let svg = OllinApp.svg(of: VectorMarkProbe())
        // A filled outline, not a stroked line: no stroke-width anywhere.
        #expect(!svg.contains("stroke-width"))
        #expect(svg.contains("<path "))
        // The average opacity of the recorded mark rides as the fill's alpha.
        #expect(svg.contains("fill-opacity="))
    }
}

// MARK: - Probes

private final class NeutralMarkProbe: Sketch {
    var drawsMark = true

    override var canvasSize: CanvasSize { .size(256, 128) }

    /// One path, drawn either as a dynamics-free mark or as the polyline it is.
    var path: [Vector2] {
        (0...40).map { i in
            let t = Double(i) / 40
            return Vector2(20 + t * 216, 64 + sin(t * .tau) * 30)
        }
    }

    override func draw() {
        background(.white)
        stroke(.black)
        strokeWeight(9)
        strokeJoin(.round)
        if drawsMark {
            var mark = StrokeMark(.uniform)
            for p in path { mark.append(StrokeMark.Sample(position: p)) }
            drawMark(mark)
        } else {
            drawPolyline(path)
        }
    }
}

/// A straight mark walked at a pace that rises across the canvas, recorded once
/// in `setup()` so the render is deterministic.
private final class PacedMarkProbe: Sketch {
    var fadesOpacity = false
    var mark = StrokeMark()

    override var canvasSize: CanvasSize { .size(256, 128) }

    override func setup() {
        // One axis each, so the two probes differ in exactly the thing they test.
        mark = StrokeMark(fadesOpacity
                          ? StrokeDynamics(opacity: .speed(reference: 900, fast: 0.1))
                          : StrokeDynamics(width: .speed(reference: 900, fast: 0.1)),
                          smoothing: 0.3)
        // 20 points per second of travel, with the step growing left to right:
        // the same path at a hand that accelerates from 90 to 1400 points/second.
        var x = 20.0
        var speed = 90.0
        while x < 236 {
            mark.record(Vector2(x, 64), dt: 1.0 / 60)
            x += speed / 60
            speed *= 1.045
        }
    }

    override func draw() {
        background(.white)
        stroke(.black)
        strokeWeight(22)
        strokeCap(.butt)
        drawMark(mark)
    }
}

private final class VectorMarkProbe: Sketch {
    override var canvasSize: CanvasSize { .square(120) }

    override func draw() {
        background(.white)
        stroke(.black)
        strokeWeight(14)
        var mark = StrokeMark()
        for i in 0...20 {
            let t = Double(i) / 20
            mark.append(StrokeMark.Sample(position: Vector2(10 + t * 100, 60),
                                          width: 0.2 + 0.8 * t,
                                          opacity: 1 - 0.6 * t))
        }
        drawMark(mark)
    }
}

// MARK: - Pixel helpers

private struct Pixels {
    var bytes: [UInt8]
    var width: Int
    func gray(_ x: Int, _ y: Int) -> Int { Int(bytes[(y * width + x) * 4]) }
}

private func pixels(of image: CGImage) -> Pixels {
    let w = image.width, h = image.height
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    bytes.withUnsafeMutableBytes { raw in
        let ctx = CGContext(data: raw.baseAddress, width: w, height: h,
                            bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return Pixels(bytes: bytes, width: w)
}
