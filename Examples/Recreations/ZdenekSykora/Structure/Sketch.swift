//  Recreation after Zdeněk Sýkora - the Structures (Struktury, from 1964),
//  black and white paintings whose elements were placed by a program he made
//  with the mathematician Jaroslav Blažek for an LGP-30 computer, after the
//  rule the two of them published in "Computer-Aided Multi-Element
//  Geometrical Abstract Paintings", Leonardo 3, no. 4 (1970). A homage, not a
//  reproduction, and not affiliated with or endorsed by the artist or his
//  estate.
//  http://www.zdeneksykora.cz/
//  https://doi.org/10.2307/1572257
//
//  An original Ollin interpretation, written from the rule as Martina Losová
//  rebuilt it from the article (Palacký University Olomouc, 2010) and from
//  what Sýkora said of it in interviews. Nothing was ported: no program text
//  was ever printed, and the paintings were painted by hand from a typed
//  table. Two details the descriptions leave open were read off the table
//  printed with the article: a rule's "does not continue" means no placed
//  neighbor continues, and a density halfway between two groups goes to the
//  lighter one. The chart each seed starts from is this sketch's own.

import Ollin

/// Structure (Zdeněk Sýkora, Prague, from 1964). A painter who had come to
/// geometry by way of landscape asked a friend from his home town, the
/// mathematician Jaroslav Blažek, whether a computer could do the combinatorics
/// his paintings had come to need. Sýkora drew a set of twenty elements, each
/// a square holding half-discs of half its width, white on black or black on
/// white, and four rules for how an element may meet the ones beside it.
/// Blažek put the rules into the language of an LGP-30. Sýkora drew a chart
/// with a few elements already placed and plus and minus signs where the
/// picture should darken or lighten, the machine filled the rest and typed it
/// as a table of codes, and he painted the table in oil, with airbrushes and
/// templates. He called the set and the rules the two creative acts, and
/// said that choosing among the rules and changing the chart was how one
/// painting came to differ from the next.
///
/// This sketch keeps the rule as the two of them published it. The twenty
/// elements fall into four groups by how much of them is black, and the
/// program walks the chart row by row, left to right and then back right to
/// left, so a dark edge does not smear one way across the picture. At each
/// empty cell it averages the groups of the placed cells around it, by side
/// or by corner, adds `coefficient` under a plus or takes it away under a
/// minus, and takes the nearest group. Then it asks the cells beside it
/// whether the color continues across the shared side (the same paint on
/// both edges) and whether the shape does (two half-discs meeting in a full
/// circle). `rule` is which answer it wants: both, the color only, the shape
/// only, or neither. The color is asked first, then the shape, a question no
/// element can answer is dropped, and when several elements remain the
/// machine draws one at random. `columns` and `rows` are the chart; `inputs`
/// is the share of cells placed by hand before the run (half of them in
/// pairs that close a circle), and `marks` the share given a sign, laid in
/// patches from a smooth field. The seed deals the chart and the draws, and
/// a press deals the next one.
///
/// Over one cycle of `seconds` the chart is written on the left sheet, the
/// machine types its codes cell by cell in the order it walked them, and the
/// canvas on the right is painted one template at a time, every cell of an
/// element at once, then holds and fades back, which is also the export loop.
///
/// Every element on the canvas exports as its black ground (a rectangle) and
/// its half-discs (polygons that start at the disc's center), and every sign
/// and every underline under a hand-placed code on the sheet as lines, so
/// `--export-svg` with a frame in the hold gives back both the chart and the
/// picture, and walking the chart again in the same order gives back every
/// group and admits every element.
@main
final class Structure: Sketch {
    /// The four relation rules of the article, by the answer each wants.
    enum Relation: String, CaseIterable, ParamOption {
        case both, colorOnly, shapeOnly, neither

        /// The number the article gives the rule.
        var number: Int { Self.allCases.firstIndex(of: self)! }
        var wantsColor: Bool { self == .both || self == .colorOnly }
        var wantsShape: Bool { self == .both || self == .shapeOnly }
    }

    @Param(icon: "arrow.triangle.branch") var rule = Relation.shapeOnly
    @Param(0 ... 2, icon: "plusminus") var coefficient = 0.75
    @Param(4 ... 40, icon: "square.grid.3x3") var columns = 11
    @Param(4 ... 40, icon: "line.3.horizontal") var rows = 22
    @Param(0 ... 0.5, icon: "pencil") var inputs = 0.19
    @Param(0 ... 1, icon: "plus.forwardslash.minus") var marks = 0.5
    @Param(8 ... 90, icon: "clock") var seconds = 30.0

    override var canvasSize: CanvasSize { .square(1080) }
    override var loopDuration: Double? { seconds }

    private enum Side: Int, CaseIterable {
        case top, right, bottom, left

