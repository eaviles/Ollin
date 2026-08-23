@testable import Ollin
import Foundation
import Testing

/// A formula is a small language, so the claims worth pinning are the ones a
/// grammar can get wrong without failing to parse: what binds tighter than
/// what, which way a remainder falls for a negative number, and whether a
/// misspelling is refused or quietly read as zero. Each of those changes a
/// picture rather than breaking a build, which is why they are laws here.
@Suite
struct FormulaTests {

    private func value(_ source: String, _ values: [String: Double] = [:]) throws -> Double {
        try Formula(source).value(values)
    }

    // MARK: Arithmetic

    @Test func arithmeticFollowsTheOrdinaryPrecedence() throws {
        #expect(try value("2 + 3 * 4") == 14)
        #expect(try value("(2 + 3) * 4") == 20)
        #expect(try value("10 - 3 - 2") == 5)          // left to right
        #expect(try value("100 / 5 / 2") == 10)        // left to right
        #expect(try value("2 * 3 ^ 2") == 18)          // a power binds tighter than a product
    }

    /// The one place this language and the one a parametric L-system's
    /// productions are written in disagree on purpose. Here a power binds
    /// tighter than a minus sign, the way a calculator reads it, so `-2^2` is
    /// `-4`. In the L-system language the minus binds tighter and the same text
    /// is `4`. Neither is a parse error, so only a test can tell them apart.
    @Test func aPowerBindsTighterThanAMinusSign() throws {
        #expect(try value("-2 ^ 2") == -4)
        #expect(try value("(-2) ^ 2") == 4)

        var rng = SystemRandomNumberGenerator()
        let theOtherLanguage = try LSystemExpressionParser.parse(Substring("-2^2"), parameters: [],
                                                                constants: [:])
        #expect(theOtherLanguage.value([], using: &rng) == 4)
    }

    /// A power associates to the right, so a stack of them climbs rather than
    /// multiplies out: `2^3^2` is `2^9`, not `(2^3)^2`.
    @Test func aPowerAssociatesToTheRight() throws {
        #expect(try value("2 ^ 3 ^ 2") == 512)
        #expect(try value("2 ^ -1") == 0.5)            // the right side may be negative
    }

    /// The remainder floors, which is what wraps a phase: `-1 % 3` is `2`. That
    /// is the shader spelling and it matches `fract`, and it is deliberately
    /// *not* Swift's `%`, which would answer `-1`. A formula that tiles a plane
    /// reaching left of the origin is where the difference shows.
    @Test func theRemainderWrapsThroughZeroRatherThanReflecting() throws {
        #expect(try value("-1 % 3") == 2)
        #expect(try value("mod(-1, 3)") == 2)
        #expect(try value("7 % 3") == 1)
        #expect((-1.0).truncatingRemainder(dividingBy: 3) == -1)   // what Swift answers

        // It agrees with `fract` at every step, which is the property that
        // makes a wrapping value continuous.
        for i in stride(from: -4.0, through: 4.0, by: 0.25) {
            #expect(abs(try value("x % 1", ["x": i]) - fract(i)) < 1e-12, "at \(i)")
        }
    }

    // MARK: Comparisons

    @Test func comparisonsAndLogicAnswerZeroOrOne() throws {
        #expect(try value("3 > 2") == 1)
        #expect(try value("3 < 2") == 0)
        #expect(try value("2 == 2 && 1 < 0") == 0)
        #expect(try value("2 == 2 || 1 < 0") == 1)
        #expect(try value("!0") == 1)
        #expect(try value("!5") == 0)
        #expect(try value("2 = 2") == 1)               // a lone `=` compares
    }

    /// A condition that came out undefined is not met. Floating point says
    /// `NaN != 0`, so without the guard a formula that divided by zero
    /// somewhere would read as *true* and pick the wrong branch.
    @Test func anUndefinedConditionIsNotMet() throws {
        #expect(try value("if(0 / 0, 1, 2)") == 2)
        #expect(try value("(0 / 0) && 1") == 0)
    }

