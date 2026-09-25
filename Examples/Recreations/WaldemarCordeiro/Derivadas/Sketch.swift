//  Recreation after Waldemar Cordeiro and Giorgio Moscati - Derivadas de uma
//  imagem (1969), made on the IBM 360/44 of the Physics Department of the
//  University of São Paulo: four line-printer sheets, the transformation of
//  degree zero (a poster read to seven levels of dark) and its first,
//  second, and third derivatives. Read from the three sheets in the visgraf
//  gallery of the 1993 Arteônica exhibition, the degree-one lithograph at the
//  V&A, the degree-zero sheet at Luciana Brito Galeria, and Moscati's own
//  account of how the work was made. A homage, not a reproduction, and not
//  affiliated with or endorsed by the artist's estate or by Giorgio Moscati.
//  https://www.visgraf.impa.br/Gallery/waldemar/obras/deriv.htm
//  https://www.visgraf.impa.br/Gallery/waldemar/moscati/derivad_.htm
//  https://collections.vam.ac.uk/item/O1426285/derivadas-de-uma-imagem-transformacao-print-waldemar-cordeiro/
//  https://lucianabritogaleria.com.br/art-fairs/14/works/artworks-11206-waldemar-cordeiro-derivadas-de-uma-imagem-transformacao-em-grau-0-1969/
//
//  An original Ollin interpretation, written from the sheets and from
//  Moscati's description of the operation. Nothing was ported: the 1969
//  program is known here only through that description.

import Foundation
import Ollin
import OllinSamplePhotos

/// The derivatives of a picture (Waldemar Cordeiro with the physicist Giorgio
/// Moscati, São Paulo, 1969). Cordeiro wanted a picture with strong human
/// content handed to "a cold, calculating machine", and chose a Valentine's
/// Day poster of a young couple. He divided it into 98 by 112 points, 10,976
/// in all, and gave each a number from 0 to 6 by how dark it was. Moscati,
/// asking which transformation a scientist uses most, answered the
/// derivative, and wrote a program that took the difference between each
/// point and the one before it, always as a positive number, and was made to
/// find a break in the picture whichever way it ran. The line printer
/// printed the numbers as characters, and for the darkest points it printed
/// the same line again without advancing the paper, one character struck
/// over another. They fed the derivative back in and derived it again, and
/// then a third time. The work is the four sheets: degree zero, the picture
/// as levels; degree one, its contours; degree two, every contour doubled;
/// degree three, the picture nearly gone. The printer's cells are taller than
/// they are wide, so the picture came out stretched, and they kept it that
/// way.
///
/// This sketch does the same operation on one of the bundled photographs
/// (`picture`), never the poster. The largest 98 by 112 box of the photograph
/// is cut into blocks; a block's tone is its mean in linear light, read as
/// luma on the encoded channels; the lightest and darkest blocks set the ends
/// of the scale, and the range between is cut into seven equal levels. A
/// derivative is the larger of the two positive differences, from the point
/// to its left and from the point above it (the first row and column have
/// nothing before them and count zero that way), which is one reading of
/// "a break whichever way it runs", and it stays on the same seven levels, so
/// it can be derived again. Each level is printed as characters whose ink
/// rises with the level, measured in this face: a blank, a dash, a plus, an
/// X, an M, then an M struck over with an X, and an M, a W, and a number
/// sign struck on one place. The sheet keeps the printer's proportion, cells
/// ten to the inch across and eight down, so the picture stretches as theirs
/// did.
///
/// The printer prints each sheet a line at a time, `linesPerSecond` lines a
/// second (the printers of the day ran at 600 to 1,100 lines a minute), and
/// strikes a dark line again before the paper moves. The sheet holds for
/// `hold` seconds, the paper feeds, and the next degree prints. `sheets`
/// holds one degree instead of the four in turn.
///
/// `--export-svg` gives the sheet back as the glyphs the printer struck, one
/// outline per strike.
@main
final class Derivadas: Sketch {
    enum Picture: String, CaseIterable, ParamOption { case profile, portrait, scarf }
    enum Sheets: String, CaseIterable, ParamOption { case all, zero, one, two, three }

    @Param(icon: "photo") var picture = Picture.profile
    @Param(icon: "doc.on.doc") var sheets = Sheets.all
    @Param(2 ... 60, icon: "printer") var linesPerSecond = 18.0
    @Param(0 ... 20, icon: "hourglass") var hold = 4.0

