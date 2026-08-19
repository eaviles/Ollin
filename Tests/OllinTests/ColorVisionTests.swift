import Foundation
import Ollin
import Testing

/// The color-vision simulation is a table of published matrices plus two
/// decisions that are easy to get wrong and invisible once wrong: which color
/// space the matrix belongs in, and what a severity between two tabulated steps
/// means. These pin both, and pin the behavior the whole feature exists for,
/// which is that colors a designer picked apart can arrive on top of each other.
@Suite
struct ColorVisionTests {

    /// The sRGB transfer function, written out here rather than borrowed from
    /// the framework, so the reference below is independent of the code it
    /// checks.
    private func toLinear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }

    private func toDisplay(_ c: Double) -> Double {
        c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
    }

    /// Distance in a perceptual space, so "these two look alike" is measured
    /// the way an eye would report it rather than by channel arithmetic.
    private func distance(_ a: Color, _ b: Color) -> Double {
        let x = OKLab(a), y = OKLab(b)
        let dl = x.l - y.l, da = x.a - y.a, db = x.b - y.b
        return (dl * dl + da * da + db * db).squareRoot()
    }

    /// Distance in hue and colorfulness alone, with lightness left out.
    ///
    /// This is the axis a cone shift takes away. Red and green stay 85% as far
    /// apart as ever under protanopia when lightness counts, because one is
    /// much darker than the other. Measured across the hue plane alone they
    /// fall to 20%, and that is the confusion the simulation is for.
    private func chroma(_ a: Color, _ b: Color) -> Double {
        let x = OKLab(a), y = OKLab(b)
        return ((x.a - y.a) * (x.a - y.a) + (x.b - y.b) * (x.b - y.b)).squareRoot()
    }

    // MARK: - The published table

    /// The severity-1 matrices are the published dichromacy ones. If a
    /// transcription slipped, this is where it shows.
    @Test func theTableHoldsThePublishedDichromacyMatrices() {
        let protan = ColorVision.protanopia.matrix
        #expect(abs(protan[0] - 0.152286) < 1e-9)
        #expect(abs(protan[1] - 1.052583) < 1e-9)
        #expect(abs(protan[2] - -0.204868) < 1e-9)

        let deutan = ColorVision.deuteranopia.matrix
        #expect(abs(deutan[0] - 0.367322) < 1e-9)
        #expect(abs(deutan[1] - 0.860646) < 1e-9)
        #expect(abs(deutan[2] - -0.227968) < 1e-9)

        let tritan = ColorVision.tritanopia.matrix
        #expect(abs(tritan[0] - 1.255528) < 1e-9)
        #expect(abs(tritan[1] - -0.076749) < 1e-9)
        #expect(abs(tritan[2] - -0.178779) < 1e-9)
    }

    /// Severity 0 is the identity for every kind, so `.normal` cannot tint
    /// anything by accident.
    @Test func severityZeroIsTheIdentity() {
        for kind in ColorVision.Kind.allCases {
            let m = ColorVision(kind, severity: 0).matrix
            let identity = [1.0, 0, 0, 0, 1, 0, 0, 0, 1]
            for i in 0..<9 { #expect(abs(m[i] - identity[i]) < 1e-6) }
        }
        for color in [Color.red, .green, .blue, .white, .black, Color(hex: 0x3A7BD5)] {
            #expect(color.simulated(.normal) == color)
            #expect(color.simulated(ColorVision(.protanomaly, severity: 0)) == color)
        }
    }

    /// A severity the table does not hold interpolates its two neighbors, the
    /// approximation the model's authors describe.
    @Test func anUntabulatedSeverityInterpolatesItsNeighbours() {
        let low = ColorVision(.deuteranomaly, severity: 0.8).matrix
        let high = ColorVision(.deuteranomaly, severity: 0.9).matrix
        let middle = ColorVision(.deuteranomaly, severity: 0.85).matrix
        for i in 0..<9 {
            #expect(abs(middle[i] - (low[i] + high[i]) / 2) < 1e-9)
        }
        // A tabulated severity is the table entry itself, not an interpolation.
        let exact = ColorVision(.deuteranomaly, severity: 0.9).matrix
        for i in 0..<9 { #expect(exact[i] == high[i]) }
    }

    /// Severity is clamped rather than extrapolated, so a knob dragged past
    /// either end keeps meaning something.
    @Test func severityIsClamped() {
        #expect(ColorVision(.protanomaly, severity: 4).severity == 1)
        #expect(ColorVision(.protanomaly, severity: -2).severity == 0)
        let past = ColorVision(.protanomaly, severity: 9).matrix
        let one = ColorVision.protanopia.matrix
        for i in 0..<9 { #expect(past[i] == one[i]) }
    }

    // MARK: - The color space it belongs in

    /// The matrix weights the power of the display primaries, so it belongs in
    /// linear light. This pins the shipped answer against a hand-computed
    /// linear-light reference, and against the same matrix applied to display
    /// values, which is the common mistake and a visibly different color.
    @Test func theMatrixIsAppliedInLinearLightNotToDisplayValues() {
        let source = Color(hex: 0xC81E1E)
        let vision = ColorVision.deuteranopia
        let m = vision.matrix

        let lr = toLinear(source.red), lg = toLinear(source.green), lb = toLinear(source.blue)
        let reference = Color(
            red: toDisplay(min(max(m[0] * lr + m[1] * lg + m[2] * lb, 0), 1)),
            green: toDisplay(min(max(m[3] * lr + m[4] * lg + m[5] * lb, 0), 1)),
            blue: toDisplay(min(max(m[6] * lr + m[7] * lg + m[8] * lb, 0), 1)))

        let shipped = source.simulated(vision)
        #expect(distance(shipped, reference) < 1e-9)

        let wrong = Color(
            red: min(max(m[0] * source.red + m[1] * source.green + m[2] * source.blue, 0), 1),
            green: min(max(m[3] * source.red + m[4] * source.green + m[5] * source.blue, 0), 1),
            blue: min(max(m[6] * source.red + m[7] * source.green + m[8] * source.blue, 0), 1))
        #expect(distance(shipped, wrong) > 0.05)
    }

    // MARK: - What it is for

    /// Red against green is the pair the commonest kinds cannot hold apart, and
    /// the tritan twin is what shows the collapse belongs to the kind rather
    /// than to the simulation flattening everything.
    @Test func redAndGreenCollapseForTheRedGreenKindsAndNotForTheOther() {
        let apart = chroma(.red, .green)

        let protan = chroma(Color.red.simulated(.protanopia),
                            Color.green.simulated(.protanopia))
        let deutan = chroma(Color.red.simulated(.deuteranopia),
                            Color.green.simulated(.deuteranopia))
        let tritan = chroma(Color.red.simulated(.tritanopia),
                            Color.green.simulated(.tritanopia))

        #expect(protan < apart * 0.30)
        #expect(deutan < apart * 0.15)
        #expect(tritan > apart * 0.70)

        // Lightness is what a dichromat has left here, and it survives: the two
        // stay most of their full distance apart once lightness counts again.
        #expect(distance(Color.red.simulated(.protanopia),
                         Color.green.simulated(.protanopia)) > distance(.red, .green) * 0.5)
    }

    /// Blue against yellow is the pair the rare kind loses, and the red-green
    /// kinds keep. The mirror of the test above.
    @Test func blueAndYellowCollapseForTheRareKindAndNotForTheOthers() {
        let apart = chroma(.blue, .yellow)
        let tritan = chroma(Color.blue.simulated(.tritanopia),
                            Color.yellow.simulated(.tritanopia))
        let protan = chroma(Color.blue.simulated(.protanopia),
                            Color.yellow.simulated(.protanopia))
        let deutan = chroma(Color.blue.simulated(.deuteranopia),
                            Color.yellow.simulated(.deuteranopia))
        #expect(tritan < apart * 0.40)
        #expect(protan > apart * 0.70)
        #expect(deutan > apart * 0.70)
    }

    /// A stronger severity moves a color further, all the way along the range.
    @Test func aStrongerSeverityMovesAColorFurther() {
        let source = Color(hex: 0x2E9B57)
        var previous = 0.0
        for step in stride(from: 0.2, through: 1.0, by: 0.2) {
            let moved = distance(source, source.simulated(.deuteranomaly(step)))
            #expect(moved > previous)
            previous = moved
        }
    }

    /// Gray has nothing for a cone shift to disagree about, so it comes back
    /// where it started whatever the kind.
    @Test func grayIsUnchangedByEveryKind() {
        for kind in ColorVision.Kind.allCases {
            for level in [0.0, 0.25, 0.5, 0.75, 1.0] {
                let gray = Color(red: level, green: level, blue: level)
                #expect(distance(gray, gray.simulated(ColorVision(kind))) < 0.02)
            }
        }
    }

    /// Transparency is not a color decision, so it rides through untouched.
    @Test func alphaIsCarriedThrough() {
        let source = Color(red: 0.9, green: 0.2, blue: 0.1, alpha: 0.42)
        #expect(source.simulated(.protanopia).alpha == 0.42)
    }

    /// The transform can land outside the display range, and a channel that
    /// does is clamped rather than wrapped.
    @Test func aResultOutsideTheDisplayRangeIsClamped() {
        for kind in ColorVision.Kind.allCases {
            for source in [Color.red, .green, .blue, .cyan, .magenta, .yellow, .white] {
                let seen = source.simulated(ColorVision(kind))
                #expect(seen.red >= 0 && seen.red <= 1)
                #expect(seen.green >= 0 && seen.green <= 1)
                #expect(seen.blue >= 0 && seen.blue <= 1)
            }
        }
    }

    // MARK: - The collections

    /// A palette and a ramp simulate entry by entry, and a ramp keeps the space
    /// it interpolates in.
    @Test func paletteAndRampSimulateEveryEntry() {
        let palette = Palette([.red, .green, .blue])
        let seen = palette.simulated(.protanopia)
        #expect(seen.count == 3)
        for (a, b) in zip(palette.colors, seen.colors) {
            #expect(b == a.simulated(.protanopia))
        }

        let ramp = Ramp([.red, .yellow, .green], in: .oklab)
        let seenRamp = ramp.simulated(.deuteranopia)
        #expect(seenRamp.stops.count == ramp.stops.count)
        #expect(seenRamp.space == ramp.space)
        for (a, b) in zip(ramp.stops, seenRamp.stops) {
            #expect(b.position == a.position)
            #expect(b.color == a.color.simulated(.deuteranopia))
        }
    }
}