    /// `if` picks its branch before evaluating it, so the branch not taken
    /// never runs. Everything in this language is a pure number, so a discarded
    /// branch could not change the answer either way; what it changes is the
    /// work. The noise field is the one call that can be counted, so it is what
    /// measures the claim.
    @Test func ifEvaluatesOnlyTheBranchItPicks() throws {
        #expect(try value("if(x != 0, 1 / x, 0)", ["x": 0]) == 0)
        #expect(try value("if(x != 0, 1 / x, 0)", ["x": 4]) == 0.25)

        final class Counter: @unchecked Sendable { var reads = 0 }
        let counter = Counter()
        let counting: Formula.NoiseField = { _, _, _ in counter.reads += 1; return 0 }
        _ = try Formula("if(0, noise(1) + noise(2), 3)").value([], noise: counting)
        #expect(counter.reads == 0, "the branch not taken was evaluated anyway")
        _ = try Formula("if(1, noise(1) + noise(2), 3)").value([], noise: counting)
        #expect(counter.reads == 2)
    }

    // MARK: Functions

    /// The functions answer what the framework's own calls of the same name
    /// answer. The point of matching spellings is that a formula reads like the
    /// Swift beside it, and that only holds if the numbers agree.
    @Test func functionsAgreeWithTheFrameworkTheyAreNamedAfter() throws {
        #expect(try value("clamp(9, 0, 5)") == clamp(9, 0, 5))
        #expect(try value("lerp(10, 20, 0.25)") == lerp(10, 20, 0.25))
        #expect(try value("mix(10, 20, 0.25)") == lerp(10, 20, 0.25))
        #expect(try value("smoothstep(0, 1, 0.25)") == smoothstep(0, 1, 0.25))
        #expect(try value("step(0.5, 0.4)") == step(0.5, 0.4))
        #expect(try value("step(0.5, 0.6)") == step(0.5, 0.6))
        #expect(try value("fract(-0.25)") == fract(-0.25))
        #expect(try value("map(0.5, 0, 1, 100, 200)") == map(0.5, 0, 1, 100, 200))
        #expect(abs(try value("sin(pi / 2)") - 1) < 1e-12)
        #expect(abs(try value("degrees(pi)") - 180) < 1e-12)
        #expect(abs(try value("radians(180)") - .pi) < 1e-12)
        #expect(try value("saturate(4)") == 1)
        #expect(try value("hypot(3, 4)") == 5)
        #expect(try value("sign(-3)") == -1)
    }

    /// `min` and `max` take as many arguments as you give them, which is what a
    /// person typing a formula reaches for.
    @Test func minAndMaxTakeAnyNumberOfArguments() throws {
        #expect(try value("min(3, 1, 2)") == 1)
        #expect(try value("max(3, 1, 2, 9, 4)") == 9)
        #expect(try value("min(3, 1)") == 1)
    }

    /// Noise reads the field it is handed, so a sketch's `noiseSeed()` reaches
    /// a formula. With no field it still answers the same number every time,
    /// which keeps a formula reproducible on its own.
    @Test func noiseReadsTheFieldItIsHanded() throws {
        let f = try Formula("noise(t)")
        #expect(f.usesNoise)
        #expect(try Formula("t * 2").usesNoise == false)

        let flat: Formula.NoiseField = { _, _, _ in 0.5 }
        #expect(f.value(["t": 1], noise: flat) == 0.75)          // unsigned is the signed field, halved
        #expect(try Formula("signedNoise(t)").value(["t": 1], noise: flat) == 0.5)

        // No field: the same answer twice, and inside its range.
        let a = f.value(["t": 0.3]), b = f.value(["t": 0.3])
        #expect(a == b)
        #expect(a >= 0 && a <= 1)
    }

    // MARK: Names

    /// Left to itself, a formula names its own variables in the order it meets
    /// them, so a caller can ask what it needs.
    @Test func aFormulaReportsTheNamesItFound() throws {
        let f = try Formula("a * 2 + b - a")
        #expect(f.variables == ["a", "b"])
        #expect(f.value([3, 1]) == 4)
        #expect(f.value(["a": 3, "b": 1]) == 4)
        #expect(f.value([3]) == 3)                     // a missing number reads as zero
    }

