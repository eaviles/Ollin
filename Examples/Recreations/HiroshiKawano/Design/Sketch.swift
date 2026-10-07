//  Recreation after Hiroshi Kawano - "Design 3-1. Data 4, 5, 6, 6, 6" and
//  "Design 3-2. Data 4, 4, 5, 5, 5" (1964, gouache on paper after a design
//  computed on the OKITAC 5090A at the University of Tokyo, 33.2 x 23 cm),
//  ZKM | Center for Art and Media Karlsruhe. A homage, not a reproduction,
//  and not affiliated with or endorsed by the artist or his estate.
//  https://zkm.de/en/artworks/design-3-1-data-4-5-6-6-6-design-1-4-data-1-2-3-3-3
//  https://zkm.de/en/artworks/design-3-2-data-4-4-5-5-5-design-1-2-data-1-1-2-2-2
//
//  An original Ollin interpretation, written from the two sheets. Nothing was
//  ported: no program text was read, and the colors were painted by hand onto
//  a printout. The counts below were measured off photographs of the sheets;
//  reading the five numbers of a title as five bands of rows is this sketch's
//  reading, not a documented fact.

import Ollin

/// Design (Hiroshi Kawano, Tokyo, 1964). A philosopher of aesthetics taught
/// himself assembly language in the autumn of 1963 to test a theory: that a
/// picture is information, and that what a style tends to do next can be
/// counted and then run forward. He counted how often one color followed
/// another in pictures of the kind he admired, gave the counts to the
/// university's computer as a Markov chain, and let it decide a grid of cells
/// one after another, each from the two before it. The line printer typed the
/// decisions as characters, and he painted them in gouache, sometimes with
/// his students' help. These two sheets are 40 cells across and 39 down, in
/// black, red, blue, yellow and white, and their titles carry five data
/// numbers each.
///
/// This sketch keeps that rule. The cells are decided in reading order, each
/// row carrying on from the end of the one above, by a chain of order 2: the
/// next paint is chosen from what followed the last two paints in the counts.
/// The counts were measured off the two sheets themselves, cell by cell, and
/// they show the habit that makes the pictures: a run of color rarely turns
/// into another color directly, it ends in black and the black hands over to
/// white, and white hands over through black to the next color. The rows fall
/// into five bands, one for each number of the title, and each band is walked
/// with the counts of its number, so a sheet changes its mind partway down.
/// `look` picks the title (`design31`, data 4, 5, 6, 6, 6, or `design32`,
/// data 4, 4, 5, 5, 5); `columns` and `rows` are the grid; the seed deals the
/// sheet, and a press deals the next one.
///
/// Over one cycle of `seconds` the printer types the sheet row by row, a code
/// for each cell, then the paint goes on cell by cell in the order the chain
/// decided, holds, and fades back to paper, which is also the export loop.
///
/// Every painted cell exports as one square, so `--export-svg` with a frame
/// in the hold gives the grid back cell by cell, and reading it in rows gives
/// back the counts it was walked with.
@main
final class Design: Sketch {
    enum Look: String, CaseIterable, ParamOption {
        case design31, design32

        /// The five data numbers of the title, one per band of rows.
        var data: [Int] {
            switch self {
            case .design31: [4, 5, 6, 6, 6]
            case .design32: [4, 4, 5, 5, 5]
            }
        }

        var title: String {
            switch self {
            case .design31: "DESIGN 3-1.  DATA 4, 5, 6, 6, 6"
            case .design32: "DESIGN 3-2.  DATA 4, 4, 5, 5, 5"
            }
        }
    }

    @Param(icon: "doc.text") var look = Look.design32
    @Param(8 ... 80, icon: "square.grid.3x3") var columns = 40
    @Param(5 ... 80, icon: "line.3.horizontal") var rows = 39
    @Param(4 ... 60, icon: "clock") var seconds = 16.0

    override var canvasSize: CanvasSize { .square(1080) }
    override var loopDuration: Double? { seconds }

    /// The five gouaches, in the order the counts list them.
    private enum Paint: Int, CaseIterable {
        case white, black, red, blue, yellow

        init(_ letter: Character) {
            self.init(rawValue: Array("WKRBY").firstIndex(of: letter) ?? 0)!
        }

        /// What the printer types for the cell before it is painted.
        var code: String { ["1", "2", "3", "4", "5"][rawValue] }
    }

