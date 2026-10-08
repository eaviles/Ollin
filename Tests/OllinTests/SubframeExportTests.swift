@testable import Ollin
import Testing
import CoreGraphics
import Foundation

/// The export that draws each frame at several moments across the shutter and
/// averages them (`--subframes`). It is the reference the canvas motion blur is
/// measured against, so it is held here to the analytic streak itself: a box
/// that crosses at a known speed while the shutter is open leaves exactly the
/// light its coverage integrates to over the opening.
@Suite
@MainActor
struct SubframeExportTests {

    // MARK: Linear read-back

    /// One frame in linear light, read before the tone map, the dither, and the
    /// 8-bit encode, so a profile can be read to a fraction of a level.
    struct Linear {
        let width: Int
        let height: Int
        let rgb: [Float]
        func red(_ x: Int, _ y: Int) -> Double { Double(rgb[(y * width + x) * 3]) }
        /// The red channel down column `x`, averaged over rows `rows`.
        func column(_ x: Int, rows: Range<Int>) -> Double {
            rows.reduce(0) { $0 + red(x, $1) } / Double(rows.count)
        }
        /// Every channel of every pixel, summed.
        var total: Double { rgb.reduce(0) { $0 + Double($1) } }
    }

    /// Render frame `n` of `sketch` with `subframes` moments (1 draws it once),
    /// reading the frame back in linear light.
    static func render(_ sketch: Sketch, frame n: Int, subframes: Int = 1,
                       shutter: Double? = nil) throws -> Linear {
        let renderer = try OllinApp.headlessRenderer(for: sketch)
        OllinApp.isRenderingHeadless = true
        OllinApp.exportSubframes = subframes
        OllinApp.exportShutter = shutter
        defer {
            OllinApp.isRenderingHeadless = false
            OllinApp.exportSubframes = 1
            OllinApp.exportShutter = nil
        }
        renderer.automaticQuality = .detail
        renderer.capturesLinearFrame = true
        _ = try OllinApp.renderImage(of: sketch, frame: n, fps: 60, renderer: renderer)
        let linear = try #require(renderer.lastLinearFrame)
        let count = linear.width * linear.height
        let halfs = linear.color.contents().bindMemory(to: Float16.self, capacity: count * 4)
        var rgb = [Float](repeating: 0, count: count * 3)
        for i in 0..<count {
            for c in 0..<3 { rgb[i * 3 + c] = Float(halfs[i * 4 + c]) }
        }
        return Linear(width: linear.width, height: linear.height, rgb: rgb)
    }

    /// The streak a box of `width` pixels leaves when its left edge sweeps
    /// uniformly from `left0` to `left1` while the shutter is open: each pixel's
    /// covered area averaged over the opening, by a fine numerical integral.
    /// Written here from the definition, so the reference does not share code
    /// with what it checks.
    static func streak(pixel p: Int, width: Double, left0: Double, left1: Double) -> Double {
        let steps = 4000
        var sum = 0.0
        for s in 0..<steps {
            let left = left0 + (left1 - left0) * (Double(s) + 0.5) / Double(steps)
            let covered = min(Double(p + 1), left + width) - max(Double(p), left)
            sum += min(1, max(0, covered))
        }
        return sum / Double(steps)
    }

    // MARK: The reference itself

