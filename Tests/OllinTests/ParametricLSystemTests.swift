import Testing
@testable import Ollin

/// Pure-CPU checks on parametric L-systems: the little arithmetic language obeys
/// the published precedence table, a module matches a rule only on letter *and*
/// arity, the two ways of choosing among several matching rules behave as the
/// formalism says, and the turtle reads a module's first parameter and ignores
/// the rest.
@Suite
struct ParametricLSystemTests {

    // MARK: - The arithmetic

    private func value(_ source: String, _ arguments: [Double] = [],
                       parameters: [String] = [], constants: [String: Double] = [:]) -> Double {
        var rng = SplitMix64(seed: 1)
        guard let expression = try? LSystemExpressionParser.parse(Substring(source),
                                                                  parameters: parameters,
                                                                  constants: constants) else {
            return .nan
        }
        return expression.value(arguments, using: &rng)
    }

    /// Exponentiation binds tighter than multiplication, which is the published
    /// table and *not* the one Swift uses. Read with Swift's precedence `2*3^2`
    /// would be `(2*3)^2 = 36`.
    @Test func exponentiationBindsTighterThanMultiplication() {
        #expect(value("2*3^2") == 18)
        #expect(value("8/2^2") == 2)
    }

    /// Exponentiation groups to the right, so `2^3^2` is `2^9` and not `8^2`.
    @Test func exponentiationGroupsToTheRight() {
        #expect(value("2^3^2") == 512)
    }

    /// Unary minus binds tighter than exponentiation, so `-2^2` is `(-2)^2`. In
    /// most languages it is `-(2^2)`, so getting this wrong flips a sign rather
    /// than failing to parse.
    @Test func unaryMinusBindsTighterThanExponentiation() {
        #expect(value("-2^2") == 4)
        #expect(value("2^-2") == 0.25)
    }

    /// The ordinary precedences still hold below that.
    @Test func arithmeticFollowsTheUsualPrecedences() {
        #expect(value("1+2*3") == 7)
        #expect(value("(1+2)*3") == 9)
        #expect(value("7%3") == 1)
        #expect(value("10-3-2") == 5)      // subtraction groups to the left
    }

    /// A comparison is worth one when it holds and zero when it does not, so it
    /// can be used in arithmetic.
    @Test func comparisonsAreOneAndZero() {
        #expect(value("3 > 2") == 1)
        #expect(value("3 < 2") == 0)
        #expect(value("2 <= 2") == 1)
        #expect(value("2 == 2") == 1)
        #expect(value("2 != 2") == 0)
        #expect(value("1 && 0") == 0)
        #expect(value("1 || 0") == 1)
        #expect(value("!0") == 1)
        #expect(value("5 * (3 > 2)") == 5)
    }

    /// The book spells and, or, and equality with single characters and the
    /// reference implementation doubles them; both are read, so a grammar can be
    /// typed straight out of either.
    @Test func bothSpellingsOfTheLogicalOperatorsAreRead() {
        #expect(value("1 & 1") == 1)
        #expect(value("0 | 1") == 1)
        #expect(value("2 = 2") == 1)
        #expect(value("2 <> 3") == 1)
    }

    /// Parameters resolve by position and constants by name, and a parameter of
    /// the same spelling as a constant wins.
    @Test func namesResolveToParametersThenConstants() {
        #expect(value("x + y", [3, 4], parameters: ["x", "y"]) == 7)
        #expect(value("s / R", [3], parameters: ["s"], constants: ["R": 1.5]) == 2)
        #expect(value("R", [9], parameters: ["R"], constants: ["R": 1.5]) == 9)
    }

    @Test func functionsAreAvailable() {
        #expect(value("sqrt(9)") == 3)
        #expect(value("abs(-4)") == 4)
        #expect(value("floor(2.7)") == 2)
        #expect(value("ceil(2.1)") == 3)
        #expect(value("sign(-3)") == -1)
        #expect(abs(value("exp(log(5))") - 5) < 1e-12)
    }

