//  Recreation after Hassan Sharif - the angular lines of the late
//  semi-systems: "Lines No 2" (2012, graphite on paper with four draft papers)
//  and the "Six Points Angular Lines" and "Seven Points Angular Lines" sets
//  (2013, drawings with their draft papers, a canvas and a wood relief). A
//  homage, not a reproduction, and not affiliated with or endorsed by the
//  artist or his estate.
//  https://www.alexandergray.com/series/hassan-sharif/hassan-sharif-semi-systems/
//
//  An original Ollin interpretation written from the works. Nothing was
//  ported: the sheets are pencil on paper, the canvas is acrylic, and the
//  numbers were picked by hand.

import Ollin

/// The angular lines (Hassan Sharif, 2012 to 2013). In his last years Sharif
/// went back to the semi-systems of his student days and filled sheets with
/// angular lines: a page ruled into a fine grid and divided into cells, and
/// in every cell one open line of a few straight pieces, its corners on the
/// grid's crossings, each corner a number picked on a draft paper. "Six
/// Points Angular Lines" is such a line through six points, "Seven Points
/// Angular Lines" through seven. The gallery text for the 2013 set says how
/// the second half went: he used calculations and permutations of his own to
/// work out the possibilities for the shape of an angular line, and then,
/// seemingly at random, picked some of them to make at a large scale, one
/// painted black across a red canvas, one cut as a relief in wood. The draft
/// papers hang with the work, so the picking is on the wall beside what it
/// picked.
///
/// This sketch is that wall. A cell is a square of twenty-five crossings
/// numbered 1 to 25 in reading order, and every cell's line is `points`
/// numbers picked without repeating, joined in the order they came: the
/// draft paper writes each pick down as it is made, one row of numbers a
/// cell, and the pen draws the line in pencil at `pace` cells a second. When
/// the sheet is full, one cell is chosen at random, boxed in red on the sheet
/// and on the draft paper, and painted on the canvas as a black band on red,
/// stretched to the canvas the way his was. The wall holds for `hold` seconds
/// and the next sheet begins with new numbers. `columns` and `rows` are the
/// sheet, `firstSheet` numbers the first one, and a press starts the next
/// sheet now.
///
/// Every line exports as one polyline, so `--export-svg` with a frame after
/// the canvas is painted gives the numbers back: every corner of every small
/// line is a crossing of its cell, no number repeats within a line, and the
/// band on the canvas is one of the sheet's lines at a larger scale.
@main
final class AngularLines: Sketch {
    @Param(3 ... 9, icon: "point.3.connected.trianglepath.dotted") var points = 6
    @Param(3 ... 9, icon: "rectangle.split.3x1") var columns = 7
    @Param(3 ... 9, icon: "rectangle.split.1x2") var rows = 6
    @Param(1 ... 60, icon: "pencil.line") var pace = 4.0
    @Param(0 ... 30, icon: "clock") var hold = 5.0
    @Param(1 ... 999, icon: "number") var firstSheet = 1

    override var canvasSize: CanvasSize { .size(1620, 1080) }

    private let wall = Color(hex: 0xE6E3DC)
    private let paper = Color(hex: 0xF6F3EB)
    private let draftPaper = Color(hex: 0xFAF8F2)
    private let pencilGrid = Color(hex: 0xD3CEC2)
    private let graphite = Color(hex: 0x33312F).withAlpha(0.85)
    private let handwriting = Color(hex: 0x2A2B5E)
    private let red = Color(hex: 0xC3342A)
    private let canvasRed = Color(hex: 0x8E2320)
    private let black = Color(hex: 0x141212)

    /// The crossings on a side of a cell.
    private let across = 5

    /// How long the band takes to cross the canvas once it is chosen.
    private let painting = 1.5

    /// One sheet: every line's numbers, and the one chosen.
    private struct Sheet {
        var number: Int
        var columns: Int
        var rows: Int
        /// The picks for each cell, in drawing order, each `points` long.
        var lines: [[Int]]
        /// Which cell goes on the canvas.
        var chosen: Int

        var cells: Int { columns * rows }
    }

    private var sheet: Sheet?
    /// When the current sheet's first line was drawn.
    private var began = 0.0
    private var pressed = 0
    private var program = (points: 0, columns: 0, rows: 0, first: 0)

    override func setup() {
        textFont(OutlineFont.systemMono)
    }