    /// The counts, measured off the two sheets in reading order: after the
    /// two paints on the left (W white, K black, R red, B blue, Y yellow),
    /// how many times each paint came next, in that same order. A transition
    /// is counted under the data number of the band of rows it lands in;
    /// data 4 heads both sheets, so it pools the two.
    private static let counted: [(data: Int, table: [(String, [Int])])] = [
        (4, [
            ("WW", [292, 40, 5, 0, 0]), ("WK", [7, 8, 0, 9, 17]), ("WR", [0, 0, 7, 0, 0]),
            ("WB", [0, 0, 0, 2, 0]), ("KW", [37, 1, 2, 2, 0]), ("KK", [14, 71, 0, 0, 1]),
            ("KR", [0, 0, 3, 0, 0]), ("KB", [0, 0, 0, 10, 0]), ("KY", [2, 1, 0, 0, 18]),
            ("RW", [1, 0, 0, 0, 0]), ("RK", [3, 6, 0, 0, 3]), ("RR", [1, 12, 88, 0, 0]),
            ("BK", [5, 1, 3, 1, 0]), ("BR", [0, 0, 2, 0, 0]), ("BB", [0, 10, 2, 107, 0]),
            ("YW", [7, 0, 0, 0, 0]), ("YK", [12, 0, 0, 1, 0]), ("YR", [0, 0, 1, 0, 0]),
            ("YY", [5, 12, 1, 0, 123]),
        ]),
        (5, [
            ("WW", [313, 36, 1, 5, 4]), ("WK", [6, 9, 6, 7, 11]), ("WR", [0, 0, 1, 0, 0]),
            ("WB", [1, 0, 1, 5, 0]), ("WY", [1, 0, 0, 0, 3]), ("KW", [41, 3, 0, 2, 0]),
            ("KK", [17, 139, 14, 0, 3]), ("KR", [0, 0, 27, 0, 0]), ("KB", [0, 0, 0, 10, 0]),
            ("KY", [0, 0, 0, 0, 14]), ("RW", [2, 0, 0, 0, 0]), ("RK", [16, 8, 4, 0, 0]),
            ("RR", [2, 28, 236, 1, 0]), ("RB", [0, 0, 0, 1, 0]), ("BW", [2, 0, 0, 0, 0]),
            ("BK", [3, 6, 3, 2, 0]), ("BR", [0, 0, 3, 0, 0]), ("BB", [2, 14, 2, 160, 0]),
            ("YW", [1, 0, 0, 0, 0]), ("YK", [3, 11, 0, 0, 0]), ("YR", [0, 0, 1, 0, 0]),
            ("YB", [0, 0, 0, 2, 0]), ("YY", [0, 14, 1, 2, 30]),
        ]),
        (6, [
            ("WW", [178, 11, 10, 8, 9]), ("WK", [2, 11, 4, 1, 3]), ("WR", [0, 1, 10, 0, 0]),
            ("WB", [1, 1, 1, 5, 0]), ("WY", [0, 1, 0, 0, 8]), ("KW", [28, 0, 0, 0, 0]),
            ("KK", [11, 182, 14, 1, 0]), ("KR", [0, 1, 21, 0, 0]), ("KB", [0, 0, 0, 2, 0]),
            ("KY", [0, 0, 1, 0, 2]), ("RW", [4, 9, 0, 0, 0]), ("RK", [12, 11, 2, 0, 0]),
            ("RR", [12, 23, 235, 2, 1]), ("RB", [0, 0, 0, 3, 0]), ("RY", [0, 0, 0, 0, 1]),
            ("BW", [5, 1, 1, 0, 0]), ("BK", [0, 1, 2, 0, 0]), ("BR", [0, 0, 4, 1, 0]),
            ("BB", [5, 2, 4, 19, 0]), ("YW", [1, 0, 0, 0, 0]), ("YK", [3, 4, 0, 0, 0]),
            ("YR", [1, 0, 3, 0, 0]), ("YB", [0, 0, 0, 1, 0]), ("YY", [1, 6, 3, 1, 8]),
        ]),
    ]

    // The sheet and the gouaches, measured off the photographs.
    private let table = Color(hex: 0x2B2926)
    private let paper = Color(hex: 0xEEE7DE)
    private let pencil = Color(hex: 0x6E6A66)
    private let printerInk = Color(hex: 0x3C3A44)
    private let gouache: [Color] = [
        Color(hex: 0xF5F0E9), Color(hex: 0x171616), Color(hex: 0xD33126),
        Color(hex: 0x4066E3), Color(hex: 0xE6BC21),
    ]

    private var sheet: [[Paint]] = []
    private var codes: [Batch] = []
    private var dealtFor: (look: Look, seed: Int, columns: Int, rows: Int)?
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
        let wanted = (look: look, seed: variation, columns: columns, rows: rows)
        if dealtFor.map({ $0 != wanted }) ?? true {
            dealtFor = wanted
            sheet = deal()
            codes = []
        }

