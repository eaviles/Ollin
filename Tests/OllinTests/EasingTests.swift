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
        ("smoothStep", .smoothStep),
    ]

    @Test func everyCurvePinsItsEndpoints() {
        for (name, curve) in Self.all {
            #expect(abs(curve(0) - 0) < 1e-9, "\(name)(0) = \(curve(0))")
            #expect(abs(curve(1) - 1) < 1e-9, "\(name)(1) = \(curve(1))")
        }
    }

    @Test func knownMidpoints() {
        #expect(abs(Easing.linear(0.5) - 0.5) < 1e-12)
        #expect(abs(Easing.easeInQuad(0.5) - 0.25) < 1e-12)
        #expect(abs(Easing.easeOutQuad(0.5) - 0.75) < 1e-12)
        #expect(abs(Easing.easeInOutQuad(0.5) - 0.5) < 1e-12)
        #expect(abs(Easing.easeInCubic(0.5) - 0.125) < 1e-12)
        #expect(abs(Easing.smoothStep(0.5) - 0.5) < 1e-12)
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

    @Test func friendlyAliasesMatchCubic() {
        for t in stride(from: 0.0, through: 1.0, by: 0.1) {
            #expect(Easing.easeIn(t) == Easing.easeInCubic(t))
            #expect(Easing.easeOut(t) == Easing.easeOutCubic(t))
            #expect(Easing.easeInOut(t) == Easing.easeInOutCubic(t))
        }
    }
}