    override func mousePressed() {
        pressed += 1
    }

    override func draw() {
        background(wall)

        let wanted = (points: points, columns: columns, rows: rows, first: firstSheet)
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

        // The sheet, the draft paper, and the canvas, hung in that order.
        let sheetPaper = Rectangle(x: 60, y: 90, width: 800, height: 900)
        let draft = Rectangle(x: 900, y: 90, width: 370, height: 900)
        let canvas = Rectangle(x: 1310, y: 300, width: 250, height: 480)
        noStroke()
        fill(paper)
        drawRect(sheetPaper)
        fill(draftPaper)
        drawRect(draft)

        // The cells: a pitch of five units, the crossings on four of them.
        let unit = 20.0
        let pitch = unit * 5
        let originX = sheetPaper.x + (sheetPaper.width - Double(current.columns) * pitch) / 2
        let originY = sheetPaper.y + (sheetPaper.height - Double(current.rows) * pitch) / 2 - unit
        func cell(_ index: Int) -> Rectangle {
            Rectangle(x: originX + Double(index % current.columns) * pitch + unit / 2,
                      y: originY + Double(index / current.columns) * pitch + unit / 2,
                      width: unit * Double(across - 1), height: unit * Double(across - 1))
        }
        func crossing(_ n: Int, in cell: Rectangle) -> Vector2 {
            Vector2(cell.x + Double((n - 1) % across) * cell.width / Double(across - 1),
                    cell.y + Double((n - 1) / across) * cell.height / Double(across - 1))
        }

        // The graph paper under the block.
        noFill()
        stroke(pencilGrid)
        strokeWeight(1)
        let right = originX + Double(current.columns) * pitch
        let bottom = originY + Double(current.rows) * pitch
        var x = originX
        while x <= right + 0.5 {
            drawLine(x, originY, x, bottom)
            x += unit
        }
        var y = originY
        while y <= bottom + 0.5 {
            drawLine(originX, y, right, y)
            y += unit
        }

        // How far the pen has got: whole lines, then the one under the hand
        // as far as it has been drawn.
        let elapsed = time - began
        let progress = elapsed * pace
        let whole = min(current.cells, Int(progress))
        let chosenAt = Double(current.cells) / max(1, pace)

        strokeCap(.butt)
        strokeJoin(.miter)
        stroke(graphite)
        strokeWeight(unit * 0.13)
        for index in 0 ..< whole {
            let box = cell(index)
            drawPolyline(current.lines[index].map { crossing($0, in: box) })
        }
        if whole < current.cells {
            let box = cell(whole)
            let corners = current.lines[whole].map { crossing($0, in: box) }
            let along = (progress - Double(whole)) * Double(corners.count - 1)
            let done = Int(along)
            var partial = Array(corners.prefix(done + 1))
            if done + 1 < corners.count {
                partial.append(corners[done].lerp(to: corners[done + 1], along - Double(done)))
            }
            drawPolyline(partial)
        }

        // The choice: boxed on the sheet, then painted on the canvas.
        let chosen = elapsed >= chosenAt
        if chosen {
            noFill()
            stroke(red)
            strokeWeight(1.5)
            let box = cell(current.chosen)
            drawRect(Rectangle(x: box.x - unit * 0.4, y: box.y - unit * 0.4,
                               width: box.width + unit * 0.8, height: box.height + unit * 0.8))
        }

        noStroke()
        fill(canvasRed)
        drawRect(canvas)
        if chosen {
            // The canvas has its own grid, the cell stretched to its proportion.
            let inset = Rectangle(x: canvas.x + canvas.width * 0.14, y: canvas.y + canvas.height * 0.09,
                                  width: canvas.width * 0.72, height: canvas.height * 0.82)
            noFill()
            stroke(black.withAlpha(0.18))
            strokeWeight(1)
            for k in 0 ..< across {
                let f = Double(k) / Double(across - 1)
                drawLine(inset.x + inset.width * f, inset.y, inset.x + inset.width * f, inset.y + inset.height)
                drawLine(inset.x, inset.y + inset.height * f, inset.x + inset.width, inset.y + inset.height * f)
            }
            let corners = current.lines[current.chosen].map { crossing($0, in: inset) }
            let along = min(1, (elapsed - chosenAt) / painting) * Double(corners.count - 1)
            let done = Int(along)
            var band = Array(corners.prefix(done + 1))
            if done + 1 < corners.count {
                band.append(corners[done].lerp(to: corners[done + 1], along - Double(done)))
            }
            stroke(black)
            strokeWeight(canvas.width * 0.09)
            strokeCap(.butt)
            strokeJoin(.miter)
            if band.count > 1 {
                drawPolyline(band)
            }
        }

        let title = "\(current.rows * current.columns) angular lines of \(points) points, sheet \(current.number)"
        drawText(title, originX, bottom + unit * 1.6, size: unit * 0.8, color: handwriting, align: .left, .top)

        drawDraftPaper(draft, for: current, drawn: whole + (whole < current.cells ? 1 : 0),
                       chosen: chosen, unit: unit)
    }