    /// A number may open with its decimal point, which the published grammars
    /// rely on: one of them writes `F(s+.1, t, c)`.
    @Test func aNumberMayOpenWithItsDecimalPoint() {
        #expect(value(".25 + .25") == 0.5)
    }

    /// A condition that came out undefined must read as *not met*. Floating
    /// point says `NaN != 0`, so a plain test against zero would let a rule fire
    /// on a division that went wrong.
    @Test func anUndefinedConditionDoesNotHold() {
        #expect(!LSystemExpression.isTrue(Double.nan))
        #expect(!LSystemExpression.isTrue(0))
        #expect(LSystemExpression.isTrue(-3))
    }

    // MARK: - Rewriting

    /// The worked example from the book, derived five passes. It exercises guard
    /// pairs that partition a range, a two-parameter module, division, and a
    /// module with no rule at all.
    @Test func theBooksOwnDerivationIsReproduced() {
        let system = ParametricLSystem(
            axiom: "B(2)A(4,4)",
            rules: ["A(x,y) : y <= 3 -> A(x*2, x+y)",
                    "A(x,y) : y > 3  -> B(x)A(x/y, 0)",
                    "B(x) : x < 1  -> C",
                    "B(x) : x >= 1 -> B(x-1)"],
            angle: 90)
        #expect(system.errors.isEmpty)
        #expect(system.expanded(iterations: 0) == "B(2)A(4,4)")
        #expect(system.expanded(iterations: 1) == "B(1)B(4)A(1,0)")
        #expect(system.expanded(iterations: 2) == "B(0)B(3)A(2,1)")
        #expect(system.expanded(iterations: 3) == "CB(2)A(4,3)")
        #expect(system.expanded(iterations: 4) == "CB(1)A(8,7)")
        #expect(system.expanded(iterations: 5) == "CB(0)B(8)A(1.142857,0)")
    }

    /// A module matches a rule only when the letter *and* the number of
    /// parameters agree, so one system can hold three different `A`s.
    @Test func theNumberOfParametersIsPartOfTheMatch() {
        let system = ParametricLSystem(
            axiom: "A A(1) A(1,2)",
            rules: ["A -> B", "A(x) -> C(x)", "A(x,y) -> D"],
            angle: 90)
        #expect(system.errors.isEmpty)
        #expect(system.expanded(iterations: 1) == "BC(1)D")
    }

    /// A module no rule matches stands for itself, which is why the turtle's own
    /// symbols need no rules.
    @Test func anUnmatchedModuleStandsForItself() {
        let system = ParametricLSystem(axiom: "X+Y(3)", rules: ["X -> XY"], angle: 90)
        #expect(system.expanded(iterations: 1) == "XY+Y(3)")
        #expect(system.expanded(iterations: 2) == "XYY+Y(3)")
    }

    /// A rule whose condition fails is not an error and does not consume the
    /// module: the next rule is tried, and if none matches the module stands.
    @Test func aFailedConditionFallsThroughToTheNextRule() {
        let system = ParametricLSystem(
            axiom: "A(5)A(0)",
            rules: ["A(d) : d > 0 -> A(d-1)", "A(d) : d == 0 -> F(1)"],
            angle: 90)
        #expect(system.expanded(iterations: 1) == "A(4)F(1)")

        let unguarded = ParametricLSystem(axiom: "A(0)", rules: ["A(d) : d > 0 -> A(d-1)"], angle: 90)
        #expect(unguarded.expanded(iterations: 3) == "A(0)")
    }

    /// With no weights anywhere, the first rule that matches wins, so two rules
    /// whose conditions overlap resolve in the order they were written.
    @Test func theFirstMatchingRuleWinsWhenNothingIsWeighted() {
        let system = ParametricLSystem(
            axiom: "A(5)",
            rules: ["A(x) : x > 0 -> B", "A(x) : x > 1 -> C"],
            angle: 90)
        #expect(system.expanded(iterations: 1) == "B")

        let reversed = ParametricLSystem(
            axiom: "A(5)",
            rules: ["A(x) : x > 1 -> C", "A(x) : x > 0 -> B"],
            angle: 90)
        #expect(reversed.expanded(iterations: 1) == "C")
    }

