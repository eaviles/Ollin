import Ollin
import Testing

/// The two derive helpers, `reversed()` and `mirrored()`, as laws over the whole
/// catalog and over closure-built curves. Pure math, no GPU.
@Suite
struct EasingDerivedTests {

    static let samples = Array(stride(from: 0.0, through: 1.0, by: 0.01))

    /// The ten families, each as its ease-in, ease-out, and ease-in-out.
    static let families: [(name: String, easeIn: Easing, easeOut: Easing, inOut: Easing)] = [
        ("Sine", .easeInSine, .easeOutSine, .easeInOutSine),
        ("Quad", .easeInQuad, .easeOutQuad, .easeInOutQuad),
        ("Cubic", .easeInCubic, .easeOutCubic, .easeInOutCubic),
        ("Quart", .easeInQuart, .easeOutQuart, .easeInOutQuart),
        ("Quint", .easeInQuint, .easeOutQuint, .easeInOutQuint),
        ("Expo", .easeInExpo, .easeOutExpo, .easeInOutExpo),
        ("Circ", .easeInCirc, .easeOutCirc, .easeInOutCirc),
        ("Back", .easeInBack, .easeOutBack, .easeInOutBack),
        ("Elastic", .easeInElastic, .easeOutElastic, .easeInOutElastic),
        ("Bounce", .easeInBounce, .easeOutBounce, .easeInOutBounce),
    ]

    /// The families whose catalog ease-in-out is the mirrored ease-in exactly.
    static let mirroredFamilies: Set<String> = ["Sine", "Quad", "Cubic", "Quart", "Quint", "Expo", "Circ", "Bounce"]

    // MARK: reversed()

    /// The law itself, over every catalog curve: reversing is reflection through
    /// the center, whatever the helper hands back.
    @Test(arguments: EasingTests.all)
    func reversedIsTheCurveReflectedThroughTheCenter(_ name: String, _ curve: Easing) {
        let reversed = curve.reversed()
        for t in Self.samples {
            #expect(abs(reversed(t) - (1 - curve(1 - t))) < 1e-12, "\(name).reversed()(\(t))")
        }
    }

    /// The catalog's ease-outs are the reflected ease-ins, so a reversal lands
    /// on the built-in across the family, by identity and not only by value.
    @Test(arguments: EasingDerivedTests.families)
    func reversingABuiltInLandsOnItsPartner(_ family: (name: String, easeIn: Easing, easeOut: Easing, inOut: Easing)) {
        #expect(family.easeIn.reversed() == family.easeOut, "\(family.name): in reversed is out")
        #expect(family.easeOut.reversed() == family.easeIn, "\(family.name): out reversed is in")
        #expect(family.inOut.reversed() == family.inOut, "\(family.name): in-out is symmetric")
        for t in Self.samples {
            #expect(abs(family.inOut(t) - (1 - family.inOut(1 - t))) < 1e-12, "\(family.name) in-out symmetric at \(t)")
        }
    }

    @Test func theSymmetricSinglesReverseToThemselves() {
        #expect(Easing.linear.reversed() == .linear)
        #expect(Easing.smoothstep.reversed() == .smoothstep)
        #expect(Easing.easeInOut.reversed() == .easeInOutCubic)
    }

    // MARK: mirrored()

    /// The construction, over every catalog curve: the curve squeezed into the
    /// first half, its reverse into the second.
    @Test(arguments: EasingTests.all)
    func mirroredIsTheCurveThenItsReverseInOneSpan(_ name: String, _ curve: Easing) {
        let mirrored = curve.mirrored()
        for t in Self.samples {
            let expected = t < 0.5 ? curve(2 * t) / 2 : 1 - curve(2 - 2 * t) / 2
            #expect(abs(mirrored(t) - expected) < 1e-12, "\(name).mirrored()(\(t))")
        }
    }