    /// The draft paper: the numbered cell, then one row of picks per line.
    private func drawDraftPaper(_ paper: Rectangle, for sheet: Sheet, drawn: Int, chosen: Bool, unit: Double) {
        let left = paper.x + 24
        var y = paper.y + 26
        let size = unit * 0.75
        let leading = size * 1.5

        drawText("draft paper, sheet \(sheet.number)", left, y, size: size, color: handwriting, align: .left, .top)
        y += leading
        drawText("\(points) points of 25, no repeats", left, y, size: size, color: handwriting, align: .left, .top)
        y += leading * 1.5

        // The numbered cell, so the rows can be read.
        let side = unit * 5.2
        let key = Rectangle(x: left + 4, y: y + 4, width: side, height: side)
        noFill()
        stroke(pencilGrid)
        strokeWeight(1)
        for k in 0 ..< across {
            let f = Double(k) / Double(across - 1)
            drawLine(key.x + key.width * f, key.y, key.x + key.width * f, key.y + key.height)
            drawLine(key.x, key.y + key.height * f, key.x + key.width, key.y + key.height * f)
        }
        for n in 1 ... across * across {
            let p = Vector2(key.x + Double((n - 1) % across) * side / Double(across - 1),
                            key.y + Double((n - 1) / across) * side / Double(across - 1))
            noStroke()
            fill(draftPaper)
            drawCircle(center: p, radius: size * 0.62)
            drawText("\(n)", p.x, p.y, size: size * 0.72, color: handwriting, align: .center, .middle)
        }
        y += side + leading * 1.4

        // The picks, one row a line, in two columns down the paper.
        let perColumn = (sheet.cells + 1) / 2
        let columnWidth = (paper.width - 48) / 2
        let top = y
        for index in 0 ..< drawn {
            let column = index / perColumn
            let rowY = top + Double(index % perColumn) * leading
            let x = left + Double(column) * columnWidth
            let text = sheet.lines[index].map { String($0) }.joined(separator: " ")
            drawText(text, x, rowY, size: size, color: handwriting, align: .left, .top)
            if chosen && index == sheet.chosen {
                noFill()
                stroke(red)
                strokeWeight(1.5)
                drawRect(Rectangle(x: x - 6, y: rowY - 3, width: columnWidth - 10, height: leading))
            }
        }
        let listed = top + Double(perColumn) * leading + leading * 0.6
        let tally = chosen ? "chosen: line \(sheet.chosen + 1)" : "\(drawn) of \(sheet.cells)"
        drawText(tally, left, listed, size: size, color: chosen ? red : handwriting, align: .left, .top)
    }

    /// Pick one whole sheet: `points` distinct crossings for every cell, and
    /// the cell that goes on the canvas.
    private func start(sheet number: Int, at moment: Double) {
        randomSeed(number)
        let cells = columns * rows
        let count = across * across
        var lines: [[Int]] = []
        lines.reserveCapacity(cells)
        for _ in 0 ..< cells {
            // The first `points` of a shuffle of 1 to 25, so no number repeats.
            var deck = Array(1 ... count)
            for i in 0 ..< points {
                let j = i + min(count - 1 - i, Int(random(0, Double(count - i))))
                deck.swapAt(i, j)
            }
            lines.append(Array(deck.prefix(points)))
        }
        let chosen = min(cells - 1, Int(random(0, Double(cells))))
        sheet = Sheet(number: number, columns: columns, rows: rows, lines: lines, chosen: chosen)
        began = moment
    }

    /// Drawing every line at `pace`, painting the canvas, then holding.
    private func duration(of sheet: Sheet) -> Double {
        Double(sheet.cells) / max(1, pace) + painting + hold
    }
}
