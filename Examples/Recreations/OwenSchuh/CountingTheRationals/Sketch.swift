//  Recreation after Owen Schuh - the left page of the notebook spread
//  "Natural = Rational / Natural ≠ Real" (2022), gouache on graph paper.
//  A homage, not a reproduction, and not affiliated with or endorsed by the
//  artist.
//  https://www.owenschuh.com
//
//  An original Ollin interpretation, written from the page and from the
//  mathematics the page draws. Nothing was ported: the work is paint on
//  paper, counted out by hand with at most a pocket calculator.

import Ollin

/// "Natural = Rational" (Owen Schuh, 2022). Schuh works from rules, in
/// notebooks and then on canvas, and carries every step out by hand. The left
/// page of this spread is the proof that there are no more fractions than
/// there are counting numbers: lay the fractions out in a table, rows the
/// numerator and columns the denominator, and walk the table along its
/// diagonals, up one and down the next. The walk reaches every cell, so the
/// fractions can be counted off one after another, and a set you can count
/// off is no bigger than the counting numbers themselves. On the page the
/// table is woven: every row is a painted ribbon and so is every column, and
/// where two ribbons meet one of them passes over.
///
/// The sketch keeps that and gives each part of it a job.
///
/// A number is painted the color of its last digit, on a scale that runs from
/// red through the spectrum to black, with white for a nought, so row 7 is
/// blue, row 17 is blue again, and the fabric repeats every ten rows the way
/// the digits do. The over and under is the walk itself: the diagonal a cell
/// sits on is `numerator + denominator`, the walk takes those diagonals in
/// turn, and a cell whose diagonal is even lets the column pass over while an
/// odd one lets the row pass. Because that number changes with every step
/// sideways or down, the result is the plain over-one-under-one weave of a
/// piece of cloth: the fabric's texture is the path.
///
/// A fraction that is not in lowest terms was already counted lower down the
/// walk, so 2/4 arrives after 1/2 and is nothing new. The walk still visits
/// it, and the page leaves it as a hole: the two ribbons pass and the crossing
/// stays the color of the paper. What is left painted is exactly the fractions
/// in lowest terms, one for each counting number, which is the bijection the
/// page is about.
///
/// The loom fills at `pace` cells a second, diagonal after diagonal from the
/// corner. `table` is how much of the endless table the page shows, `hold` is
/// how long the finished page stays up, and `firstPage` numbers the first one:
/// the count is the same every time, but the hand is not, so each page lays
/// its paint down a little differently. A press starts the next page.
///
/// Every ribbon and every crossing exports as a rect, so `--export-svg` with a
/// frame after the weave is finished gives the table back as marks: one
/// crossing for each of the `table * table` cells, paper colored exactly where
/// the fraction was already counted.
@main
final class CountingTheRationals: Sketch {
    @Param(6 ... 16, icon: "square.grid.3x3") var table = 12
    @Param(1 ... 40, icon: "paintbrush.pointed") var pace = 10.0
    @Param(0 ... 30, icon: "clock") var hold = 5.0
    @Param(1 ... 999, icon: "number") var firstPage = 1

    override var canvasSize: CanvasSize { .size(920, 1200) }

    private let paper = Color(hex: 0xE7DFD2)
    private let ruling = Color(hex: 0xD3CBB9)
    private let pencil = Color(hex: 0xB3AA98)
    private let ink = Color(hex: 0x2B2622)
    private let blue = Color(hex: 0x2775C4)
    private let red = Color(hex: 0xD93E33)

    /// The ten digits, painted. The scale runs from a nought left white
    /// through red and the spectrum to black, the way the notebook's key does.
    private nonisolated static let digits: [Color] = [
        Color(hex: 0xFBF7EC), Color(hex: 0xD93E33), Color(hex: 0xE4633C),
        Color(hex: 0xEFA23F), Color(hex: 0xF2C432), Color(hex: 0xBFCB45),
        Color(hex: 0x127F6B), Color(hex: 0x2775C4), Color(hex: 0x22386A),
        Color(hex: 0x1E1A19),
    ]

    /// One cell of the table: the fraction `numerator / denominator`.
    private struct Cell {
        var numerator: Int
        var denominator: Int

