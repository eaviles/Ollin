import CoreGraphics
import Ollin
import Testing

/// Behavioral probes for the chromatic-aberration family: the five `Dispersion`
/// modes, the spectral tap budget, and the layer-driven `disperse` combine. A pixel
/// snapshot pins one sheet of them as a picture; these pin the rules that a mean
/// difference averages away. Every mode has to be an identity at zero, a flat offset
/// has to split the middle of the frame where a radial one cannot, the split has to
/// be the same size in both directions on a wide canvas, a layer whose alpha varies
/// under one color has to come back untouched, and the drive layer has to decide
/// where any of it happens. Metal-gated.
@Suite
@MainActor
struct DispersionTests {

    // MARK: Identity

    /// Zero is identity, in every mode. The knob is only honest if an A/B costs
    /// nothing, and a mode that tints or shifts at zero makes the whole family
    /// untrustworthy. `.axial` is included because its gather is the one that could
    /// blur at a zero radius.
    @Test(.enabled(if: Snapshot.hasMetal))
    func zeroIsIdentityInEveryMode() throws {
        let plain = try #require(OllinApp.image(of: DiscProbe.make(nil), frame: 1))
        let modes: [Filter.Dispersion] = [
            .magnify, .lens(), .lens(radius: 0, falloff: 1), .offset(angle: 0.7), .edges, .axial,
        ]
        for mode in modes {
            let filtered = try #require(OllinApp.image(
                of: DiscProbe.make(.chromaticAberration(amount: 0, mode: mode)), frame: 1))
            #expect(maxDifference(plain, filtered) == 0, "\(mode) moved at amount 0")
        }
        // The spectral path normalizes its own weights, so it has to be identity too.
        let spectral = try #require(OllinApp.image(
            of: DiscProbe.make(.chromaticAberration(amount: 0, spectral: true)), frame: 1))
        #expect(maxDifference(plain, spectral) == 0)
    }

    /// A flat field stays exactly its own color however wide the spectral split is.
    /// Each tap reads the same color there, so the answer is only that color again if
    /// the accumulated weights sum to one *per channel*, and they do not on their own
    /// (over fifteen taps green collects about 5.0 and red about 3.0), so an
    /// un-normalized loop would tint every flat area in the frame green.
    @Test(.enabled(if: Snapshot.hasMetal))
    func spectralTapsDoNotTintAFlatField() throws {
        let image = try #require(OllinApp.image(
            of: FlatProbe.make(.chromaticAberration(amount: 0.05, spectral: true,
                                                    quality: .detail)), frame: 1))
        let px = pixels(of: image)
        // Read well inside the field, away from the frame edge the sampler clamps at.
        let (r, g, b) = channels(px, x: 128, y: 128)
        #expect(abs(r - g) <= 1 && abs(g - b) <= 1, "flat field came back \(r),\(g),\(b)")
    }

    // MARK: What each mode does that the others cannot

    /// The default mode is a scale about the center, so the frame-center side of a
    /// shape fringes warm and the far side fringes cool: red reads from further out
    /// than blue does, everywhere.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theDefaultModeFringesRadially() throws {
        let image = try #require(OllinApp.image(
            of: DiscProbe.make(.chromaticAberration(amount: 0.03)), frame: 1))
        // The disc sits above the frame center, so its top rim is the far side.
        #expect(strongestBlueOverRed(image, x: 128, y: 30 ... 50) > 40)
        #expect(strongestRedOverBlue(image, x: 128, y: 105 ... 125) > 40)
    }

    /// The one thing a radial mode cannot do: split the exact middle of the frame. A
    /// flat offset moves every pixel by the same vector, which is misregistration
    /// rather than optics, and it is why the mode axis exists at all. Measured down the
    /// center column, across an edge that runs through the middle of the frame: the
    /// flat split is 17px of colored fringe there, the default mode leaves one
    /// anti-aliased pixel, and a lens that starts at a quarter of the way out leaves
    /// nothing whatsoever.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aFlatOffsetSplitsTheCenterWhereARadialModeCannot() throws {
        let flat = try #require(OllinApp.image(
            of: HalfPlaneProbe.make(.chromaticAberration(amount: 0.03,
                                                         mode: .offset(angle: .pi / 2))), frame: 1))
        let radial = try #require(OllinApp.image(
            of: HalfPlaneProbe.make(.chromaticAberration(amount: 0.03)), frame: 1))
        let lens = try #require(OllinApp.image(
            of: HalfPlaneProbe.make(.chromaticAberration(amount: 0.03, mode: .lens())), frame: 1))
        #expect(fringeWidthDown(flat, x: 128, from: 118, to: 138) > 10)
        #expect(fringeWidthDown(radial, x: 128, from: 118, to: 138) <= 2)
        #expect(fringeWidthDown(lens, x: 128, from: 118, to: 138) == 0)
    }

    /// The split is worked out in a space where one unit is one unit both ways, so a
    /// flat offset of the same `amount` moves the same number of *pixels* across a
    /// wide frame as it does down it. Offsetting in uv instead makes the horizontal
    /// split 16/9 of the vertical one on this canvas, which is the defect the shipped
    /// filter carried (the square default hid it).
    @Test(.enabled(if: Snapshot.hasMetal))
    func theSplitIsTheSameSizeBothWaysOnAWideCanvas() throws {
        let across = try #require(OllinApp.image(
            of: WideBarProbe.make(.chromaticAberration(amount: 0.05,
                                                       mode: .offset(angle: 0))), frame: 1))
        let down = try #require(OllinApp.image(
            of: WideBarProbe.make(.chromaticAberration(amount: 0.05,
                                                       mode: .offset(angle: .pi / 2))), frame: 1))
        let horizontal = fringeWidthAcross(across, y: 90, from: 60, to: 130)
        let vertical = fringeWidthDown(down, x: 160, from: 30, to: 100)
        #expect(horizontal > 4, "no horizontal split measured")
        #expect(abs(horizontal - vertical) <= 1,
                "split was \(horizontal)px across and \(vertical)px down")
    }

    /// A fringe only where there is an edge: a flat region keeps its exact color, and
    /// the rim does not. This is the mode's whole claim, and it is what makes it read
    /// as a lens rather than as a filter over the picture.
    @Test(.enabled(if: Snapshot.hasMetal))
    func edgesLeaveFlatRegionsAlone() throws {
        let plain = try #require(OllinApp.image(of: DiscProbe.make(nil), frame: 1))
        let fringed = try #require(OllinApp.image(
            of: DiscProbe.make(.chromaticAberration(amount: 0.03, mode: .edges)), frame: 1))
        // Deep inside the disc, and deep in the background: both untouched.
        #expect(differenceAt(plain, fringed, x: 128, y: 77) == 0)
        #expect(differenceAt(plain, fringed, x: 40, y: 210) == 0)
        // At the rim it is a different picture.
        #expect(strongestRedOverBlue(fringed, x: 128, y: 105 ... 125) > 40)
    }

    /// Longitudinal color puts one end of the spectrum out of focus and leaves the
    /// other sharp, which is a difference in *focus* rather than in position: red
    /// keeps the rim's step and blue spreads it. A negative amount swaps them, which
    /// is what an out-of-focus highlight does on the other side of focus.
    @Test(.enabled(if: Snapshot.hasMetal))
    func axialPutsOneEndOfTheSpectrumOutOfFocus() throws {
        let warm = try #require(OllinApp.image(
            of: DiscProbe.make(.chromaticAberration(amount: 0.03, mode: .axial)), frame: 1))
        let redEdge = transitionWidth(warm, channel: 0, x: 128, from: 100, to: 130)
        let blueEdge = transitionWidth(warm, channel: 2, x: 128, from: 100, to: 130)
        #expect(blueEdge > redEdge * 2, "red \(redEdge)px, blue \(blueEdge)px")

        let cool = try #require(OllinApp.image(
            of: DiscProbe.make(.chromaticAberration(amount: -0.03, mode: .axial)), frame: 1))
        #expect(transitionWidth(cool, channel: 0, x: 128, from: 100, to: 130)
                > transitionWidth(cool, channel: 2, x: 128, from: 100, to: 130) * 2)
    }

    // MARK: Coverage and the drive layer

    /// A layer holding one color under an alpha that varies has to come back exactly
    /// as it went in: unpremultiplied, every tap is reading the same color, so there
    /// is nothing to split. Taking the channels straight off the premultiplied texels
    /// instead mixes one texel's color with another's coverage, which is what leaves a
    /// darkened fringe along a layer's own soft edges.
    ///
    /// The probe's alpha falls to a quarter rather than to zero, because a fully
    /// transparent texel carries no color to borrow (its unpremultiplied value is
    /// undefined and reads as black), so a tap that lands out there really does have
    /// nothing to bring back. That is a property of the layer, not of the split.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aLayerWhoseAlphaVariesKeepsItsColor() throws {
        let plain = try #require(OllinApp.image(of: SoftEdgeProbe.make(nil), frame: 1))
        let split = try #require(OllinApp.image(
            of: SoftEdgeProbe.make(.chromaticAberration(amount: 0.04)), frame: 1))
        #expect(maxDifference(plain, split) <= 1)
    }

    /// The drive layer decides where the split happens, not how the split looks: the
    /// half the aux leaves black is the base again, texel for texel.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theDriveLayerDecidesWhereTheSplitHappens() throws {
        let plain = try #require(OllinApp.image(of: DrivenProbe.make(driven: false), frame: 1))
        let driven = try #require(OllinApp.image(of: DrivenProbe.make(driven: true), frame: 1))
        // Left half: the aux is black, so nothing may move.
        for y in stride(from: 20, to: 240, by: 20) {
            #expect(differenceAt(plain, driven, x: 40, y: y) == 0)
        }
        // Right half: the aux is white, so the lines come apart.
        #expect(strongestRedOverBlue(driven, x: 200, y: 60 ... 200) > 40)
    }

    /// The same drive, declared as an aside inside a `compose` block: the sugar has to
    /// resolve to the same op the substrate runs, so the black half stays untouched and
    /// the white half comes apart.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theComposeModifierResolvesToTheSameOp() throws {
        let plain = try #require(OllinApp.image(of: DrivenProbe.make(driven: false), frame: 1))
        let composed = try #require(OllinApp.image(of: ComposedDriveProbe(), frame: 1))
        for y in stride(from: 20, to: 240, by: 20) {
            #expect(differenceAt(plain, composed, x: 40, y: y) == 0)
        }
        #expect(strongestRedOverBlue(composed, x: 200, y: 60 ... 200) > 40)
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

    private func channels(_ px: (bytes: [UInt8], width: Int, height: Int), x: Int, y: Int)
        -> (Int, Int, Int) {
        let i = (y * px.width + x) * 4
        return (Int(px.bytes[i]), Int(px.bytes[i + 1]), Int(px.bytes[i + 2]))
    }

    private func maxDifference(_ a: CGImage, _ b: CGImage) -> Int {
        let pa = pixels(of: a), pb = pixels(of: b)
        var worst = 0
        for i in 0 ..< min(pa.bytes.count, pb.bytes.count) {
            worst = max(worst, abs(Int(pa.bytes[i]) - Int(pb.bytes[i])))
        }
        return worst
    }

    private func differenceAt(_ a: CGImage, _ b: CGImage, x: Int, y: Int) -> Int {
        let pa = pixels(of: a), pb = pixels(of: b)
        var worst = 0
        for c in 0 ..< 3 {
            let i = (y * pa.width + x) * 4 + c
            worst = max(worst, abs(Int(pa.bytes[i]) - Int(pb.bytes[i])))
        }
        return worst
    }

    /// The largest red-minus-blue anywhere in a short vertical run: a warm fringe.
    private func strongestRedOverBlue(_ image: CGImage, x: Int, y: ClosedRange<Int>) -> Int {
        let px = pixels(of: image)
        return y.map { channels(px, x: x, y: $0) }.map { $0.0 - $0.2 }.max() ?? 0
    }

    /// The same the other way: a cool fringe.
    private func strongestBlueOverRed(_ image: CGImage, x: Int, y: ClosedRange<Int>) -> Int {
        let px = pixels(of: image)
        return y.map { channels(px, x: x, y: $0) }.map { $0.2 - $0.0 }.max() ?? 0
    }

    /// How many pixels along a scanline carry a color cast (red and blue disagreeing
    /// by more than a dither step): the width of the split, in pixels.
    private func fringeWidthAcross(_ image: CGImage, y: Int, from x0: Int, to x1: Int) -> Int {
        let px = pixels(of: image)
        return (x0 ... x1).filter { x in
            let c = channels(px, x: x, y: y); return abs(c.0 - c.2) > 8
        }.count
    }

    /// The same measurement down a column.
    private func fringeWidthDown(_ image: CGImage, x: Int, from y0: Int, to y1: Int) -> Int {
        let px = pixels(of: image)
        return (y0 ... y1).filter { y in
            let c = channels(px, x: x, y: y); return abs(c.0 - c.2) > 8
        }.count
    }

    /// How many pixels one channel takes to cross from a tenth to nine tenths of its
    /// range down a column: how sharp that channel's edge is.
    private func transitionWidth(_ image: CGImage, channel: Int, x: Int,
                                 from y0: Int, to y1: Int) -> Int {
        let px = pixels(of: image)
        let run = (y0 ... y1).map { y -> Int in
            let c = channels(px, x: x, y: y)
            return [c.0, c.1, c.2][channel]
        }
        guard let lo = run.min(), let hi = run.max(), hi - lo > 20 else { return 0 }
        let low = lo + (hi - lo) / 10, high = hi - (hi - lo) / 10
        let inside = run.enumerated().filter { $0.element > low && $0.element < high }
        guard let first = inside.first?.offset, let last = inside.last?.offset else { return 0 }
        return last - first + 1
    }
}