    override var canvasSize: CanvasSize { .size(1080, 1472) }
    override var loopDuration: Double? { sheetSeconds * Double(shownDegrees.count) }

    // The printer's grid: 98 points across, 112 down, in cells ten to the
    // inch across and eight down.
    static let columns = 98
    static let rows = 112
    static let cellWidth = 8.8
    static let cellHeight = cellWidth * 1.25
    static let left = (1080 - Double(columns) * cellWidth) / 2
    static let top = 170.0

    /// The characters struck on one place for each level, lightest first.
    static let strikes: [[Character]] = [
        [], ["-"], ["+"], ["X"], ["M"], ["M", "X"], ["M", "W", "#"],
    ]

    static let titles = ["TRANSFORMACAO EM GRAU ZERO", "TRANSFORMACAO EM GRAU UM",
                         "TRANSFORMACAO EM GRAU DOIS", "TRANSFORMACAO EM GRAU TRES"]

    private let paper = Color(hex: 0xF0EDE4)
    private let ink = Color(hex: 0x1D1C1A)
    private let feedSeconds = 1.2

    /// Each pass of the printer over each line, recorded once:
    /// `passes[degree][row][strike]`, nil where the pass strikes nothing.
    private var passes: [[[Batch?]]] = []
    private var titleLines: [Batch] = []
    private var builtFor: Picture?
    private var face = OutlineFont.systemMono

    private var shownDegrees: [Int] {
        switch sheets {
        case .all: [0, 1, 2, 3]
        case .zero: [0]
        case .one: [1]
        case .two: [2]
        case .three: [3]
        }
    }

    /// A title line and 112 rows, a slot each, then the hold and the feed.
    private var printSeconds: Double { Double(Self.rows + 1) / linesPerSecond }
    private var sheetSeconds: Double { printSeconds + hold + feedSeconds }

    override func setup() {
        face = OutlineFont(name: "Menlo-Bold") ?? .systemMono
        build()
    }

    override func draw() {
        if builtFor != picture { build() }
        background(paper)

        let order = shownDegrees
        let lap = sheetSeconds * Double(order.count)
        let t = time.truncatingRemainder(dividingBy: lap)
        let index = min(order.count - 1, Int(t / sheetSeconds))
        let local = t - Double(index) * sheetSeconds
        let degree = order[index]

        // Once the hold is over the paper feeds the printed page up and out.
        let feedStart = printSeconds + hold
        let lift = local > feedStart ? smoothstep(0, 1, (local - feedStart) / feedSeconds) : 0

        withState {
            translate(0, -lift * height)
            drawPerforations()
            printSheet(degree, slots: local * linesPerSecond)
        }
    }

    // MARK: - Reading the picture

    private func build() {
        let image = photo(picture).load()
        var grids = [Self.levels(of: image)]
        for _ in 1 ... 3 { grids.append(Self.derived(grids[grids.count - 1])) }

        withState {
            textFont(face)
            textSize(100)
            // A character is set a little smaller than its cell, so the struck
            // marks stand apart the way the printer's did.
            textSize(0.78 * Self.cellWidth * 100 / textWidth("M"))
            textAlign(.center, .middle)
            textMode(.atlas)
            noStroke()
            passes = grids.enumerated().map { degree, grid in
                grid.enumerated().map { r, row in
                    (0 ..< 3).map { k -> Batch? in
                        let marks = row.enumerated().compactMap { c, level in
                            k < Self.strikes[level].count ? (c, Self.strikes[level][k]) : nil
                        }
                        guard !marks.isEmpty else { return nil }
                        return makeBatch {
                            fill(ribbon(degree, row: r, pass: k))
                            for (c, mark) in marks {
                                drawText(String(mark), Self.x(c), Self.y(r))
                            }
                        }
                    }
                }
            }
            titleLines = Self.titles.enumerated().map { degree, title in
                makeBatch {
                    fill(ribbon(degree, row: -3, pass: 0))
                    for (c, mark) in title.enumerated() where mark != " " {
                        drawText(String(mark), Self.x(c), Self.y(-3))
                    }
                }
            }
        }
        builtFor = picture
    }

