import Foundation

/// An L-system (Lindenmayer system): a tiny grammar that grows a string by
/// rewriting its symbols, which a turtle then walks to draw self-similar,
/// branching structure (plants, snowflakes, dragon curves, space-filling
/// curves). A small rule set unfolds into enormous detail.
///
/// Three pieces define one: an **axiom** (the starting string), **production
/// rules** (how each symbol rewrites, applied to every symbol at once each
/// pass), and the number of **iterations** (rewrite passes). A turtle then reads
/// the final string left to right, drawing a line for each `F`, turning at each
/// `+`/`-`, and branching at each `[`/`]`.
///
/// The output is a set of open `[Contour]`s (the line-work), so it feeds straight
/// into stroking, the shape booleans, hatching, and SVG export. A run is a pure
/// function of the system (and, for a stochastic one, the seed), so the same
/// seed always grows the same form.
///
/// ```swift
/// // A preset, fit to the canvas:
/// stroke(.white); strokeWeight(2)
/// drawLSystem(.dragonCurve, iterations: 12)
///
/// // Or build one by hand:
/// let koch = LSystem(axiom: "F", rules: ["F": "F+F-F-F+F"], angle: 90)
/// for c in lSystem(koch, iterations: 4) { drawPolyline(c.points) }
/// ```
///
/// ### The turtle alphabet
///
/// - `F`, `G` move forward one step, drawing a line.
/// - `f` moves forward one step without drawing (a gap).
/// - `+` turns left by `angle`, `-` turns right, `|` turns around.
/// - `[` pushes the turtle's position and heading, `]` pops back to it (the
///   branch mechanism).
/// - `X`, `Y` (and any other letter) draw nothing; they only steer the rewriting.
public struct LSystem: Sendable {
    /// The starting string.
    public let axiom: String
    /// The turn angle in **degrees** (turtle `+`/`-`).
    public let angle: Double
    /// Each symbol maps to one or more replacement strings. A symbol with more
    /// than one is *stochastic*: one is chosen at random each time it rewrites.
    let rules: [Character: [String]]

    /// A deterministic L-system: each symbol rewrites to exactly one string.
    ///
    /// - Parameters:
    ///   - axiom: The starting string.
    ///   - rules: The production for each symbol (a symbol with no rule is left
    ///     as-is).
    ///   - angle: The turn angle in degrees.
    public init(axiom: String, rules: [Character: String], angle: Double) {
        self.axiom = axiom
        self.angle = angle
        self.rules = rules.mapValues { [$0] }
    }

    /// A stochastic L-system: a symbol may have several productions, one picked
    /// uniformly at random each time it rewrites, so every run varies while
    /// staying reproducible for a given seed. A single-element list behaves
    /// deterministically.
    ///
    /// - Parameters:
    ///   - axiom: The starting string.
    ///   - choices: The candidate productions for each symbol.
    ///   - angle: The turn angle in degrees.
    public init(axiom: String, choices: [Character: [String]], angle: Double) {
        self.axiom = axiom
        self.angle = angle
        self.rules = choices.filter { !$0.value.isEmpty }
    }

    /// Whether any symbol has more than one production (so expansion depends on
    /// the random source).
    public var isStochastic: Bool { rules.contains { $0.value.count > 1 } }

    // A safety valve: a rule that grows the string severalfold per pass reaches
    // billions of symbols in a dozen iterations, so expansion stops once a pass
    // would cross this and keeps the last string under it.
    static let maxSymbols = 2_000_000

    /// The string after `iterations` rewrite passes, drawing random productions
    /// (for a stochastic system) from `rng`.
    public func expanded<R: RandomNumberGenerator>(iterations: Int, using rng: inout R) -> String {
        var string = axiom
        for _ in 0 ..< Swift.max(iterations, 0) {
            var next = ""
            next.reserveCapacity(string.count * 2)
            for symbol in string {
                if let productions = rules[symbol] {
                    next += productions.count == 1 ? productions[0] : productions.randomElement(using: &rng)!
                } else {
                    next.append(symbol)
                }
            }
            if next.count > Self.maxSymbols {
                LSystem.warnCapped()
                break
            }
            string = next
        }
        return string
    }

    /// The string after `iterations` passes. For a stochastic system this draws
    /// from a fixed internal source, so pass an `rng` (or use the `Sketch` sugar)
    /// when you want the seed to vary it.
    public func expanded(iterations: Int) -> String {
        var rng = SplitMix64(seed: 0)
        return expanded(iterations: iterations, using: &rng)
    }