        /// The diagonal the cell sits on. The walk takes these in turn.
        var diagonal: Int { numerator + denominator }

        /// Whether the fraction is new, which is to say in lowest terms.
        var isNew: Bool { CountingTheRationals.greatestCommonDivisor(numerator, denominator) == 1 }
    }

    /// One page: the walk it draws and the hand that draws it.
    private struct Page {
        var number: Int
        var table: Int
        var walk: [Cell]
        /// A small offset and a width for every row and every column, so a
        /// ribbon runs straight but a little off true, the way a hand lays it.
        var rows: [(off: Double, width: Double)]
        var columns: [(off: Double, width: Double)]
        /// How many fractions had been counted after each step of the walk.
        var counted: [Int]
    }

    private var page: Page?
    private var began = 0.0
    private var pressed = 0
    private var program = (table: 0, first: 0)

    override func setup() {
        textFont(OutlineFont.system)
    }

    override func mousePressed() {
        pressed += 1
    }

    override func draw() {
        background(paper)

        let wanted = (table: table, first: firstPage)
        if page == nil || program != wanted {
            program = wanted
            start(page: firstPage, at: time)
        }
        while pressed > 0 {
            pressed -= 1
            start(page: (page?.number ?? firstPage) + 1, at: time)
        }
        while let current = page, time - began >= duration(of: current) {
            start(page: current.number + 1, at: began + duration(of: current))
        }
        guard let current = page else { return }

        drawRuling()
        drawText("Natural = Rational", width / 2, 84, size: 42, color: ink, align: .center, .top)

        // The table, square on the page.
        let side = 700.0
        let origin = Vector2((width - side) / 2, 178)
        let pitch = side / Double(current.table)
        let ribbon = pitch * 0.6

        func truth(_ index: Int) -> Double { (Double(index) - 0.5) * pitch }
        func center(_ cell: Cell) -> Vector2 {
            Vector2(origin.x + truth(cell.denominator) + current.columns[cell.denominator - 1].off,
                    origin.y + truth(cell.numerator) + current.rows[cell.numerator - 1].off)
        }

        // The numbers along the two edges, in pencil, so the table can be read.
        for index in 1 ... current.table {
            let along = Double(index) - 0.5
            drawText("\(index)", origin.x + along * pitch, origin.y - 10,
                     size: min(15, pitch * 0.3), color: pencil, align: .center, .bottom)
            drawText("\(index)", origin.x - 10, origin.y + along * pitch,
                     size: min(15, pitch * 0.3), color: pencil, align: .right, .center)
        }

        // The weave, one cell per step of the walk.
        let woven = min(current.walk.count, Int((time - began) * pace))
        noStroke()
        for step in 0 ..< woven {
            let cell = current.walk[step]
            let middle = center(cell)
            let down = ribbon * current.columns[cell.denominator - 1].width
            let across = ribbon * current.rows[cell.numerator - 1].width
            // The two ribbons run the whole length of the cell, so a column's
            // pieces abut into one unbroken stripe; only the crossing tells
            // which of them passed over.
            fill(Self.color(of: cell.denominator))
            drawRect(center: Vector2(middle.x, origin.y + truth(cell.numerator)), width: down, height: pitch)
            fill(Self.color(of: cell.numerator))
            drawRect(center: Vector2(origin.x + truth(cell.denominator), middle.y), width: pitch, height: across)
            fill(crossing(of: cell))
            drawRect(center: middle, width: down, height: across)
        }

        // Where the shuttle is now.
        if woven > 0, woven < current.walk.count {
            let middle = center(current.walk[woven - 1])
            noFill()
            stroke(red)
            strokeWeight(2)
            drawRect(center: middle, width: ribbon + 10, height: ribbon + 10)
            noStroke()
        }

        drawFoot(under: origin.y + side, for: current, woven: woven)
        drawInfinity(at: Vector2(width / 2, 1128))
    }

    /// The color a crossing takes: the ribbon the walk lets pass over, or the
    /// paper where the fraction had already been counted.
    private func crossing(of cell: Cell) -> Color {
        guard cell.isNew else { return paper }
        return cell.diagonal % 2 == 0
            ? Self.color(of: cell.denominator)
            : Self.color(of: cell.numerator)
    }

