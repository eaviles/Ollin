//  Recreation after Frieder Nake - "13/9/65 Nr. 3" and "13/9/65 Nr. 7" (1965),
//  the two plotter drawings titled "Zufälliger Polygonzug" (random polygon):
//  one line that turns only in a few permitted directions. A homage, not a
//  reproduction, and not affiliated with or endorsed by the artist.
//  http://dada.compart-bremen.de/item/artwork/1326
//
//  An original Ollin interpretation written from the description of the
//  drawing in the compArt database (one polygonal line; at each vertex the
//  direction and the length of the next edge are chosen by chance; the
//  direction from a short list, the horizontal, two oblique directions, and
//  slight deviations from the vertical) and from Nake's own list of its random
//  elements in Programm-Information PI-21 (the number of vertices, the
//  direction of each edge, the length of each edge). No source was ported: the
//  drawings were made on a Zuse Graphomat Z64 from a machine-language program
//  for the ER56 that is not the program here. The weights of the directions,
//  the angle of the oblique ones, the distribution of the lengths, and what
//  happens at the frame are this sketch's own, tuned by eye against the two
//  sheets.

import Ollin

/// "Zufälliger Polygonzug" (Frieder Nake, 13 September 1965) is one line. It
/// starts somewhere on the sheet, and at every vertex the program rolls two
/// things: which way to go next, and how far. A random polygon was the
/// simplest drawing a computer could make in 1965, and the usual one let the
/// line leave in any direction with the same chance, which gives a tangle.
///
/// This one restricts the roll. Only four kinds of direction are allowed: the
/// horizontal, two oblique directions that mirror each other, and the
/// vertical, which alone may lean a little. The result is a drawing that looks
/// composed: parallel lines, triangles, and trapezoids appear because the same
/// few directions keep coming back, and the long uprights that lean by a
/// degree or two gather into bundles. Two drawings were plotted the same night
/// from the same settings, Nr. 3 and Nr. 7. What they show is how much the
/// choice of a probability distribution does to even so simple a scheme.
///
/// Three things are rolled, as he listed them: the number of vertices, the
/// direction of each edge, and its length. Here the directions are weighted
/// (`uprights` is the share of near-vertical edges; the rest goes half to the
/// horizontal and a quarter to each oblique), each direction is taken either
/// way with equal chance, and a length is rolled from an exponential
/// distribution whose mean is `span` of the frame, so most edges are a short
/// step and a few cross the sheet. An edge that would leave the frame stops on
/// it; a roll that points out of the frame from a point on it goes the other
/// way instead.
///
/// Try it: `sheetSeed` is the whole piece. `oblique` is the angle of the two
/// slanted directions (60 makes triangles with equal sides), `lean` is how far
/// an upright may tip, and `reach` is how much longer the uprights run than
/// the rest. With `uprights` at 0 and `oblique` at 90 every edge is level or
/// plumb, a kind of polygon he had drawn that February. The line exports as
/// one stroke, so `--export-svg` gives the plotter drawing back.
@main
final class RandomPolygon: Sketch {

    /// How many vertices the line has, give or take a quarter: the number
    /// itself is rolled.
    @Param(20...600) var vertices = 220
    /// The mean length of an edge, as a share of the frame's side.
    @Param(0.02...0.3) var span = 0.11
    /// The share of edges that are near-vertical.
    @Param(0...1) var uprights = 0.3
    /// How many times longer the near-vertical edges run.
    @Param(1...6) var reach = 2.0
    /// The angle of the two oblique directions above the horizontal, in
    /// degrees.
    @Param(30...90) var oblique = 60.0
    /// The most a near-vertical edge may lean, in degrees.
    @Param(0...10) var lean = 1.5
    /// Seconds for one lap: the finished sheet, a clean one, and the pen.
    @Param(8...120) var cycle = 24.0
    @Param(1...9999, icon: "dice") var sheetSeed = 31

    override var loopDuration: Double? { cycle }

    // MARK: The program

    /// The four kinds of direction, in the order a roll reads their weights.
    enum Kind: Int, CaseIterable { case upright, horizontal, rising, falling }

    /// The chance of each kind of direction.
    static func weights(uprights: Double) -> [Double] {
        let rest = 1 - uprights
        return [uprights, rest / 2, rest / 4, rest / 4]
    }

    /// How far a point at `point` can travel along `direction` before it
    /// meets the unit frame.
    static func room(from point: Vector2, along direction: Vector2) -> Double {
        var room = Double.infinity
        if direction.x > 0 { room = min(room, (1 - point.x) / direction.x) }
        if direction.x < 0 { room = min(room, -point.x / direction.x) }
        if direction.y > 0 { room = min(room, (1 - point.y) / direction.y) }
        if direction.y < 0 { room = min(room, -point.y / direction.y) }
        return max(room, 0)
    }