        var opposite: Side { Side(rawValue: (rawValue + 2) % 4)! }
        var step: (row: Int, column: Int) {
            switch self {
            case .top: (-1, 0)
            case .right: (0, 1)
            case .bottom: (1, 0)
            case .left: (0, -1)
            }
        }
        /// Where a half-disc whose diameter lies along this side starts its
        /// arc, so the half-turn bulges into the cell.
        var arcStart: Double {
            switch self {
            case .top: 0
            case .right: .pi / 2
            case .bottom: .pi
            case .left: -.pi / 2
            }
        }
    }

    /// One of the twenty elements: a square holding half-discs whose radius
    /// is half its side, white on black (groups 1 and 3) or black on white
    /// (groups 2 and 4). A single has one half-disc on a side; a double adds a
    /// second on the midline, bulging the same way; a facing pair has two on
    /// opposite sides, meeting at the center.
    private struct Element {
        /// As the program printed it: the group and a letter.
        let code: String
        let group: Int
        /// The sides a half-disc's diameter lies along.
        let flat: [Side]
        let isDouble: Bool

        var figureIsWhite: Bool { group == 1 || group == 3 }
        func isFlat(_ side: Side) -> Bool { flat.contains(side) }
        /// The paint along a side: the figure's where a diameter lies on it,
        /// the ground's elsewhere.
        func isWhite(along side: Side) -> Bool { isFlat(side) == figureIsWhite }
    }

    /// The set in the order of the article's chart.
    private static let elements: [Element] = {
        func doubles(_ group: Int) -> [Element] {
            [("z", Side.left), ("b", .bottom), ("y", .right), ("i", .top)].map {
                Element(code: "\(group)\($0.0)", group: group, flat: [$0.1], isDouble: true)
            } + [Element(code: "\(group)r", group: group, flat: [.left, .right], isDouble: false),
                 Element(code: "\(group)d", group: group, flat: [.top, .bottom], isDouble: false)]
        }
        func singles(_ group: Int) -> [Element] {
            [("z", Side.left), ("b", .bottom), ("y", .right), ("r", .top)].map {
                Element(code: "\(group)\($0.0)", group: group, flat: [$0.1], isDouble: false)
            }
        }
        return doubles(1) + singles(2) + singles(3) + doubles(4)
    }()

    private enum Mark { case none, darker, lighter }

    /// A chart and the picture the machine made of it.
    private struct Sheet {
        var marks: [[Mark]]
        var inputs: [[Int?]]
        /// The element of every cell, as an index into `elements`.
        var cells: [[Int]]
        /// The cells the machine decided, in the order it walked them.
        var walked: [(row: Int, column: Int)]
        /// The templates in the order they are painted: the elements that
        /// occur, in the chart's order.
        var templates: [Int]
    }

    private struct Dealt: Equatable {
        var rule: Relation, coefficient: Double, columns: Int, rows: Int
        var inputs: Double, marks: Double, seed: Int
    }

    // The canvas, the paints, and the sheet.
    private let wall = Color(hex: 0xA8A39B)
    private let primed = Color(hex: 0xF1EEE7)
    private let oilBlack = Color(hex: 0x141313)
    private var oilWhite: Color { primed }
    private let paper = Color(hex: 0xEDE8DF)
    private let pencil = Color(hex: 0x76716B)
    private let printerInk = Color(hex: 0x37353F)

    private var sheet: Sheet?
    private var dealtFor: Dealt?
    private var pressed = false

    override func setup() {
        textFont(OutlineFont.systemMono)
    }

    override func mousePressed() {
        pressed = true
    }