/// A palette is judged by whether its colors stay apart, and that judgment is
/// the whole of both axes: two colors close in hue survive a difference in
/// lightness. These pin the measured tolerance against the two sets it was
/// calibrated on, and pin the report's order and determinism.
@Suite
struct ColorblindPaletteTests {

    /// The published safe set passes at the shipped tolerance, under every kind.
    @Test func thePublishedSafeSetIsSafe() {
        #expect(Palette.colorblindSafe.count == 8)
        #expect(Palette.colorblindSafe.isColorblindSafe())
        for kind in ColorVision.Kind.allCases {
            #expect(Palette.colorblindSafe.confusions(under: ColorVision(kind)).isEmpty)
        }
    }

    /// A familiar six-color chart set is not safe, and the check says which pair
    /// goes and under which kind. Orange against green is the classic one.
    @Test func aFamiliarChartSetIsNotSafeAndSaysWhichPair() {
        let chart = Palette([Color(hex: 0x1F77B4), Color(hex: 0xFF7F0E), Color(hex: 0x2CA02C),
                             Color(hex: 0xD62728), Color(hex: 0x9467BD), Color(hex: 0x8C564B)])
        #expect(!chart.isColorblindSafe())

        let worst = chart.confusions().first
        #expect(worst?.first == 1)                       // orange
        #expect(worst?.second == 2)                      // green
        #expect(worst?.vision.kind == .protanomaly)
        #expect((worst?.distance ?? 1) < 0.02)
    }

