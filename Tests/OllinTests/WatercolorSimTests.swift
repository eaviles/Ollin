import CoreGraphics
import Testing
@testable import Ollin

/// The watercolor sim, pinned from both ends: the Kubelka-Munk layer optics as
/// pure CPU math (the same closed forms the render pass evaluates), and
/// Metal-gated behavioral probes for what a whole-frame mean diff averages away:
/// the darkened wet edge, the dry-brush gaps, the wash freezing when dried, the
/// backrun creep into damp paper, and byte-exact replay.
@Suite
@MainActor
struct WatercolorSimTests {

    // MARK: Kubelka-Munk (CPU, no GPU needed)

    @Test func zeroThicknessIsTheIdentityLayer() {
        let (r, t) = KubelkaMunk.layer(k: 0.7, s: 0.2, x: 0)
        #expect(r == 0 && t == 1)
    }

    @Test func thickLayerApproachesItsInfiniteReflectance() {
        // As x grows, R tends to a - b (the classic infinite-thickness limit).
        let k = 0.5, s = 0.2
        let a = 1 + k / s
        let expected = a - (a * a - 1).squareRoot()
        let (r, t) = KubelkaMunk.layer(k: k, s: s, x: 200)
        #expect(abs(r - expected) < 1e-3)
        #expect(t < 1e-3)
    }

    @Test func compositeOverNothingIsTheLayerItself() {
        let (r1, t1) = KubelkaMunk.layer(k: 0.3, s: 0.4, x: 1)
        let (r, t) = KubelkaMunk.composite(r1: r1, t1: t1, r2: 0, t2: 1)
        #expect(abs(r - r1) < 1e-12)
        #expect(abs(t - t1) < 1e-12)
    }

    @Test func inversionRecoversCoefficientsFromTheTwoSwatches() {
        // Forward: a unit layer's color over black is its own reflectance, and
        // over white its reflectance plus what bounces back through it. The
        // inversion must recover K and S from exactly those two observables.
        for (k, s) in [(0.5, 0.3), (0.1, 0.9), (2.0, 0.05), (0.02, 0.5)] {
            let (r, t) = KubelkaMunk.layer(k: k, s: s, x: 1)
            let overBlack = r
            let overWhite = r + t * t / (1 - r)
            let recovered = KubelkaMunk.coefficients(overWhite: overWhite, overBlack: overBlack)
            #expect(abs(recovered.k - k) / k < 0.02, "k for (\(k), \(s))")
            #expect(abs(recovered.s - s) / s < 0.02, "s for (\(k), \(s))")
        }
    }

    @Test func pigmentFromSwatchesShowsTheChosenColorOverWhite() {
        let overWhite = Color(red: 0.8, green: 0.3, blue: 0.45)
        let overBlack = Color(red: 0.3, green: 0.1, blue: 0.15)
        let pigment = WatercolorPigment(overWhite: overWhite, overBlack: overBlack)
        for (c, want) in [(0, 0.8), (1, 0.3), (2, 0.45)] {
            let (r, t) = KubelkaMunk.layer(k: pigment.k[c], s: pigment.s[c], x: 1)
            let shown = r + t * t / (1 - r)
            #expect(abs(shown - want) < 0.02)
        }
    }

    // MARK: Behavioral probes (Metal-gated)

