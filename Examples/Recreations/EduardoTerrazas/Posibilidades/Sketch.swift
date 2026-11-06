//  Recreation after Eduardo Terrazas - Posibilidades de una estructura (from
//  the early 1970s): the drawings and tablas that work one structure over and
//  over by changing its lines and the spaces between them. A homage, not a
//  reproduction of any one work, and not affiliated with or endorsed by the
//  artist or his galleries.
//  https://eduardoterrazas.com/index.php/possibilities-of-a-structure/
//  https://www.artic.edu/artworks/239806
//
//  An original Ollin interpretation, written from the structure as the artist
//  states it and from the operations the Museo del Palacio de Bellas Artes
//  names for the series. Nothing was ported: the works are ink on paper and
//  yarn on wax.

import Foundation
import Ollin

/// Posibilidades de una estructura (Eduardo Terrazas, from the early
/// 1970s). The series is one diagram and what can be done to it. The
/// diagram of its largest subseries is a square, the circle that fills it,
/// the horizontal and the vertical, the two diagonals, a second square
/// turned 45 degrees, and a small circle at the center. The museum that
/// showed his work of 1968 to 2023 says where the variation happens: in the
/// lines (multiplication, repetition, subtraction, widening, a change of
/// color) or in the spaces between them (shading, emptiness, coloring,
/// filling).
///
/// This sketch is a sheet of `across` by `across` small drawings, each the
/// same structure after one operation. **coloring** fills every field,
/// neighbors free to share. **widening** draws the lines as white or black
/// bands over the fields. **multiplication** repeats lines beside
/// themselves, the circles as concentric rings or the straight lines as
/// parallels, and colors the fields in turn so no two that share an edge
/// match. **subtraction** leaves some lines out, and the fields they
/// divided become one. **shading** rules every other field with stripes.
/// **emptiness** leaves some fields as bare paper. **repetition** draws the
/// structure four times in the square. `operation` holds the sheet to one
/// of them, or deals them across it.
///
/// Every drawing is made the same way: the lines that are left go to
/// `regions(enclosedBy:)`, which hands back every field they wall off as a
/// closed shape, and the operation colors the shapes. The fields are never
/// listed by hand, so a line taken out or put in changes them with no other
/// code. The seed deals every drawing; over one cycle of `seconds` each
/// drawing in turn is redrawn as another possibility, field by field, and
/// then each is drawn back, which is also the export loop.
///
/// `--export-svg` writes each field as a closed outline in its color and the
/// widened lines as strokes, ready for a plotter or a cutter.
@main
final class Posibilidades: Sketch {
    enum Operation: String, CaseIterable, ParamOption {
        case all, coloring, widening, multiplication, subtraction, shading, emptiness, repetition
    }

    /// The drawings on a side of the sheet.
    @Param(1 ... 5, icon: "square.grid.3x3") var across = 3
    /// One operation for the whole sheet, or all of them dealt across it.
    @Param(icon: "wand.and.rays") var operation = Operation.all
    /// How many colors a drawing is filled with.
    @Param(2 ... 8, icon: "paintpalette") var colors = 5
    /// The small circle's radius as a part of the large one's.
    @Param(0.3 ... 0.55, icon: "circle.circle") var earth = 0.414
    /// Whether each drawing's operation is written under it.
    @Param(icon: "textformat") var namesOperations = true
    /// One cycle: every drawing redrawn, and drawn back.
    @Param(8 ... 120, icon: "clock") var seconds = 27.0

    override var canvasSize: CanvasSize { .square(1080) }
    override var loopDuration: Double? { seconds }

    private let paper = Color(hex: 0xF3F0E8)
    private let ink = Color(hex: 0x16161A)
    private let white = Color(hex: 0xFBFAF6)
    private let gouache: [Color] = [
        Color(hex: 0xC8102E), Color(hex: 0x1D4E9E), Color(hex: 0xF2C230), Color(hex: 0x1E7A46),
        Color(hex: 0xF28C28), Color(hex: 0xD12C8A), Color(hex: 0x4BA3D9), Color(hex: 0x6A3FA0),
    ]

    // MARK: - The structure's lines

    /// One line of a drawing, in units of half the drawing's side from its
    /// middle: a straight line across it, a circle, or a turned square.
    enum Member: Hashable {
        case line(Vector2, Vector2)
        case circle(center: Vector2, radius: Double)
        case turned(center: Vector2, reach: Double)