        background(table)
        let page = Rectangle(center: Vector2(width / 2, height / 2),
                             width: 0.926 * height * 23 / 33.2, height: 0.926 * height)
        noStroke()
        fill(paper)
        drawRect(page)

        // The grid sits in the lower part of the sheet, as on both originals;
        // a cell is a little taller than it is wide, as the printer's were.
        let box = Rectangle(x: page.x + 0.072 * page.width, y: page.y + 0.324 * page.height,
                            width: 0.862 * page.width, height: 0.59 * page.height)
        let aspect = 12.0 / 11.7
        let cellWidth = min(box.width / Double(columns), box.height / (Double(rows) * aspect))
        let cell = Vector2(cellWidth, cellWidth * aspect)
        let grid = Rectangle(x: box.x + (box.width - cell.x * Double(columns)) / 2, y: box.y,
                             width: cell.x * Double(columns), height: cell.y * Double(rows))
        if codes.isEmpty { codes = printRows(grid: grid, cell: cell) }

        drawText(look.title, page.x + 0.13 * page.width, page.y + 0.09 * page.height,
                 size: 0.034 * page.width, color: pencil, align: .left, .top)
        drawText("seed \(variation)", page.x + 0.13 * page.width, page.y + 0.15 * page.height,
                 size: 0.026 * page.width, color: pencil, align: .left, .top)
        noFill()
        stroke(pencil.withAlpha(0.55))
        strokeWeight(1)
        drawRect(grid)
        noStroke()

        // Printing, then painting in the order the chain decided, then the
        // hold and the fade back to paper.
        let phase = loopProgress(over: seconds)
        let count = rows * columns
        let printed = min(rows, Int(Double(rows) * min(1, phase / 0.3)))
        let painted = phase < 0.3 ? 0 : min(count, Int(Double(count) * min(1, (phase - 0.3) / 0.35)))

        // A row's codes show until its last cell is painted; the paint goes on
        // over them, so the row under the brush shows its codes ahead of it.
        for r in 0 ..< printed where (r + 1) * columns > painted {
            drawBatch(codes[r])
        }
        for i in 0 ..< painted {
            let r = i / columns, c = i % columns
            fill(gouache[sheet[r][c].rawValue])
            drawRect(grid.x + Double(c) * cell.x, grid.y + Double(r) * cell.y, cell.x, cell.y)
        }

        if phase > 0.9 {
            fill(paper.withAlpha(smoothstep(0.9, 1, phase)))
            drawRect(grid.x - 2, grid.y - 2, grid.width + 4, grid.height + 4)
        }
    }

    /// Walks the sheet: one chain per data number, each learned from its
    /// counts, and every cell chosen by the chain of its band from the last
    /// two cells decided, across the end of a row and across a band.
    private func deal() -> [[Paint]] {
        var chains: [Int: MarkovChain<Paint>] = [:]
        for (data, table) in Self.counted {
            // Each chain keeps its own generator, seeded from the sheet's seed
            // and its data number, so a band never moves another band's rolls.
            var chain = MarkovChain<Paint>(order: 2, seed: variation &* 7919 &+ data)
            for (context, counts) in table {
                let before = context.map(Paint.init)
                for (k, times) in counts.enumerated() {
                    chain.learn(Paint(rawValue: k)!, after: before, times: times)
                }
            }
            chains[data] = chain
        }

        var last: [Paint] = []
        var cells: [[Paint]] = []
        for r in 0 ..< rows {
            let data = look.data[r * 5 / rows]
            var row: [Paint] = []
            for _ in 0 ..< columns {
                chains[data]!.start(with: last)
                let paint = chains[data]!.next() ?? .white
                row.append(paint)
                last = Array((last + [paint]).suffix(2))
            }
            cells.append(row)
        }
        return cells
    }

    /// The printout: every row's codes as one retained batch, a character
    /// centered in each cell.
    private func printRows(grid: Rectangle, cell: Vector2) -> [Batch] {
        var batches: [Batch] = []
        withState {
            textFont(OutlineFont.systemMono)
            textSize(100)
            textSize(0.62 * cell.x * 100 / textWidth("M"))
            textAlign(.center, .middle)
            textMode(.atlas)
            noStroke()
            fill(printerInk)
            for r in 0 ..< rows {
                batches.append(makeBatch {
                    for c in 0 ..< columns {
                        drawText(sheet[r][c].code, grid.x + (Double(c) + 0.5) * cell.x,
                                 grid.y + (Double(r) + 0.5) * cell.y)
                    }
                })
            }
        }
        return batches
    }
}
