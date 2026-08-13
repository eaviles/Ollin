import Foundation

// The turtle a grown parametric word is walked by. It is the plain L-system's
// turtle with three additions: every symbol may carry its own number, the pen
// has a width that `[` and `]` save and restore along with the pose, and `%`
// abandons the rest of a branch.
//
// One published symbol takes its meaning from its parameter list rather than its
// letter: with a number, `!` *sets* the width; without one, the reference
// implementation nudges it by an amount declared outside the grammar. There is
// no such outside amount here, so a bare `!` says so once and leaves the width
// where it was.

extension ParametricLSystem {

    /// Walk a grown word, giving one branch per unbroken run of drawn segments.
    /// Each branch carries the width in force at every point of it.
    static func turtle(_ word: ParametricWord, angleDegrees: Double, step: Double,
                       start: Vector2, headingDegrees: Double) -> [LSystemBranch] {
        let defaultTurn = angleDegrees * .pi / 180
        var position = start
        var heading = headingDegrees * .pi / 180
        var width = 1.0
        // Which way a turn goes. A roll of half a turn about the heading leaves
        // the drawing plane exactly where it was and only swaps the turtle's
        // idea of left for right, so it costs one sign rather than a dimension.
        var handedness = 1.0
        var stack: [(position: Vector2, heading: Double, width: Double, handedness: Double)] = []
        var branches: [LSystemBranch] = []
        var points: [Vector2] = [start]
        var widths: [Double] = [1]

        func flush() {
            if points.count >= 2 { branches.append(LSystemBranch(points: points, widths: widths)) }
            points = [position]
            widths = [width]
        }

        func advanced(_ length: Double) -> Vector2 {
            Vector2(position.x + cos(heading) * length, position.y + sin(heading) * length)
        }

        var i = 0
        while i < word.count {
            let letter = word.letter(i)
            let parameter = word.firstParameter(i)

            switch letter {
            case UInt8(ascii: "F"), UInt8(ascii: "G"):
                position = advanced((parameter ?? 1) * step)
                points.append(position)
                widths.append(width)

            case UInt8(ascii: "f"), UInt8(ascii: "g"):
                flush()
                position = advanced((parameter ?? 1) * step)
                points = [position]
                widths = [width]

            case UInt8(ascii: "+"):
                heading += handedness * (parameter.map { $0 * .pi / 180 } ?? defaultTurn)
            case UInt8(ascii: "-"):
                heading -= handedness * (parameter.map { $0 * .pi / 180 } ?? defaultTurn)
            case UInt8(ascii: "|"):
                heading += .pi

            // A roll turns the turtle about its own heading. Half a turn of it
            // keeps the drawing plane and only swaps left for right; a whole
            // turn changes nothing. Any other roll leaves the plane, so it is
            // the only case this turtle has to decline.
            case UInt8(ascii: "\\"), UInt8(ascii: "/"):
                guard let turns = halfTurns(parameter ?? angleDegrees) else {
                    report(complaint(about: letter)); break
                }
                if turns % 2 != 0 { handedness = -handedness }

            // A pitch turns the turtle about its own left. Half a turn of it
            // reverses the heading within the plane and swaps left for right.
            case UInt8(ascii: "&"), UInt8(ascii: "^"):
                guard let turns = halfTurns(parameter ?? angleDegrees) else {
                    report(complaint(about: letter)); break
                }
                if turns % 2 != 0 { heading += .pi; handedness = -handedness }

            case UInt8(ascii: "["):
                stack.append((position, heading, width, handedness))
            case UInt8(ascii: "]"):
                flush()
                if let saved = stack.popLast() {
                    position = saved.position
                    heading = saved.heading
                    width = saved.width
                    handedness = saved.handedness
                }
                points = [position]
                widths = [width]

            case UInt8(ascii: "!"), UInt8(ascii: "#"):
                guard let parameter else {
                    report("'\(Character(UnicodeScalar(letter)))' with no width after it steps the width by an amount declared outside the grammar, which Ollin has none of; write '!(w)' to set a width.")
                    break
                }
                width = Swift.max(parameter, 0)
                // A width set before anything has been drawn from the current
                // point belongs to the segment about to leave it, which is how
                // every published tree writes it: "!(w)F(l)".
                if widths.count == 1 { widths[0] = width }

            case UInt8(ascii: "%"):
                // Abandon the rest of this branch: skip to the `]` that closes
                // it, which then pops in the ordinary way.
                var depth = 0
                var j = i + 1
                while j < word.count {
                    let skipped = word.letter(j)
                    if skipped == UInt8(ascii: "[") {
                        depth += 1
                    } else if skipped == UInt8(ascii: "]") {
                        if depth == 0 { break }
                        depth -= 1
                    }
                    j += 1
                }
                i = j
                continue

            default:
                if unrepresented[letter] != nil { report(complaint(about: letter)) }
            }
            i += 1
        }
        flush()
        return branches
    }