    /// Given a list of names, a name outside it is refused rather than read as
    /// an unknown value that quietly answers zero. That is the difference
    /// between a typed formula that reports a typo and one that draws nothing.
    @Test func anUnknownNameIsRefusedWhenTheNamesAreKnown() throws {
        let error = #expect(throws: FormulaError.self) {
            try Formula("sin(tine)", variables: ["time"])
        }
        #expect(error?.message.contains("tine") == true)
        #expect(error?.message.contains("time") == true)     // it says what was available
        #expect(error?.offset == 4)                          // and points at the word

        // The same text is fine when the name is not declared ahead.
        #expect(try Formula("sin(tine)").variables == ["tine"])
    }

    /// A declared list keeps its order, so the numbers handed over line up with
    /// the list rather than with the order the formula happens to read them in.
    @Test func aDeclaredListKeepsItsOrder() throws {
        let f = try Formula("b - a", variables: ["a", "b"])
        #expect(f.variables == ["a", "b"])
        #expect(f.value([1, 10]) == 9)
    }

    @Test func constantsAreNumbersNotVariables() throws {
        #expect(try Formula("pi + tau + e").variables.isEmpty)
        #expect(abs(try value("tau") - .pi * 2) < 1e-12)
    }

    // MARK: Reading the text

    /// A number may carry an exponent, and `e` is also a constant. Which one a
    /// letter means is decided by whether a digit follows it.
    @Test func anExponentIsTakenOnlyWhenItReallyIsOne() throws {
        #expect(try value("1e3") == 1000)
        #expect(try value("2.5e-3") == 0.0025)
        #expect(try value("2 * e") == 2 * Foundation.exp(1.0))
        #expect(try value(".5") == 0.5)
    }

    @Test func badTextIsRefusedWithASpot() throws {
        let cases: [(String, Int)] = [
            ("2 +", 3),              // stops early
            ("2 2", 2),              // more than one formula
            ("(2", 0),               // never closed
            ("2 $ 3", 2),            // no meaning
            ("nope(1)", 0),          // not a function
            ("clamp(1)", 0),         // wrong count
            ("", 0),                 // empty
        ]
        for (source, offset) in cases {
            let error = #expect(throws: FormulaError.self) { try Formula(source) }
            #expect(error?.offset == offset, "\(source) points at \(String(describing: error))")
        }
    }

    @Test func theArityMessageSaysWhatItWanted() throws {
        let error = #expect(throws: FormulaError.self) { try Formula("clamp(1)") }
        #expect(error?.message.contains("3 argument") == true)
        let variadic = #expect(throws: FormulaError.self) { try Formula("min(1)") }
        #expect(variadic?.message.contains("or more") == true)
    }

    // MARK: The value itself

    @Test func aFormulaIsItsTextAndItsNames() throws {
        #expect(try Formula("1 + 1") == Formula("1 + 1"))
        #expect(try Formula("1 + 1") != Formula("1 +  1"))
        #expect(try Formula("a", variables: ["a", "b"]) != Formula("a", variables: ["a"]))
        #expect(try Formula("1 + 1").description == "1 + 1")
    }

    /// Whitespace never changes an answer, and neither does a redundant pair of
    /// parentheses. A cheap sweep, but it is what a hand-rolled tokenizer gets
    /// wrong first.
    @Test func spacingDoesNotChangeAnAnswer() throws {
        let spellings = ["1+2*3", "1 + 2 * 3", "  1+2 * 3  ", "(1)+((2)*(3))"]
        for spelling in spellings {
            #expect(try value(spelling) == 7, "\(spelling)")
        }
    }

    /// A dot joins a knob to one of its parts, so `center.x` is one name. The
    /// dot in a number is untouched by that, which is the pair a tokenizer gets
    /// wrong: reading `1.5` as a name, or `center.x` as three tokens.
    @Test func aDotJoinsAKnobToOneOfItsParts() throws {
        let formula = try Formula("center.x + center.y * 2")
        #expect(formula.variables == ["center.x", "center.y"])
        #expect(formula.value(["center.x": 3, "center.y": 4]) == 11)

        #expect(try value("1.5 + .5") == 2)
        #expect(try value("2e3") == 2000)
        #expect(try Formula("a.b.c").variables == ["a.b.c"])

        // A dot with no name after it belongs to nothing, and says so.
        #expect(throws: FormulaError.self) { try Formula("center. + 1") }
        #expect(throws: FormulaError.self) { try Formula("1 . 5") }
    }
}
