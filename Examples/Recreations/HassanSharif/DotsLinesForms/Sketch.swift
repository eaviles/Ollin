//  Recreation after Hassan Sharif - "Dots, Lines and Forms" (1984, ink on
//  paper with one draft paper; reconstituted by the artist in 2006), one of
//  the semi-systems he drew as a student in London. A homage, not a
//  reproduction, and not affiliated with or endorsed by the artist or his
//  estate.
//  https://www.alexandergray.com/series/hassan-sharif/hassan-sharif-semi-systems/
//
//  An original Ollin interpretation written from the drawing and from what
//  Sharif and his readers said about the method. Nothing was ported: the work
//  is ink on paper, and the numbers were picked by hand.

import Ollin

/// "Dots, Lines and Forms" (Hassan Sharif, 1984). Sharif studied at the Byam
/// Shaw School of Art in London from 1980 to 1984, in the abstract and
/// experimental department, where he took up Kenneth Martin's "chance and
/// order": the crossings of a grid are numbered, the numbers are picked at
/// random, and a line is drawn between each pair as it comes out. Sharif kept
/// the numbered grid and the picking and put his own rules over them,
/// arbitrary and over-elaborate on purpose, worked out on a draft paper that
/// he kept with the drawing and later hung beside it. He called the results
/// semi-systems. "I am not a systematic person," he said. "If somebody tells
/// me this isn't a system, I'll say: this isn't a system, it's a
/// semi-system." Mistakes stayed in: "I keep them as they are without
/// correction because I believe that art is a result of errors."
///
/// The 1984 sheet is one table drawn three ways, four columns by seven rows.
/// In the third panel every cell is a small square with a line or two inside
/// it; in the second the same lines stand bare on the graph paper; in the
/// first only the points the lines touch are marked, and the marks read as
/// the numbers they came from. Down the table, each column keeps one line, a
/// line through the middle of the square, and each row adds a second, shorter
/// one from the middle out to a corner, taking the corners in turn, so the
/// first row is empty, the second holds the column's line alone, and the rest
/// are the two together.
///
/// This sketch keeps that rule and lets chance pick the columns. A cell is a
/// square of nine points numbered 1 to 9 the way a keypad is. For every
/// column two numbers are picked, not along one side of the square, and that
/// pair is the column's line; the rows then add a line from 5 to 3, 9, 7, 1,
/// 2, 6, 8, 4 in turn, one more row, one more point around the square. Every
/// cell is its column's line with its row's, read three ways: `dots` marks
/// the points the two lines name, `lines` draws them, and `forms` draws them
/// inside the square. The draft paper beside the sheet holds the picks, the
/// walk, and the rule, which is the whole of what a cell needs, so the sheet
/// can be read back off any panel, and the dots panel is the number sheet
/// itself.
///
/// The pen goes through the dots first, then the lines, then the forms, at
/// `pace` cells a second, and a finished sheet holds for `hold` seconds
/// before the next one is picked. `columns` and `rows` are the table (`rows`
/// past nine repeat the walk), and `firstSheet` numbers the first one. A press
/// starts the next sheet now.
///
/// Every dot exports as a circle, every line as a line, and every square as a
/// rect, so `--export-svg` with a frame after the sheet is complete gives the
/// table back as marks that can be read: each column's pair off the dots,
/// and the same pair in the lines and the forms.
@main
final class DotsLinesForms: Sketch {
    @Param(2 ... 6, icon: "rectangle.split.3x1") var columns = 4
    @Param(2 ... 10, icon: "rectangle.split.1x2") var rows = 7
    @Param(1 ... 60, icon: "pencil.line") var pace = 8.0
    @Param(0 ... 30, icon: "clock") var hold = 5.0
    @Param(1 ... 999, icon: "number") var firstSheet = 1

    override var canvasSize: CanvasSize { .size(1620, 1080) }

    private let wall = Color(hex: 0xE3DFD6)
    private let paper = Color(hex: 0xF2ECDA)
    private let draftPaper = Color(hex: 0xF8F6EE)
    private let pencil = Color(hex: 0xCBC4B2)
    private let ink = Color(hex: 0x1B1919)
    private let handwriting = Color(hex: 0x2A2B5E)
    private let red = Color(hex: 0xC3342A)

    /// The points the rows walk to from the middle: the corners first, then
    /// the sides, clockwise from the top right.
    private nonisolated static let walk = [3, 9, 7, 1, 2, 6, 8, 4]

    /// One sheet: the numbers picked for it.
    private struct Sheet {
        var number: Int
        var columns: Int
        var rows: Int
        /// The pair picked for each column, points 1 to 9.
        var picks: [(Int, Int)]