    /// The line-work after `iterations` passes, walked by the turtle from `start`
    /// with the given `heading` (degrees; `-90` points up the screen) and `step`
    /// length per `F`. Random productions are drawn from `rng`.
    public func contours<R: RandomNumberGenerator>(
        iterations: Int,
        step: Double = 1,
        start: Vector2 = .zero,
        heading: Double = -90,
        using rng: inout R
    ) -> [Contour] {
        let string = expanded(iterations: iterations, using: &rng)
        return LSystem.turtle(string, angleDegrees: angle, step: step, start: start, headingDegrees: heading)
    }

    /// The line-work after `iterations` passes (deterministic source; see
    /// `expanded(iterations:)`).
    public func contours(iterations: Int, step: Double = 1,
                         start: Vector2 = .zero, heading: Double = -90) -> [Contour] {
        var rng = SplitMix64(seed: 0)
        return contours(iterations: iterations, step: step, start: start, heading: heading, using: &rng)
    }

    // MARK: - Turtle

    /// Walk `string` with a turtle, emitting one open `Contour` per unbroken run
    /// of drawn segments (a branch or the trunk between branch points).
    static func turtle(_ string: String, angleDegrees: Double, step: Double,
                       start: Vector2, headingDegrees: Double) -> [Contour] {
        let turn = angleDegrees * .pi / 180
        var position = start
        var heading = headingDegrees * .pi / 180
        var stack: [(position: Vector2, heading: Double)] = []
        var contours: [Contour] = []
        var current: [Vector2] = [start]

        func flush() {
            if current.count >= 2 { contours.append(Contour(current, closed: false)) }
            current = [position]
        }

        for symbol in string {
            switch symbol {
            case "F", "G":
                if current.isEmpty { current = [position] }
                position = Vector2(position.x + cos(heading) * step,
                                   position.y + sin(heading) * step)
                current.append(position)
            case "f", "g":
                flush()
                position = Vector2(position.x + cos(heading) * step,
                                   position.y + sin(heading) * step)
                current = [position]
            case "+": heading += turn
            case "-": heading -= turn
            case "|": heading += .pi
            case "[": stack.append((position, heading))
            case "]":
                flush()
                if let saved = stack.popLast() { position = saved.position; heading = saved.heading }
                current = [position]
            default: break   // X, Y, and any other symbol: control only, no movement
            }
        }
        flush()
        return contours
    }

    // MARK: - Fit

    /// Scale and center `contours` to fit inside `bounds` (with a `padding`
    /// margin), preserving aspect. The turtle draws at an arbitrary size and
    /// place, so this is what makes a preset fill the canvas regardless of its
    /// iteration count.
    static func fit(_ contours: [Contour], in bounds: Rectangle, padding: Double) -> [Contour] {
        let points = contours.flatMap(\.points)
        guard let first = points.first else { return contours }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in points {
            minX = Swift.min(minX, p.x); maxX = Swift.max(maxX, p.x)
            minY = Swift.min(minY, p.y); maxY = Swift.max(maxY, p.y)
        }
        let spanX = maxX - minX, spanY = maxY - minY
        let target = Rectangle(center: bounds.center,
                               width: Swift.max(bounds.width - 2 * padding, 1),
                               height: Swift.max(bounds.height - 2 * padding, 1))
        let scaleX = spanX > 0 ? target.width / spanX : .infinity
        let scaleY = spanY > 0 ? target.height / spanY : .infinity
        let scale = Swift.min(scaleX, scaleY).isFinite ? Swift.min(scaleX, scaleY) : 1
        let sourceCenter = Vector2((minX + maxX) / 2, (minY + maxY) / 2)
        let targetCenter = target.center
        func map(_ p: Vector2) -> Vector2 {
            Vector2(targetCenter.x + (p.x - sourceCenter.x) * scale,
                    targetCenter.y + (p.y - sourceCenter.y) * scale)
        }
        return contours.map { Contour($0.points.map(map), closed: $0.isClosed) }
    }

    // A best-effort one-time warning when a very growthy rule hits the symbol cap.
    nonisolated(unsafe) private static var didWarnCap = false
    static func warnCapped() {
        if didWarnCap { return }
        didWarnCap = true
        print("Ollin: LSystem expansion hit the \(maxSymbols)-symbol cap; lower the iteration count.")
    }
}

// MARK: - Presets

public extension LSystem {
    /// The Koch curve: a line that grows a square bump on each segment.
    static var kochCurve: LSystem { LSystem(axiom: "F", rules: ["F": "F+F-F-F+F"], angle: 90) }