    @Test(.enabled(if: Snapshot.hasMetal))
    func untouchedFieldStaysBarePaper() throws {
        let sketch = WatercolorProbeSketch()
        sketch.script = []
        let image = try #require(OllinApp.image(of: sketch, frame: 30))
        let lum = luminances(of: image)
        // No pigment anywhere: the whole sheet reads as the near-white paper.
        #expect(lum.min()! > 0.85)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aWashDriesWithADarkenedEdge() throws {
        let sketch = WatercolorProbeSketch()
        sketch.script = [.paint(frame: 1, at: Vector2(64, 64), radius: 34, pigment: 0, load: 0.5, water: 1)]
        let image = try #require(OllinApp.image(of: sketch, frame: 220))
        let lum = luminances(of: image)
        let w = 128
        var rim = 0.0, rimCount = 0.0, core = 0.0, coreCount = 0.0
        for y in 0 ..< w {
            for x in 0 ..< w {
                let d = (Double(x - 64) * Double(x - 64) + Double(y - 64) * Double(y - 64)).squareRoot()
                if d < 16 { core += lum[y * w + x]; coreCount += 1 }
                if d > 26 && d < 32 { rim += lum[y * w + x]; rimCount += 1 }
            }
        }
        // Pigment migrated outward and settled: the rim band reads darker than the core.
        #expect(rim / rimCount < core / coreCount - 0.01)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func dryBrushBreaksTheStrokeAcrossTheTooth() throws {
        func coverage(dryBrush: Double) throws -> Double {
            let sketch = WatercolorProbeSketch()
            sketch.dryBrush = dryBrush
            sketch.script = [.paint(frame: 1, at: Vector2(64, 64), radius: 40, pigment: 0, load: 0.6, water: 1)]
            let image = try #require(OllinApp.image(of: sketch, frame: 30))
            let lum = luminances(of: image)
            let inked = lum.filter { $0 < 0.88 }.count
            return Double(inked) / Double(lum.count)
        }
        let wet = try coverage(dryBrush: 0)
        let dry = try coverage(dryBrush: 0.55)
        #expect(wet > 0.1)
        #expect(dry < wet * 0.7)   // the same stroke skips across the raised tooth
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func dryingFreezesTheWash() throws {
        func frameBytes(_ frame: Int) throws -> [UInt8] {
            let sketch = WatercolorProbeSketch()
            sketch.script = [.paint(frame: 1, at: Vector2(64, 64), radius: 30, pigment: 0, load: 0.5, water: 1),
                             .dry(frame: 40)]
            return bytes(of: try #require(OllinApp.image(of: sketch, frame: frame))).bytes
        }
        let just = try frameBytes(50)
        let later = try frameBytes(140)
        var meanDiff = 0.0
        for i in 0 ..< just.count { meanDiff += abs(Double(just[i]) - Double(later[i])) }
        meanDiff /= Double(just.count) * 255
        // A dried sheet stops evolving entirely (the render reads only the baked
        // glaze stack, and damp paper below the re-wet threshold stays inert).
        #expect(meanDiff < 0.002)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func backrunsBloomThroughDampPaintAndStopWhenOff() throws {
        // The classic backrun staging: a wash is blotted (water lifted, pigment
        // parked, sheet damp), then a held clean-water drop lands in its middle.
        // With the capillary layer on, the drop floods back through the damp
        // ground and pushes the parked pigment ahead of it: the paling reaches
        // well past the drop's own footprint (which confined water cannot do)
        // and the pigment piles into a darker ridge outside it. With it off,
        // the water stays inside the drop and both bands hold the wash's tone.
        func bands(backruns: Bool) throws -> (cleared: Double, ridge: Double) {
            let sketch = WatercolorProbeSketch()
            sketch.backruns = backruns
            sketch.script = [.paint(frame: 1, at: Vector2(64, 64), radius: 34, pigment: 0, load: 0.35, water: 1),
                             .blot(frame: 60),
                             .paint(frames: 66 ... 96, at: Vector2(64, 64), radius: 8,
                                    pigment: -1, load: 0, water: 0.8)]
            let image = try #require(OllinApp.image(of: sketch, frame: 200))
            let lum = luminances(of: image)
            var cleared = 0.0, clearedN = 0.0, ridge = 0.0, ridgeN = 0.0
            for y in 0 ..< 128 {
                for x in 0 ..< 128 {
                    let d = (Double(x - 64) * Double(x - 64) + Double(y - 64) * Double(y - 64)).squareRoot()
                    if d > 8, d < 12 { cleared += lum[y * 128 + x]; clearedN += 1 }
                    if d > 12, d < 20 { ridge += lum[y * 128 + x]; ridgeN += 1 }
                }
            }
            return (cleared / clearedN, ridge / ridgeN)
        }
        let on = try bands(backruns: true)
        let off = try bands(backruns: false)
        #expect(on.cleared > off.cleared + 0.015)   // the flood cleared past the drop's footprint
        #expect(on.ridge < off.ridge - 0.005)       // and piled the pigment into a ridge outside it
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func sameRunReplaysExactly() throws {
        func run() throws -> [UInt8] {
            let sketch = WatercolorProbeSketch()
            sketch.script = [.paint(frame: 1, at: Vector2(50, 60), radius: 28, pigment: 0, load: 0.5, water: 1),
                             .paint(frame: 20, at: Vector2(80, 70), radius: 16, pigment: 1, load: 0.6, water: 0.8)]
            return bytes(of: try #require(OllinApp.image(of: sketch, frame: 90))).bytes
        }
        #expect(try run() == run())
    }

    // MARK: Readback helpers

    private func bytes(of image: CGImage) -> (bytes: [UInt8], width: Int, height: Int) {
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

    private func luminances(of image: CGImage) -> [Double] {
        let (data, w, h) = bytes(of: image)
        var lum = [Double](repeating: 0, count: w * h)
        for p in 0 ..< w * h {
            let i = p * 4
            lum[p] = (0.2126 * Double(data[i]) + 0.7152 * Double(data[i + 1])
                      + 0.0722 * Double(data[i + 2])) / 255
        }
        return lum
    }
}

/// A tiny sheet: a full-res 128² watercolor field under a 128² canvas, painted
/// by a fixed script (paint and dry events keyed to frames), the raw painting
/// drawn full-canvas for readback. Fixed paper seed, no rng: byte-deterministic.
@MainActor
private final class WatercolorProbeSketch: Sketch {
    override var canvasSize: CanvasSize { .square(128) }

    enum Event {
        case paint(frames: ClosedRange<Int>, at: Vector2, radius: Double,
                   pigment: Int, load: Double, water: Double)
        case dry(frame: Int)
        case blot(frame: Int)

        static func paint(frame: Int, at: Vector2, radius: Double,
                          pigment: Int, load: Double, water: Double) -> Event {
            .paint(frames: frame ... frame, at: at, radius: radius,
                   pigment: pigment, load: load, water: water)
        }
    }

    var script: [Event] = []
    var backruns = true
    var dryBrush = 0.0

    private var paint: WatercolorField!

    override func setup() {
        paint = watercolor(.watercolor(pigments: [.frenchUltramarine, .quinacridoneRose],
                                       backruns: backruns, dryBrush: dryBrush, paperSeed: 7),
                           scale: 1)
    }

    override func draw() {
        withField(paint) {
            noStroke()
            for event in script {
                switch event {
                case let .paint(frames, at, radius, pigment, load, water):
                    if frames.contains(frameCount) {
                        fill(pigment >= 0 ? paint.ink(pigment, load: load, water: water)
                                          : paint.water(water))
                        drawCircle(at.x, at.y, radius)
                    }
                case let .dry(frame):
                    if frame == frameCount { paint.dry() }
                case let .blot(frame):
                    if frame == frameCount { paint.blot() }
                }
            }
        }
        drawImage(paint.image, 0, 0)
    }
}