    /// A number is painted the color of its last digit.
    private nonisolated static func color(of number: Int) -> Color {
        digits[number % 10]
    }

    private nonisolated static func greatestCommonDivisor(_ a: Int, _ b: Int) -> Int {
        var (a, b) = (a, b)
        while b != 0 { (a, b) = (b, a % b) }
        return a
    }

    /// The graph paper the page is drawn on.
    private func drawRuling() {
        noFill()
        stroke(ruling)
        strokeWeight(1)
        var x = 0.0
        while x <= width { drawLine(x, 0, x, height); x += 23 }
        var y = 0.0
        while y <= height { drawLine(0, y, width, y); y += 23 }
        noStroke()
    }

    /// What the page says about itself, and the key to the colors.
    private func drawFoot(under bottom: Double, for page: Page, woven: Int) {
        let left = (width - 700.0) / 2
        var y = bottom + 34
        let size = 20.0

        drawText("rows the numerator, columns the denominator.", left, y,
                 size: size, color: ink, align: .left, .top)
        y += 29
        drawText("the walk takes the diagonals in turn and reaches every cell.", left, y,
                 size: size, color: ink, align: .left, .top)
        y += 29
        let counted = woven > 0 ? page.counted[woven - 1] : 0
        let done = woven >= page.walk.count
        let tally: String
        if done {
            tally = "\(counted) fractions counted in \(page.walk.count) cells, and the table goes on."
        } else if let cell = woven > 0 ? page.walk[woven - 1] : nil {
            tally = cell.isNew
                ? "counted so far: \(counted).  \(cell.numerator)/\(cell.denominator) is the \(counted)."
                : "counted so far: \(counted).  \(cell.numerator)/\(cell.denominator) was counted already."
        } else {
            tally = "counted so far: 0."
        }
        drawText(tally, left, y, size: size, color: done ? red : ink, align: .left, .top)

        // The key: a number is the color of its last digit.
        y += 46
        let chip = 26.0
        for digit in 0 ... 9 {
            let x = left + Double(digit) * (chip + 12)
            noStroke()
            fill(Self.digits[digit])
            drawRect(x, y, chip, chip)
            if digit == 0 {
                noFill()
                stroke(pencil)
                strokeWeight(1)
                drawRect(x, y, chip, chip)
                noStroke()
            }
            drawText("\(digit)", x + chip / 2, y + chip + 6, size: 15, color: pencil, align: .center, .top)
        }
        drawText("the color of its last digit", left + 10 * (chip + 12) + 8, y + chip / 2,
                 size: size, color: ink, align: .left, .center)
    }

    /// The hand-drawn loop at the foot of the page: the table goes on.
    private func drawInfinity(at middle: Vector2) {
        let radius = 13.0
        noFill()
        stroke(blue)
        strokeWeight(3)
        drawCircle(middle.x - radius, middle.y, radius)
        drawCircle(middle.x + radius, middle.y, radius)
        noStroke()
    }

    /// Lay out one page: the zigzag over a table of `table` by `table`, and a
    /// hand for it.
    private func start(page number: Int, at moment: Double) {
        let size = table
        var walk: [Cell] = []
        for diagonal in 2 ... 2 * size {
            let low = max(1, diagonal - size), high = min(size, diagonal - 1)
            let numerators = diagonal % 2 == 1 ? Array(low ... high) : Array((low ... high).reversed())
            for numerator in numerators {
                walk.append(Cell(numerator: numerator, denominator: diagonal - numerator))
            }
        }
        var counted: [Int] = []
        var running = 0
        for cell in walk {
            if cell.isNew { running += 1 }
            counted.append(running)
        }
        randomSeed(number)
        let reach = 700.0 / Double(size) * 0.045
        func hand() -> [(off: Double, width: Double)] {
            (0 ..< size).map { _ in (off: random(-reach, reach), width: random(0.9, 1.08)) }
        }
        let rows = hand()
        let columns = hand()
        page = Page(number: number, table: size, walk: walk, rows: rows, columns: columns, counted: counted)
        began = moment
    }

    /// Weaving the whole table at `pace`, then holding the page.
    private func duration(of page: Page) -> Double {
        Double(page.walk.count) / max(1, pace) + hold
    }
}