// MARK: - Probes

/// A white disc above the frame center on black, the shape every radial claim is
/// measured against: its top rim is the far side of the frame and its bottom rim the
/// near side, so the two fringes have opposite colors.
private final class DiscProbe: Sketch {
    var filter: Filter?
    static func make(_ filter: Filter?) -> DiscProbe {
        let s = DiscProbe(); s.filter = filter; return s
    }
    override var canvasSize: CanvasSize { .square(256) }
    override func draw() {
        let scene = makeRenderTarget()
        withTarget(scene) {
            background(.black)
            noStroke(); fill(.white)
            drawCircle(128, 77, 40)
        }
        drawImage((filter.map { scene.filtered($0) } ?? scene).image, 0, 0)
    }
}

/// One flat mid-gray field: nothing to split, so any color that appears came from the
/// filter rather than from the picture.
private final class FlatProbe: Sketch {
    var filter: Filter?
    static func make(_ filter: Filter?) -> FlatProbe {
        let s = FlatProbe(); s.filter = filter; return s
    }
    override var canvasSize: CanvasSize { .square(256) }
    override func draw() {
        let scene = makeRenderTarget()
        withTarget(scene) { background(Color(white: 0.5)) }
        drawImage((filter.map { scene.filtered($0) } ?? scene).image, 0, 0)
    }
}

