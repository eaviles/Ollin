//  Recreation after Hassan Sharif - "10th to 13th October No. 1 & No. 2"
//  (1984, ink, pencil and marker on paper, two sheets; the drawing on the
//  second made again by the artist in 2006), a semi-system from his last
//  year at the Byam Shaw School of Art in London. A homage, not a
//  reproduction, and not affiliated with or endorsed by the artist or his
//  estate.
//  https://www.alexandergray.com/series/hassan-sharif/hassan-sharif-semi-systems/
//
//  An original Ollin interpretation written from the two sheets. Nothing was
//  ported: the work is ink on paper, and the numbers were picked by hand.

import Ollin

/// "10th to 13th October No. 1 & No. 2" (Hassan Sharif, 1984). Four days of
/// work: the first sheet is four pages of trials dated the 10th and the 11th,
/// grids of digits, Latin squares, a red checker, a plan for fifteen
/// drawings in five groups, most of it crossed out in red. The second sheet,
/// dated the 13th, holds the rule that survived, and all of it is on the
/// page. A table: a header 2 3 4 5 6, then the rows 22 to 26, 32 to 36, 42
/// to 46 and 52 to 56, the row's digit written in front of the column's. A
/// wavy line cuts the table from its top left corner down and to the right,
/// and the numbers on its left are taken, in red: 2, 22, 32, 33, 42, 43, 44,
/// 52, 53, 54. Each taken number becomes the sum of its digits, written out
/// as a list, 22 = 4, 23 = 5, 33 = 6 and so on (the 23 is his slip for 32,
/// kept). The repeated sums are dropped, and what is left stands in a red
/// box: 2, 4, 5, 6, 7, 8, 9. Beside an arrow, in his hand: the numbers turn
/// into lines, semi-straight or wavy, in ink on paper or directly on the
/// wall. The drawing under it is forty-one ruled lines in seven bands, one
/// band per number with as many lines as the number says, the bands straight
/// and wavy in turn: two straight, four wavy, five straight, six wavy, seven
/// straight, eight wavy, nine straight.
///
/// This sketch keeps the table and the rule and lets chance draw the cut.
/// For each of the table's five rows the cut passes between two columns,
/// starting anywhere and stepping at most one column left or right as it
/// goes down, so it is a wavy line from the top edge to the bottom edge and
/// every row keeps at least its first number. The numbers on its left turn
/// red, each becomes the sum of its digits on the list, the repeats are
/// dropped, and the sums that remain go into the red box in the order they
/// came. Then the pen rules the drawing: one band per sum, as many lines as
/// the sum, straight and wavy bands in turn, straight first, on the sheet in
/// the red frame and at the same time on the wall beside it, since the sheet
/// says the wall will do. `pace` is lines a second, a finished sheet holds
/// for `hold` seconds before the next cut is drawn, `firstSheet` numbers the
/// first, and a press starts the next sheet now.
///
/// Every straight line exports as a line and every wavy one as a polyline,
/// so `--export-svg` with a frame after the wall is painted gives the rule
/// back: the cut's position at each row of the table names the numbers
/// taken, their digit sums without repeats are the bands, and each band on
/// the wall and on the sheet holds exactly that many lines, straight and
/// wavy in turn.
@main
final class OctoberLines: Sketch {
    @Param(1 ... 60, icon: "pencil.line") var pace = 6.0
    @Param(0 ... 30, icon: "clock") var hold = 5.0
    @Param(1 ... 999, icon: "number") var firstSheet = 1

    override var canvasSize: CanvasSize { .size(1620, 1080) }

    private let wall = Color(hex: 0xE6E3DC)
    private let paper = Color(hex: 0xF6F3EB)
    private let pencil = Color(hex: 0xC9C3B5)
    private let handwriting = Color(hex: 0x2A2B5E)
    private let red = Color(hex: 0xC3342A)
    private let ink = Color(hex: 0x1B1919)