    override func draw() {
        if pressed {
            pressed = false
            seed(variation + 1)
        }
        let wanted = Dealt(rule: rule, coefficient: coefficient, columns: columns, rows: rows,
                           inputs: inputs, marks: marks, seed: variation)
        if dealtFor != wanted || sheet == nil {
            dealtFor = wanted
            sheet = deal()
        }
        guard let sheet else { return }

        background(wall)
        let margin = 0.06 * width, gap = 0.05 * width
        let panel = (width - 2 * margin - gap) / 2
        let s = min(panel / Double(columns), (height - 2 * margin) / Double(rows))
        let size = Vector2(s * Double(columns), s * Double(rows))
        let top = (height - size.y) / 2
        let chart = Rectangle(x: margin + (panel - size.x) / 2, y: top, width: size.x, height: size.y)
        let canvas = Rectangle(x: margin + panel + gap + (panel - size.x) / 2, y: top,
                               width: size.x, height: size.y)

        let phase = loopProgress(over: seconds)
        let written = 0.08, typed = 0.38, painted = 0.78, held = 0.92

        noStroke()
        fill(paper)
        drawRect(chart.x - 0.6 * s, chart.y - 1.6 * s, chart.width + 1.2 * s, chart.height + 2.2 * s)
        fill(primed)
        drawRect(canvas)

        let hundredths = Int((coefficient * 100).rounded())
        let c = "\(hundredths / 100).\(hundredths % 100 < 10 ? "0" : "")\(hundredths % 100)"
        drawText("RULE \(rule.number)   C \(c)   SEED \(variation)",
                 chart.x, chart.y - 0.8 * s, size: 0.34 * s, color: pencil, align: .left, .middle)
        stroke(pencil.withAlpha(0.35))
        strokeWeight(1)
        noFill()
        drawRect(chart)
        noStroke()

        // The chart in reading order: the signs, then the hand-placed codes.
        let count = rows * columns
        let shown = min(count, Int(Double(count) * min(1, phase / written)))
        withState {
            textMode(.atlas)
            textAlign(.center, .middle)
            textSize(0.36 * s)
            for i in 0 ..< shown {
                let r = i / columns, c = i % columns
                let x = chart.x + Double(c) * s, y = chart.y + Double(r) * s
                drawMark(sheet.marks[r][c], x: x, y: y, s: s)
                if let e = sheet.inputs[r][c] {
                    fill(pencil)
                    drawText(Self.elements[e].code, x + 0.55 * s, y + 0.48 * s)
                    noFill()
                    stroke(pencil)
                    strokeWeight(max(1, 0.04 * s))
                    drawLine(x + 0.3 * s, y + 0.72 * s, x + 0.8 * s, y + 0.72 * s)
                    noStroke()
                }
            }

            // The machine's walk, one code a cell, the head on the next cell.
            let walk = sheet.walked.count
            let typing = phase < written ? 0 : min(1, (phase - written) / (typed - written))
            let done = min(walk, Int(Double(walk) * typing))
            fill(printerInk)
            for (r, c) in sheet.walked.prefix(done) {
                drawText(Self.elements[sheet.cells[r][c]].code,
                         chart.x + (Double(c) + 0.55) * s, chart.y + (Double(r) + 0.48) * s)
            }
            if done < walk, phase >= written {
                let (r, c) = sheet.walked[done]
                fill(printerInk.withAlpha(0.18))
                drawRect(chart.x + Double(c) * s, chart.y + Double(r) * s, s, s)
            }
        }

        // The canvas, one template at a time.
        let progress = phase < typed ? 0 : Double(sheet.templates.count) * min(1, (phase - typed) / (painted - typed))
        for (t, template) in sheet.templates.enumerated() where Double(t) < progress {
            let alpha = min(1, progress - Double(t))
            for r in 0 ..< rows {
                for c in 0 ..< columns where sheet.cells[r][c] == template {
                    paint(Self.elements[template], x: canvas.x + Double(c) * s,
                          y: canvas.y + Double(r) * s, s: s, alpha: smoothstep(0, 1, alpha))
                }
            }
        }

        if phase > held {
            let veil = smoothstep(held, 1, phase)
            fill(primed.withAlpha(veil))
            drawRect(canvas)
            fill(paper.withAlpha(veil))
            drawRect(chart.x - 0.5 * s, chart.y - 1.5 * s, chart.width + s, chart.height + 2 * s)
        }
    }

    /// A sign written small in the corner of a chart cell, as two lines or one.
    private func drawMark(_ mark: Mark, x: Double, y: Double, s: Double) {
        guard mark != .none else { return }
        stroke(pencil)
        strokeWeight(max(1, 0.035 * s))
        let cx = x + 0.17 * s, cy = y + 0.2 * s, arm = 0.08 * s
        drawLine(cx - arm, cy, cx + arm, cy)
        if mark == .darker { drawLine(cx, cy - arm, cx, cy + arm) }
        noStroke()
    }

    /// An element in oil: the black ground where the figure is white, then
    /// the half-discs in the figure's paint.
    private func paint(_ e: Element, x: Double, y: Double, s: Double, alpha: Double) {
        if e.figureIsWhite {
            fill(oilBlack.withAlpha(alpha))
            drawRect(x, y, s, s)
        }
        fill((e.figureIsWhite ? oilWhite : oilBlack).withAlpha(alpha))
        let r = s / 2
        for side in e.flat {
            let center: Vector2 = switch side {
            case .top: Vector2(x + r, y)
            case .right: Vector2(x + s, y + r)
            case .bottom: Vector2(x + r, y + s)
            case .left: Vector2(x, y + r)
            }
            drawArc(center: center, radiusX: r, radiusY: r,
                    start: side.arcStart, stop: side.arcStart + .pi, mode: .pie)
        }
        if e.isDouble, let side = e.flat.first {
            drawArc(center: Vector2(x + r, y + r), radiusX: r, radiusY: r,
                    start: side.arcStart, stop: side.arcStart + .pi, mode: .pie)
        }
    }