    /// Rewriting happens all at once against the previous word, so a rule can
    /// never see what another rule produced in the same pass.
    @Test func everyModuleIsRewrittenAgainstThePreviousWord() {
        let system = ParametricLSystem(axiom: "A(1)", rules: ["A(x) -> A(x+1)A(x+1)"], angle: 90)
        #expect(system.expanded(iterations: 2) == "A(3)A(3)A(3)A(3)")
    }

    // MARK: - Weights

    /// Weights are shared out in the ratio they are written, not treated as
    /// probabilities that must add to one.
    @Test func weightsAreSharedOutInTheirOwnRatio() {
        let system = ParametricLSystem(axiom: "A", rules: ["A -> B : 2", "A -> C : 1"], angle: 90)
        #expect(system.isStochastic)

        var bs = 0
        let trials = 6000
        for seed in 0 ..< trials {
            var rng = SplitMix64(seed: UInt64(seed))
            if system.expanded(iterations: 1, using: &rng) == "B" { bs += 1 }
        }
        let share = Double(bs) / Double(trials)
        #expect(abs(share - 2.0 / 3.0) < 0.03)
    }

    /// A condition rules a candidate out *before* the weights are shared, so a
    /// grammar whose guards partition the range stays deterministic even though
    /// its rules carry weights.
    @Test func conditionsFilterBeforeWeightsAreShared() {
        let system = ParametricLSystem(
            axiom: "A(1)",
            rules: ["A(x) : x > 0 -> B : 1", "A(x) : x < 0 -> C : 1"],
            angle: 90)
        for seed in 0 ..< 50 {
            var rng = SplitMix64(seed: UInt64(seed))
            #expect(system.expanded(iterations: 1, using: &rng) == "B")
        }
    }

    /// A weight may be an expression in the module's own parameters, so the odds
    /// can change as a form grows.
    @Test func aWeightMayBeAnExpression() {
        let never = ParametricLSystem(
            axiom: "A(0)",
            rules: ["A(x) -> B : x", "A(x) -> C : 1"],
            angle: 90)
        for seed in 0 ..< 50 {
            var rng = SplitMix64(seed: UInt64(seed))
            #expect(never.expanded(iterations: 1, using: &rng) == "C")
        }
    }

    /// The same seed grows the same form and a different one grows a different
    /// form, which is what makes a stochastic sketch reproducible.
    @Test func aSeedFixesAStochasticForm() {
        let system = ParametricLSystem(
            axiom: "A(1)",
            rules: ["A(s) -> F(s)[+A(s*0.6)]A(s*0.8) : 1",
                    "A(s) -> F(s)[-A(s*0.6)]A(s*0.8) : 1"],
            angle: 25)
        func grown(_ seed: UInt64) -> String {
            var rng = SplitMix64(seed: seed)
            return system.expanded(iterations: 5, using: &rng)
        }
        #expect(grown(4) == grown(4))
        #expect(grown(4) != grown(9))
    }

    // MARK: - Reading a rule

    /// A name may be bound only once in a predecessor, which is what lets a
    /// module bind to it by position with nothing to check.
    @Test func aParameterMayNotBeNamedTwice() {
        let system = ParametricLSystem(axiom: "A(1,2)", rules: ["A(x,x) -> B"], angle: 90)
        #expect(system.errors.count == 1)
        #expect(system.errors[0].contains("twice"))
    }

    /// A rule that will not parse costs that rule and not the sketch: it is left
    /// out, said out loud, and the modules it should have rewritten stand still.
    @Test func aBadRuleIsReportedAndLeftOut() {
        let system = ParametricLSystem(
            axiom: "A(1)",
            rules: ["A(s) -> F(s)", "A(s) -> F(q)"],   // q is not a parameter of the rule
            angle: 90)
        #expect(system.errors.count == 1)
        #expect(system.errors[0].contains("q"))
        #expect(system.expanded(iterations: 1) == "F(1)")   // the good rule still runs
    }

