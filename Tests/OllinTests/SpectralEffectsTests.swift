import CoreGraphics
import Ollin
import Testing

/// Behavioral probes for the spectral GPU trio: the thin-film and diffraction
/// filters and the paint-mix combine. The rules a snapshot's mean difference
/// can't pin: zero amounts and empty aux layers are exact identities, equal
/// inputs survive a paint mix, yellow paint over blue meets in green on the
/// GPU the same way it does on the CPU, a thin film darkens toward zero
/// thickness and saturates at the strong-color depths, a flat field keeps its
/// color through a grating, and a grating sends red farther than blue (the
/// grating equation, the physical claim of the whole filter). Metal-gated.
@Suite
@MainActor
struct SpectralEffectsTests {

    // MARK: Identities

    /// Zero amount is an exact identity for both spectral filters: the parameter is
    /// only honest if an A/B costs nothing.
    @Test(.enabled(if: Snapshot.hasMetal))
    func zeroAmountIsIdentity() throws {
        let plain = try #require(OllinApp.image(of: FilterProbe.make(nil), frame: 1))
        for filter in [Filter.thinFilm(amount: 0), .diffraction(amount: 0)] {
            let filtered = try #require(OllinApp.image(of: FilterProbe.make(filter), frame: 1))
            #expect(maxDifference(plain, filtered) == 0)
        }
    }

    /// Outside the aux's own coverage the base passes through exactly: the
    /// aux's alpha gates the mix per pixel, so paint that isn't there mixes
    /// nothing.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theBasePassesThroughOutsideTheAuxCoverage() throws {
        let plain = try #require(OllinApp.image(of: PaintMixProbe.make(.plainBase), frame: 1))
        let mixed = try #require(OllinApp.image(of: PaintMixProbe.make(.yellowDisc), frame: 1))
        // The disc sits at (128, 128) with radius 60; (30, 30) is well clear of it.
        let before = pixel(plain, x: 30, y: 30)
        let after = pixel(mixed, x: 30, y: 30)
        #expect(before == after)
    }

    /// Mixing a layer with itself changes nothing (to the model's clamp): the
    /// absorption ratio round trip is algebraically exact, so equal inputs
    /// must come back as themselves at any tap count.
    @Test(.enabled(if: Snapshot.hasMetal))
    func equalLayersSurviveAPaintMix() throws {
        let plain = try #require(OllinApp.image(of: PaintMixProbe.make(.plainBase), frame: 1))
        let mixed = try #require(OllinApp.image(of: PaintMixProbe.make(.equalAux), frame: 1))
        #expect(maxDifference(plain, mixed) <= 2)
    }

    // MARK: Paint on the GPU

    /// The flagship, on the GPU: a yellow wash over a blue field reads green
    /// where they overlap, matching the CPU's `.paint` mixing.
    @Test(.enabled(if: Snapshot.hasMetal))
    func yellowOverBlueMeetsInGreen() throws {
        let image = try #require(OllinApp.image(of: PaintMixProbe.make(.yellowDisc), frame: 1))
        let (r, g, b) = pixel(image, x: 128, y: 128)
        #expect(g > r, "mix center read (\(r), \(g), \(b))")
        #expect(g > b, "mix center read (\(r), \(g), \(b))")
    }

    // MARK: The film

    /// A film thins toward clear and blooms into color at the strong-color
    /// depths: brightness and saturation both climb from a near-zero film to a
    /// mid-hundreds one.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aThinnerFilmIsDarkerAndGrayer() throws {
        func film(_ nm: Double) throws -> (brightness: Int, saturation: Int) {
            let filter = Filter.thinFilm(amount: 1, thickness: nm, variation: 0)
            let image = try #require(OllinApp.image(of: FlatFieldProbe.make(filter), frame: 1))
            let (r, g, b) = pixel(image, x: 128, y: 128)
            return (max(r, g, b), max(r, g, b) - min(r, g, b))
        }
        let thin = try film(25)
        let strong = try film(350)
        #expect(thin.brightness < strong.brightness)
        #expect(thin.saturation < strong.saturation)
        #expect(strong.saturation > 30)
    }

    // MARK: The grating

    /// A flat field keeps its color through the grating: every tap lands on the
    /// same texel and the tap colors sum to white, so nothing tints.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aFlatFieldDoesNotTint() throws {
        let filter = Filter.diffraction(amount: 0.1)
        let image = try #require(OllinApp.image(of: FlatFieldProbe.make(filter), frame: 1))
        let (r, g, b) = pixel(image, x: 128, y: 128)
        #expect(abs(r - b) <= 1 && abs(r - g) <= 1)
    }

    /// The grating equation: along the first order, blue lands near and red
    /// lands far, because an order's offset grows with wavelength.
    @Test(.enabled(if: Snapshot.hasMetal))
    func redReachesFartherThanBlue() throws {
        let filter = Filter.diffraction(amount: 0.15, angle: 0, orders: 1)
        let image = try #require(OllinApp.image(of: DotProbe.make(filter), frame: 1))
        // The dot sits at x = 128; first-order offsets are amount * 256 * (lambda / 550):
        // about 31 px at 450 nm, about 45 px at 650 nm.
        let near = pixel(image, x: 128 + 31, y: 128)
        let far = pixel(image, x: 128 + 45, y: 128)
        #expect(near.b > near.r, "near band read \(near)")
        #expect(far.r > far.b, "far band read \(far)")
    }

    // MARK: Probes

    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        let px = pixels(of: image)
        let i = (y * px.width + x) * 4
        return (Int(px.bytes[i]), Int(px.bytes[i + 1]), Int(px.bytes[i + 2]))
    }

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
}

