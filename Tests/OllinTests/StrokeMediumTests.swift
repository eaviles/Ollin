import Testing
import CoreGraphics
import Foundation
import ImageIO
@testable import Ollin

/// Stroke media (`strokeMedium(_:)`): a stroke's ribbon shaded per pixel in its
/// own coordinates. Every probe renders headless and reads the frame back.
@Suite(.enabled(if: Snapshot.hasMetal))
@MainActor
struct StrokeMediumTests {

    /// The frame `draw` makes on a 256-point canvas over `ground`.
    func render(ground: Color = .white, _ draw: @escaping @MainActor (Sketch) -> Void) throws -> Pixels {
        Pixels(try OllinApp.image(of: MediumSketch(ground: ground, draw), frame: 1))
    }

    /// Writes a frame to the session's scratch folder when `OLLIN_MEDIUM_LOOK`
    /// names one, for looking at a medium while it is tuned.
    func look(_ name: String, _ draw: @escaping @MainActor (Sketch) -> Void) throws {
        guard let folder = ProcessInfo.processInfo.environment["OLLIN_MEDIUM_LOOK"] else { return }
        let image = try OllinApp.image(of: MediumSketch(ground: Color(white: 0.96), draw), frame: 1)
        let url = URL(fileURLWithPath: folder).appendingPathComponent("\(name).png")
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    /// An S-curve across the canvas, sampled finely.
    nonisolated static let curve: [Vector2] = (0...80).map { i in
        let t = Double(i) / 80
        return Vector2(24 + 208 * t, 128 + 70 * sin(t * .pi * 2))
    }

    // MARK: Reading the frame

    /// The ink a pixel holds over white: one minus its light, in linear light.
    func ink(_ p: Pixels, _ x: Int, _ y: Int) -> Double { 1 - linear(UInt8(p.gray(x, y))) }

    /// The share of a stroke's interior holding at least half the ink, and its
    /// mean ink, over the box `x0..<x1` by `y0..<y1`.
    func inkReading(_ p: Pixels, x0: Int, x1: Int, y0: Int, y1: Int) -> (lit: Double, mean: Double) {
        var lit = 0, sum = 0.0, n = 0
        for y in y0..<y1 {
            for x in x0..<x1 {
                let k = ink(p, x, y)
                if k >= 0.5 { lit += 1 }
                sum += k
                n += 1
            }
        }
        return (Double(lit) / Double(n), sum / Double(n))
    }

    /// A horizontal stroke 40 wide across the middle in `color`, under `medium`.
    func band(_ medium: StrokeMedium?, color: Color = .black,
              from x0: Double = 20, to x1: Double = 236) throws -> Pixels {
        try render { s in
            s.stroke(color)
            s.strokeWeight(40)
            if let medium { s.strokeMedium(medium) }
            s.drawLine(x0, 128, x1, 128)
        }
    }

    // MARK: Dry media

    @Test func aLightPencilLineBreaksIntoSpecklesRatherThanFading() throws {
        // At full density the pencil inks nearly the whole interior. At a third of
        // it, the share of inked pixels falls with the density while each inked
        // pixel keeps its ink: speckles. The same alpha on a plain stroke inks every
        // pixel a third, so not one pixel reaches half: a fade.
        let full = inkReading(try band(.pencil), x0: 40, x1: 216, y0: 116, y1: 140)
        let light = inkReading(try band(.pencil, color: Color.black.withAlpha(1.0 / 3)),
                               x0: 40, x1: 216, y0: 116, y1: 140)
        let fade = inkReading(try band(nil, color: Color.black.withAlpha(1.0 / 3)),
                              x0: 40, x1: 216, y0: 116, y1: 140)
        #expect(full.lit > 0.85, "a full pencil line inks \(full.lit) of its interior")
        #expect(light.lit > 0.15 && light.lit < 0.6 * full.lit,
                "a light line inks \(light.lit) of its interior against \(full.lit) at full")
        #expect(light.mean / light.lit > 0.75 * (full.mean / full.lit),
                "an inked pixel of the light line holds \(light.mean / light.lit) against \(full.mean / full.lit)")
        #expect(light.mean > 0.2 && light.mean < 0.5, "a third of the density lays \(light.mean) of the ink")
        #expect(fade.lit == 0 && abs(fade.mean - 1.0 / 3) < 0.02, "the plain stroke fades evenly (\(fade))")
    }

    @Test func pencilCharcoalAndPastelAreOneRendererUnderThreeSettings() throws {
        #expect(StrokeMedium.pencil == .dry(tooth: 1.4, softness: 0.12, roughness: 0.12))
        #expect(StrokeMedium.charcoal == .dry(tooth: 3.2, softness: 0.4, roughness: 0.5))
        #expect(StrokeMedium.pastel == .dry(tooth: 4.5, softness: 0.25, roughness: 0.35))
        for medium in [StrokeMedium.pencil, .charcoal, .pastel, .pastel(palette: [.red, .blue])] {
            #expect(medium.kind == .dry)
        }
        // A coarser tooth breaks the line into coarser grain: fewer, larger specks.
        func specks(_ p: Pixels) -> Int {
            var edges = 0
            for y in 116..<140 { for x in 40..<215 where (ink(p, x, y) >= 0.5) != (ink(p, x + 1, y) >= 0.5) { edges += 1 } }
            return edges
        }
        let pencil = specks(try band(.pencil, color: Color.black.withAlpha(0.5)))
        let pastel = specks(try band(.pastel, color: Color.black.withAlpha(0.5)))
        #expect(pencil > Int(Double(pastel) * 1.8), "pencil \(pencil) speck edges against pastel's \(pastel)")
    }

    @Test func aMulticolorStickInksEachToothCellInOneOfItsColors() throws {
        let red = Color(red: 0.9, green: 0.1, blue: 0.1), blue = Color(red: 0.1, green: 0.2, blue: 0.9)
        let p = try band(.pastel(palette: [red, blue]))
        var reds = 0, blues = 0
        for y in 116..<140 {
            for x in 40..<216 {
                let r = p.channel(0, x, y), b = p.channel(2, x, y)
                if r > b + 100 { reds += 1 } else if b > r + 100 { blues += 1 }
            }
        }
        #expect(reds > 300 && blues > 300, "\(reds) red and \(blues) blue pixels")
    }

    // MARK: Brushes

    @Test func aBristleStrokesCrossSectionHoldsBothPigments() throws {
        let red = Color(red: 0.85, green: 0.1, blue: 0.1), blue = Color(red: 0.1, green: 0.2, blue: 0.9)
        let p = try render { s in
            s.stroke(red)
            s.strokeWeight(60)
            s.strokeMedium(.bristles(blue, amount: 0.5))
            s.drawLine(20, 128, 236, 128)
        }
        for x in [70, 128, 180] {
            var reds = 0, blues = 0
            for y in 102..<154 {
                let r = p.channel(0, x, y), b = p.channel(2, x, y)
                if r > b + 60 { reds += 1 } else if b > r + 60 { blues += 1 }
            }
            #expect(reds >= 3 && blues >= 3, "column \(x) holds \(reds) red and \(blues) blue pixels")
        }
    }

    @Test func aDryBrushRunsDryAlongTheMark() throws {
        // The brush's load falls along the path, so the tail inks less of the
        // stroke than the head.
        let p = try band(.dryBrush(amount: 0.9))
        let head = inkReading(p, x0: 30, x1: 80, y0: 116, y1: 140)
        let tail = inkReading(p, x0: 176, x1: 226, y0: 116, y1: 140)
        #expect(tail.mean < 0.75 * head.mean, "the head lays \(head.mean) and the tail \(tail.mean)")
    }

    // MARK: One coat

    /// An hourglass whose first and third legs cross at the canvas's center.
    nonisolated static let hourglass = [Vector2(40, 60), Vector2(216, 196), Vector2(216, 60), Vector2(40, 196)]

    @Test func aTranslucentMarkThatCrossesItselfLaysOneCoat() throws {
        // A uniform medium (wet paint dragging nothing) at alpha 0.3: the crossing
        // reads as the rest of the leg does. The same path as a plain stroke lays
        // two coats there, which is what the medium's coat buffer takes away.
        func drawn(_ medium: StrokeMedium?) throws -> Pixels {
            try render { s in
                s.stroke(Color.black.withAlpha(0.3))
                s.strokeWeight(24)
                if let medium { s.strokeMedium(medium) }
                s.drawPolyline(Self.hourglass)
            }
        }
        let coat = try drawn(.wet(amount: 0))
        let plain = try drawn(nil)
        // (84, 94) is a quarter of the way down the first leg, crossed by nothing.
        #expect(abs(coat.gray(128, 128) - coat.gray(84, 94)) <= 1,
                "the crossing reads \(coat.gray(128, 128)) and the leg \(coat.gray(84, 94))")
        #expect(abs(plain.gray(84, 94) - coat.gray(84, 94)) <= 1, "one leg is the plain stroke's own coat")
        #expect(plain.gray(128, 128) < plain.gray(84, 94) - 10, "a plain stroke lays two coats at its crossing")
    }

    @Test func twoMarksStillLayerOverEachOther() throws {
        // The coat is per stroke: a second mark crossing the first lays its own.
        let p = try render { s in
            s.stroke(Color.black.withAlpha(0.3))
            s.strokeWeight(24)
            s.strokeMedium(.wet(amount: 0))
            s.drawLine(40, 128, 216, 128)
            s.drawLine(128, 40, 128, 216)
        }
        #expect(p.gray(128, 128) < p.gray(80, 128) - 10, "the crossing reads \(p.gray(128, 128)) against \(p.gray(80, 128))")
        #expect(abs(p.gray(80, 128) - p.gray(128, 80)) <= 1)
    }

    @Test func oneCoatHoldsInsideAClip() throws {
        let p = try render { s in
            s.withClip(Shape(contours: [Contour([Vector2(0, 0), Vector2(256, 0), Vector2(256, 256), Vector2(0, 256)])])) {
                s.stroke(Color.black.withAlpha(0.3))
                s.strokeWeight(24)
                s.strokeMedium(.wet(amount: 0))
                s.drawPolyline(Self.hourglass)
            }
        }
        #expect(abs(p.gray(128, 128) - p.gray(84, 94)) <= 1,
                "inside a clip the crossing reads \(p.gray(128, 128)) and the leg \(p.gray(84, 94))")
    }

    // MARK: Wet paint

    /// A wet stroke 40 wide drawn across a ground red on the left half and blue on
    /// the right, at `amount` 1 and a reach of 36, in mid-gray pigment.
    func wetAcross(from x0: Double, to x1: Double, keepsCanvas: Bool = false) throws -> Pixels {
        let sketch = WetSketch(from: x0, to: x1, keepsCanvas: keepsCanvas)
        // Frames count from 0: frame 1 is the second draw.
        return Pixels(try OllinApp.image(of: sketch, frame: 1))
    }

    /// At pixel (x, 128) of a wet stroke over the red and blue ground in gray
    /// pigment, how far the stroke mixed toward the ground (`k`) and the red share
    /// of what it dragged in (`rho`). With pigment 0.5 in every channel and a
    /// ground that holds no green, green is 0.5 (1 - k), and red is
    /// 0.5 (1 - k) + k rho.
    func dragged(_ p: Pixels, _ x: Int) -> (k: Double, rho: Double) {
        let g = linear(UInt8(p.channel(1, x, 128))), r = linear(UInt8(p.channel(0, x, 128)))
        let k = 1 - 2 * g
        return (k, k > 0.05 ? (r - 0.5 * (1 - k)) / k : 0)
    }

    /// The red share eight taps reaching 36 pixels back from `x` would find over
    /// a boundary at 128, weighted as the fragment weighs them.
    func expectedRedShare(at x: Double, leftToRight: Bool) -> Double {
        var red = 0.0, total = 0.0
        for i in 0..<8 {
            let f = (Double(i) + 0.5) / 8, w = 1 - 0.5 * f
            let q = leftToRight ? x + 0.5 - 36 * f : x + 0.5 + 36 * f
            if q < 128 { red += w }
            total += w
        }
        return red / total
    }

    @Test func aWetStrokeDragsTheGroundAlongItsDirection() throws {
        // Drawn left to right, the pixel 22 past the boundary drags red from behind
        // it in the share the taps reach; drawn right to left, the same pixel drags
        // only blue. Mirrored on the red side.
        let ltr = try wetAcross(from: 20, to: 236)
        let rtl = try wetAcross(from: 236, to: 20)
        let a = dragged(ltr, 150), b = dragged(rtl, 150)
        #expect(a.k > 0.2 && b.k > 0.2, "the stroke mixes \(a.k) and \(b.k) of the ground")
        #expect(abs(a.rho - expectedRedShare(at: 150, leftToRight: true)) < 0.08,
                "left to right drags \(a.rho) red against \(expectedRedShare(at: 150, leftToRight: true))")
        #expect(b.rho < 0.05, "right to left drags \(b.rho) red")
        let c = dragged(rtl, 106), d = dragged(ltr, 106)
        #expect(abs((1 - c.rho) - (1 - expectedRedShare(at: 106, leftToRight: false))) < 0.08,
                "right to left drags \(1 - c.rho) blue onto the red side")
        #expect(d.rho > 0.95, "left to right keeps \(d.rho) red there")
    }

    @Test func aWetStrokeOnAPilingCanvasDragsThePileSoFar() throws {
        // The ground drawn on the first frame only, the wet stroke on the second:
        // the stroke drags the pile.
        let p = try wetAcross(from: 20, to: 236, keepsCanvas: true)
        let a = dragged(p, 150)
        #expect(a.k > 0.2 && abs(a.rho - expectedRedShare(at: 150, leftToRight: true)) < 0.08,
                "on a piling canvas the stroke drags \(a.rho) red at k \(a.k)")
    }

    @Test func noWetStrokeDrawsTheFrameTwice() throws {
        // A frame with no wet stroke asks for no ground.
        let sketch = MediumSketch(ground: .white) { s in
            s.stroke(.black); s.strokeWeight(10); s.strokeMedium(.pencil); s.drawLine(20, 20, 200, 200)
        }
        _ = try OllinApp.image(of: sketch, frame: 1)
        #expect(sketch.drawer.batches.contains { $0.medium?.readsGround == true } == false)
        #expect(sketch.drawer.batches.contains { $0.medium != nil })
    }

    // MARK: The ribbon's coordinates

    /// A shader stroke showing the ribbon's coordinates: red the distance along
    /// over `scale`, green the place across, blue the half-width over 32.
    nonisolated static func ribbonShader(scale: Double) -> Shader {
        Shader("""
        float4 shade(float2 uv, ShaderInfo info) {
            return float4(info.arcLength / \(scale), info.across * 0.5 + 0.5, info.halfWidth / 32.0, 1.0);
        }
        """)
    }

    @Test func aShaderStrokeReadsTheDistanceAlongAndThePlaceAcross() throws {
        let p = try render(ground: .black) { s in
            s.stroke(Self.ribbonShader(scale: 256))
            s.strokeWeight(20)
            s.drawLine(20, 128, 236, 128)
        }
        // Pixel centers: (128.5, 128.5) is 108.5 along and 0.5 of 10 across.
        #expect(abs(p.channel(0, 128, 128) - Int((108.5 / 256 * 255).rounded())) <= 1, "along reads \(p.channel(0, 128, 128))")
        #expect(abs(p.channel(1, 128, 128) - Int((0.525 * 255).rounded())) <= 1, "across reads \(p.channel(1, 128, 128))")
        #expect(abs(p.channel(1, 128, 122) - Int((0.225 * 255).rounded())) <= 1, "across reads \(p.channel(1, 128, 122)) at row 122")
        #expect(abs(p.channel(2, 128, 128) - Int((10.0 / 32 * 255).rounded())) <= 1, "the half-width reads \(p.channel(2, 128, 128))")
    }

    @Test func aClosedLoopsLastSideRunsOnToItsWholeLength() throws {
        // A closed square 176 a side: its last side, from the bottom-left corner
        // back up to the first, runs from 528 to 704 along, so its middle reads
        // 616, never a coordinate running back down to 0.
        let p = try render(ground: .black) { s in
            s.stroke(Self.ribbonShader(scale: 1024))
            s.strokeWeight(8)
            s.noFill()
            s.drawPolygon([Vector2(40, 40), Vector2(216, 40), Vector2(216, 216), Vector2(40, 216)])
        }
        let expected = Int((616 / 1024.0 * 255).rounded())
        #expect(abs(p.channel(0, 40, 128) - expected) <= 2, "the last side's middle reads \(p.channel(0, 40, 128)) against \(expected)")
        #expect(abs(p.channel(0, 128, 40) - Int((88.5 / 1024 * 255).rounded())) <= 2, "the first side's middle reads \(p.channel(0, 128, 40))")
    }

    // MARK: Routes

    @Test func anAnalyticShapeHandsItsOutlineToTheRibbon() throws {
        func circle(_ medium: StrokeMedium?) throws -> Pixels {
            try render { s in
                s.fill(Color(red: 0.2, green: 0.5, blue: 0.8))
                s.stroke(Color.black.withAlpha(0.5))
                s.strokeWeight(16)
                if let medium { s.strokeMedium(medium) }
                s.drawCircle(128, 128, 80)
            }
        }
        let plain = try circle(nil), shaded = try circle(.pencil)
        #expect(plain.channel(2, 128, 128) == shaded.channel(2, 128, 128), "the fill is the instance it always was")
        var differs = 0
        for a in stride(from: 0.0, to: 2 * .pi, by: 0.05) {
            let x = Int(128 + 80 * cos(a)), y = Int(128 + 80 * sin(a))
            if abs(plain.gray(x, y) - shaded.gray(x, y)) > 20 { differs += 1 }
        }
        #expect(differs > 20, "the outline is shaded at \(differs) of 126 points")
    }

    @Test func theToothIsThePapersAndItsSeedChoosesThePaper() throws {
        let gray = Color.black.withAlpha(0.5)
        let a = try band(.pencil, color: gray), b = try band(.pencil, color: gray)
        #expect(a.bytes == b.bytes)
        let other = try band(.dry(tooth: 1.4, softness: 0.12, roughness: 0.12, seed: 7), color: gray)
        #expect(other.bytes != a.bytes)
        // Two strokes over one spot catch the same peaks: the tooth belongs to the
        // paper, not to the stroke.
        let first = try render { s in
            s.stroke(gray); s.strokeWeight(40); s.strokeMedium(.pencil); s.drawLine(20, 128, 236, 128)
        }
        let shifted = try render { s in
            s.stroke(gray); s.strokeWeight(40); s.strokeMedium(.pencil); s.drawLine(10, 128, 246, 128)
        }
        var same = 0, n = 0
        for y in 116..<140 { for x in 60..<196 { n += 1; if abs(first.gray(x, y) - shifted.gray(x, y)) <= 2 { same += 1 } } }
        #expect(Double(same) / Double(n) > 0.95, "\(same) of \(n) interior pixels agree")
    }

    @Test func aRetainedBatchReplaysAMediumStrokeAsDrawn() throws {
        let direct = try render { s in
            s.stroke(Color.black.withAlpha(0.3)); s.strokeWeight(24); s.strokeMedium(.charcoal)
            s.drawPolyline(Self.hourglass)
        }
        let replayed = try render { s in
            let batch = s.makeBatch {
                s.stroke(Color.black.withAlpha(0.3)); s.strokeWeight(24); s.strokeMedium(.charcoal)
                s.drawPolyline(Self.hourglass)
            }
            s.drawBatch(batch)
        }
        #expect(direct.bytes == replayed.bytes)
    }

    @Test func aBatchRecordedInSetupStillLaysOneCoat() throws {
        // Recorded once, replayed on the frame after: the replay asks for the
        // coat's stencil itself.
        let p = Pixels(try OllinApp.image(of: SetupBatchSketch(), frame: 1))
        #expect(abs(p.gray(128, 128) - p.gray(84, 94)) <= 1,
                "replayed, the crossing reads \(p.gray(128, 128)) and the leg \(p.gray(84, 94))")
    }

    @Test func aVectorFileWritesTheFlatRibbon() throws {
        let shaded = MediumSketch(ground: .white) { s in
            s.stroke(.black); s.strokeWeight(10); s.strokeMedium(.oil); s.drawPolyline(Self.hourglass)
        }
        let plain = MediumSketch(ground: .white) { s in
            s.stroke(.black); s.strokeWeight(10); s.drawPolyline(Self.hourglass)
        }
        // The files agree line for line but for the provenance comment, whose
        // seed is each run's own.
        func body(_ svg: String) -> [Substring] { svg.split(separator: "\n").filter { !$0.contains("<!--") } }
        #expect(body(try OllinApp.svg(of: shaded)) == body(try OllinApp.svg(of: plain)))
    }

    @Test func theWebPageCarriesEveryMedium() throws {
        // A wet, a dry, and an ink medium all cross (WebStrokeMediumTests has
        // the page, and the one refusal left, a wet stroke over a kept canvas).
        let wet = MediumSketch(ground: .white) { s in
            s.stroke(.black); s.strokeWeight(10); s.strokeMedium(.oil); s.drawLine(20, 20, 200, 200)
        }
        #expect(throws: Never.self) { _ = try OllinApp.recordWebFrames(of: wet, frames: 2, fps: 30) }
        let dry = MediumSketch(ground: .white) { s in
            s.stroke(.black); s.strokeWeight(10); s.strokeMedium(.pencil); s.drawLine(20, 20, 200, 200)
        }
        #expect(throws: Never.self) { _ = try OllinApp.recordWebFrames(of: dry, frames: 2, fps: 30) }
        let ink = MediumSketch(ground: .white) { s in
            s.stroke(.black); s.strokeWeight(10); s.strokeMedium(.ink)
            s.drawMark(StrokeMediumTests.penLine(speed: 300))
        }
        #expect(throws: Never.self) { _ = try OllinApp.recordWebFrames(of: ink, frames: 2, fps: 30) }
    }

    // MARK: Ink

    /// A horizontal mark across the middle, from `x0` to `x1` at `y`, every
    /// point made at `speed` canvas points a second (`nil` for no timing).
    nonisolated static func penLine(speed: Double?, from x0: Double = 20, to x1: Double = 236,
                                    y: Double = 128) -> StrokeMark {
        let count = Int((x1 - x0) / 4)
        return StrokeMark(samples: (0 ... count).map { i in
            StrokeMark.Sample(position: Vector2(x0 + (x1 - x0) * Double(i) / Double(count), y), speed: speed)
        })
    }

    /// That mark drawn 12 wide under a pen, in black at `alpha`.
    func pen(speed: Double?, alpha: Double = 1, medium: StrokeMedium = .ink(pooling: 0)) throws -> Pixels {
        try render { s in
            s.stroke(Color.black.withAlpha(alpha))
            s.strokeWeight(12)
            s.strokeMedium(medium)
            s.drawMark(Self.penLine(speed: speed))
        }
    }

    /// How many rows above the nib's top edge (y = 122 on the 12-wide line at
    /// 128) still carry ink, read as the mean over the middle of the line.
    func rim(_ p: Pixels) -> Int {
        var rows = 0
        for y in stride(from: 121, through: 90, by: -1) {
            let mean = inkReading(p, x0: 80, x1: 176, y0: y, y1: y + 1).mean
            if mean > 0.03 { rows += 1 }
        }
        return rows
    }

    @Test func theFeatherReachesFartherWhereThePenRested() throws {
        // The nib's own line is inked solid at any pace; past its edge the ink
        // soaks into the paper, and farther where the pen crawled than where it
        // wrote at its writing speed. A line with no timing reads as written.
        let slow = try pen(speed: 100)
        let writing = try pen(speed: 900)
        let untimed = try pen(speed: nil)
        try look("ink-slow") { s in s.stroke(.black); s.strokeWeight(12); s.strokeMedium(.ink(pooling: 0)); s.drawMark(Self.penLine(speed: 100)) }
        try look("ink-writing") { s in s.stroke(.black); s.strokeWeight(12); s.strokeMedium(.ink(pooling: 0)); s.drawMark(Self.penLine(speed: 900)) }
        for p in [slow, writing, untimed] {
            #expect(inkReading(p, x0: 60, x1: 196, y0: 124, y1: 132).lit > 0.98, "the nib's line is solid")
        }
        #expect(rim(slow) >= rim(writing) + 2, "a resting pen feathers \(rim(slow)) rows against \(rim(writing)) at writing speed")
        #expect(rim(writing) >= 1, "the ink feathers past the nib even at writing speed")
        #expect(rim(untimed) == rim(writing), "a line without timing is written at the writing speed")
    }

    @Test func theInkPoolsWhereThePenLandedAndLifted() throws {
        // A translucent ink at full pooling lies denser over the first and last
        // pen width than along the middle; with no pooling the ends read as the
        // middle does.
        let pooled = try pen(speed: 900, alpha: 0.55, medium: .ink(pooling: 1))
        let flat = try pen(speed: 900, alpha: 0.55, medium: .ink(pooling: 0))
        try look("ink-pooled") { s in s.stroke(Color.black.withAlpha(0.55)); s.strokeWeight(12); s.strokeMedium(.ink(pooling: 1)); s.drawMark(Self.penLine(speed: 900)) }
        func ends(_ p: Pixels) -> Double {
            (inkReading(p, x0: 21, x1: 33, y0: 124, y1: 132).mean + inkReading(p, x0: 223, x1: 235, y0: 124, y1: 132).mean) / 2
        }
        func middle(_ p: Pixels) -> Double { inkReading(p, x0: 100, x1: 156, y0: 124, y1: 132).mean }
        #expect(ends(pooled) > middle(pooled) * 1.15, "the ends read \(ends(pooled)) against the middle's \(middle(pooled))")
        #expect(abs(ends(flat) - middle(flat)) < 0.02 * max(middle(flat), 1e-6) + 0.01,
                "without pooling the ends read \(ends(flat)) against \(middle(flat))")
    }

    @Test func anInkStrokeLaysASecondCoatWhereItCrossesItself() throws {
        // The hourglass that lays one coat under every other medium lays two
        // under ink, as a pen does: the crossing reads darker than a leg. Two
        // separate pen strokes cross the same way.
        let ink = try render { s in
            s.stroke(Color.black.withAlpha(0.3))
            s.strokeWeight(24)
            s.strokeMedium(.ink(feather: 0, pooling: 0))
            s.drawPolyline(Self.hourglass)
        }
        #expect(ink.gray(128, 128) < ink.gray(84, 94) - 10,
                "the crossing reads \(ink.gray(128, 128)) and the leg \(ink.gray(84, 94))")
        let two = try render { s in
            s.stroke(Color.black.withAlpha(0.3))
            s.strokeWeight(24)
            s.strokeMedium(.ink(feather: 0, pooling: 0))
            s.drawLine(40, 128, 216, 128)
            s.drawLine(128, 40, 128, 216)
        }
        #expect(two.gray(128, 128) < two.gray(80, 128) - 10)
    }

    @Test func aHurriedPenSkipsAndASlowOneDoesNot() throws {
        // At three times the writing speed and full thinning the flow breaks
        // into a ballpoint's skips along the line; at the writing speed the
        // line is whole.
        func bare(_ p: Pixels) -> Double {
            var n = 0, bare = 0
            for x in 40 ..< 216 {
                for y in 126 ..< 130 {
                    n += 1
                    if ink(p, x, y) < 0.3 { bare += 1 }
                }
            }
            return Double(bare) / Double(n)
        }
        let hurried = try pen(speed: 2700, medium: .ink(pooling: 0, amount: 1))
        let writing = try pen(speed: 900, medium: .ink(pooling: 0, amount: 1))
        try look("ink-hurried") { s in s.stroke(.black); s.strokeWeight(12); s.strokeMedium(.ink(pooling: 0, amount: 1)); s.drawMark(Self.penLine(speed: 2700)) }
        #expect(bare(hurried) > 0.15, "a hurried pen leaves \(bare(hurried)) of the line bare")
        #expect(bare(writing) < 0.01, "a pen at writing speed leaves \(bare(writing)) bare")
        // With no thinning the hurried pen writes a whole line too.
        let steady = try pen(speed: 2700, medium: .ink(pooling: 0, amount: 0))
        #expect(bare(steady) < 0.01)
    }

    // MARK: Pressure

    @Test func aDeadZoneAndACurveShapeThePress() {
        var mark = StrokeMark(.pressure(light: 0))
        mark.pressureDeadZone = 0.2
        #expect(mark.shapedPressure(0.1) == 0)
        #expect(mark.shapedPressure(0.2) == 0)
        #expect(abs(mark.shapedPressure(0.6) - 0.5) < 1e-12)
        #expect(mark.shapedPressure(1) == 1)
        mark.pressureCurve = 2
        #expect(abs(mark.shapedPressure(0.6) - 0.25) < 1e-12)
        // Through a recording: a press under the dead zone draws at `light`.
        var light = StrokeMark(.pressure(light: 0.25), smoothing: 0, minSpacing: 0)
        light.pressureDeadZone = 0.3
        for i in 0..<12 { light.record(Vector2(Double(i) * 10, 0), deltaTime: 1.0 / 60, pressure: 0.2) }
        #expect(light.samples.allSatisfy { abs($0.width - 0.25) < 1e-9 })
    }

    @Test func aSlopeLimitKeepsTheWidthFromStepping() {
        // A response that jumps from thin to full halfway along: unlimited, the
        // width steps; limited to 0.01 a point at 10 points a step, each step
        // changes it by no more than 0.1.
        let jump = StrokeDynamics(width: StrokeResponse { $0.distance > 50 ? 1 : 0.1 })
        func widths(_ limit: Double?) -> [Double] {
            var mark = StrokeMark(jump, smoothing: 0, minSpacing: 0)
            mark.maxWidthChange = limit
            for i in 0...20 { mark.record(Vector2(Double(i) * 10, 0), deltaTime: 1.0 / 60) }
            return mark.samples.map(\.width)
        }
        let free = widths(nil), limited = widths(0.01)
        #expect(zip(free, free.dropFirst()).contains { abs($1 - $0) > 0.5 })
        #expect(zip(limited, limited.dropFirst()).allSatisfy { abs($1 - $0) <= 0.1 + 1e-9 })
        #expect(abs(limited.last! - 1) < 1e-9, "the limited width still arrives")
    }

    @Test func looksForTuning() throws {
        let media: [(String, StrokeMedium)] = [
            ("pencil", .pencil), ("charcoal", .charcoal), ("pastel", .pastel),
            ("pastel-palette", .pastel(palette: [hex("#E4572E"), hex("#F3A712"), hex("#29335C")])),
            ("bristles", .bristles(hex("#F3A712"))), ("dry-brush", .dryBrush),
            ("wet", .wet), ("oil", .oil), ("ink", .ink),
        ]
        // A page of pen lines at three paces, and the hourglass crossing itself.
        try look("ink-page") { s in
            s.noFill()
            s.stroke(hex("#1B2A4A"))
            s.strokeWeight(5)
            s.strokeMedium(.ink(feather: 2, pooling: 0.6, amount: 0.7))
            for (i, speed) in [120.0, 600, 2400].enumerated() {
                let y = 40 + Double(i) * 44
                s.drawMark(Self.penLine(speed: speed, from: 24, to: 232, y: y))
            }
            s.strokeWeight(3)
            s.stroke(hex("#1B2A4A").withAlpha(0.7))
            s.drawPolyline([Vector2(30, 170), Vector2(226, 236), Vector2(226, 170), Vector2(30, 236)])
            s.strokeMedium(.ink(feather: 2, pooling: 0.6))
            s.drawPolyline(Contour([Vector2(60, 200), Vector2(200, 180), Vector2(190, 230)], closed: false)
                .handDrawn(wobble: 1.5, bow: 2, overshoot: 5, seed: 3).points)
        }
        for (name, medium) in media {
            try look(name) { s in
                // A ground with two colors for the wet media to drag.
                s.noStroke()
                s.fill(hex("#3A6EA5")); s.drawRect(0, 0, 128, 256)
                s.fill(hex("#F4D35E")); s.drawRect(128, 0, 128, 256)
                s.noFill()
                s.stroke(hex("#C0392B"))
                s.strokeWeight(34)
                s.strokeCap(.round)
                s.strokeMedium(medium)
                s.drawPolyline(Self.curve)
                s.strokeWeight(10)
                s.stroke(hex("#1B1B1F").withAlpha(0.35))
                s.drawLine(30, 30, 226, 40)
            }
        }
    }
}