    /// A rule with no arrow, and an expression that will not close, are both
    /// reported rather than thrown or trapped.
    @Test func malformedRulesAreReportedNotThrown() {
        #expect(ParametricLSystem(axiom: "A", rules: ["A B"], angle: 90).errors.count == 1)
        #expect(ParametricLSystem(axiom: "A", rules: ["A -> F(1"], angle: 90).errors.count == 1)
        #expect(ParametricLSystem(axiom: "F(", rules: [], angle: 90).errors.count == 1)
    }

    /// The book spaces a turn from its angle, as in "- (120) F(1)", so a
    /// parameter list may sit off from its letter.
    @Test func aParameterListMaySitOffFromItsLetter() {
        let system = ParametricLSystem(axiom: "F(1) - (120) F(1)", rules: [], angle: 90)
        #expect(system.errors.isEmpty)
        #expect(system.expanded(iterations: 0) == "F(1)-(120)F(1)")
    }

    /// All three spellings of the arrow are read.
    @Test func everySpellingOfTheArrowIsRead() {
        for arrow in ["->", "-->", "\u{2192}"] {
            let system = ParametricLSystem(axiom: "A", rules: ["A \(arrow) B"], angle: 90)
            #expect(system.errors.isEmpty)
            #expect(system.expanded(iterations: 1) == "B")
        }
    }

    /// A condition written `*`, and no condition at all, both always hold.
    @Test func anEmptyConditionAlwaysHolds() {
        let starred = ParametricLSystem(axiom: "A(1)", rules: ["A(l) : * -> F(l)"], angle: 90)
        let bare = ParametricLSystem(axiom: "A(1)", rules: ["A(l) -> F(l)"], angle: 90)
        #expect(starred.errors.isEmpty && bare.errors.isEmpty)
        #expect(starred.expanded(iterations: 1) == "F(1)")
        #expect(bare.expanded(iterations: 1) == "F(1)")
    }

    // MARK: - The turtle

    private func points(_ system: ParametricLSystem, iterations: Int = 0,
                        step: Double = 1) -> [[Vector2]] {
        system.contours(iterations: iterations, step: step, start: .zero, heading: 0)
            .map(\.points)
    }

    /// A forward move is as long as its first parameter says, and any further
    /// parameters are ignored, which is what lets a module carry counters the
    /// drawing knows nothing about.
    @Test func aForwardMoveReadsItsFirstParameterOnly() {
        let plain = points(ParametricLSystem(axiom: "F(10)", rules: [], angle: 90))
        #expect(plain.count == 1)
        #expect(abs(plain[0][1].x - 10) < 1e-9)

        let extra = points(ParametricLSystem(axiom: "F(10, 99)", rules: [], angle: 90))
        #expect(abs(extra[0][1].x - 10) < 1e-9)
    }

    /// A turtle symbol with no parameter falls back to the step and the angle
    /// the system was built with.
    @Test func abareSymbolFallsBackToTheSystemsOwnStepAndAngle() {
        let walked = points(ParametricLSystem(axiom: "F+F", rules: [], angle: 90), step: 5)
        #expect(abs(walked[0][1].x - 5) < 1e-9)
        #expect(abs(walked[0][2].x - 5) < 1e-9)
        #expect(abs(walked[0][2].y - 5) < 1e-9)   // the bare + turned the full 90
    }

    /// An angle may be negative, which turns the other way; the published tree
    /// tables use negative branching angles.
    @Test func aNegativeAngleTurnsTheOtherWay() {
        let left = points(ParametricLSystem(axiom: "F(1)+(90)F(1)", rules: [], angle: 90))
        let right = points(ParametricLSystem(axiom: "F(1)+(-90)F(1)", rules: [], angle: 90))
        #expect(abs(left[0][2].y - 1) < 1e-9)
        #expect(abs(right[0][2].y + 1) < 1e-9)
    }

    /// A bracket puts back the position and the heading it saved.
    @Test func aBracketRestoresThePose() {
        let walked = points(ParametricLSystem(axiom: "F(1)[+(90)F(1)]F(1)", rules: [], angle: 90))
        #expect(walked.count == 2)
        #expect(abs(walked[1][0].x - 1) < 1e-9 && abs(walked[1][0].y) < 1e-9)
        #expect(abs(walked[1][1].x - 2) < 1e-9 && abs(walked[1][1].y) < 1e-9)
    }