/// A white disc on black through an optional filter.
private final class FilterProbe: Sketch {
    var filter: Filter?
    static func make(_ filter: Filter?) -> FilterProbe {
        let s = FilterProbe(); s.filter = filter; return s
    }
    override var canvasSize: CanvasSize { .square(256) }
    override func draw() {
        let scene = makeRenderTarget()
        withTarget(scene) {
            background(.black)
            noStroke(); fill(.white)
            drawCircle(128, 100, 40)
        }
        drawImage((filter.map { scene.filtered($0) } ?? scene).image, 0, 0)
    }
}

/// One flat mid-gray field: any color that appears came from the filter.
private final class FlatFieldProbe: Sketch {
    var filter: Filter?
    static func make(_ filter: Filter?) -> FlatFieldProbe {
        let s = FlatFieldProbe(); s.filter = filter; return s
    }
    override var canvasSize: CanvasSize { .square(256) }
    override func draw() {
        let scene = makeRenderTarget()
        withTarget(scene) { background(Color(white: 0.5)) }
        drawImage((filter.map { scene.filtered($0) } ?? scene).image, 0, 0)
    }
}

/// A small bright dot on black, for reading where a grating order lands.
private final class DotProbe: Sketch {
    var filter: Filter?
    static func make(_ filter: Filter?) -> DotProbe {
        let s = DotProbe(); s.filter = filter; return s
    }
    override var canvasSize: CanvasSize { .square(256) }
    override func draw() {
        let scene = makeRenderTarget()
        withTarget(scene) {
            background(.black)
            noStroke(); fill(.white)
            drawCircle(128, 128, 4)
        }
        drawImage((filter.map { scene.filtered($0) } ?? scene).image, 0, 0)
    }
}

/// A blue base with a configurable aux, through the paint-mix combine.
private final class PaintMixProbe: Sketch {
    enum Mode { case plainBase, equalAux, yellowDisc }
    var mode: Mode = .plainBase
    static func make(_ mode: Mode) -> PaintMixProbe {
        let s = PaintMixProbe(); s.mode = mode; return s
    }
    override var canvasSize: CanvasSize { .square(256) }
    override func draw() {
        let blue = Color(red: 0.1, green: 0.25, blue: 0.9)
        let base = makeRenderTarget()
        withTarget(base) { background(blue) }
        switch mode {
        case .plainBase:
            drawImage(base.image, 0, 0)
        case .equalAux:
            let aux = makeRenderTarget()
            withTarget(aux) { background(blue) }
            drawImage(base.combined(with: aux, .paintMix(amount: 0.5)).image, 0, 0)
        case .yellowDisc:
            let aux = makeRenderTarget()
            withTarget(aux) {
                noStroke(); fill(Color(red: 1, green: 0.85, blue: 0.05))
                drawCircle(128, 128, 60)
            }
            drawImage(base.combined(with: aux, .paintMix(amount: 0.5)).image, 0, 0)
        }
    }
}
