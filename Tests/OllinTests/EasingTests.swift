import Ollin
import Testing

/// Pure-math checks on the easing curves — no GPU, so these run everywhere
/// (including CI). They pin every curve's endpoints, spot-check known values,
/// confirm the overshoot curves do overshoot, and confirm the input clamp.
@Suite
struct EasingTests {

    /// Every named curve, for the endpoint sweep.
    static let all: [(String, Easing)] = [
        ("linear", .linear),
        ("easeInSine", .easeInSine), ("easeOutSine", .easeOutSine), ("easeInOutSine", .easeInOutSine),
        ("easeInQuad", .easeInQuad), ("easeOutQuad", .easeOutQuad), ("easeInOutQuad", .easeInOutQuad),
        ("easeInCubic", .easeInCubic), ("easeOutCubic", .easeOutCubic), ("easeInOutCubic", .easeInOutCubic),
        ("easeInQuart", .easeInQuart), ("easeOutQuart", .easeOutQuart), ("easeInOutQuart", .easeInOutQuart),
        ("easeInQuint", .easeInQuint), ("easeOutQuint", .easeOutQuint), ("easeInOutQuint", .easeInOutQuint),
        ("easeInExpo", .easeInExpo), ("easeOutExpo", .easeOutExpo), ("easeInOutExpo", .easeInOutExpo),
        ("easeInCirc", .easeInCirc), ("easeOutCirc", .easeOutCirc), ("easeInOutCirc", .easeInOutCirc),
        ("easeInBack", .easeInBack), ("easeOutBack", .easeOutBack), ("easeInOutBack", .easeInOutBack),
        ("easeInElastic", .easeInElastic), ("easeOutElastic", .easeOutElastic), ("easeInOutElastic", .easeInOutElastic),
        ("easeInBounce", .easeInBounce), ("easeOutBounce", .easeOutBounce), ("easeInOutBounce", .easeInOutBounce),
        ("smoothstep", .smoothstep),
    ]

    @Test(arguments: EasingTests.all)
    func everyCurvePinsItsEndpoints(_ name: String, _ curve: Easing) {
        #expect(abs(curve(0) - 0) < 1e-9, "\(name)(0) = \(curve(0))")
        #expect(abs(curve(1) - 1) < 1e-9, "\(name)(1) = \(curve(1))")
    }

    /// A curve, the input to evaluate, and the value it should produce there.
    static let midpoints: [(name: String, curve: Easing, input: Double, expected: Double)] = [
        ("linear", .linear, 0.5, 0.5),
        ("easeInQuad", .easeInQuad, 0.5, 0.25),
        ("easeOutQuad", .easeOutQuad, 0.5, 0.75),
        ("easeInOutQuad", .easeInOutQuad, 0.5, 0.5),
        ("easeInCubic", .easeInCubic, 0.5, 0.125),
        ("smoothstep", .smoothstep, 0.5, 0.5),
    ]

    @Test(arguments: EasingTests.midpoints)
    func knownMidpoints(_ midpoint: (name: String, curve: Easing, input: Double, expected: Double)) {
        let got = midpoint.curve(midpoint.input)
        #expect(abs(got - midpoint.expected) < 1e-12,
                "\(midpoint.name)(\(midpoint.input)) = \(got), expected \(midpoint.expected)")
    }

    @Test func overshootCurvesLeaveTheUnitRange() {
        #expect(Easing.easeInBack(0.5) < 0, "back dips below 0 easing in")
        #expect(Easing.easeOutBack(0.5) > 1, "back overshoots above 1 easing out")
        let elasticPasses1 = stride(from: 0.0, through: 1.0, by: 0.01).contains { Easing.easeOutElastic($0) > 1 }
        #expect(elasticPasses1, "elastic springs past 1")
    }

    @Test func inputIsClampedToUnitRange() {
        #expect(Easing.linear(-0.5) == 0)
        #expect(Easing.linear(1.5) == 1)
        #expect(Easing.easeInQuad(2) == 1)   // clamped to 1, then squared
    }

    @Test(arguments: Array(stride(from: 0.0, through: 1.0, by: 0.1)))
    func friendlyAliasesMatchCubic(_ t: Double) {
        #expect(Easing.easeIn(t) == Easing.easeInCubic(t))
        #expect(Easing.easeOut(t) == Easing.easeOutCubic(t))
        #expect(Easing.easeInOut(t) == Easing.easeInOutCubic(t))
    }
}