    /// The table's digits: the header's, and the row digits in front of them.
    private let columnDigits = [2, 3, 4, 5, 6]
    private let rowDigits = [2, 3, 4, 5]

    /// How long the cut takes to draw, a number to turn red, the box to
    /// appear.
    private let cutting = 1.2
    private let listing = 0.3
    private let boxing = 0.6

    /// One sheet: the cut, and everything the rule makes of it.
    private struct Sheet {
        var number: Int
        /// For each row, how many columns lie left of the cut (1 to 5).
        var cut: [Int]
        /// The numbers taken, in reading order, with their digit sums.
        var taken: [(number: Int, sum: Int)]
        /// The sums with the repeats dropped, in the order they came.
        var sums: [Int]
        /// Per line of the drawing: the band it belongs to, and the hand's
        /// small differences, a weight, a phase, a period.
        var lines: [(band: Int, weight: Double, phase: Double, period: Double)]

        var lineCount: Int { lines.count }
    }

    private var sheet: Sheet?
    private var began = 0.0
    private var pressed = 0
    private var program = 0

    override func setup() {
        textFont(OutlineFont.system)
    }

    override func mousePressed() {
        pressed += 1
    }

    override func draw() {
        background(wall)

        if sheet == nil || program != firstSheet {
            program = firstSheet
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

        // The sheet on the left, in the proportion of his, and the wall
        // drawing on the right.
        let sheetPaper = Rectangle(x: 70, y: 60, width: 680, height: 960)
        let wallDrawing = Rectangle(x: 940, y: 100, width: 560, height: 880)
        noStroke()
        fill(paper)
        drawRect(sheetPaper)

        // How far the pen has got.
        let elapsed = time - began
        let cutProgress = min(1, elapsed / cutting)
        let listed = elapsed < cutting ? 0 : min(current.taken.count, Int((elapsed - cutting) / listing))
        let listingEnds = cutting + Double(current.taken.count) * listing
        let boxed = elapsed >= listingEnds + boxing
        let drawn = boxed ? min(current.lineCount, Int((elapsed - listingEnds - boxing) * pace)) : 0

        // The table, top left of the sheet.
        let cell = 54.0
        let table = Rectangle(x: sheetPaper.x + 48, y: sheetPaper.y + 56,
                              width: cell * Double(columnDigits.count), height: cell * Double(rowDigits.count + 1))
        drawTable(table, cell: cell, sheet: current, listed: listed)
        drawCut(table, cell: cell, sheet: current, progress: cutProgress)

        // The list of sums to the right of the table, in columns of thirteen
        // when the cut takes many, and the box beyond it.
        let listX = table.x + table.width + 40
        let size = 18.0
        let leading = 24.0
        let perColumn = 13
        for index in 0 ..< listed {
            let entry = current.taken[index]
            let text = "\(entry.number) = \(entry.sum)"
            drawText(text, listX + Double(index / perColumn) * 92, table.y + Double(index % perColumn) * leading,
                     size: size, color: index == 0 ? red : handwriting, align: .left, .top)
        }
        let listColumns = (current.taken.count + perColumn - 1) / perColumn
        let box = Rectangle(x: listX + Double(listColumns) * 92 + 16, y: table.y - 6, width: 64,
                            height: max(leading * 2.2, Double(current.sums.count) * leading + 20))
        if boxed {
            noFill()
            stroke(red)
            strokeWeight(3)
            drawRect(box)
            for (index, sum) in current.sums.enumerated() {
                drawText("\(sum)", box.center.x, box.y + 10 + Double(index) * leading, size: size,
                         color: handwriting, align: .center, .top)
            }
            let listBottom = table.y + Double(min(perColumn, current.taken.count)) * leading
            let noteY = max(box.y + box.height, listBottom) + 22
            drawText("the numbers turn into lines,", listX, noteY, size: size * 0.85, color: handwriting, align: .left, .top)
            drawText("semi-straight or wavy, on paper", listX, noteY + leading * 0.8, size: size * 0.85, color: handwriting, align: .left, .top)
            drawText("or directly on the wall.", listX, noteY + leading * 1.6, size: size * 0.85, color: handwriting, align: .left, .top)
        }

        // The drawing on the sheet, in its red frame, under the table and
        // the list.
        let frame = Rectangle(x: sheetPaper.x + 150, y: table.y + table.height + 118, width: 300, height: 430)
        let drawing = Rectangle(x: frame.x + 30, y: frame.y + 26, width: frame.width - 60, height: frame.height - 52)
        noFill()
        stroke(red)
        strokeWeight(4)
        drawRect(frame)
        drawLines(drawing, sheet: current, drawn: drawn, scale: 1)

        // The same lines on the wall, at the wall's scale.
        drawLines(wallDrawing, sheet: current, drawn: drawn, scale: wallDrawing.width / drawing.width)

        let title = "\(current.lineCount) lines in \(current.sums.count) bands, sheet \(current.number)"
        drawText(title, sheetPaper.x + 48, sheetPaper.y + sheetPaper.height - 44, size: size * 0.9,
                 color: handwriting, align: .left, .top)
        drawText("sheet \(current.number), on the wall", wallDrawing.x, wallDrawing.y + wallDrawing.height + 24,
                 size: size * 0.9, color: handwriting, align: .left, .top)
    }

    /// The table: a header of single digits, then the two-digit rows, the
    /// taken numbers in red once they are listed.
    private func drawTable(_ table: Rectangle, cell: Double, sheet: Sheet, listed: Int) {
        let size = 22.0
        var counted = 0
        for row in 0 ... rowDigits.count {
            for column in 0 ..< columnDigits.count {
                let center = Vector2(table.x + (Double(column) + 0.5) * cell, table.y + (Double(row) + 0.5) * cell)
                let text = row == 0 ? "\(columnDigits[column])" : "\(rowDigits[row - 1])\(columnDigits[column])"
                var color = handwriting
                if column < sheet.cut[row] {
                    counted += 1
                    if counted <= listed { color = red }
                }
                drawText(text, center.x, center.y, size: size, color: color, align: .center, .middle)
                // The slashes he wrote between the numbers.
                if column + 1 < columnDigits.count {
                    noFill()
                    stroke(handwriting)
                    strokeWeight(1.2)
                    let x = table.x + Double(column + 1) * cell
                    drawLine(x - 4, center.y + cell * 0.32, x + 4, center.y - cell * 0.32)
                }
            }
        }
        // The rule under the table.
        noFill()
        stroke(handwriting)
        strokeWeight(1.2)
        drawLine(table.x - 6, table.y + table.height + 4, table.x + table.width + 6, table.y + table.height + 4)
    }

    /// The cut: a wavy line down the table, passing between two columns in
    /// every row, drawn as far as `progress`.
    private func drawCut(_ table: Rectangle, cell: Double, sheet: Sheet, progress: Double) {
        guard progress > 0 else { return }
        let points = cutPoints(table, cell: cell, sheet: sheet)
        let count = max(2, Int(Double(points.count) * progress))
        noFill()
        stroke(handwriting)
        strokeWeight(1.6)
        strokeCap(.round)
        strokeJoin(.round)
        drawPolyline(Array(points.prefix(count)))
    }

    /// The cut's polyline: at every row's center it sits exactly on the
    /// grid line the row's count names, and between rows it wanders a
    /// little, the way a hand does.
    private func cutPoints(_ table: Rectangle, cell: Double, sheet: Sheet) -> [Vector2] {
        let rows = sheet.cut.count
        func anchor(_ row: Int) -> Vector2 {
            Vector2(table.x + Double(sheet.cut[row]) * cell, table.y + (Double(row) + 0.5) * cell)
        }
        var points = [Vector2(anchor(0).x, table.y - 8)]
        let steps = 12
        for row in 0 ..< rows {
            let from = row == 0 ? Vector2(anchor(0).x, table.y - 8) : anchor(row - 1)
            let to = anchor(row)
            if row > 0 {
                for step in 1 ..< steps {
                    let t = Double(step) / Double(steps)
                    let base = from.lerp(to: to, t)
                    let wiggle = sin(t * .pi * 4 + Double(row) * 1.7) * 3.2 * sin(t * .pi)
                    points.append(Vector2(base.x + wiggle, base.y))
                }
            }
            points.append(to)
        }
        let last = anchor(rows - 1)
        for step in 1 ... steps {
            let t = Double(step) / Double(steps)
            let y = last.y + (table.y + table.height + 8 - last.y) * t
            points.append(Vector2(last.x + sin(t * .pi * 4) * 3.2 * sin(t * .pi), y))
        }
        return points
    }

    /// The bands of lines in `area`: as many lines as the sheet has, evenly
    /// spaced, the straight ones ruled and the wavy ones waved with the
    /// hand's own phase and period, `drawn` of them so far.
    private func drawLines(_ area: Rectangle, sheet: Sheet, drawn: Int, scale: Double) {
        guard sheet.lineCount > 0 else { return }
        let pitch = area.height / Double(sheet.lineCount + 1)
        let amplitude = pitch * 0.2
        noFill()
        stroke(ink)
        strokeCap(.butt)
        strokeJoin(.round)
        for index in 0 ..< min(drawn, sheet.lineCount) {
            let line = sheet.lines[index]
            let y = area.y + pitch * Double(index + 1)
            if line.band.isMultiple(of: 2) {
                // A ruled line, the pen a little heavier or lighter each time.
                strokeWeight(pitch * 0.4 * line.weight)
                drawLine(area.x, y, area.x + area.width, y)
            } else {
                // A wavy line: a wave of the hand's period from edge to edge.
                strokeWeight(pitch * 0.36 * line.weight)
                let period = pitch * line.period
                let step = max(1.0, period / 14)
                var points: [Vector2] = []
                var x = 0.0
                while x < area.width {
                    points.append(Vector2(area.x + x, y + amplitude * sin(x / period * 2 * .pi + line.phase)))
                    x += step
                }
                points.append(Vector2(area.x + area.width, y + amplitude * sin(area.width / period * 2 * .pi + line.phase)))
                drawPolyline(points)
            }
        }
    }

    /// Chance draws the cut; the rule does the rest.
    private func start(sheet number: Int, at moment: Double) {
        randomSeed(number)
        let columns = columnDigits.count
        var cut: [Int] = []
        var position = 1 + min(columns - 1, Int(random(0, Double(columns))))
        for _ in 0 ... rowDigits.count {
            cut.append(position)
            let step = min(2, Int(random(0, 3))) - 1
            position = max(1, min(columns, position + step))
        }
        var taken: [(number: Int, sum: Int)] = []
        for row in 0 ... rowDigits.count {
            for column in 0 ..< cut[row] {
                if row == 0 {
                    taken.append((columnDigits[column], columnDigits[column]))
                } else {
                    let tens = rowDigits[row - 1]
                    taken.append((tens * 10 + columnDigits[column], tens + columnDigits[column]))
                }
            }
        }
        var sums: [Int] = []
        for entry in taken where !sums.contains(entry.sum) {
            sums.append(entry.sum)
        }
        var lines: [(band: Int, weight: Double, phase: Double, period: Double)] = []
        for (band, sum) in sums.enumerated() {
            for _ in 0 ..< sum {
                lines.append((band, random(0.82, 1.1), random(0, 2 * .pi), random(2.1, 2.7)))
            }
        }
        sheet = Sheet(number: number, cut: cut, taken: taken, sums: sums, lines: lines)
        began = moment
    }

    /// Drawing the cut, listing, boxing, ruling every line at `pace`, then
    /// holding.
    private func duration(of sheet: Sheet) -> Double {
        cutting + Double(sheet.taken.count) * listing + boxing + Double(sheet.lineCount) / max(1, pace) + hold
    }
}