    /// How many half-turns `degrees` is, or `nil` when it is not a whole number
    /// of them and so leaves the plane.
    static func halfTurns(_ degrees: Double) -> Int? {
        let turns = degrees / 180
        let whole = turns.rounded()
        guard Swift.abs(turns - whole) < 1e-9, Swift.abs(whole) < 1e9 else { return nil }
        return Int(whole)
    }

    static func complaint(about letter: UInt8) -> String {
        let symbol = Character(UnicodeScalar(letter))
        guard let what = unrepresented[letter] else {
            return "the symbol '\(symbol)' draws nothing here."
        }
        return "the symbol '\(symbol)' \(what), which this turtle draws in the plane; it was rewritten as usual but drew nothing."
    }

    /// The published symbols this plane-drawing turtle carries but cannot show,
    /// each with what it would have done. Rolls and pitches are absent because
    /// they are only refused for the angles that genuinely leave the plane.
    /// Anything else, `A` and `X` and the rest, steers the rewriting and is
    /// meant to draw nothing, so it says nothing either.
    static let unrepresented: [UInt8: String] = [
        UInt8(ascii: "\\"): "rolls the turtle out of the plane",
        UInt8(ascii: "/"): "rolls the turtle out of the plane",
        UInt8(ascii: "&"): "pitches the turtle out of the plane",
        UInt8(ascii: "^"): "pitches the turtle out of the plane",
        UInt8(ascii: "$"): "rolls the turtle level with the ground",
        UInt8(ascii: "{"): "begins a filled polygon",
        UInt8(ascii: "}"): "closes a filled polygon",
        UInt8(ascii: "~"): "places a prepared surface",
        UInt8(ascii: "'"): "steps through a color table",
        UInt8(ascii: ";"): "steps forward through a color table",
        UInt8(ascii: ","): "steps back through a color table",
        UInt8(ascii: "@"): "is one of the reference implementation's own commands",
    ]

    /// Scale and centre branches to fill `bounds`, keeping their widths. Shares
    /// its transform with the plain L-system's fit, so a parametric form and a
    /// symbolic one land the same way in the same frame.
    static func fit(_ branches: [LSystemBranch], in bounds: Rectangle,
                    padding: Double) -> [LSystemBranch] {
        guard let place = LSystem.fitTransform(for: branches.flatMap(\.points),
                                               in: bounds, padding: padding) else {
            return branches
        }
        return branches.map { LSystemBranch(points: $0.points.map(place), widths: $0.widths) }
    }
}

// MARK: - Sketch sugar

public extension Sketch {

    /// The line-work of a parametric L-system, scaled and centred to fill
    /// `bounds` (the whole canvas by default) with a `padding` margin. Driven by
    /// the seeded `random` for a stochastic system, so `seed(_:)` makes the form
    /// reproducible.
    ///
    /// ```swift
    /// stroke(.white); strokeWeight(2); noFill()
    /// for branch in lSystem(.selfSimilarBranch, iterations: 9) {
    ///     drawPolyline(branch.points, closed: false)
    /// }
    /// ```
    func lSystem(_ system: ParametricLSystem, iterations: Int,
                 in bounds: Rectangle? = nil, padding: Double = 60) -> [Contour] {
        let raw = system.branches(iterations: iterations, step: 1,
                                  start: .zero, heading: -90, using: &rng)
        return ParametricLSystem.fit(raw, in: bounds ?? self.bounds, padding: padding)
            .map { Contour($0.points, closed: false) }
    }

    /// The line-work of a parametric L-system as marks that **carry the width**
    /// each `!(w)` asked for, fit to `bounds` and ready for `drawMark(_:)`.
    /// Widths are multiples of `strokeWeight`, scaled so the widest is 1, so
    /// `strokeWeight` sets the thickness of the trunk.
    ///
    /// ```swift
    /// stroke(.white); strokeWeight(14)
    /// for mark in lSystemMarks(.taperedTree(), iterations: 10) { drawMark(mark) }
    /// ```
    func lSystemMarks(_ system: ParametricLSystem, iterations: Int,
                      in bounds: Rectangle? = nil, padding: Double = 60) -> [StrokeMark] {
        let raw = system.branches(iterations: iterations, step: 1,
                                  start: .zero, heading: -90, using: &rng)
        return ParametricLSystem.marks(from: ParametricLSystem.fit(raw, in: bounds ?? self.bounds,
                                                                   padding: padding))
    }

    /// Draw a parametric L-system, fit to `bounds` (the canvas by default), with
    /// the current `stroke`. Ask for `tapered` and the widths the grammar sets
    /// with `!(w)` are drawn too, `strokeWeight` setting the trunk; for
    /// per-branch color, iterate `lSystem(…)` or `lSystemMarks(…)` instead.
    func drawLSystem(_ system: ParametricLSystem, iterations: Int,
                     in bounds: Rectangle? = nil, padding: Double = 60,
                     tapered: Bool = false) {
        if tapered {
            for mark in lSystemMarks(system, iterations: iterations, in: bounds, padding: padding) {
                drawMark(mark)
            }
        } else {
            for contour in lSystem(system, iterations: iterations, in: bounds, padding: padding) {
                drawPolyline(contour.points, closed: false)
            }
        }
    }
}
