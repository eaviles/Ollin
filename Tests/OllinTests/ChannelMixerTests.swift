import CoreGraphics
import Testing
@testable import Ollin

/// The channel mixer: a `ColorMatrix` run over a layer. The identity matrix has
/// to change no byte, including through a half-transparent layer, since the
/// color is straightened out of its alpha for the multiply and put back after;
/// the gray mix has to be the display's own luminance; a swap has to read one
/// channel where the other was; an offset has to add in linear light; and the
/// row-by-row reading of the matrix has to fill in what a sketch leaves out.
@Suite
@MainActor
struct ChannelMixerTests {

    // MARK: The matrix as a value

    @Test func rowsLeftOutKeepTheirChannelAndShortRowsReadAsZero() {
        let traded = ColorMatrix(red: [0, 0, 1], blue: [1, 0, 0])
        #expect(traded.values == [0, 0, 1, 0, 0,  0, 1, 0, 0, 0,  1, 0, 0, 0, 0,  0, 0, 0, 1, 0])
        #expect(traded == .swapping(.red, .blue))
        #expect(ColorMatrix.swapping(.green, .green) == .identity)
        #expect(ColorMatrix.swapping(.red, .alpha) == .swapping(.alpha, .red))
        #expect(ColorMatrix.gray == .gray())
        #expect(ColorMatrix.gray.values[0 ..< 3] == [0.2126, 0.7152, 0.0722])
        #expect(ColorMatrix.gray.values[15 ..< 20] == [0, 0, 0, 1, 0])
        // A long row is read to its fifth number, and the identity is what it says.
        #expect(ColorMatrix(red: [1, 0, 0, 0, 0, 9, 9]).values == ColorMatrix.identity.values)
    }

    // MARK: Identity