        /// Which side of the line a point is on: inside a circle or a turned
        /// square, or to the left of a straight line as it is drawn.
        func holds(_ q: Vector2) -> Bool {
            switch self {
            case let .line(a, b):
                return (b.x - a.x) * (q.y - a.y) - (b.y - a.y) * (q.x - a.x) > 0
            case let .circle(center, radius):
                return (q - center).length < radius
            case let .turned(center, reach):
                return abs(q.x - center.x) + abs(q.y - center.y) < reach
            }
        }

        /// The line as an outline, in pixels.
        func contour(center c: Vector2, half h: Double) -> Contour {
            switch self {
            case let .line(a, b):
                return Contour([c + a * h, c + b * h], closed: false)
            case let .circle(center, radius):
                return Circle(center: c + center * h, radius: radius * h).contour(segments: 128)
            case let .turned(center, reach):
                let m = c + center * h, r = reach * h
                return Contour([m + Vector2(r, 0), m + Vector2(0, r), m + Vector2(-r, 0), m + Vector2(0, -r)],
                               closed: true)
            }
        }
    }

    /// The structure, about `center`, `size` half-sides across: the circle,
    /// the turned square, the small circle, the two axes, the two diagonals.
    nonisolated static func structure(center: Vector2 = .zero, size: Double = 1, earth: Double) -> [Member] {
        let s = size
        func at(_ x: Double, _ y: Double) -> Vector2 { center + Vector2(x, y) * s }
        return [
            .circle(center: center, radius: s),
            .turned(center: center, reach: s),
            .circle(center: center, radius: s * earth),
            .line(at(-1, 0), at(1, 0)),
            .line(at(0, -1), at(0, 1)),
            .line(at(-1, -1), at(1, 1)),
            .line(at(-1, 1), at(1, -1)),
        ]
    }

    // MARK: - One drawing

    /// A drawing ready to draw: its fields in the order they are put down,
    /// each with its color (nil is bare paper), and the lines drawn over
    /// them, if the operation widens them.
    struct Drawing {
        var operation: Operation
        var fields: [(shape: Shape, color: Color?)]
        var lines: [Contour] = []
        var lineColor: Color = .black
        var lineWidth = 0.0
        /// The drawing's own square: its lines are cut off at it.
        var square = Rectangle(x: 0, y: 0, width: 0, height: 0)
    }

    /// A point inside a shape: halfway between the first two places a level
    /// line through its middle crosses its outline.
    nonisolated static func pointInside(_ shape: Shape) -> Vector2 {
        guard let bounds = shape.bounds else { return .zero }
        for step in [0.5, 0.37, 0.63, 0.21, 0.79] {
            let y = bounds.y + bounds.height * step + 1e-4
            var crossings: [Double] = []
            for contour in shape.contours {
                let points = contour.points
                for i in points.indices {
                    let a = points[i], b = points[(i + 1) % points.count]
                    if (a.y > y) != (b.y > y) { crossings.append(a.x + (y - a.y) / (b.y - a.y) * (b.x - a.x)) }
                }
            }
            crossings.sort()
            if crossings.count >= 2, crossings[1] - crossings[0] > 1e-6 {
                return Vector2((crossings[0] + crossings[1]) / 2, y)
            }
        }
        return shape.centroid
    }