    /// The vertices of the line in a frame one unit wide and high. Every edge
    /// takes four rolls in the same order (its kind, which way along it, its
    /// lean, its length), whether it uses them all or not.
    static func line(seed: UInt64, vertices: Int, span: Double, uprights: Double,
                     reach: Double, oblique: Double, lean: Double) -> [Vector2] {
        var generator = SplitMix64(seed: seed)
        func roll() -> Double { Double(generator.next() >> 11) * 0x1p-53 }

        let count = Int((Double(vertices) * (0.75 + 0.5 * roll())).rounded())
        var point = Vector2(roll(), roll())
        var points = [point]
        let chances = Self.weights(uprights: uprights)
        let slant = oblique * .pi / 180

        for _ in 1 ..< max(count, 2) {
            let kindRoll = roll(), backward = roll() < 0.5
            let tip = (2 * roll() - 1) * lean * .pi / 180
            let steps = -log(1 - roll())

            var kind = Kind.falling
            var sum = 0.0
            for candidate in Kind.allCases {
                sum += chances[candidate.rawValue]
                if kindRoll < sum { kind = candidate; break }
            }
            var direction: Vector2
            var length = span * steps
            switch kind {
            case .upright:
                direction = Vector2(sin(tip), -cos(tip))
                length *= reach
            case .horizontal: direction = Vector2(1, 0)
            case .rising: direction = Vector2(cos(slant), -sin(slant))
            case .falling: direction = Vector2(cos(slant), sin(slant))
            }
            if backward { direction = Vector2(-direction.x, -direction.y) }

            // Stop on the frame; from a point on it, a roll that points out
            // goes the other way.
            var travel = min(length, room(from: point, along: direction))
            if travel <= 1e-9 {
                direction = Vector2(-direction.x, -direction.y)
                travel = min(length, room(from: point, along: direction))
            }
            if travel <= 1e-9 { continue }
            point = Vector2(min(max(point.x + direction.x * travel, 0), 1),
                            min(max(point.y + direction.y * travel, 0), 1))
            points.append(point)
        }
        return points
    }

    /// The share of the line drawn at `lap` (0 to 1 of the cycle) and how much
    /// ink the sheet carries. The lap opens on the finished sheet, clears it,
    /// and draws it again.
    static func stage(at lap: Double) -> (drawn: Double, ink: Double) {
        let hold = 0.2, clear = 0.28, done = 0.97
        if lap < hold { return (1, 1) }
        if lap < clear {
            let gone = (lap - hold) / (clear - hold)
            return (1, 1 - gone * gone * (3 - 2 * gone))
        }
        return (min(1, (lap - clear) / (done - clear)), 1)
    }

    // MARK: The sheet

    let paper = Color(hex: 0xF4F1EA)
    let pen = Color(hex: 0x15130F)
    let head = Color(hex: 0xD8432B)

    override func draw() {
        background(paper)
        let stage = Self.stage(at: loopProgress(over: cycle))

        let side = min(width, height) * 0.8
        let frame = Rectangle(center: center, width: side, height: side)
        let line = Self.line(seed: UInt64(sheetSeed), vertices: vertices, span: span,
                             uprights: uprights, reach: reach, oblique: oblique, lean: lean)
            .map { Vector2(frame.x + $0.x * side, frame.y + $0.y * side) }

        // The frame the line may not leave, as the sheet in Bremen has it.
        noFill()
        stroke(pen)
        strokeWeight(1.2 * scale)
        strokeJoin(.miter)
        drawRect(frame.x, frame.y, side, side)

        // The pen moves at one speed, so the share drawn is a share of the
        // line's length.
        var lengths: [Double] = [0]
        for index in 1 ..< line.count {
            lengths.append(lengths[index - 1] + (line[index] - line[index - 1]).length)
        }
        let reached = (lengths.last ?? 0) * stage.drawn
        var drawn: [Vector2] = []
        for index in line.indices {
            if lengths[index] <= reached {
                drawn.append(line[index])
            } else {
                let from = line[index - 1], edge = lengths[index] - lengths[index - 1]
                drawn.append(from + (line[index] - from) * ((reached - lengths[index - 1]) / edge))
                break
            }
        }

        stroke(pen.withAlpha(stage.ink))
        strokeWeight(1.7 * scale)
        strokeJoin(.round)
        strokeCap(.round)
        drawPolyline(drawn)

        // Where the pen is.
        if stage.drawn < 1, let tip = drawn.last {
            noStroke()
            fill(head)
            drawCircle(center: tip, radius: 5 * scale)
        }
    }
}