/// A color from a hex string the test spells right.
private func hex(_ text: String) -> Color { Color(hex: text)! }

/// A wet stroke over a ground red on the left half and blue on the right. On a
/// piling canvas the ground is drawn on the first frame alone and the stroke on
/// the second, so the stroke drags the pile.
private final class WetSketch: Sketch {
    var x0 = 20.0, x1 = 236.0
    var keepsCanvas = false
    var drawn = 0

    convenience init(from x0: Double, to x1: Double, keepsCanvas: Bool) {
        self.init()
        self.x0 = x0
        self.x1 = x1
        self.keepsCanvas = keepsCanvas
    }

    override var canvasSize: CanvasSize { .square(256) }

    override func setup() {
        if keepsCanvas { noClear() }
    }

    override func draw() {
        drawn += 1
        if !keepsCanvas || drawn == 1 {
            background(.white)
            noStroke()
            fill(Color(red: 1, green: 0, blue: 0)); drawRect(0, 0, 128, 256)
            fill(Color(red: 0, green: 0, blue: 1)); drawRect(128, 0, 128, 256)
        }
        if !keepsCanvas || drawn >= 2 {
            noFill()
            stroke(Color(white: linearToSRGB(0.5)))
            strokeWeight(40)
            strokeMedium(.wet(amount: 1, reach: 36))
            drawLine(x0, 128, x1, 128)
        }
    }
}

/// A translucent hourglass in a uniform medium, recorded into a batch in
/// `setup()` and replayed every frame.
private final class SetupBatchSketch: Sketch {
    var batch: Batch?

    override var canvasSize: CanvasSize { .square(256) }

    override func setup() {
        batch = makeBatch {
            stroke(Color.black.withAlpha(0.3))
            strokeWeight(24)
            strokeMedium(.wet(amount: 0))
            drawPolyline(StrokeMediumTests.hourglass)
        }
    }

    override func draw() {
        background(.white)
        if let batch { drawBatch(batch) }
    }
}

/// A linear-light level as the sRGB component that encodes it.
private func linearToSRGB(_ v: Double) -> Double {
    v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055
}

/// One drawing call over a ground, on a 256-point canvas.
private final class MediumSketch: Sketch {
    var ground: Color = .white
    var body: @MainActor (Sketch) -> Void = { _ in }

    convenience init(ground: Color, _ body: @escaping @MainActor (Sketch) -> Void) {
        self.init()
        self.ground = ground
        self.body = body
    }

    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(ground)
        body(self)
    }
}