    /// A pen-up move breaks the line without drawing it.
    @Test func aPenUpMoveBreaksTheLine() {
        let walked = points(ParametricLSystem(axiom: "F(1)f(5)F(1)", rules: [], angle: 90))
        #expect(walked.count == 2)
        #expect(abs(walked[1][0].x - 6) < 1e-9)
    }

    /// The cut symbol abandons the rest of the branch it is in, and only that
    /// branch: the same word without it draws one segment more.
    @Test func theCutSymbolAbandonsTheRestOfItsBranch() {
        let cut = points(ParametricLSystem(axiom: "F(1)[F(1)%F(1)]F(1)", rules: [], angle: 90))
        let whole = points(ParametricLSystem(axiom: "F(1)[F(1)F(1)]F(1)", rules: [], angle: 90))
        #expect(cut[0].count == 3)
        #expect(whole[0].count == 4)
    }

    /// Widths come back as multiples of the stroke weight, scaled so the widest
    /// is exactly one, and a width set before anything is drawn belongs to the
    /// segment about to leave that point.
    @Test func widthsAreCarriedAndNormalisedToTheWidest() {
        let system = ParametricLSystem(axiom: "!(4)F(1)!(2)F(1)", rules: [], angle: 90)
        let marks = system.marks(iterations: 0, step: 1, start: .zero, heading: 0)
        #expect(marks.count == 1)
        let widths = marks[0].samples.map(\.width)
        #expect(widths.count == 3)
        #expect(abs(widths[0] - 1) < 1e-9)
        #expect(abs(widths[1] - 1) < 1e-9)
        #expect(abs(widths[2] - 0.5) < 1e-9)
    }

    /// A bracket puts back the width it saved along with the pose, so a thin
    /// twig never thins the trunk that carries it.
    @Test func aBracketRestoresTheWidth() {
        let system = ParametricLSystem(axiom: "!(4)F(1)[!(1)F(1)]F(1)", rules: [], angle: 90)
        let marks = system.marks(iterations: 0, step: 1, start: .zero, heading: 0)
        #expect(marks.count == 2)
        // The trunk that carries on after the twig is back at the full width.
        #expect(marks[1].samples.allSatisfy { abs($0.width - 1) < 1e-9 })
        // The twig itself came out at a quarter of it.
        #expect(abs(marks[0].samples.last!.width - 0.25) < 1e-9)
    }

    /// A grammar that sets no width at all comes back at one width throughout,
    /// so asking for marks costs a plain form nothing.
    @Test func aWidthlessGrammarIsUniform() {
        let system = ParametricLSystem(axiom: "F(1)+(90)F(1)", rules: [], angle: 90)
        let marks = system.marks(iterations: 0, step: 1, start: .zero, heading: 0)
        #expect(marks.allSatisfy { mark in mark.samples.allSatisfy { $0.width == 1 } })
    }

    /// The two ways out of one walk draw the same path, so the width-carrying
    /// form can never drift from the plain one.
    @Test func marksAndContoursWalkTheSamePath() {
        let system = ParametricLSystem(
            axiom: "A(1)",
            rules: ["A(s) : s > 0.05 -> !(s)F(s)[+(30)A(s*0.6)][-(30)A(s*0.6)]"],
            angle: 30)
        let contours = system.contours(iterations: 5, step: 10)
        let marks = system.marks(iterations: 5, step: 10)
        #expect(contours.count == marks.count)
        for (contour, mark) in zip(contours, marks) {
            #expect(contour.points == mark.positions)
        }
    }

    // MARK: - Reproducibility

