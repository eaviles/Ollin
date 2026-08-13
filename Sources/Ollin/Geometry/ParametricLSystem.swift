import os
import Foundation

/// A **parametric L-system**: an L-system whose symbols carry numbers, and whose
/// rules do arithmetic on them. Where a plain `LSystem` rewrites bare letters, a
/// parametric one rewrites *modules* like `A(1.5)` or `F(x, t)`, so a rule can
/// say how much shorter the next branch is, how much thinner, and when a bud
/// should finally stop.
///
/// That is the whole reason it exists. A plain grammar can only choose *which*
/// symbols come next, so every length it draws must be a whole multiple of one
/// step. A parametric one carries the length itself, so a segment can shrink by
/// a ratio each pass, a trunk can taper, and a bud can wait a few seasons before
/// opening.
///
/// ```swift
/// // A branch that halves at every fork and stops when it gets too short:
/// let system = ParametricLSystem(
///     axiom: "A(1)",
///     rules: ["A(s) : s > 0.02 -> F(s)[+A(s*0.5)][-A(s*0.5)]"],
///     angle: 30)
/// stroke(.white); strokeWeight(2); noFill()
/// drawLSystem(system, iterations: 8)
/// ```
///
/// ### Writing a rule
///
/// A rule is one string in the notation the literature uses:
///
/// ```
///   predecessor  :  condition  ->  successor  :  weight
///        A(s)    :   s > 0.02  ->  F(s)[+A(s/2)]
/// ```
///
/// - The **predecessor** is a module with *names* for its parameters. Those
///   names are what the condition and the successor may use.
/// - The **condition** is optional. Write `*`, or leave it out, for a rule that
///   always applies. A rule whose condition is false simply does not apply, and
///   the next rule is tried.
/// - The **successor** is the modules that replace it, with an expression in
///   place of every number.
/// - The **weight** is optional; see *Stochastic rules* below.
///
/// A module matches a rule only when the letter **and the number of parameters**
/// agree, so `A`, `A(x)`, and `A(x, y)` are three different things and may all
/// appear in one system. A module that matches no rule is left exactly as it is,
/// which is why the turtle's own `+`, `-`, and `[` need no rules at all.
///
/// ### Arithmetic
///
/// Expressions take `+ - * / %`, exponentiation `^`, comparison
/// `< <= > >= == !=`, and `&& || !`. A comparison is worth `1` when it holds and
/// `0` when it does not. The functions are `sin cos tan asin acos atan floor
/// ceil trunc abs exp log sqrt sign` and `ran(x)`, a random number in `0 ..< x`;
/// the trigonometry is in **radians**, while every angle the turtle turns is in
/// **degrees**.
///
/// Two precedence rules are worth knowing because they are not the ones Swift
/// uses: `^` binds *tighter* than `*` and groups to the right, so `2^3^2` is
/// `2^9`; and unary minus binds tighter still, so `-2^2` is `4`. Both follow the
/// published table.
///
/// Numbers you want to name go in `constants`, and a rule may then use them:
///
/// ```swift
/// ParametricLSystem(axiom: "A(1)",
///                   rules: ["A(s) -> F(s)[+A(s/R)][-A(s/R)]"],
///                   angle: 85,
///                   constants: ["R": 1.456])
/// ```
///
/// ### Stochastic rules
///
/// Give two rules the same predecessor and a weight each, and one is picked at
/// random every time a module is rewritten:
///
/// ```swift
/// ParametricLSystem(axiom: "A(1)",
///                   rules: ["A(s) -> F(s)[+A(s*0.6)]A(s*0.8) : 2",
///                           "A(s) -> F(s)[-A(s*0.6)]A(s*0.8) : 1"],
///                   angle: 25)
/// ```
///
/// The numbers are *weights*, not probabilities: they need not add to one, and
/// they are shared out among whichever rules actually matched, so a condition
/// still gets to rule a branch out first. A weight may itself be an expression
/// in the module's own parameters, so the odds can change as a form grows. When
/// no rule anywhere carries a weight the system is deterministic and the first
/// matching rule always wins.
///
/// ### The turtle
///
/// The line-work comes out as open `[Contour]`s, exactly like `LSystem`, so it
/// feeds stroking, the shape booleans, hatching, and SVG export. Where a system
/// sets widths with `!(w)`, ask for `lSystemMarks` instead and the widths come
/// with it.
///
/// ```
///   F(a) G(a)   move forward a, drawing
///   f(a) g(a)   move forward a, pen up
///   +(a) -(a)   turn left / right by a degrees   (a may be negative)
///   |           turn around
///   [  ]        push / pop position, heading, and width
///   !(w) #(w)   set the line width to w
///   %           cut: abandon the rest of this branch
/// ```
///
/// A turtle symbol with no parameter falls back to the system's own `angle` and
/// step, so `+` is `+(angle)` and `F` is `F(1)`. Extra parameters are ignored,
/// which is what lets `F(x, t)` draw `x` while `t` carries a counter the
/// drawing never reads.
///
/// - Note: The turtle draws in the plane. The published three-dimensional
///   symbols (`&` `^` `\` `/` `$`), and the polygon and color symbols, are
///   carried through the rewriting untouched but draw nothing, and say so once
///   on the console rather than silently flattening a solid model.
public struct ParametricLSystem: Sendable {
    /// The starting word, as written.
    public let axiom: String
    /// The turn in **degrees** a bare `+` or `-` makes.
    public let angle: Double
    /// Anything that would not parse, in plain words. Empty when all is well.
    /// A rule that failed to parse is left out, so the modules it should have
    /// rewritten stand still instead.
    public let errors: [String]