/// One hard edge running straight through the middle of the frame, where a radial
/// split is zero by construction and a flat one is not.
private final class HalfPlaneProbe: Sketch {
    var filter: Filter?
    static func make(_ filter: Filter?) -> HalfPlaneProbe {
        let s = HalfPlaneProbe(); s.filter = filter; return s
    }
    override var canvasSize: CanvasSize { .square(256) }
    override func draw() {
        let scene = makeRenderTarget()
        withTarget(scene) {
            background(.black)
            noStroke(); fill(.white)
            drawRect(0, 0, 256, 128)
        }
        drawImage((filter.map { scene.filtered($0) } ?? scene).image, 0, 0)
    }
}

/// A white block on a 16:9 canvas, so the split can be measured across the wide
/// direction and down the short one and the two compared in pixels.
private final class WideBarProbe: Sketch {
    var filter: Filter?
    static func make(_ filter: Filter?) -> WideBarProbe {
        let s = WideBarProbe(); s.filter = filter; return s
    }
    override var canvasSize: CanvasSize { .size(320, 180) }
    override func draw() {
        let scene = makeRenderTarget()
        withTarget(scene) {
            background(.black)
            noStroke(); fill(.white)
            drawRect(center: Vector2(160, 90), width: 160, height: 90)
        }
        drawImage((filter.map { scene.filtered($0) } ?? scene).image, 0, 0)
    }
}