    /// The middle of column `c` and of row `r`.
    static func x(_ c: Int) -> Double { left + (Double(c) + 0.5) * cellWidth }
    static func y(_ r: Int) -> Double { top + (Double(r) + 0.5) * cellHeight }

    /// The ribbon lays a slightly different weight of ink on every pass, and
    /// ink struck over ink is darker.
    private func ribbon(_ degree: Int, row: Int, pass: Int) -> Color {
        ink.withAlpha(0.8 + 0.12 * Self.unit(degree * 1_000_003 + (row + 8) * 7 + pass))
    }

    private func photo(_ picture: Picture) -> SamplePhoto {
        switch picture {
        case .portrait: .portrait
        case .profile: .profile
        case .scarf: .scarf
        }
    }

    /// Degree zero: the largest 98 by 112 box of the picture, centered, cut into
    /// blocks on whole pixels, each block's mean tone scaled between the
    /// lightest and darkest block and cut into seven equal levels.
    static func levels(of image: Image) -> [[Int]] {
        let w = Double(image.width), h = Double(image.height)
        var boxWidth = h * Double(columns) / Double(rows)
        var boxHeight = h
        if boxWidth > w {
            boxWidth = w
            boxHeight = w * Double(rows) / Double(columns)
        }
        let x0 = (w - boxWidth) / 2, y0 = (h - boxHeight) / 2

        var dark: [[Double]] = []
        for r in 0 ..< rows {
            let ya = (y0 + Double(r) * boxHeight / Double(rows)).rounded(.down)
            let yb = (y0 + Double(r + 1) * boxHeight / Double(rows)).rounded(.down)
            var line: [Double] = []
            for c in 0 ..< columns {
                let xa = (x0 + Double(c) * boxWidth / Double(columns)).rounded(.down)
                let xb = (x0 + Double(c + 1) * boxWidth / Double(columns)).rounded(.down)
                let mean = image.averageColor(in: Rectangle(x: xa, y: ya, width: xb - xa, height: yb - ya))
                line.append(1 - (0.2126 * mean.red + 0.7152 * mean.green + 0.0722 * mean.blue))
            }
            dark.append(line)
        }
        let all = dark.flatMap { $0 }
        let lo = all.min() ?? 0, hi = all.max() ?? 1
        let span = max(hi - lo, 1e-9)
        return dark.map { line in
            line.map { min(6, Int(((($0 - lo) / span) * 7).rounded(.down))) }
        }
    }

    /// The derivative: at each point, the larger of the positive differences
    /// from the point to its left and from the point above it.
    static func derived(_ grid: [[Int]]) -> [[Int]] {
        var out = grid
        for r in grid.indices {
            for c in grid[r].indices {
                let across = c > 0 ? abs(grid[r][c] - grid[r][c - 1]) : 0
                let down = r > 0 ? abs(grid[r][c] - grid[r - 1][c]) : 0
                out[r][c] = max(across, down)
            }
        }
        return out
    }

    // MARK: - Printing

    /// Everything the printer has struck by `slots` line slots into the sheet:
    /// slot 0 is the title, slot `r + 1` is row `r`, and a row's second and
    /// third strikes land a third and two thirds of the way through its slot.
    private func printSheet(_ degree: Int, slots: Double) {
        guard degree < passes.count else { return }
        if slots > 0 { drawBatch(titleLines[degree]) }
        let rowsDone = min(Self.rows, Int(slots) - 1)
        if rowsDone > 0 {
            for r in 0 ..< rowsDone {
                for case let pass? in passes[degree][r] { drawBatch(pass) }
            }
        }
        let current = Int(slots) - 1
        if current >= 0, current < Self.rows {
            let into = slots - Double(current + 1)
            for k in 0 ..< 3 where Double(k) / 3 <= into {
                if let pass = passes[degree][current][k] { drawBatch(pass) }
            }
        }
    }

    /// The perforations between one page of the continuous form and the next.
    private func drawPerforations() {
        stroke(ink.withAlpha(0.18))
        strokeWeight(1)
        for y in [0.0, height] {
            var x = 6.0
            while x < width {
                drawLine(x, y, x + 5, y)
                x += 11
            }
        }
    }

    /// A fixed number in 0 ..< 1 for an integer.
    static func unit(_ n: Int) -> Double {
        var z = UInt64(bitPattern: Int64(n)) &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}