        var cells: Int { columns * rows }

        /// What row `row` adds to every cell in it, or nil for the two rows
        /// that add nothing.
        func addition(row: Int) -> Int? {
            row < 2 ? nil : DotsLinesForms.walk[(row - 2) % DotsLinesForms.walk.count]
        }

        /// The lines in one cell, as pairs of point numbers.
        func lines(column: Int, row: Int) -> [(Int, Int)] {
            guard row > 0 else { return [] }
            var out = [picks[column]]
            if let to = addition(row: row) { out.append((5, to)) }
            return out
        }

        /// The points one cell's lines touch, in number order.
        func points(column: Int, row: Int) -> [Int] {
            var named = Set<Int>()
            for (a, b) in lines(column: column, row: row) {
                named.insert(a)
                named.insert(b)
            }
            return named.sorted()
        }
    }

    private var sheet: Sheet?
    /// When the current sheet's first cell was drawn.
    private var began = 0.0
    private var pressed = 0
    private var program = (columns: 0, rows: 0, first: 0)

    override func setup() {
        textFont(OutlineFont.system)
    }

    override func mousePressed() {
        pressed += 1
    }

    override func draw() {
        background(wall)

        let wanted = (columns: columns, rows: rows, first: firstSheet)
        if sheet == nil || program != wanted {
            program = wanted
            start(sheet: firstSheet, at: time)
        }
        while pressed > 0 {
            pressed -= 1
            start(sheet: (sheet?.number ?? firstSheet) + 1, at: time)
        }
        while let current = sheet, time - began >= duration(of: current) {
            start(sheet: current.number + 1, at: began + duration(of: current))
        }
        guard let current = sheet else { return }

        // The drawing sheet and the draft paper, hung side by side.
        let margin = 60.0
        let drawing = Rectangle(x: margin, y: 160, width: 1120, height: 760)
        let draft = Rectangle(x: drawing.x + drawing.width + 40, y: drawing.y,
                              width: width - margin - (drawing.x + drawing.width + 40), height: drawing.height)
        noStroke()
        fill(paper)
        drawRect(drawing)
        fill(draftPaper)
        drawRect(draft)

        // The table: three panels of the same cells, four grid units to a
        // cell, the square on three of them, one panel's width between them.
        let unit = 14.0
        let pitch = unit * 5
        let square = unit * 4
        let gap = pitch
        let block = Double(3 * current.columns) * pitch + 2 * gap
        let originX = drawing.x + (drawing.width - block) / 2
        let originY = drawing.y + (drawing.height - Double(current.rows) * pitch) / 2 - unit

        let drawn = min(3 * current.cells, Int((time - began) * pace))
        func panelOrigin(_ panel: Int) -> Double {
            originX + Double(panel) * (Double(current.columns) * pitch + gap)
        }
        func cellSquare(panel: Int, column: Int, row: Int) -> Rectangle {
            Rectangle(x: panelOrigin(panel) + Double(column) * pitch + (pitch - square) / 2,
                      y: originY + Double(row) * pitch + (pitch - square) / 2,
                      width: square, height: square)
        }
        func point(_ n: Int, in cell: Rectangle) -> Vector2 {
            Vector2(cell.x + Double((n - 1) % 3) * cell.width / 2,
                    cell.y + Double((n - 1) / 3) * cell.height / 2)
        }

        // The graph paper under each panel.
        noFill()
        stroke(pencil)
        strokeWeight(1)
        for panel in 0 ..< 3 {
            let left = panelOrigin(panel)
            let right = left + Double(current.columns) * pitch
            let bottom = originY + Double(current.rows) * pitch
            var x = left
            while x <= right + 0.5 {
                drawLine(x, originY, x, bottom)
                x += unit
            }
            var y = originY
            while y <= bottom + 0.5 {
                drawLine(left, y, right, y)
                y += unit
            }
        }

        // The cells, in the order the pen went: dots, then lines, then forms.
        strokeCap(.round)
        for index in 0 ..< drawn {
            let panel = index / current.cells
            let within = index % current.cells
            let column = within % current.columns
            let row = within / current.columns
            let cell = cellSquare(panel: panel, column: column, row: row)
            switch panel {
            case 0:
                noStroke()
                fill(ink)
                for n in current.points(column: column, row: row) {
                    drawCircle(center: point(n, in: cell), radius: unit * 0.22)
                }
            case 1:
                noFill()
                stroke(ink)
                strokeWeight(unit * 0.22)
                for (a, b) in current.lines(column: column, row: row) {
                    drawLine(point(a, in: cell), point(b, in: cell))
                }
            default:
                noFill()
                stroke(ink)
                strokeWeight(unit * 0.22)
                drawRect(cell)
                for (a, b) in current.lines(column: column, row: row) {
                    drawLine(point(a, in: cell), point(b, in: cell))
                }
            }
        }

        // The title under the table, in his own order of words.
        let title = "Dots - Lines - Forms - sheet \(current.number)"
        drawText(title, originX, originY + Double(current.rows) * pitch + unit * 2.2,
                 size: unit * 1.3, color: handwriting, align: .left, .top)

        drawDraftPaper(draft, for: current, drawn: drawn, unit: unit)
    }