    /// The Koch snowflake: three Koch curves closed into a star of frost.
    static var kochSnowflake: LSystem { LSystem(axiom: "F++F++F", rules: ["F": "F-F++F-F"], angle: 60) }

    /// The Sierpinski triangle traced as a single connected curve.
    static var sierpinskiTriangle: LSystem {
        LSystem(axiom: "F-G-G", rules: ["F": "F-G+F+G-F", "G": "GG"], angle: 120)
    }

    /// The Sierpinski arrowhead: the same gasket drawn as one unbroken path.
    static var sierpinskiArrowhead: LSystem {
        LSystem(axiom: "F", rules: ["F": "G-F-G", "G": "F+G+F"], angle: 60)
    }

    /// The Heighway dragon: a folded curve that tiles the plane.
    static var dragonCurve: LSystem { LSystem(axiom: "F", rules: ["F": "F+G", "G": "F-G"], angle: 90) }

    /// The Hilbert curve: a space-filling curve that visits every cell of a grid.
    static var hilbertCurve: LSystem {
        LSystem(axiom: "X", rules: ["X": "-YF+XFX+FY-", "Y": "+XF-YFY-FX+"], angle: 90)
    }

    /// The Gosper curve (flowsnake): a hexagonal space-filling curve.
    static var gosperCurve: LSystem {
        LSystem(axiom: "XF",
                rules: ["X": "X+YF++YF-FX--FXFX-YF+", "Y": "-FX+YFYF++YF+FX--FX-Y"],
                angle: 60)
    }

    /// The Lévy C curve: a curve of nested right-angle bends.
    static var levyCurve: LSystem { LSystem(axiom: "F", rules: ["F": "-F++F-"], angle: 45) }

    /// The Peano curve: an early space-filling curve on a square grid.
    static var peanoCurve: LSystem {
        LSystem(axiom: "X",
                rules: ["X": "XFYFX+F+YFXFY-F-XFYFX", "Y": "YFXFY-F-XFYFX+F+YFXFY"],
                angle: 90)
    }

    /// A fern-like plant that branches and droops.
    static var plant: LSystem {
        LSystem(axiom: "X", rules: ["X": "F+[[X]-X]-F[-FX]+X", "F": "FF"], angle: 25)
    }

    /// An upright bushy weed, the classic branching plant.
    static var bush: LSystem {
        LSystem(axiom: "X", rules: ["X": "F-[[X]+X]+F[+FX]-X", "F": "FF"], angle: 22.5)
    }

    /// A symmetric binary tree that forks at every tip.
    static var tree: LSystem { LSystem(axiom: "F", rules: ["F": "FF+[+F-F-F]-[-F+F+F]"], angle: 22.5) }

    /// A stochastic plant: each branch picks one of several productions at
    /// random, so a `seed` grows a unique but plant-like form every time.
    static var randomPlant: LSystem {
        LSystem(axiom: "X",
                choices: ["X": ["F[+X]F[-X]+X", "F[-X]F[+X]-X", "F[+X][-X]FX", "F[-X]F[+X]X"],
                          "F": ["FF"]],
                angle: 22)
    }
}

// MARK: - Sketch sugar

public extension Sketch {
    /// The line-work of an L-system, scaled and centered to fill `bounds` (the
    /// whole canvas by default) with a `padding` margin. Driven by the seeded
    /// `random` for a stochastic system, so `seed(_:)` makes the form
    /// reproducible. Returns open `Contour`s you stroke (or feed to the booleans,
    /// hatching, or SVG export); for the plain case, `drawLSystem` strokes them.
    ///
    /// ```swift
    /// seed(3)
    /// stroke(.white); strokeWeight(2); strokeCap(.round)
    /// for c in lSystem(.plant, iterations: 5) {
    ///     drawPolyline(c.points, closed: false)
    /// }
    /// ```
    func lSystem(_ system: LSystem, iterations: Int,
                 in bounds: Rectangle? = nil, padding: Double = 60) -> [Contour] {
        let raw = system.contours(iterations: iterations, using: &rng)
        return LSystem.fit(raw, in: bounds ?? self.bounds, padding: padding)
    }

    /// Draw an L-system, fit to `bounds` (the canvas by default), with the
    /// current `stroke`. For per-contour color, iterate the `lSystem(…)` value
    /// instead.
    func drawLSystem(_ system: LSystem, iterations: Int,
                     in bounds: Rectangle? = nil, padding: Double = 60) {
        for contour in lSystem(system, iterations: iterations, in: bounds, padding: padding) {
            drawPolyline(contour.points, closed: false)
        }
    }
}