    /// A 24-pixel box crossing at 20 pixels a frame under a fully open shutter
    /// averages to the analytic streak: a four-pixel plateau at the box's own
    /// value and a twenty-pixel ramp on either side, column by column.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aMovingBoxAveragesToItsAnalyticStreak() throws {
        let sharp = try Self.render(SubframeBoxProbe(), frame: 3)
        let streaked = try Self.render(SubframeBoxProbe(), frame: 3, subframes: 20, shutter: 1)
        let rows = 90..<102                             // inside the box, clear of its top and bottom edges
        let value = sharp.column(SubframeBoxProbe.center(at: 3), rows: rows)
        #expect(value > 0.2, "the box drew nothing: \(value)")
        // The left edge at the frame's instant, in canvas pixels, and the sweep
        // the open shutter gives it: half a frame's travel either side.
        let left = Double(SubframeBoxProbe.center(at: 3)) + 0.5 - 12
        var worst = 0.0
        for x in 60..<160 {
            let expected = value * Self.streak(pixel: x, width: 24, left0: left - 10, left1: left + 10)
            worst = max(worst, abs(streaked.column(x, rows: rows) - expected))
        }
        // Twenty moments step the edge a pixel at a time, which the integral
        // smooths by at most an eighth of a moment's share at a ramp's ends.
        #expect(worst < 0.01 * value + 0.002, "a column strayed \(worst) from the analytic streak (box \(value))")
        // And no light is made or lost.
        #expect(abs(streaked.total / sharp.total - 1) < 0.002,
                "the streak holds \(streaked.total / sharp.total) of the box's light")
    }

    /// A 2D sketch blurs the same way: the moments do not care what drew them.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aFlatShapeStreaksAndKeepsItsLight() throws {
        let sharp = try Self.render(SubframeFlatProbe(), frame: 3)
        let streaked = try Self.render(SubframeFlatProbe(), frame: 3, subframes: 16, shutter: 1)
        #expect(abs(streaked.total / sharp.total - 1) < 0.003,
                "the streak holds \(streaked.total / sharp.total) of the shape's light")
        // The streak reaches past where the sharp shape stops, and its middle
        // is dimmer than the shape, since the shape spent part of the opening
        // elsewhere.
        let rows = 90..<102
        let edge = SubframeFlatProbe.right(at: 3)
        #expect(sharp.column(edge + 6, rows: rows) < 0.002)
        #expect(streaked.column(edge + 6, rows: rows) > 0.02)
    }

    /// A picture that does not move is the same picture however many moments
    /// it is drawn at.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aStillPictureIsUnchanged() throws {
        let once = try Self.render(SubframeStillProbe(), frame: 2)
        let four = try Self.render(SubframeStillProbe(), frame: 2, subframes: 4)
        #expect(once.rgb == four.rgb)
    }

    // MARK: The clock the sketch sees

    /// Every moment is a draw: `time` steps through the shutter, centered on the
    /// frame's instant, `deltaTime` is the time since the draw before, and
    /// `frameCount` counts each draw.
    @Test(.enabled(if: Snapshot.hasMetal))
    func everyMomentIsADraw() throws {
        let probe = SubframeClockProbe()
        _ = try Self.render(probe, frame: 3, subframes: 4, shutter: 0.5)
        // Frames 0, 1, and 2 once each, then frame 3's four moments.
        #expect(probe.draws.count == 7)
        let moments = probe.draws.suffix(4)
        let instant = 3.0 / 60
        for (i, draw) in moments.enumerated() {
            let expected = instant + 0.5 / 60 * ((Double(i) + 0.5) / 4 - 0.5)
            #expect(abs(draw.time - expected) < 1e-12, "moment \(i) at \(draw.time), not \(expected)")
        }
        #expect(probe.draws.map(\.frameCount) == Array(1...7))
        for (before, after) in zip(probe.draws, probe.draws.dropFirst()) {
            #expect(abs(after.deltaTime - (after.time - before.time)) < 1e-12)
        }
    }

    /// The first frame's shutter cannot open before the run began: its early
    /// moments are drawn at time 0, never before it.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theFirstFrameNeverReachesBeforeTimeZero() throws {
        let probe = SubframeClockProbe()
        _ = try Self.render(probe, frame: 0, subframes: 4, shutter: 1)
        let times = probe.draws.map(\.time)
        #expect(times.count == 4)
        for (time, expected) in zip(times, [0, 0, 0.125 / 60, 0.375 / 60]) {
            #expect(abs(time - expected) < 1e-12, "a moment at \(time), not \(expected)")
        }
    }

    /// Unsaid, the shutter is the one the sketch asks of its canvas blur.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theShutterComesFromTheSketch() throws {
        let probe = SubframeClockProbe()
        probe.shutter = 1
        _ = try Self.render(probe, frame: 3, subframes: 2)
        let times = probe.draws.suffix(2).map(\.time)
        #expect(abs(times[0] - (3 - 0.25) / 60) < 1e-12)
        #expect(abs(times[1] - (3 + 0.25) / 60) < 1e-12)
    }

    // MARK: What stands down and what is refused

    /// The sketch's own canvas blur stands down under the moments, since they
    /// are the blur: the export with it asked for is the export without it.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theCanvasBlurStandsDown() throws {
        let blurred = SubframeBoxProbe()
        blurred.asksForCanvasBlur = true
        let with = try Self.render(blurred, frame: 3, subframes: 8, shutter: 1)
        let without = try Self.render(SubframeBoxProbe(), frame: 3, subframes: 8, shutter: 1)
        #expect(with.rgb == without.rgb)
    }

    /// A picture the GPU carries from draw to draw would step once per moment,
    /// so the export refuses it and says which one.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aCarriedPictureIsRefusedByName() throws {
        for (carrier, name) in [(SubframeCarrierProbe.Carrier.pile, "noClear()"),
                                (.feedback, "makeFeedback")] {
            let probe = SubframeCarrierProbe()
            probe.carrier = carrier
            do {
                _ = try Self.render(probe, frame: 2, subframes: 4)
                Issue.record("the \(name) sketch exported under --subframes")
            } catch let error as ExportError {
                #expect(error.kind == .unsupported)
                #expect("\(error)".contains(name), "the refusal did not name \(name): \(error)")
            }
        }
    }

    /// The recipe says how many moments made the frame and how far apart.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theRecipeSaysSo() throws {
        let probe = SubframeBoxProbe()
        _ = try Self.render(probe, frame: 3, subframes: 6, shutter: 0.75)
        OllinApp.exportSubframes = 6
        defer { OllinApp.exportSubframes = 1 }
        let recipe = ExportMetadata.capture(from: probe, frame: 3, fps: 60).recipe
        #expect(recipe.contains("\"subframes\":6"))
        #expect(recipe.contains("\"shutter\":0.75"))
        OllinApp.exportSubframes = 1
        #expect(!ExportMetadata.capture(from: probe, frame: 3, fps: 60).recipe.contains("subframes"))
    }
}