    /// The identity matrix changes no byte, over a layer that is opaque in one
    /// disc and half transparent in another, so the straighten-and-premultiply
    /// round trip is proven exact, not only the multiply.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theIdentityMatrixChangesNoByte() throws {
        let plain = try OllinApp.image(of: DiscsProbe.make(nil), frame: 1)
        let filtered = try OllinApp.image(of: DiscsProbe.make(.channelMixer(.identity)), frame: 1)
        #expect(maxDifference(plain, filtered) == 0)
        // The gate can fail: a swap over the same discs moves bytes.
        let swapped = try OllinApp.image(of: DiscsProbe.make(.channelMixer(.swapping(.red, .blue))), frame: 1)
        #expect(maxDifference(plain, swapped) > 60)
    }

    // MARK: What the presets do

    /// `.gray` is the luminance a display makes of the color: the same value in
    /// all three channels, and that value the BT.709 weighting of the patch in
    /// linear light, encoded back. Read against the CPU sum.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theGrayMixIsTheLuminance() throws {
        let patch = (r: 0.88, g: 0.44, b: 0.23)
        let image = try OllinApp.image(
            of: PatchProbe.make(patch, .channelMixer(.gray)), frame: 1)
        let (r, g, b) = channels(Pixels(image), x: 64, y: 64)
        #expect(abs(r - g) <= 1 && abs(g - b) <= 1, "the gray came back \(r),\(g),\(b)")
        let luma = 0.2126 * Color.srgbToLinear(patch.r) + 0.7152 * Color.srgbToLinear(patch.g)
            + 0.0722 * Color.srgbToLinear(patch.b)
        let expected = Int((Color.linearToSrgb(luma) * 255).rounded())
        #expect(abs(r - expected) <= 2, "gray \(r) against the CPU's \(expected)")
        // A recipe that is not the display's: all red is the red channel's own value.
        let redFilter = try OllinApp.image(
            of: PatchProbe.make(patch, .channelMixer(.gray(red: 1, green: 0, blue: 0))), frame: 1)
        let (fr, fg, fb) = channels(Pixels(redFilter), x: 64, y: 64)
        let red = Int((patch.r * 255).rounded())
        #expect(abs(fr - red) <= 1 && abs(fg - red) <= 1 && abs(fb - red) <= 1,
                "the red-filter gray came back \(fr),\(fg),\(fb) for a red of \(red)")
    }

    /// A swap shows one channel where the other was, to the byte.
    @Test(.enabled(if: Snapshot.hasMetal))
    func swappingTradesTwoChannels() throws {
        let patch = (r: 0.80, g: 0.30, b: 0.12)
        let plain = try OllinApp.image(of: PatchProbe.make(patch, nil), frame: 1)
        let swapped = try OllinApp.image(
            of: PatchProbe.make(patch, .channelMixer(.swapping(.red, .blue))), frame: 1)
        let (r, g, b) = channels(Pixels(plain), x: 64, y: 64)
        let (sr, sg, sb) = channels(Pixels(swapped), x: 64, y: 64)
        #expect(abs(sr - b) <= 1 && abs(sg - g) <= 1 && abs(sb - r) <= 1,
                "\(r),\(g),\(b) swapped came back \(sr),\(sg),\(sb)")
    }

    /// The offset adds in linear light: a quarter of full light on black encodes
    /// to about 137, not to a quarter of 255.
    @Test(.enabled(if: Snapshot.hasMetal))
    func anOffsetAddsInLinearLight() throws {
        let image = try OllinApp.image(
            of: PatchProbe.make((r: 0, g: 0, b: 0), .channelMixer(ColorMatrix(red: [1, 0, 0, 0, 0.25]))), frame: 1)
        let (r, g, b) = channels(Pixels(image), x: 64, y: 64)
        let expected = Int((Color.linearToSrgb(0.25) * 255).rounded())
        #expect(abs(r - expected) <= 2 && g <= 1 && b <= 1, "an offset of 0.25 came back \(r),\(g),\(b)")
    }

    /// The alpha row is a channel like the others: halving it over a white disc
    /// on black shows the disc at half its light.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theAlphaRowScalesCoverage() throws {
        let image = try OllinApp.image(
            of: DiscsProbe.make(.channelMixer(ColorMatrix(alpha: [0, 0, 0, 0.5]))), frame: 1)
        let (r, g, b) = channels(Pixels(image), x: 64, y: 64)   // inside the opaque white disc
        let expected = Int((Color.linearToSrgb(0.5) * 255).rounded())
        #expect(abs(r - expected) <= 2 && abs(g - expected) <= 2 && abs(b - expected) <= 2,
                "half alpha came back \(r),\(g),\(b) for \(expected)")
    }

    // MARK: Pixels

    private func channels(_ px: Pixels, x: Int, y: Int)
        -> (Int, Int, Int) {
        let i = (y * px.width + x) * 4
        return (Int(px.bytes[i]), Int(px.bytes[i + 1]), Int(px.bytes[i + 2]))
    }

    private func maxDifference(_ a: CGImage, _ b: CGImage) -> Int {
        let pa = Pixels(a), pb = Pixels(b)
        var worst = 0
        for i in 0 ..< min(pa.bytes.count, pb.bytes.count) {
            worst = max(worst, abs(Int(pa.bytes[i]) - Int(pb.bytes[i])))
        }
        return worst
    }
}

/// An opaque white disc and a half-transparent orange one in an otherwise
/// transparent layer, laid over black.
private final class DiscsProbe: Sketch {
    var filter: Filter?
    static func make(_ filter: Filter?) -> DiscsProbe {
        let s = DiscsProbe(); s.filter = filter; return s
    }
    override var canvasSize: CanvasSize { .square(128) }
    override func draw() {
        background(.black)
        let layer = makeRenderTarget()
        withTarget(layer) {
            noStroke()
            fill(.white); drawCircle(64, 64, 28)
            fill(Color(red: 0.9, green: 0.5, blue: 0.2, alpha: 0.5)); drawCircle(96, 96, 24)
        }
        drawImage((filter.map { layer.filtered($0) } ?? layer).image, 0, 0)
    }
}

/// One flat patch of a color, given as display values.
private final class PatchProbe: Sketch {
    var patch = (r: 0.5, g: 0.5, b: 0.5)
    var filter: Filter?
    static func make(_ patch: (r: Double, g: Double, b: Double), _ filter: Filter?) -> PatchProbe {
        let s = PatchProbe(); s.patch = patch; s.filter = filter; return s
    }
    override var canvasSize: CanvasSize { .square(128) }
    override func draw() {
        background(.black)
        let layer = makeRenderTarget()
        withTarget(layer) { background(Color(red: patch.r, green: patch.g, blue: patch.b)) }
        drawImage((filter.map { layer.filtered($0) } ?? layer).image, 0, 0)
    }
}