    /// The report is ordered worst pair first, so the first entry is the one to
    /// fix, and it is the same order every run.
    @Test func confusionsComeBackWorstFirstAndInAStableOrder() {
        let messy = Palette([.red, .green, Color(hex: 0x00FF01), .blue, Color(hex: 0x0100FF)])
        let found = messy.confusions()
        #expect(found.count > 1)
        for (a, b) in zip(found, found.dropFirst()) {
            #expect(a.distance <= b.distance)
        }
        #expect(found == messy.confusions())
    }

    /// A pair that differs only in hue merges, while the same two hues separated
    /// in lightness survive. This is the advice the docs give, stated as a test.
    ///
    /// The two colors below were measured rather than picked by eye. At matched
    /// lightness the red and the green sit 0.281 apart for average vision and
    /// 0.014 apart under the worst kind. Pull them apart in lightness and the
    /// same two hues stay 0.601 apart under every kind.
    @Test func lightnessIsWhatSavesAPairThatSharesAHueAxis() {
        let flat = Palette([Color(hex: 0xD75734), Color(hex: 0x30A030)])
        let stepped = Palette([Color(hex: 0x400F0D), Color(hex: 0x9EE69E)])
        #expect(!flat.isColorblindSafe())
        #expect(stepped.isColorblindSafe())
    }