    /// The drawing for one cell of the sheet: deal the operation's choices
    /// from the seed, cut the fields from the lines that result, and color
    /// them by the operation's rule.
    private func drawing(_ kind: Operation, seed: Int, center c: Vector2, half h: Double) -> Drawing {
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(seed &* 2_654_435_761 &+ 97)))
        func unit() -> Double { Double(rng.next() >> 11) / Double(1 << 53) }
        func pick(_ count: Int) -> Int { min(count - 1, Int(unit() * Double(count))) }

        // The colors this drawing uses: a run of the set from a dealt start.
        let start = pick(gouache.count)
        let set = (0 ..< colors).map { gouache[(start + $0 * 3) % gouache.count] }
        let frame = Rectangle(x: c.x - h, y: c.y - h, width: 2 * h, height: 2 * h).contour
        var members = Posibilidades.structure(earth: earth)
        var result = Drawing(operation: kind, fields: [])
        result.square = Rectangle(x: c.x - h, y: c.y - h, width: 2 * h, height: 2 * h)

        /// Color by turn: a field's number is how many of the lines hold it,
        /// so two fields that share an edge differ by one.
        func byTurn(_ shapes: [Shape], _ cycle: [Color?]) -> [(shape: Shape, color: Color?)] {
            shapes.map { shape in
                let q = (Posibilidades.pointInside(shape) - c) / h
                return (shape, cycle[members.filter { $0.holds(q) }.count % cycle.count])
            }
        }
        func dealt(_ shapes: [Shape], empty: Double = 0) -> [(shape: Shape, color: Color?)] {
            shapes.map { ($0, unit() < empty ? nil : set[pick(set.count)]) }
        }
        func cut() -> [Shape] {
            regions(enclosedBy: [frame] + members.map { $0.contour(center: c, half: h) })
        }

        switch kind {
        case .all, .coloring:
            result.fields = dealt(cut())

        case .widening:
            result.fields = dealt(cut())
            result.lines = [frame] + members.map { $0.contour(center: c, half: h) }
            result.lineColor = unit() < 0.5 ? white : ink
            result.lineWidth = h * (0.035 + 0.045 * unit())

        case .multiplication:
            let straight = members.filter { if case .line = $0 { return true } else { return false } }
            if unit() < 0.5 {
                // The circles, repeated inward as rings.
                let rings = 4 + pick(6)
                members = straight + (1 ... rings).map { .circle(center: .zero, radius: Double($0) / Double(rings)) }
            } else {
                // The straight lines, each repeated beside itself.
                let copies = 2 + pick(2), gap = 0.07 + 0.06 * unit()
                var repeated: [Member] = members.filter { !straight.contains($0) }
                for case let .line(a, b) in straight {
                    let across = (b - a).perpendicular.normalized
                    // Run each copy well past the square, so it is cut by the frame.
                    let far = (b - a).normalized * 3
                    for copy in 0 ..< copies {
                        let shift = across * (Double(copy) - Double(copies - 1) / 2) * gap
                        repeated.append(.line((a + b) / 2 + shift - far, (a + b) / 2 + shift + far))
                    }
                }
                members = repeated
            }
            let third: [Color?] = unit() < 0.4 ? [set[0], set[1 % set.count], white] : [set[0], white]
            result.fields = byTurn(cut(), third)

        case .subtraction:
            let leave = 2 + pick(3)
            for _ in 0 ..< leave where members.count > 2 { members.remove(at: pick(members.count)) }
            result.fields = unit() < 0.5 ? dealt(cut()) : byTurn(cut(), [set[0], set[1 % set.count]])

        case .shading:
            // Fields taken in turn: one flat, the next ruled, so a ruled
            // field always lies between flat ones.
            let spacing = h * (0.05 + 0.04 * unit())
            let flats = Array(set.prefix(max(1, set.count / 2)))
            let ruled = Array(set.suffix(max(1, set.count - flats.count)))
            for field in cut() {
                let q = (Posibilidades.pointInside(field) - c) / h
                let number = members.filter { $0.holds(q) }.count
                guard number % 2 == 1, let bounds = field.bounds else {
                    result.fields.append((field, flats[pick(flats.count)]))
                    continue
                }
                // Rule the field: parallel lines across its bounds, the
                // strips between them alternately a color and white.
                let base = ruled[pick(ruled.count)]
                let angle = Double(pick(4)) * .pi / 4
                let along = Vector2(angle: angle, length: 1), across = along.perpendicular
                let middle = bounds.center, span = max(bounds.width, bounds.height)
                let count = Int(span / spacing) + 2
                var rules: [Contour] = []
                for i in -count ... count {
                    let at = middle + across * (Double(i) * spacing)
                    rules.append(Contour([at - along * span * 2, at + along * span * 2], closed: false))
                }
                for strip in regions(enclosedBy: field.contours + rules) {
                    let offset = (Posibilidades.pointInside(strip) - middle).dot(across) / spacing
                    let even = Int(floor(offset)) % 2 == 0
                    result.fields.append((strip, even ? base : white))
                }
            }

        case .emptiness:
            result.fields = dealt(cut(), empty: 0.45)
            result.lines = [frame] + members.map { $0.contour(center: c, half: h) }
            result.lineColor = ink
            result.lineWidth = max(1, h * 0.008)

        case .repetition:
            members = [.line(Vector2(-1, 0), Vector2(1, 0)), .line(Vector2(0, -1), Vector2(0, 1))]
            for corner in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(-0.5, 0.5), Vector2(0.5, 0.5)] {
                members += Posibilidades.structure(center: corner, size: 0.5, earth: earth)
            }
            result.fields = unit() < 0.5 ? dealt(cut())
                : byTurn(cut(), [set[0], white, set[1 % set.count], white])
        }
        return result
    }

    // MARK: - The sheet

    private var kept: [String: Drawing] = [:]

    /// The operation a cell draws at a generation: the one the sheet is held
    /// to, or one dealt so that a sheet shows as many as it has room for.
    private func operation(cell: Int, generation: Int) -> Operation {
        guard operation == .all else { return operation }
        let kinds = Operation.allCases.filter { $0 != .all }
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(variation &* 7_919 &+ 13)))
        let turn = Int(rng.next() % UInt64(kinds.count))
        return kinds[(cell * 3 + generation * 4 + turn) % kinds.count]
    }

    private func drawing(cell: Int, generation: Int, center: Vector2, half: Double) -> Drawing {
        let kind = operation(cell: cell, generation: generation)
        let name = "\(variation)/\(cell)/\(generation)/\(kind.rawValue)/\(across)/\(colors)/\(earth)"
        if let found = kept[name] { return found }
        if kept.count > 120 { kept.removeAll() }
        let made = drawing(kind, seed: variation &* 131 &+ cell &* 17 &+ generation &* 7_001,
                           center: center, half: half)
        kept[name] = made
        return made
    }

    private func put(_ drawing: Drawing, fields count: Int? = nil) {
        noStroke()
        for field in drawing.fields.prefix(count ?? drawing.fields.count) {
            guard let color = field.color else { continue }
            fill(color)
            drawShape(field.shape)
        }
        guard drawing.lineWidth > 0, count == nil || count == drawing.fields.count else { return }
        // The lines stop at the drawing's edge. The square's own line is
        // drawn at twice the width, so the half inside is a whole band.
        withClip(drawing.square) {
            noFill()
            stroke(drawing.lineColor)
            strokeJoin(.miter)
            for (index, line) in drawing.lines.enumerated() {
                strokeWeight(index == 0 ? drawing.lineWidth * 2 : drawing.lineWidth)
                drawPolyline(line.points, closed: line.isClosed)
            }
        }
    }

    override func draw() {
        background(paper)
        let cells = across * across
        let margin = 70.0, gap = across > 3 ? 34.0 : 46.0
        let side = (width - 2 * margin - gap * Double(across - 1)) / Double(across)

        // The order the drawings change in, and where the cycle is: each is
        // redrawn in turn through the first half, and drawn back in the second.
        var order = Array(0 ..< cells)
        var rng = SplitMix64(seed: UInt64(bitPattern: Int64(variation &* 31 &+ 5)))
        for i in stride(from: cells - 1, to: 0, by: -1) { order.swapAt(i, Int(rng.next() % UInt64(i + 1))) }
        let place = loopProgress(over: seconds) * Double(2 * cells)
        let step = min(2 * cells - 1, Int(place)), within = place - Double(step)

        for cell in 0 ..< cells {
            let column = cell % across, row = cell / across
            let center = Vector2(margin + side / 2 + Double(column) * (side + gap),
                                 margin + side / 2 + Double(row) * (side + gap) - 8)
            let turn = order.firstIndex(of: cell) ?? 0
            // The generation this drawing has reached, and the one it is
            // being redrawn as, if this is its step.
            let changed = step > turn && step <= turn + cells
            let settled = changed ? 1 : 0
            let changing = step == turn || step == turn + cells
            let before = changing ? (step == turn ? 0 : 1) : settled

            noStroke()
            fill(white)
            drawRect(center: center, width: side, height: side)
            let old = drawing(cell: cell, generation: before, center: center, half: side / 2)
            put(old)
            var shown = old
            if changing {
                let new = drawing(cell: cell, generation: 1 - before, center: center, half: side / 2)
                // A step rests on the sheet as it stands, then redraws.
                let t = max(0, (within - 0.4) / 0.6)
                let count = Int((t * t * (3 - 2 * t) * Double(new.fields.count)).rounded(.up))
                if count > 0 {
                    // The paper first, under the fields put down so far, so a
                    // bare field of the new drawing covers the old one.
                    fill(white)
                    for field in new.fields.prefix(count) { drawShape(field.shape) }
                    put(new, fields: count)
                }
                if count == new.fields.count { shown = new }
            }
            noFill()
            stroke(ink)
            strokeWeight(1.5)
            drawRect(center: center, width: side, height: side)
            if namesOperations, !isVectorExporting {
                drawText(shown.operation.rawValue, center.x, center.y + side / 2 + 12, size: 13,
                         color: Color(white: 0, alpha: 0.5), align: .center, .top)
            }
        }
    }
}