/// One color under an alpha that falls away: unpremultiplied there is nothing to
/// split, so the filter has to hand it straight back.
private final class SoftEdgeProbe: Sketch {
    var filter: Filter?
    static func make(_ filter: Filter?) -> SoftEdgeProbe {
        let s = SoftEdgeProbe(); s.filter = filter; return s
    }
    override var canvasSize: CanvasSize { .square(256) }
    override func draw() {
        background(.black)
        let scene = makeRenderTarget()
        withTarget(scene) {
            noStroke()
            fill(.radial(center: Vector2(128, 128), radius: 110,
                         Ramp([Color(hex: 0xFF8000), Color(hex: 0xFF8000, alpha: 0.25)])))
            drawRect(0, 0, 256, 256)
        }
        drawImage((filter.map { scene.filtered($0) } ?? scene).image, 0, 0)
    }
}

/// Thin white lines under an aux layer that is black on the left and white on the
/// right: the split may only happen on the right.
private final class DrivenProbe: Sketch {
    var driven = false
    static func make(driven: Bool) -> DrivenProbe {
        let s = DrivenProbe(); s.driven = driven; return s
    }
    override var canvasSize: CanvasSize { .square(256) }
    override func draw() {
        let scene = makeRenderTarget()
        withTarget(scene) {
            background(Color(hex: 0x101010))
            stroke(.white); strokeWeight(2); noFill()
            for i in 0 ..< 10 { drawLine(0, 20 + Double(i) * 24, 256, 20 + Double(i) * 24) }
        }
        guard driven else { drawImage(scene.image, 0, 0); return }
        let drive = makeRenderTarget()
        withTarget(drive) {
            background(.black)
            noStroke(); fill(.white)
            drawRect(128, 0, 128, 256)
        }
        drawImage(scene.combined(with: drive, .disperse(amount: 0.03)).image, 0, 0)
    }
}

/// The `DrivenProbe` scene again, declared through the `compose` DSL instead of the
/// substrate, so `.dispersed(by:)` is exercised as well as `Combine.disperse`.
private final class ComposedDriveProbe: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    override func draw() {
        compose {
            layer {
                background(Color(hex: 0x101010))
                stroke(.white); strokeWeight(2); noFill()
                for i in 0 ..< 10 { drawLine(0, 20 + Double(i) * 24, 256, 20 + Double(i) * 24) }
            }
            .dispersed(by: aside {
                background(.black)
                noStroke(); fill(.white); drawRect(128, 0, 128, 256)
            }, amount: 0.03)
        }
    }
}