    /// A palette of one color has no pairs, and an empty one is not a crash.
    @Test func aPaletteTooSmallToHaveAPairIsQuiet() {
        #expect(Palette([]).confusions().isEmpty)
        #expect(Palette([.red]).confusions().isEmpty)
        #expect(Palette([.red]).isColorblindSafe())
    }
}

/// The filter and the `Color` call have to be one model rather than two, so this
/// renders a patch through the GPU filter and compares it with the CPU answer.
/// Metal-gated.
@Suite
@MainActor
struct ColorVisionRenderProbes {

    private func center(of image: CGImage) -> Color {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        if let ctx = CGContext(data: &data, width: image.width, height: image.height,
                               bitsPerComponent: 8, bytesPerRow: image.width * 4,
                               space: space, bitmapInfo: info) {
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let i = ((image.height / 2) * image.width + image.width / 2) * 4
        return Color(red: Double(data[i]) / 255, green: Double(data[i + 1]) / 255,
                     blue: Double(data[i + 2]) / 255)
    }

    private func apart(_ a: Color, _ b: Color) -> Double {
        let x = OKLab(a), y = OKLab(b)
        return ((x.l - y.l) * (x.l - y.l) + (x.a - y.a) * (x.a - y.a)
                + (x.b - y.b) * (x.b - y.b)).squareRoot()
    }

    /// The filter lands where `Color.simulated(_:)` says it should, for every
    /// kind. One model, reached two ways.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theFilterAgreesWithTheColorCall() throws {
        let patch = Color(hex: 0xC8321E)
        for kind in ColorVision.Kind.allCases {
            let vision = ColorVision(kind)
            let image = try #require(OllinApp.image(of: ColorVisionProbe.make(patch: patch, vision: vision),
                                                    frame: 1))
            #expect(apart(center(of: image), patch.simulated(vision)) < 0.01)
        }
    }

    /// The control: with no filter the patch renders as itself, so the check
    /// above is measuring the filter rather than the pipeline.
    @Test(.enabled(if: Snapshot.hasMetal))
    func withoutTheFilterThePatchIsItself() throws {
        let patch = Color(hex: 0xC8321E)
        let image = try #require(OllinApp.image(of: ColorVisionProbe.make(patch: patch, vision: nil),
                                                frame: 1))
        #expect(apart(center(of: image), patch) < 0.01)
    }

    /// Severity 0 through the filter changes nothing either.
    @Test(.enabled(if: Snapshot.hasMetal))
    func severityZeroThroughTheFilterChangesNothing() throws {
        let patch = Color(hex: 0x2E9B57)
        let image = try #require(OllinApp.image(of: ColorVisionProbe.make(patch: patch, vision: .normal),
                                                frame: 1))
        #expect(apart(center(of: image), patch) < 0.01)
    }

    /// A headless render reports no reduced-motion preference whatever this
    /// machine is set to, so an export is the same file anywhere.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aHeadlessRenderNeverPrefersReducedMotion() throws {
        let sketch = ReducedMotionProbe()
        _ = try #require(OllinApp.image(of: sketch, frame: 1))
        #expect(sketch.seen == false)
    }
}

private final class ColorVisionProbe: Sketch {
    var patch: Color = .white
    var vision: ColorVision?

    static func make(patch: Color, vision: ColorVision?) -> ColorVisionProbe {
        let probe = ColorVisionProbe()
        probe.patch = patch
        probe.vision = vision
        return probe
    }

    override var canvasSize: CanvasSize { .square(64) }

    override func draw() {
        noLoop()
        background(patch)
        if let vision { postProcess(.colorVision(vision)) }
    }
}

private final class ReducedMotionProbe: Sketch {
    var seen: Bool?

    override var canvasSize: CanvasSize { .square(32) }

    override func draw() {
        noLoop()
        seen = prefersReducedMotion
        background(.white)
    }
}