    let axiomModules: [SuccessorModule]
    /// Source order is load-bearing: with no weights anywhere, the first rule
    /// that matches is the one that applies.
    let productions: [ParametricProduction]
    /// Whether any rule carries a weight, which decides between the two ways of
    /// choosing among several matching rules. They are mutually exclusive.
    let isWeighted: Bool

    /// Build a system from an axiom, a list of rules, and the turn angle.
    ///
    /// - Parameters:
    ///   - axiom: The starting word, such as `"A(1)"`.
    ///   - rules: One rule per string, in the order they should be tried.
    ///   - angle: The turn in degrees a bare `+` or `-` makes.
    ///   - constants: Numbers the rules may refer to by name.
    public init(axiom: String, rules: [String], angle: Double,
                constants: [String: Double] = [:]) {
        self.axiom = axiom
        self.angle = angle

        var problems: [String] = []
        var parsed: [ParametricProduction] = []

        do {
            self.axiomModules = try ParametricLSystem.parseModules(Substring(axiom),
                                                                   parameters: [],
                                                                   constants: constants)
        } catch let error as LSystemParseError {
            problems.append("axiom '\(axiom)': \(error.message)")
            self.axiomModules = []
        } catch {
            problems.append("axiom '\(axiom)': could not be read")
            self.axiomModules = []
        }

        for rule in rules {
            do {
                parsed.append(try ParametricProduction(rule, constants: constants))
            } catch let error as LSystemParseError {
                problems.append("rule '\(rule)': \(error.message)")
            } catch {
                problems.append("rule '\(rule)': could not be read")
            }
        }

        self.productions = parsed
        self.isWeighted = parsed.contains { $0.weight != nil }
        self.errors = problems
        for problem in problems { ParametricLSystem.report(problem) }
    }

    /// Whether the grown form depends on the random source, either because rules
    /// carry weights or because an expression calls `ran`.
    public var isStochastic: Bool {
        isWeighted
            || productions.contains { $0.usesRandom }
            || axiomModules.contains { $0.usesRandom }
    }

    // A rule that grows the word severalfold each pass reaches billions of
    // modules in a dozen passes, so a pass that would cross this is abandoned
    // and the previous word kept. The published grammars run to derivation
    // lengths in the forties, so this sits well above any of them.
    static let maxModules = 2_000_000

    // MARK: - Rewriting