    /// The draft paper: the numbered square, the picks, the walk, the rule.
    private func drawDraftPaper(_ paper: Rectangle, for sheet: Sheet, drawn: Int, unit: Double) {
        let left = paper.x + 28
        var y = paper.y + 30
        let size = unit * 1.25
        let leading = size * 1.55

        drawText("draft paper, sheet \(sheet.number)", left, y, size: size, color: handwriting, align: .left, .top)
        y += leading * 1.6

        // The square of nine, so the numbers on the paper can be read.
        let side = unit * 5
        let keypad = Rectangle(x: left + 6, y: y + 6, width: side, height: side)
        noFill()
        stroke(pencil)
        strokeWeight(1)
        drawRect(keypad)
        drawLine(keypad.x, keypad.center.y, keypad.x + keypad.width, keypad.center.y)
        drawLine(keypad.center.x, keypad.y, keypad.center.x, keypad.y + keypad.height)
        for n in 1 ... 9 {
            let p = Vector2(keypad.x + Double((n - 1) % 3) * side / 2,
                            keypad.y + Double((n - 1) / 3) * side / 2)
            noStroke()
            fill(draftPaper)
            drawCircle(center: p, radius: size * 0.55)
            drawText("\(n)", p.x, p.y, size: size * 0.85, color: handwriting, align: .center, .middle)
        }
        drawText("a cell: nine points", keypad.x + side + 18, keypad.y + side / 2,
                 size: size, color: handwriting, align: .left, .center)
        y += side + leading * 1.4

        drawText("columns, picked:", left, y, size: size, color: handwriting, align: .left, .top)
        y += leading
        for (index, pair) in sheet.picks.enumerated() {
            drawText("\(index + 1):  \(pair.0) - \(pair.1)", left + 16, y, size: size, color: handwriting, align: .left, .top)
            y += leading
        }
        y += leading * 0.5

        drawText("rows, in turn:", left, y, size: size, color: handwriting, align: .left, .top)
        y += leading
        for row in 0 ..< sheet.rows {
            let what: String
            if row == 0 {
                what = "nothing"
            } else if let to = sheet.addition(row: row) {
                what = "the column's line, and 5 - \(to)"
            } else {
                what = "the column's line"
            }
            drawText("\(row + 1):  \(what)", left + 16, y, size: size, color: handwriting, align: .left, .top)
            y += leading
        }
        y += leading * 0.5

        drawText("dots where they end; lines; the square.", left, y, size: size, color: handwriting, align: .left, .top)
        y += leading * 1.6

        // How far the pen has got, panel by panel.
        let names = ["dots", "lines", "forms"]
        for panel in 0 ..< 3 {
            let done = min(sheet.cells, max(0, drawn - panel * sheet.cells))
            let tally = "\(names[panel]): \(done) of \(sheet.cells)"
            drawText(tally, left, y, size: size, color: done == sheet.cells ? red : handwriting, align: .left, .top)
            y += leading
        }
    }

    /// Pick one whole sheet: a pair of points for every column.
    private func start(sheet number: Int, at moment: Double) {
        randomSeed(number)
        var picks: [(Int, Int)] = []
        for _ in 0 ..< columns {
            var a = 1, b = 1
            repeat {
                a = 1 + min(8, Int(random(0, 9)))
                b = 1 + min(8, Int(random(0, 9)))
            } while a == b || DotsLinesForms.alongOneSide(a, b)
            picks.append((min(a, b), max(a, b)))
        }
        sheet = Sheet(number: number, columns: columns, rows: rows, picks: picks)
        began = moment
    }

    /// Whether two of the nine points lie on one side of the square, where a
    /// line between them would sit on the square's own edge.
    private static func alongOneSide(_ a: Int, _ b: Int) -> Bool {
        let sides: [Set<Int>] = [[1, 2, 3], [7, 8, 9], [1, 4, 7], [3, 6, 9]]
        return sides.contains { $0.contains(a) && $0.contains(b) }
    }

    /// Drawing all three panels at `pace`, then holding the sheet.
    private func duration(of sheet: Sheet) -> Double {
        Double(3 * sheet.cells) / max(1, pace) + hold
    }
}