// MARK: - The probe scenes

/// A 24-pixel box under a pixel-exact orthographic camera, crossing at 20
/// pixels a frame by the clock, so every moment of a twenty-moment, fully open
/// shutter lands its edges on whole pixels and the triangle path covers them
/// exactly.
private final class SubframeBoxProbe: Sketch {
    var asksForCanvasBlur = false

    /// The column whose middle the box's center sits on at frame `n`'s instant.
    /// Its edges are then on half pixels, and a moment a whole pixel either
    /// side puts them on whole ones.
    static func center(at n: Int) -> Int { 96 + 20 * n - 40 }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        ortho(eye: Vector3(0, 0, 100), target: .zero, height: 192, near: 1, far: 200)
        if asksForCanvasBlur { motionBlur(shutter: 1) }
        noStroke()
        fill(Color(white: 0.6))
        withMotion {
            withState {
                translate(1200 * time - 40 + 0.5, 0, 0)
                drawBox(width: 24, height: 24, depth: 2)
            }
        }
    }
}

/// The same crossing drawn flat, through the triangle path.
private final class SubframeFlatProbe: Sketch {
    static func right(at n: Int) -> Int { 60 + 20 * n + 24 }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        noStroke()
        fill(Color(white: 0.6))
        let x = 1200 * time + 60
        drawPolygon([Vector2(x, 84), Vector2(x + 24, 84), Vector2(x + 24, 108), Vector2(x, 108)])
    }
}

/// A picture with nothing in it that moves.
private final class SubframeStillProbe: Sketch {
    override var canvasSize: CanvasSize { .square(96) }

    override func draw() {
        background(Color(white: 0.2))
        fill(Color(red: 0.8, green: 0.4, blue: 0.1))
        drawCircle(48, 48, 30)
        fill(Color(white: 0.9))
        drawRect(10, 10, 20, 50)
    }
}

/// Writes down the clock of every draw.
private final class SubframeClockProbe: Sketch {
    struct Draw { let time: Double; let deltaTime: Double; let frameCount: Int }
    var draws: [Draw] = []
    var shutter: Double?

    override var canvasSize: CanvasSize { .square(32) }

    override func draw() {
        draws.append(Draw(time: time, deltaTime: deltaTime, frameCount: frameCount))
        background(.black)
        if let shutter {
            camera(Camera3D(eye: Vector3(0, 0, 5), target: .zero))
            motionBlur(shutter: shutter)
        }
        drawCircle(16 + 10 * time, 16, 4)
    }
}

/// A sketch whose picture the GPU carries from one draw to the next.
private final class SubframeCarrierProbe: Sketch {
    enum Carrier { case pile, feedback }
    var carrier = Carrier.pile
    var trail: Feedback?

    override var canvasSize: CanvasSize { .square(32) }

    override func draw() {
        switch carrier {
        case .pile:
            noClear()
            drawCircle(16 + 100 * time, 16, 3)
        case .feedback:
            background(.black)
            let trail = self.trail ?? makeFeedback()
            self.trail = trail
            withFeedback(trail) { prev in
                drawImage(prev, 0, 0)
                drawCircle(16 + 100 * time, 16, 3)
            }
            drawImage(trail.image, 0, 0)
        }
    }
}