    /// The word after `iterations` rewriting passes.
    func word<R: RandomNumberGenerator>(iterations: Int, using rng: inout R) -> ParametricWord {
        var current = ParametricWord()
        var arguments: [Double] = []
        for module in axiomModules {
            arguments.removeAll(keepingCapacity: true)
            for parameter in module.parameters {
                arguments.append(parameter.value([], using: &rng))
            }
            current.append(module.letter, arguments)
        }

        guard !productions.isEmpty else { return current }

        var matches: [Int] = []
        var weights: [Double] = []

        for _ in 0 ..< Swift.max(iterations, 0) {
            var next = ParametricWord()
            next.reserve(current.count * 2)

            for index in 0 ..< current.count {
                let letter = current.letter(index)
                let arity = current.parameterCount(index)
                arguments.removeAll(keepingCapacity: true)
                current.appendParameters(index, into: &arguments)

                let chosen: Int?
                if isWeighted {
                    // Every matching rule takes a share of the total weight. The
                    // conditions have already ruled the others out, so a grammar
                    // whose guards partition the range still behaves exactly as
                    // it would with no weights at all.
                    matches.removeAll(keepingCapacity: true)
                    weights.removeAll(keepingCapacity: true)
                    var total = 0.0
                    for i in 0 ..< productions.count {
                        let production = productions[i]
                        guard production.matches(letter: letter, arity: arity,
                                                 arguments: arguments, using: &rng) else { continue }
                        var weight = 1.0
                        if let expression = production.weight {
                            weight = expression.value(arguments, using: &rng)
                        }
                        guard weight > 0 else { continue }
                        matches.append(i)
                        weights.append(weight)
                        total += weight
                    }
                    if matches.isEmpty || total <= 0 {
                        chosen = nil
                    } else {
                        var pick = Double.random(in: 0 ..< total, using: &rng)
                        var landed = matches[matches.count - 1]
                        for (i, weight) in weights.enumerated() {
                            if pick < weight { landed = matches[i]; break }
                            pick -= weight
                        }
                        chosen = landed
                    }
                } else {
                    // With no weights anywhere, the first rule that matches is
                    // the one that applies, which is what lets a grammar spell
                    // its cases as a list rather than as a partition.
                    var first: Int?
                    for i in 0 ..< productions.count
                    where productions[i].matches(letter: letter, arity: arity,
                                                 arguments: arguments, using: &rng) {
                        first = i
                        break
                    }
                    chosen = first
                }

                guard let chosen else {
                    // No rule matched, so the module stands for itself.
                    next.append(letter, arguments)
                    continue
                }
                for module in productions[chosen].successor {
                    var values: [Double] = []
                    values.reserveCapacity(module.parameters.count)
                    for parameter in module.parameters {
                        values.append(parameter.value(arguments, using: &rng))
                    }
                    next.append(module.letter, values)
                }
            }

            if next.count > Self.maxModules {
                ParametricLSystem.report("expansion hit the \(Self.maxModules)-module cap; lower the iteration count.")
                break
            }
            current = next
        }
        return current
    }

    /// The word after `iterations` passes, as the modules it is made of. This is
    /// the way to read a grown form without the turtle, so a sketch can draw
    /// something of its own for each module.
    public func modules<R: RandomNumberGenerator>(iterations: Int,
                                                  using rng: inout R) -> [LSystemModule] {
        let grown = word(iterations: iterations, using: &rng)
        var result: [LSystemModule] = []
        result.reserveCapacity(grown.count)
        var values: [Double] = []
        for index in 0 ..< grown.count {
            values.removeAll(keepingCapacity: true)
            grown.appendParameters(index, into: &values)
            result.append(LSystemModule(letter: Character(UnicodeScalar(grown.letter(index))),
                                        parameters: values))
        }
        return result
    }

    /// The word after `iterations` passes (fixed random source; pass an `rng`,
    /// or use the `Sketch` sugar, when a stochastic system should vary).
    public func modules(iterations: Int) -> [LSystemModule] {
        var rng = SplitMix64(seed: 0)
        return modules(iterations: iterations, using: &rng)
    }