    /// Writes a chart for the seed, then walks it as the machine did.
    private func deal() -> Sheet {
        randomSeed(variation)
        noiseSeed(variation)
        let count = rows * columns

        // The signs, in patches: the cells ranked by a smooth field, the
        // highest given a plus and the lowest a minus.
        var ranked: [(value: Double, row: Int, column: Int)] = []
        for r in 0 ..< rows {
            for c in 0 ..< columns {
                ranked.append((signedNoise(Double(c) * 0.23 + 0.5, Double(r) * 0.23 + 0.5), r, c))
            }
        }
        ranked.sort { $0.value < $1.value }
        var markGrid = Array(repeating: Array(repeating: Mark.none, count: columns), count: rows)
        let each = min(count / 2, Int((Double(count) * marks / 2).rounded()))
        for k in 0 ..< each {
            markGrid[ranked[k].row][ranked[k].column] = .lighter
            markGrid[ranked[count - 1 - k].row][ranked[count - 1 - k].column] = .darker
        }

        // The hand-placed elements, half of them in pairs that close a circle
        // across one of the first element's diameters.
        var placed = Array(repeating: [Int?](repeating: nil, count: columns), count: rows)
        let wanted = Int((Double(count) * inputs).rounded())
        var total = 0, tries = 0
        while total < wanted, tries < count * 20 {
            tries += 1
            let r = min(rows - 1, Int(random(0, Double(rows))))
            let c = min(columns - 1, Int(random(0, Double(columns))))
            guard placed[r][c] == nil else { continue }
            let e = min(19, Int(random(0, 20)))
            placed[r][c] = e
            total += 1
            guard total < wanted, random() < 0.5 else { continue }
            let side = randomChoice(Self.elements[e].flat)
            let (nr, nc) = (r + side.step.row, c + side.step.column)
            guard nr >= 0, nr < rows, nc >= 0, nc < columns, placed[nr][nc] == nil else { continue }
            let partners = Self.elements.indices.filter { Self.elements[$0].isFlat(side.opposite) }
            placed[nr][nc] = randomChoice(Array(partners))
            total += 1
        }
        for r in 0 ..< rows {
            for c in 0 ..< columns where placed[r][c] != nil { markGrid[r][c] = .none }
        }

        // The walk: odd rows left to right, even rows back right to left.
        var known = placed
        var walked: [(row: Int, column: Int)] = []
        for r in 0 ..< rows {
            for c in r % 2 == 0 ? Array(0 ..< columns) : Array((0 ..< columns).reversed())
            where placed[r][c] == nil {
                known[r][c] = choose(row: r, column: c, known: known, mark: markGrid[r][c])
                walked.append((r, c))
            }
        }
        let cells = known.map { $0.map { $0! } }
        let used = Set(cells.flatMap { $0 })
        return Sheet(marks: markGrid, inputs: placed, cells: cells, walked: walked,
                     templates: Self.elements.indices.filter { used.contains($0) })
    }

    /// The machine's decision for one cell: a group from the density around
    /// it, then the elements of that group the rule admits, then a draw.
    private func choose(row: Int, column: Int, known: [[Int?]], mark: Mark) -> Int {
        func element(_ r: Int, _ c: Int) -> Element? {
            guard r >= 0, r < rows, c >= 0, c < columns, let e = known[r][c] else { return nil }
            return Self.elements[e]
        }
        var sum = 0, around = 0
        for dr in -1 ... 1 {
            for dc in -1 ... 1 where dr != 0 || dc != 0 {
                if let e = element(row + dr, column + dc) {
                    sum += e.group
                    around += 1
                }
            }
        }
        var level = around > 0 ? Double(sum) / Double(around) : Double(1 + min(3, Int(random(0, 4))))
        switch mark {
        case .darker: level += coefficient
        case .lighter: level -= coefficient
        case .none: break
        }
        // The nearest group, a density halfway between two going to the lighter.
        let group = min(4, max(1, Int((level - 0.5).rounded(.up))))

        let beside = Side.allCases.compactMap { side in
            element(row + side.step.row, column + side.step.column).map { (side, $0) }
        }
        func colorContinues(_ e: Element) -> Bool {
            beside.contains { e.isWhite(along: $0.0) == $0.1.isWhite(along: $0.0.opposite) }
        }
        func shapeContinues(_ e: Element) -> Bool {
            beside.contains { e.isFlat($0.0) && $0.1.isFlat($0.0.opposite) }
        }
        let candidates = Self.elements.indices.filter { Self.elements[$0].group == group }
        let byColor = candidates.filter { colorContinues(Self.elements[$0]) == rule.wantsColor }
        let kept = byColor.isEmpty ? candidates : byColor
        let byShape = kept.filter { shapeContinues(Self.elements[$0]) == rule.wantsShape }
        return randomChoice(Array(byShape.isEmpty ? kept : byShape))
    }
}
