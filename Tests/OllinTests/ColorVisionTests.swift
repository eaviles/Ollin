import Foundation
import Ollin
import Testing

/// The color-vision simulation is a published projection plus two decisions
/// that are easy to get wrong and invisible once wrong: which color space it
/// belongs in, and what a severity short of dichromacy means. These pin both,
/// and pin the behavior the whole feature exists for, which is that colors a
/// designer picked apart can arrive on top of each other.
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

    // MARK: - Severity

    private func seen(_ vision: ColorVision, _ c: (Double, Double, Double)) -> (Double, Double, Double) {
        vision.applied(toLinear: c.0, c.1, c.2)
    }

    private func gap(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
        max(abs(a.0 - b.0), abs(a.1 - b.1), abs(a.2 - b.2))
    }

    private static let linearSamples: [(Double, Double, Double)] = [
        (1, 0, 0), (0, 1, 0), (0, 0, 1), (0.8, 0.6, 0.1), (0.05, 0.4, 0.9), (0.3, 0.3, 0.3),
    ]

    /// Severity 0 is the identity for every kind, so `.normal` cannot tint
    /// anything by accident.
    @Test func severityZeroIsTheIdentity() {
        for kind in ColorVision.Kind.allCases {
            for c in Self.linearSamples {
                #expect(gap(seen(ColorVision(kind, severity: 0), c), c) < 1e-12)
            }
        }
        for color in [Color.red, .green, .blue, .white, .black, Color(hex: 0x3A7BD5)] {
            #expect(color.simulated(.normal) == color)
            #expect(color.simulated(ColorVision(.protanomaly, severity: 0)) == color)
        }
    }

    /// A severity short of dichromacy moves a color part of the way, along the
    /// straight line in linear light from where it starts to where severity 1
    /// puts it.
    @Test func aPartialSeverityIsThatShareOfTheWayInLinearLight() {
        for kind in ColorVision.Kind.allCases {
            for c in Self.linearSamples {
                let end = seen(ColorVision(kind), c)
                for severity in [0.15, 0.5, 0.85] {
                    let part = seen(ColorVision(kind, severity: severity), c)
                    let line = (c.0 + (end.0 - c.0) * severity, c.1 + (end.1 - c.1) * severity,
                                c.2 + (end.2 - c.2) * severity)
                    #expect(gap(part, line) < 1e-12, "\(kind) at \(severity) left the line for \(c)")
                }
            }
        }
    }

    /// Severity is clamped rather than extrapolated, so a parameter dragged past
    /// either end keeps meaning something.
    @Test func severityIsClamped() {
        #expect(ColorVision(.protanomaly, severity: 4).severity == 1)
        #expect(ColorVision(.protanomaly, severity: -2).severity == 0)
        for c in Self.linearSamples {
            #expect(gap(seen(ColorVision(.protanomaly, severity: 9), c), seen(.protanopia, c)) == 0)
        }
    }

    // MARK: - The color space it belongs in

    /// The projection weights the power of the display primaries, so it belongs
    /// in linear light. This pins the shipped answer against the model applied
    /// to the linearized color by hand, and against the same model applied to
    /// display values, which is the common mistake and a visibly different color.
    @Test func theModelIsAppliedInLinearLightNotToDisplayValues() {
        let source = Color(hex: 0xC81E1E)
        let vision = ColorVision.deuteranopia

        let (r, g, b) = vision.applied(toLinear: toLinear(source.red), toLinear(source.green),
                                       toLinear(source.blue))
        #expect(min(r, g, b) >= 0 && max(r, g, b) <= 1, "the reference needs a result in range")
        let reference = Color(red: toDisplay(r), green: toDisplay(g), blue: toDisplay(b))

        let shipped = source.simulated(vision)
        #expect(distance(shipped, reference) < 1e-9)

        let (wr, wg, wb) = vision.applied(toLinear: source.red, source.green, source.blue)
        let wrong = Color(red: min(max(wr, 0), 1), green: min(max(wg, 0), 1), blue: min(max(wb, 0), 1))
        #expect(distance(shipped, wrong) > 0.05)
    }

    // MARK: - What it is for

    /// Red against green is the pair the commonest kinds cannot hold apart, and
    /// the tritan twin is what shows the collapse belongs to the kind rather
    /// than to the simulation flattening everything. Measured on the hue plane:
    /// 23% of the gap survives protanopia, 7.6% deuteranopia, 78% tritanopia.
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
    /// kinds keep. The mirror of the test above: 22% of the gap survives
    /// tritanopia, 95% protanopia, 87% deuteranopia.
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

    /// Gray has nothing for a missing cone to disagree about: the gray axis lies
    /// on every dichromat's surface, so a gray comes back exactly where it
    /// started whatever the kind.
    @Test func grayIsUnchangedByEveryKind() {
        for kind in ColorVision.Kind.allCases {
            for level in [0.0, 0.25, 0.5, 0.75, 1.0] {
                let gray = Color(red: level, green: level, blue: level)
                #expect(distance(gray, gray.simulated(ColorVision(kind))) < 1e-9)
            }
        }
    }

    /// Transparency is not a color decision, so it rides through untouched.
    @Test func alphaIsCarriedThrough() {
        let source = Color(red: 0.9, green: 0.2, blue: 0.1, alpha: 0.42)
        #expect(source.simulated(.protanopia).alpha == 0.42)
    }

    /// A dichromat's surface reaches outside the display range, and a result
    /// that does is clamped channel by channel. The clamp moves it mostly along
    /// the missing cone's response, which the simulated viewer cannot see: the
    /// two cones they have respond to the clamped color within 0.07 of how they
    /// respond to the model's own result (white responds 1), where pulling it
    /// toward a gray of its own lightness instead moved them by up to 0.78.
    @Test func aResultOutsideTheDisplayRangeIsClampedWherePeopleWithThatKindCannotSee() {
        // The cone responses of linear sRGB (Smith and Pokorny over the
        // corrected primaries), written out so the check stands apart.
        let cones: [[Double]] = [[17.88240413, 43.51609057, 4.11934969],
                                 [3.45564232, 27.15538246, 3.86713084],
                                 [0.02995656, 0.18430896, 1.46708614]]
        func response(_ c: (Double, Double, Double)) -> [Double] {
            cones.map { $0[0] * c.0 + $0[1] * c.1 + $0[2] * c.2 }
        }
        let white = response((1, 1, 1))
        var clamped = 0
        for (kind, missing) in [(ColorVision.Kind.protanomaly, 0), (.deuteranomaly, 1), (.tritanomaly, 2)] {
            let vision = ColorVision(kind)
            for source in [Color.red, .green, .blue, .cyan, .magenta, .yellow, .white] {
                let shown = source.simulated(vision)
                #expect(shown.red >= 0 && shown.red <= 1)
                #expect(shown.green >= 0 && shown.green <= 1)
                #expect(shown.blue >= 0 && shown.blue <= 1)

                let raw = vision.applied(toLinear: toLinear(source.red), toLinear(source.green),
                                         toLinear(source.blue))
                guard min(raw.0, raw.1, raw.2) < 0 || max(raw.0, raw.1, raw.2) > 1 else { continue }
                clamped += 1
                let a = response(raw)
                let b = response((toLinear(shown.red), toLinear(shown.green), toLinear(shown.blue)))
                var seen = 0.0
                for k in 0..<3 where k != missing {
                    seen += ((a[k] - b[k]) / white[k]) * ((a[k] - b[k]) / white[k])
                }
                #expect(seen.squareRoot() < 0.07, "\(kind) moved what it sees in \(source) by \(seen.squareRoot())")
            }
        }
        #expect(clamped > 0, "no color here left the range, so the clamp went unchecked")
        let green = ColorVision.tritanopia.applied(toLinear: 0, 1, 0)
        #expect(green.2 > 1.1)
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

    /// The published safe set passes at the shipped tolerance, under every kind,
    /// and its closest pair sits where the docs say (0.078, under deuteranopia),
    /// which is one side of the calibration.
    @Test func thePublishedSafeSetIsSafe() {
        #expect(Palette.colorblindSafe.count == 8)
        #expect(Palette.colorblindSafe.isColorblindSafe())
        let closest = Palette.colorblindSafe.confusions(tolerance: 1).first
        #expect(abs((closest?.distance ?? 0) - 0.078) < 0.0005, "closest pair at \(String(describing: closest))")
        #expect(closest?.vision.kind == .deuteranomaly)
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
        #expect(abs((worst?.distance ?? 1) - 0.013) < 0.0005, "worst pair at \(String(describing: worst))")
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
    /// 0.013 apart under the worst kind. Pull them apart in lightness and the
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
    /// kind, at full and partial severity. One model, reached two ways. Pure
    /// green and blue leave the display range under every kind (blue's red falls
    /// to -0.31 under protanopia, green's blue reaches 1.13 under tritanopia), so
    /// they pin the clamp on both paths, and between the three patches every kind
    /// uses both halves of its surface.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theFilterAgreesWithTheColorCall() throws {
        for patch in [Color(hex: 0xC8321E), Color(hex: 0x00FF00), Color(hex: 0x0000FF)] {
            for kind in ColorVision.Kind.allCases {
                for severity in [1.0, 0.5] {
                    let vision = ColorVision(kind, severity: severity)
                    let image = try OllinApp.image(of: ColorVisionProbe.make(patch: patch, vision: vision),
                                                   frame: 1)
                    let gap = apart(center(of: image), patch.simulated(vision))
                    #expect(gap < 0.01, "\(patch) under \(kind) at \(severity) is \(gap) from the Color call")
                }
            }
        }
    }

    /// A layer brighter than white keeps its range through the filter: only the
    /// low end is clamped, so the tone map still sees the light the sketch drew.
    /// Read in linear light before the present pass, against the model applied
    /// to the same linear color with its low end clamped.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aPixelBrighterThanWhiteKeepsItsRange() throws {
        func linear(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let patch = Color(red: 1.4, green: 1.2, blue: 0.3)
        let frame = try LayerStyleTests.render(ColorVisionProbe.make(patch: patch, vision: .tritanopia))
        let x = frame.width / 2, y = frame.height / 2
        let drawn = (frame.value(x, y, 0), frame.value(x, y, 1), frame.value(x, y, 2))
        let raw = ColorVision.tritanopia.applied(toLinear: linear(patch.red), linear(patch.green),
                                                 linear(patch.blue))
        let want = (max(raw.0, 0), max(raw.1, 0), max(raw.2, 0))
        #expect(max(want.0, want.1, want.2) > 1.2, "the patch should simulate past white")
        for (got, wanted) in [(drawn.0, want.0), (drawn.1, want.1), (drawn.2, want.2)] {
            #expect(abs(got - wanted) <= wanted * 0.003 + 0.002, "filter \(drawn), model \(want)")
        }
    }

    /// The control: with no filter the patch renders as itself, so the check
    /// above is measuring the filter rather than the pipeline.
    @Test(.enabled(if: Snapshot.hasMetal))
    func withoutTheFilterThePatchIsItself() throws {
        let patch = Color(hex: 0xC8321E)
        let image = try OllinApp.image(of: ColorVisionProbe.make(patch: patch, vision: nil),
                                                frame: 1)
        #expect(apart(center(of: image), patch) < 0.01)
    }

    /// Severity 0 through the filter changes nothing either.
    @Test(.enabled(if: Snapshot.hasMetal))
    func severityZeroThroughTheFilterChangesNothing() throws {
        let patch = Color(hex: 0x2E9B57)
        let image = try OllinApp.image(of: ColorVisionProbe.make(patch: patch, vision: .normal),
                                                frame: 1)
        #expect(apart(center(of: image), patch) < 0.01)
    }

    /// A headless render reports no reduced-motion preference whatever this
    /// machine is set to, so an export is the same file anywhere.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aHeadlessRenderNeverPrefersReducedMotion() throws {
        let sketch = ReducedMotionProbe()
        _ = try OllinApp.image(of: sketch, frame: 1)
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