    /// The word after `iterations` passes, written back out in the notation the
    /// rules are written in.
    public func expanded<R: RandomNumberGenerator>(iterations: Int, using rng: inout R) -> String {
        let grown = word(iterations: iterations, using: &rng)
        var text = ""
        var values: [Double] = []
        for index in 0 ..< grown.count {
            text.append(Character(UnicodeScalar(grown.letter(index))))
            guard grown.parameterCount(index) > 0 else { continue }
            values.removeAll(keepingCapacity: true)
            grown.appendParameters(index, into: &values)
            text.append("(")
            text.append(values.map(ParametricLSystem.text(for:)).joined(separator: ","))
            text.append(")")
        }
        return text
    }

    /// The word after `iterations` passes, written back out (fixed random
    /// source; see `expanded(iterations:using:)`).
    public func expanded(iterations: Int) -> String {
        var rng = SplitMix64(seed: 0)
        return expanded(iterations: iterations, using: &rng)
    }

    /// Print a parameter the way it was most likely written: a whole number
    /// without a decimal point, anything else to six places with the trailing
    /// zeros trimmed.
    static func text(for value: Double) -> String {
        if value == value.rounded() && Swift.abs(value) < 1e15 {
            return String(Int64(value))
        }
        var text = String(format: "%.6f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    // MARK: - Drawing

    /// The line-work after `iterations` passes, walked by the turtle from
    /// `start` with the given `heading` (degrees; `-90` points up the screen).
    /// Every forward move is scaled by `step`, so a bare `F` moves `step`.
    public func contours<R: RandomNumberGenerator>(
        iterations: Int,
        step: Double = 1,
        start: Vector2 = .zero,
        heading: Double = -90,
        using rng: inout R
    ) -> [Contour] {
        branches(iterations: iterations, step: step, start: start, heading: heading, using: &rng)
            .map { Contour($0.points, closed: false) }
    }

    /// The line-work after `iterations` passes (fixed random source).
    public func contours(iterations: Int, step: Double = 1,
                         start: Vector2 = .zero, heading: Double = -90) -> [Contour] {
        var rng = SplitMix64(seed: 0)
        return contours(iterations: iterations, step: step, start: start, heading: heading, using: &rng)
    }

    /// The line-work after `iterations` passes as marks that **carry the width**
    /// each `!(w)` asked for, ready for `drawMark(_:)`. Widths come back as
    /// multiples of `strokeWeight`, scaled so the widest is exactly 1, so
    /// `strokeWeight` sets the thickness of the trunk.
    public func marks<R: RandomNumberGenerator>(
        iterations: Int,
        step: Double = 1,
        start: Vector2 = .zero,
        heading: Double = -90,
        using rng: inout R
    ) -> [StrokeMark] {
        ParametricLSystem.marks(from: branches(iterations: iterations, step: step,
                                               start: start, heading: heading, using: &rng))
    }

    /// The marks after `iterations` passes (fixed random source).
    public func marks(iterations: Int, step: Double = 1,
                      start: Vector2 = .zero, heading: Double = -90) -> [StrokeMark] {
        var rng = SplitMix64(seed: 0)
        return marks(iterations: iterations, step: step, start: start, heading: heading, using: &rng)
    }

    /// Turn walked branches into marks, normalising the widths so the widest is
    /// 1. A branch of one point draws nothing, so it is dropped.
    static func marks(from branches: [LSystemBranch]) -> [StrokeMark] {
        let widest = branches.flatMap(\.widths).max() ?? 1
        let scale = widest > 0 ? 1 / widest : 1
        return branches.compactMap { branch in
            guard branch.points.count >= 2 else { return nil }
            let samples = zip(branch.points, branch.widths).map {
                StrokeMark.Sample(position: $0, width: $1 * scale)
            }
            return StrokeMark(samples: samples)
        }
    }

    func branches<R: RandomNumberGenerator>(
        iterations: Int, step: Double, start: Vector2, heading: Double, using rng: inout R
    ) -> [LSystemBranch] {
        ParametricLSystem.turtle(word(iterations: iterations, using: &rng),
                                 angleDegrees: angle, step: step,
                                 start: start, headingDegrees: heading)
    }

    // One note per distinct message. A system is a value, so this is reached
    // from whichever thread built or walked one, and several may be doing so at
    // once; the lock is what keeps the set of already-said messages sound.
    private static let reported = OSAllocatedUnfairLock(initialState: Set<String>())
    static func report(_ message: String) {
        guard reported.withLock({ $0.insert(message).inserted }) else { return }
        print("Ollin: parametric L-system: \(message)")
    }
}

/// One module of a grown word: its letter and the numbers it carries.
public struct LSystemModule: Sendable, Equatable {
    /// The letter, such as `F` or `A`.
    public let letter: Character
    /// Its parameters, in order. Empty for a bare module.
    public let parameters: [Double]

    public init(letter: Character, parameters: [Double]) {
        self.letter = letter
        self.parameters = parameters
    }
}

/// One unbroken run of drawn segments, with the width in force at each point.
struct LSystemBranch {
    var points: [Vector2]
    var widths: [Double]
}

// MARK: - The word

/// A parametric word laid out flat: the letters in one array, every parameter in
/// another, and where each module's parameters begin in a third. A word runs to
/// millions of modules, and giving each one its own array of parameters would
/// spend the whole expansion in the allocator.
struct ParametricWord {
    private(set) var letters: [UInt8] = []
    /// One more entry than there are modules: module `i` owns
    /// `values[bounds[i] ..< bounds[i + 1]]`.
    private(set) var bounds: [Int32] = [0]
    private(set) var values: [Double] = []

    var count: Int { letters.count }

    mutating func reserve(_ capacity: Int) {
        letters.reserveCapacity(capacity)
        bounds.reserveCapacity(capacity + 1)
        values.reserveCapacity(capacity)
    }

    mutating func append(_ letter: UInt8, _ parameters: [Double]) {
        letters.append(letter)
        values.append(contentsOf: parameters)
        bounds.append(Int32(values.count))
    }

    func letter(_ index: Int) -> UInt8 { letters[index] }

    func parameterCount(_ index: Int) -> Int { Int(bounds[index + 1] - bounds[index]) }

    func appendParameters(_ index: Int, into destination: inout [Double]) {
        for i in Int(bounds[index]) ..< Int(bounds[index + 1]) { destination.append(values[i]) }
    }

    /// The first parameter, or `nil` for a bare module. This is what the turtle
    /// reads: the published rule is that the first parameter steers it and any
    /// others are ignored.
    func firstParameter(_ index: Int) -> Double? {
        bounds[index + 1] > bounds[index] ? values[Int(bounds[index])] : nil
    }
}

// MARK: - Productions

/// A module in a successor: a letter and an expression for each parameter.
struct SuccessorModule: Sendable {
    let letter: UInt8
    let parameters: [LSystemExpression]

    var usesRandom: Bool { parameters.contains(where: \.usesRandom) }
}

struct ParametricProduction: Sendable {
    let letter: UInt8
    let arity: Int
    let condition: LSystemExpression?
    let successor: [SuccessorModule]
    let weight: LSystemExpression?

    var usesRandom: Bool {
        (condition?.usesRandom ?? false)
            || (weight?.usesRandom ?? false)
            || successor.contains(where: \.usesRandom)
    }

    /// A rule applies when the letter agrees, the number of parameters agrees,
    /// and the condition holds. A false condition is not an error: the rule
    /// simply does not apply and the next one is tried.
    func matches<R: RandomNumberGenerator>(letter: UInt8, arity: Int,
                                           arguments: [Double], using rng: inout R) -> Bool {
        guard self.letter == letter, self.arity == arity else { return false }
        guard let condition else { return true }
        return LSystemExpression.isTrue(condition.value(arguments, using: &rng))
    }
}
