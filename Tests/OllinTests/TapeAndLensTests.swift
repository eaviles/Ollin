import CoreGraphics
import Foundation
import Testing
@testable import Ollin

/// The tape and lens looks: a JPEG at quality 100 comes back within a level and
/// at quality 10 holds, in every 8 by 8 block, only the coefficients its tables
/// keep; the videotape at amount 0 is the layer and otherwise keeps its luma
/// sharper than its chroma; the tilt-shift's band is untouched byte for byte and
/// the progressive blur's far side is the plain Gaussian; a light leak never
/// darkens a pixel and raises the alpha over transparency; a datamosh whose
/// blocks all refresh is the drawing, and whose blocks all hold is the first
/// frame moving by the stated drift; a page peel at amount 0 is the layer and
/// the corner it lifts is transparent; and scratches are clear between the
/// lines and hold still while flicker is off.
@Suite
@MainActor
struct TapeAndLensTests {

    static let side = 240

    /// Mid-tone shapes over a soft gradient: nothing near black or white, so a
    /// block transform's ringing never clips.
    static func pastelScene(_ s: Sketch) {
        s.noStroke()
        for row in 0 ..< 24 {
            let u = Double(row) / 23
            s.fill(Color(red: 0.45 + 0.2 * u, green: 0.5, blue: 0.62 - 0.15 * u))
            s.drawRect(0, Double(row) * 10, 240, 10)
        }
        s.fill(Color(red: 0.72, green: 0.45, blue: 0.4)); s.drawCircle(80, 90, 46)
        s.fill(Color(red: 0.4, green: 0.58, blue: 0.46)); s.drawRect(130, 40, 70, 150)
        s.fill(Color(red: 0.62, green: 0.6, blue: 0.38)); s.drawCircle(150, 180, 30)
        s.fill(Color(red: 0.42, green: 0.42, blue: 0.62))
        for i in 0 ..< 6 { s.drawRect(20 + Double(i) * 14, 170, 6, 50) }
    }

    /// The pastel scene drawn into a layer, then that layer through `filter`
    /// (or as it is) onto the canvas.
    final class Filtered: Sketch {
        var filter: Filter?
        var clear = false
        override var canvasSize: CanvasSize { .square(TapeAndLensTests.side) }
        override func draw() {
            background(clear ? .clear : .black)
            let scene = makeRenderTarget()
            withTarget(scene) { TapeAndLensTests.pastelScene(self) }
            drawImage((filter.map { scene.filtered($0) } ?? scene).image, 0, 0)
        }
    }

    private func render(_ filter: Filter?, clear: Bool = false) throws -> Pixels {
        let s = Filtered(); s.filter = filter; s.clear = clear
        return Pixels(try OllinApp.image(of: s, frame: 1))
    }

    private func maxDifference(_ a: Pixels, _ b: Pixels, rows: Range<Int>) -> (max: Int, mean: Double) {
        var worst = 0, total = 0, count = 0
        for y in rows {
            for x in 0 ..< a.width {
                for c in 0 ..< 3 {
                    let d = abs(a.channel(c, x, y) - b.channel(c, x, y))
                    worst = max(worst, d); total += d; count += 1
                }
            }
        }
        return (worst, Double(total) / Double(max(count, 1)))
    }

    // MARK: JPEG

    @Test func theTablesFollowTheQualityCurve() {
        let fifty = Filter.jpegTables(quality: 50)
        #expect(fifty.luma[0] == 16 && fifty.chroma[0] == 17, "quality 50 is the standard's own tables")
        let hundred = Filter.jpegTables(quality: 100)
        #expect(hundred.luma.allSatisfy { $0 == 1 } && hundred.chroma.allSatisfy { $0 == 1 })
        let ten = Filter.jpegTables(quality: 10)
        #expect(ten.luma[0] == 80, "a factor of five below 50: 16 x 500 / 100")
        #expect(ten.chroma[63] == 255, "held at 255")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func qualityOneHundredComesBackWithinALevel() throws {
        let plain = try render(nil), saved = try render(.jpeg(quality: 100, subsamplesChroma: false))
        // Every step is one level, so what is lost is the rounding of each
        // coefficient: a level at most in all but a handful of channels, the
        // rest a level more where the frame's own dither falls the other way.
        var within = 0, worst = 0
        for y in 0 ..< Self.side {
            for x in 0 ..< Self.side {
                for c in 0 ..< 3 {
                    let d = abs(plain.channel(c, x, y) - saved.channel(c, x, y))
                    if d <= 1 { within += 1 }
                    worst = max(worst, d)
                }
            }
        }
        #expect(Double(within) / Double(Self.side * Self.side * 3) > 0.99, "within a level: \(within)")
        #expect(worst <= 3, "worst channel \(worst)")
    }