    /// A deterministic system grows the same form every time it is asked.
    @Test func aDeterministicSystemRepeatsExactly() {
        let system = ParametricLSystem(
            axiom: "A(1)",
            rules: ["A(s) -> F(s)[+A(s/R)][-A(s/R)]"],
            angle: 85, constants: ["R": 1.456])
        #expect(system.expanded(iterations: 6) == system.expanded(iterations: 6))
        #expect(system.contours(iterations: 6).map(\.points)
                == system.contours(iterations: 6).map(\.points))
    }

    // MARK: - Rolling in a plane

    /// Half a turn about the heading keeps the drawing plane and only swaps left
    /// for right, so a turn after it goes the other way. This is what lets the
    /// published tree family's mirrored rows be drawn exactly rather than
    /// approximated.
    @Test func aHalfTurnRollSwapsLeftForRight() {
        let plain = points(ParametricLSystem(axiom: "F(1)+(90)F(1)", rules: [], angle: 90))
        let rolled = points(ParametricLSystem(axiom: "F(1)/(180)+(90)F(1)", rules: [], angle: 90))
        #expect(abs(plain[0][2].y - 1) < 1e-9)
        #expect(abs(rolled[0][2].y + 1) < 1e-9)
    }

    /// A whole turn, or none at all, changes nothing.
    @Test func aWholeTurnRollChangesNothing() {
        let plain = points(ParametricLSystem(axiom: "F(1)+(90)F(1)", rules: [], angle: 90))
        for roll in ["/(0)", "/(360)", "\\(-360)"] {
            let rolled = points(ParametricLSystem(axiom: "F(1)\(roll)+(90)F(1)", rules: [], angle: 90))
            #expect(rolled == plain)
        }
    }

    /// Two half turns put it back.
    @Test func twoHalfTurnRollsCancel() {
        let plain = points(ParametricLSystem(axiom: "F(1)+(90)F(1)", rules: [], angle: 90))
        let rolled = points(ParametricLSystem(axiom: "F(1)/(180)/(180)+(90)F(1)", rules: [], angle: 90))
        #expect(rolled == plain)
    }

    /// A bracket puts back which way turns go, along with the pose, so a rolled
    /// branch cannot leave the rest of the form mirrored.
    @Test func aBracketRestoresTheHandedness() {
        let plain = points(ParametricLSystem(axiom: "F(1)[+(90)F(1)]+(90)F(1)", rules: [], angle: 90))
        let rolled = points(ParametricLSystem(axiom: "F(1)[/(180)+(90)F(1)]+(90)F(1)", rules: [], angle: 90))
        #expect(plain.count == rolled.count)
        #expect(plain[1] == rolled[1])            // the trunk carried on unmirrored
        #expect(plain[0][2].y != rolled[0][2].y)  // only the rolled branch turned the other way
    }

    /// Half a turn of pitch also stays in the plane: it reverses the heading and
    /// swaps left for right together.
    @Test func aHalfTurnPitchReversesTheHeading() {
        let pitched = points(ParametricLSystem(axiom: "F(1)&(180)F(1)", rules: [], angle: 90))
        #expect(pitched[0].count == 3)
        #expect(abs(pitched[0][2].x) < 1e-9)   // it walked back over itself
    }

    // MARK: - The published grammars

    /// Every preset reads cleanly and draws something.
    @Test func everyPresetParsesAndDraws() {
        let presets: [(String, ParametricLSystem, Int)] = [
            ("triangleCurve", .triangleCurve, 4),
            ("delayedTriangleCurve", .delayedTriangleCurve, 6),
            ("selfSimilarBranch", .selfSimilarBranch, 6),
            ("growingBranch", .growingBranch, 6),
            ("compoundLeaf", .compoundLeaf, 10),
            ("alternatingLeaf", .alternatingLeaf, 12),
            ("snowflake", .snowflake, 3),
            ("mesotonicBranch", .mesotonicBranch, 8),
            ("taperedTree", .taperedTree(), 6),
            ("randomBranch", .randomBranch, 6),
        ]
        for (name, system, iterations) in presets {
            #expect(system.errors.isEmpty, "\(name): \(system.errors)")
            let drawn = system.contours(iterations: iterations, step: 10)
            #expect(!drawn.isEmpty, "\(name) drew nothing")
            #expect(drawn.allSatisfy { $0.points.allSatisfy { $0.x.isFinite && $0.y.isFinite } },
                    "\(name) drew a point that is not a number")
        }
    }

    /// One pass of the self-similar branch is the rule with its numbers worked
    /// out: a segment of one, then two buds at one over the published ratio.
    @Test func theSelfSimilarBranchTakesItsPublishedRatio() {
        #expect(ParametricLSystem.selfSimilarBranch.expanded(iterations: 1)
                == "F(1)[+A(0.686813)][-A(0.686813)]")   // 1 / 1.456
    }

    /// The two constructions of the same branching form agree on where the tips
    /// land, which is the point the source makes by giving both: one shortens
    /// each new segment, the other lengthens every old one.
    @Test func bothConstructionsOfTheBranchAgree() {
        func tips(_ system: ParametricLSystem) -> [Vector2] {
            LSystem.fit(system.contours(iterations: 7),
                        in: Rectangle(x: 0, y: 0, width: 100, height: 100), padding: 0)
                .compactMap(\.points.last)
                .sorted { ($0.x, $0.y) < ($1.x, $1.y) }
        }
        let a = tips(.selfSimilarBranch)
        let b = tips(.growingBranch)
        #expect(a.count == b.count)
        for (p, q) in zip(a, b) { #expect(p.distance(to: q) < 0.01) }
    }

    /// The mesotonic form really is widest partway up, which is the whole claim:
    /// the branches lengthen up the stem and then run out of passes to grow in.
    /// Measured as how far the form reaches sideways at each height.
    @Test func theMesotonicFormIsWidestPartwayUp() {
        let drawn = ParametricLSystem.mesotonicBranch.contours(iterations: 14, step: 1,
                                                               start: .zero, heading: -90)
        let points = drawn.flatMap(\.points)
        let top = points.map(\.y).min() ?? 0        // the stem grows towards -y
        let bottom = points.map(\.y).max() ?? 0
        let bands = 9
        var reach = [Double](repeating: 0, count: bands)
        for point in points {
            let t = (point.y - bottom) / (top - bottom)
            let band = Swift.min(bands - 1, Swift.max(0, Int(t * Double(bands))))
            reach[band] = Swift.max(reach[band], abs(point.x))
        }
        let widest = reach.firstIndex(of: reach.max()!)!
        #expect(widest > 0 && widest < bands - 1, "widest band was \(widest) of \(bands): \(reach)")
        #expect(reach[widest] > reach[0] * 1.5)
        #expect(reach[widest] > reach[bands - 1] * 1.5)
    }

    /// The tapered tree really tapers: the trunk comes back at the full stroke
    /// weight and the twigs at a fraction of it.
    @Test func theTaperedTreeThinsTowardsItsTwigs() {
        let marks = ParametricLSystem.taperedTree().marks(iterations: 8, step: 1)
        let widths = marks.flatMap { $0.samples.map(\.width) }
        #expect(abs(widths.max()! - 1) < 1e-9)   // normalised to the widest
        #expect(widths.min()! < 0.2)
    }

    /// The length guard arrests growth rather than slowing it: a tree told to
    /// stop below almost its own trunk length puts out one segment and stops,
    /// however many passes it is given.
    @Test func theLengthGuardArrestsGrowth() {
        let free = ParametricLSystem.taperedTree(minimumLength: 0)
        let arrested = ParametricLSystem.taperedTree(minimumLength: 90)
        #expect(arrested.contours(iterations: 10).count < 5)
        #expect(free.contours(iterations: 10).count > 200)
        // And it has genuinely settled: more passes change nothing.
        #expect(arrested.expanded(iterations: 4) == arrested.expanded(iterations: 12))
    }

    /// Reading a word back gives the modules it is made of, so a sketch can draw
    /// something of its own for each one instead of using the turtle.
    @Test func aGrownWordCanBeReadAsModules() {
        let system = ParametricLSystem(axiom: "A(1)", rules: ["A(s) -> F(s)+A(s/2)"], angle: 90)
        let modules = system.modules(iterations: 2)
        #expect(modules.map(\.letter) == ["F", "+", "F", "+", "A"])
        #expect(modules[0].parameters == [1])
        #expect(modules[2].parameters == [0.5])
        #expect(modules[4].parameters == [0.25])
        #expect(modules[1].parameters.isEmpty)
    }
}