    /// Eight families build their ease-in-out exactly this way, so mirroring
    /// their ease-in is the catalog curve. Back and elastic were tuned apart, so
    /// there the helper builds a curve of its own that visibly differs.
    @Test(arguments: EasingDerivedTests.families)
    func mirroringAnEaseInMeetsTheCatalogWhereTheCatalogAgrees(_ family: (name: String, easeIn: Easing, easeOut: Easing, inOut: Easing)) {
        let mirrored = family.easeIn.mirrored()
        let largestGap = Self.samples.map { abs(mirrored($0) - family.inOut($0)) }.max()!
        if Self.mirroredFamilies.contains(family.name) {
            #expect(mirrored == family.inOut, "\(family.name): mirrored ease-in is the catalog ease-in-out")
            #expect(largestGap < 1e-12, "\(family.name): identical to the last digit, gap \(largestGap)")
        } else {
            #expect(mirrored != family.inOut, "\(family.name): the catalog tuned its own")
            #expect(largestGap > 1e-3, "\(family.name): visibly its own curve, gap \(largestGap)")
        }
    }

    /// An ease-out mirrored is an out-in curve: fast at both ends, slow through
    /// the middle, and level exactly at the center.
    @Test func mirroringAnEaseOutGivesAnOutInCurve() {
        let outIn = Easing.easeOutQuad.mirrored()
        #expect(outIn != .easeInOutQuad)
        #expect(abs(outIn(0.5) - 0.5) < 1e-12)
        #expect(outIn(0.25) > 0.25 + 0.05, "leaps off the start")
        #expect(outIn(0.75) < 0.75 - 0.05, "lags before the end")
        let slopeAtCenter = (outIn(0.5 + 1e-4) - outIn(0.5 - 1e-4)) / 2e-4
        #expect(slopeAtCenter < 0.05, "level through the middle, slope \(slopeAtCenter)")
    }

    // MARK: Every derived curve is still an easing

    @Test(arguments: EasingTests.all)
    func derivedCurvesPinTheirEndpointsAndClampTheirInput(_ name: String, _ curve: Easing) {
        for derived in [curve.reversed(), curve.mirrored(), curve.reversed().mirrored(), curve.mirrored().reversed()] {
            #expect(abs(derived(0)) < 1e-9, "\(name) derived (0)")
            #expect(abs(derived(1) - 1) < 1e-9, "\(name) derived (1)")
            #expect(derived(-1) == derived(0), "\(name) derived clamps below")
            #expect(derived(2) == derived(1), "\(name) derived clamps above")
        }
    }

    @Test(arguments: EasingTests.all)
    func reversingTwiceIsTheCurveAgain(_ name: String, _ curve: Easing) {
        let twice = curve.reversed().reversed()
        #expect(twice == curve, "\(name): a built-in comes back as itself")
        for t in Self.samples {
            #expect(abs(twice(t) - curve(t)) < 1e-12, "\(name) at \(t)")
        }
    }

    // MARK: Identity

    /// A closure curve's derivations are values: the same derivation twice is
    /// equal, a different one is not, and none of them is the origin.
    @Test func derivationsOfAClosureCurveCompareByTheirOrigin() {
        let steep = Easing { t in t * t * t * t }
        let other = Easing { t in t * t * t * t }
        #expect(steep.reversed() == steep.reversed())
        #expect(steep.mirrored() == steep.mirrored())
        #expect(steep.reversed() != steep.mirrored())
        #expect(steep.reversed() != steep)
        #expect(steep.reversed() != other.reversed(), "two closures are two curves, so are their reversals")
        #expect(steep.reversed().reversed() != steep, "a closure curve has no catalog partner to land on")
        for t in Self.samples {
            #expect(abs(steep.reversed().reversed()(t) - steep(t)) < 1e-12)
        }
    }

    /// The derive helpers land on the menu when the catalog holds the result and
    /// stay off it otherwise, exactly like a closure curve.
    @Test func aDerivedCurvePersistsUnderTheCatalogNameItLandsOn() {
        #expect(Easing.stored(Easing.easeInQuad.reversed()) == .option("easeOutQuad"))
        #expect(Easing.stored(Easing.easeInCubic.mirrored()) == .option("easeInOutCubic"))
        #expect(Easing.stored(Easing.easeOutQuad.mirrored()) == .option("linear"), "off the menu reads as the first entry")
        #expect(Easing.stored(Easing.easeInBack.mirrored()) == .option("linear"))
    }
}