    /// The 8 by 8 cosine transform of one block of the frame read back, in
    /// levels, for the JFIF luma or a chroma channel.
    private func coefficients(_ px: Pixels, bx: Int, by: Int, channel: Int) -> [Double] {
        var f = [Double](repeating: 0, count: 64)
        for y in 0 ..< 8 {
            for x in 0 ..< 8 {
                let r = Double(px.channel(0, bx * 8 + x, by * 8 + y))
                let g = Double(px.channel(1, bx * 8 + x, by * 8 + y))
                let b = Double(px.channel(2, bx * 8 + x, by * 8 + y))
                let ycc = [0.299 * r + 0.587 * g + 0.114 * b - 128,
                           -0.168736 * r - 0.331264 * g + 0.5 * b,
                           0.5 * r - 0.418688 * g - 0.081312 * b]
                f[y * 8 + x] = ycc[channel]
            }
        }
        var out = [Double](repeating: 0, count: 64)
        for v in 0 ..< 8 {
            for u in 0 ..< 8 {
                var sum = 0.0
                for y in 0 ..< 8 {
                    for x in 0 ..< 8 {
                        sum += f[y * 8 + x] * cos(Double(2 * x + 1) * Double(u) * .pi / 16)
                            * cos(Double(2 * y + 1) * Double(v) * .pi / 16)
                    }
                }
                let cu = u == 0 ? 1 / 2.0.squareRoot() : 1, cv = v == 0 ? 1 / 2.0.squareRoot() : 1
                out[v * 8 + u] = 0.25 * cu * cv * sum
            }
        }
        return out
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func qualityTenHoldsOnlyTheKeptCoefficients() throws {
        let px = try render(.jpeg(quality: 10, subsamplesChroma: false))
        let tables = Filter.jpegTables(quality: 10)
        var checked = 0, off = 0, zeroed = 0, high = 0
        for by in 0 ..< Self.side / 8 {
            for bx in 0 ..< Self.side / 8 {
                for channel in 0 ..< 3 {
                    let table = channel == 0 ? tables.luma : tables.chroma
                    let f = coefficients(px, bx: bx, by: by, channel: channel)
                    for i in 0 ..< 64 {
                        let q = table[i]
                        let residue = abs(f[i] - q * (f[i] / q).rounded())
                        checked += 1
                        // The frame is read back through eight bits and a dither,
                        // which moves a coefficient by a level or two at most.
                        if residue > 4 { off += 1 }
                        if i >= 16 { high += 1; if abs(f[i]) < 4 { zeroed += 1 } }
                    }
                }
            }
        }
        // A coefficient with no step behind it would sit between steps nine
        // times in ten; here it is fewer than one in a hundred, the blocks whose
        // ringing a channel clipped at the edge of the range.
        #expect(off * 100 < checked, "\(off) of \(checked) coefficients sit between their steps")
        #expect(Double(zeroed) / Double(high) > 0.97, "the fine coefficients round away: \(zeroed) of \(high)")
    }

    /// A one-pixel-wide orange line on gray, through a JPEG at quality 100 (or
    /// as it is).
    final class ColorLine: Sketch {
        var filter: Filter?
        override var canvasSize: CanvasSize { .square(TapeAndLensTests.side) }
        override func draw() {
            background(.black)
            let scene = makeRenderTarget()
            withTarget(scene) {
                background(Color(white: 0.5))
                noStroke(); fill(Color(red: 0.95, green: 0.45, blue: 0.1)); drawRect(101, 0, 1, 240)
            }
            drawImage((filter.map { scene.filtered($0) } ?? scene).image, 0, 0)
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func subsampledColorSpreadsAcrossItsPairOfPixels() throws {
        func render(_ filter: Filter?) throws -> Pixels {
            let s = ColorLine(); s.filter = filter
            return Pixels(try OllinApp.image(of: s, frame: 1))
        }
        func warmth(_ px: Pixels, _ x: Int) -> Int { px.channel(0, x, 120) - px.channel(2, x, 120) }
        let plain = try render(nil)
        let full = try render(.jpeg(quality: 100, subsamplesChroma: false))
        let half = try render(.jpeg(quality: 100))
        // Full-resolution color keeps every column's hue.
        for x in 96 ..< 108 {
            #expect(abs(warmth(full, x) - warmth(plain, x)) <= 3, "column \(x): \(warmth(full, x)) against \(warmth(plain, x))")
        }
        // Half-resolution color is one value for each pair of columns, so the
        // one-column line gives up much of its hue, while the brightness, kept
        // at full resolution, stays the layer's in every column.
        #expect(warmth(half, 101) < warmth(plain, 101) - 15, "the line's hue is shared out")
        func luma(_ px: Pixels, _ x: Int) -> Double {
            0.299 * Double(px.channel(0, x, 120)) + 0.587 * Double(px.channel(1, x, 120))
                + 0.114 * Double(px.channel(2, x, 120))
        }
        for x in 96 ..< 108 {
            #expect(abs(luma(half, x) - luma(plain, x)) <= 4, "column \(x)'s brightness: \(luma(half, x)) against \(luma(plain, x))")
        }
    }

    // MARK: Videotape

    @Test(.enabled(if: Snapshot.hasMetal))
    func theTapeAtAmountZeroIsTheLayer() throws {
        let plain = try render(nil), taped = try render(.vhs(amount: 0, phase: 3))
        #expect(maxDifference(plain, taped, rows: 0 ..< Self.side).max == 0)
    }

    /// A black field with a block of saturated orange, whose edge the tape
    /// crosses: across that edge the luma climbs in a pixel or two, the chroma
    /// over the smear.
    final class Edge: Sketch {
        override var canvasSize: CanvasSize { .square(TapeAndLensTests.side) }
        override func draw() {
            background(.black)
            let scene = makeRenderTarget()
            withTarget(scene) {
                background(Color(white: 0.2))
                noStroke(); fill(Color(red: 0.95, green: 0.35, blue: 0.1)); drawRect(100, 0, 140, 240)
            }
            drawImage(scene.filtered(.vhs(smear: 16, jitter: 0, damage: 0, phase: 1)).image, 0, 0)
        }
    }

    /// The distance along a row from 10% to 90% of the way between the two
    /// ends of `values`.
    private func rise(_ values: [Double]) -> Int {
        let a = values.first!, b = values.last!
        let low = a + 0.1 * (b - a), high = a + 0.9 * (b - a)
        let up = b > a
        let start = values.firstIndex { up ? $0 > low : $0 < low } ?? 0
        let end = values.firstIndex { up ? $0 >= high : $0 <= high } ?? values.count - 1
        return end - start
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theTapeKeepsItsLumaSharperThanItsChroma() throws {
        let px = Pixels(try OllinApp.image(of: Edge(), frame: 1))
        let row = 120
        var luma: [Double] = [], chroma: [Double] = []
        for x in 80 ..< 140 {
            let r = Double(px.channel(0, x, row)), g = Double(px.channel(1, x, row)), b = Double(px.channel(2, x, row))
            luma.append(0.299 * r + 0.587 * g + 0.114 * b)
            chroma.append(0.596 * r - 0.274 * g - 0.322 * b)
        }
        let lumaRise = rise(luma), chromaRise = rise(chroma)
        #expect(lumaRise <= 2, "luma rises in \(lumaRise) px")
        #expect(chromaRise >= 6, "chroma bleeds over \(chromaRise) px")
        // It trails to the right: past the edge the color is still arriving.
        #expect(chroma[22] < chroma[59] * 0.9)
    }

    // MARK: Lenses

    @Test(.enabled(if: Snapshot.hasMetal))
    func theTiltShiftsBandIsUntouched() throws {
        let plain = try render(nil)
        let lens = try render(.tiltShift(focus: 0.5, angle: 0, band: 0.1, falloff: 0.2, radius: 10))
        let band = Int(Double(Self.side) * 0.42) ..< Int(Double(Self.side) * 0.58)
        #expect(maxDifference(plain, lens, rows: band).max == 0)
        // Away from the band it is blurred.
        #expect(maxDifference(plain, lens, rows: 40 ..< 90).mean > 1)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theProgressiveBlursFarSideIsThePlainGaussian() throws {
        let plain = try render(nil)
        let blurred = try render(.gaussianBlur(radius: 6))
        let fading = try render(.progressiveBlur(angle: .pi / 2, start: 0, end: 0.4, radius: 6))
        // Past the end, and past the reach of the kernel back into the ramp.
        let far = Int(Double(Self.side) * 0.4) + 20 ..< Self.side
        let diff = maxDifference(blurred, fading, rows: far)
        #expect(diff.max <= 3 && diff.mean < 0.5, "against the Gaussian: \(diff)")
        // At its start it is the layer.
        #expect(maxDifference(plain, fading, rows: 0 ..< 1).max == 0)
    }

    // MARK: Light leak

    @Test(.enabled(if: Snapshot.hasMetal))
    func theLeakNeverDarkensAPixel() throws {
        let plain = try render(nil)
        let leak = try render(.lightLeak(intensity: 0.8, phase: 2.5, seed: 3))
        var raised = 0
        for y in 0 ..< Self.side {
            for x in 0 ..< Self.side {
                for c in 0 ..< 3 {
                    let before = plain.channel(c, x, y), after = leak.channel(c, x, y)
                    #expect(after >= before, "darkened at \(x), \(y): \(before) to \(after)")
                    if after > before + 8 { raised += 1 }
                    if after < before { return }
                }
            }
        }
        #expect(raised > Self.side * Self.side / 10, "it lights a good part of the frame: \(raised)")
    }

    /// The leak over nothing at all.
    final class LeakOverClear: Sketch {
        override var canvasSize: CanvasSize { .square(TapeAndLensTests.side) }
        override func draw() {
            background(.clear)
            let empty = makeRenderTarget()
            withTarget(empty) { background(.clear) }
            drawImage(empty.filtered(.lightLeak(anchor: Vector2(1, 0.5))).image, 0, 0)
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theLeakRaisesTheAlphaOverTransparency() throws {
        let px = Pixels(try OllinApp.image(of: LeakOverClear(), frame: 1))
        #expect(px.channel(3, 236, 120) > 200, "the core is all light: \(px.channel(3, 236, 120))")
        #expect(px.channel(3, 4, 4) < px.channel(3, 200, 120))
    }

    // MARK: Datamosh

    /// A disc crossing a striped ground, a new place every frame, through a
    /// datamosh field (or a plain layer, the reference).
    final class Mosh: Sketch {
        var sim: Sim?
        var field: SimField?
        override var canvasSize: CanvasSize { .square(TapeAndLensTests.side) }
        override func setup() { if let sim { field = makeSimField(sim) } }
        func scene() {
            background(Color(white: 0.3))
            noStroke()
            for i in 0 ..< 12 {
                fill(i % 2 == 0 ? Color(red: 0.8, green: 0.6, blue: 0.3) : Color(red: 0.3, green: 0.5, blue: 0.7))
                drawRect(Double(i) * 20, 0, 10, 240)
            }
            fill(.white); drawCircle(60 + Double(frameCount) * 9, 120, 30)
        }
        override func draw() {
            background(.black)
            if let field {
                withField(field) { scene() }
                drawImage(field.image, 0, 0)
            } else {
                let layer = makeRenderTarget()
                withTarget(layer) { scene() }
                drawImage(layer.image, 0, 0)
            }
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func everyBlockRefreshingIsTheDrawing() throws {
        let plain = Mosh()
        let mosh = Mosh(); mosh.sim = .datamosh(amount: 0)
        let a = Pixels(try OllinApp.image(of: plain, frame: 6))
        let b = Pixels(try OllinApp.image(of: mosh, frame: 6))
        #expect(maxDifference(a, b, rows: 0 ..< Self.side).max == 0)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func everyBlockHeldIsTheFirstFrameDrifting() throws {
        let first = Pixels(try OllinApp.image(of: Mosh(), frame: 0))
        let mosh = Mosh(); mosh.sim = .datamosh(amount: 1, motion: 0, drift: Vector2(3, -2), wander: 0)
        let frame = 5
        let held = Pixels(try OllinApp.image(of: mosh, frame: frame))
        // Frame k has decoded k + 1 times, each a step of the drift.
        let dx = 3 * (frame + 1), dy = -2 * (frame + 1)
        // The same light lands at a pixel the frame's dither treats differently,
        // so the bytes may differ by the dither's two levels and no more.
        var worst = 0, total = 0
        for y in 30 ..< 200 {
            for x in 30 ..< 200 {
                for c in 0 ..< 3 {
                    let d = abs(held.channel(c, x, y) - first.channel(c, x - dx, y - dy))
                    worst = max(worst, d); total += d
                }
            }
        }
        #expect(worst <= 2, "the held frame is the first moved by the drift: worst \(worst)")
        #expect(Double(total) / Double(170 * 170 * 3) < 0.6)
        // And not where it started, nor where this frame's drawing is.
        let live = Pixels(try OllinApp.image(of: Mosh(), frame: frame))
        #expect(maxDifference(held, live, rows: 0 ..< Self.side).mean > 5)
    }

    // MARK: Page peel

    @Test(.enabled(if: Snapshot.hasMetal))
    func thePeelAtAmountZeroIsTheLayer() throws {
        let plain = try render(nil), flat = try render(.pagePeel(amount: 0))
        #expect(maxDifference(plain, flat, rows: 0 ..< Self.side).max == 0)
    }

    /// A white sheet over nothing, peeled from its bottom-right corner.
    final class Sheet: Sketch {
        override var canvasSize: CanvasSize { .square(TapeAndLensTests.side) }
        override func draw() {
            background(.clear)
            let page = makeRenderTarget()
            withTarget(page) { background(.white) }
            drawImage(page.filtered(.pagePeel(amount: 0.3, radius: 0.05, shadow: 1)).image, 0, 0)
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theLiftedCornerIsTransparent() throws {
        let px = Pixels(try OllinApp.image(of: Sheet(), frame: 1))
        #expect(px.channel(3, 236, 236) == 0, "the corner the sheet left: \(px.channel(3, 236, 236))")
        #expect(px.channel(3, 10, 10) == 255 && px.gray(10, 10) > 240, "the far corner is the flat sheet")
        // Along the diagonal: the flat sheet, darker toward the crease under the
        // curl, then the curl, then a soft shadow on the ground past it.
        // The fold line crosses the diagonal at (168, 168); the flipped flap lies
        // over the sheet near the diagonal, so the crease is read off it, eight
        // pixels short of the fold and seventy along it.
        #expect(px.gray(212, 113) < px.gray(40, 40) - 6, "the crease's shadow on the sheet: \(px.gray(212, 113))")
        let past = px.channel(3, 188, 188)
        #expect(past > 0 && past < 200, "a shadow on the ground past the curl: \(past)")
    }

    // MARK: Scratches

    /// The scratches alone over nothing, at a given phase.
    final class Lines: Sketch {
        var phase = 0.0
        var flicker = 0.0
        override var canvasSize: CanvasSize { .square(TapeAndLensTests.side) }
        override func draw() {
            background(.clear)
            drawImage(generate(.scratches(count: 10, thickness: 1.5, length: 1, flicker: flicker,
                                          color: .white, phase: phase, seed: 4)).image, 0, 0)
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func scratchesAreClearBetweenTheirLinesAndHoldStill() throws {
        let a = Lines(); a.phase = 0.5
        let px = Pixels(try OllinApp.image(of: a, frame: 1))
        var lit = 0
        for x in 0 ..< Self.side where px.channel(3, x, 120) > 0 { lit += 1 }
        #expect(lit > 0 && lit < Self.side / 6, "a few hairlines across the row: \(lit) px")
        // With no flicker, a frame later (a 24th of a second) the lines hold:
        // only a lane whose scratch's life ends between the two may change.
        let b = Lines(); b.phase = 0.5 + 1.0 / 24
        let next = Pixels(try OllinApp.image(of: b, frame: 1))
        var held = 0, moved = 0
        for x in 0 ..< Self.side where px.channel(3, x, 120) > 0 || next.channel(3, x, 120) > 0 {
            if abs(px.channel(3, x, 120) - next.channel(3, x, 120)) <= 1 { held += 1 } else { moved += 1 }
        }
        #expect(held >= 3 * moved, "the lines hold still: \(held) held, \(moved) moved")
    }
}
