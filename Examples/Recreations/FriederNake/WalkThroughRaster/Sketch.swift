//  Recreation after Frieder Nake - "Walk-Through-Raster" (1966), the program
//  and the four small pictures of its series 2.1: one chain of signs, each
//  chosen by chance from the sign before it, laid into the cells of a raster
//  along four different walks. A homage, not a reproduction, and not
//  affiliated with or endorsed by the artist.
//  https://dam.org/museum/artists_ui/artists/nake-frieder/walk-through-raster/
//
//  An original Ollin interpretation written from Nake's own short description
//  of the program ("Walk-through-Raster, a Generative Aesthetics from 1966",
//  May 2021, published by the Digital Art Museum): the five ingredients, the
//  three signs, the four walks, and how the probabilities move along the
//  chain. No source was ported: the pictures were drawn on a Zuse Graphomat
//  Z64 from an ALGOL 60 program for the Telefunken TR4 that is not the program
//  here. The numbers in the table, the curve they move along, and the edge of
//  its cell each stroke lies on are this sketch's own readings, taken off the
//  Victoria and Albert Museum's photograph of one drawing of the series by
//  counting its 2,500 cells.

import Ollin

/// "Walk-Through-Raster" (Frieder Nake, 1966) is a program more than a
/// picture, and he listed what it needs: a repertoire of signs, a picture
/// plane covered by a grid of cells, a way to choose the first sign, a table
/// that gives the chances of the next sign from the one before it, and a walk,
/// a rule for which cell comes next. The program first makes a chain of signs,
/// one after another from the table. Then it lays the chain into the cells in
/// the order of the walk.
///
/// The four pictures here use the repertoire of his series 2.1: a short
/// vertical stroke, a horizontal stroke of the same length, and the empty
/// sign. The table changes along the chain. At the start the empty sign is
/// likely and a stroke turns up only now and then; the vertical stroke then
/// gains at the empty sign's cost until the middle of the chain, and gives it
/// back toward the end. The horizontal stroke stays rare throughout. So every
/// chain is thin, then dense, then thin again, and the only thing that
/// differs between the four pictures is the walk, which decides where on the
/// sheet "the start", "the middle", and "the end" fall:
///
/// - top left, diagonals, from the top edge down to the right edge and then
///   from the left edge down to the bottom edge;
/// - top right, hooks, along the top from right to left and down the left
///   side, then the same one line down and one line to the right;
/// - bottom left, rows, left to right, top to bottom;
/// - bottom right, a square spiral from the upper left corner inward.
///
/// Two things are worth noticing. The long vertical lines are made of short
/// strokes that happen to stand one above another: a stroke lies on an edge of
/// its cell, so neighbors join into lines and corners. And nothing in the
/// program knows about density or diagonals or a center. He put it as "think
/// the image, don't make it".
///
/// Try it: `sheetSeed` rolls four new chains from the same table. `sheet`
/// shows the four together or one walk large. `swell` is how soon the chain
/// fills (1 is a straight ramp to the middle), `strays` is the chance of each
/// stroke at the two ends, and `memory` makes a sign repeat the one before it,
/// which is what lets the walk show in the texture. The lines export as
/// strokes, so `--export-svg` gives a plotter drawing back.
@main
final class WalkThroughRaster: Sketch {

    /// What the sheet shows: the four walks together, or one of them large.
    enum Sheet: String, CaseIterable, ParamOption { case fourWalks, diagonals, hooks, rows, spiral }

    /// A rule for which cell comes next.
    enum Walk: Int, CaseIterable { case diagonals, hooks, rows, spiral }

    /// The repertoire, in the order a roll reads the table.
    enum Sign: Int, CaseIterable { case empty, vertical, horizontal }

    @Param var sheet = Sheet.fourWalks
    /// Cells along one side of a picture. The photographed drawing has 50.
    @Param(10...80, step: 2) var cells = 50
    /// How soon the chain fills: the empty sign's chance falls as the distance
    /// to the middle of the chain raised to this power.
    @Param(1...8) var swell = 4.0
    /// The chance of each stroke at the two ends of the chain, and of the
    /// horizontal stroke all along it.
    @Param(0...0.3) var strays = 0.1
    /// The share of the table that says "the same sign again". At 0 every row
    /// of the table is the same and a sign does not lean on the one before it.
    @Param(0...0.9) var memory = 0.0
    /// Seconds for one lap: the finished sheet, a clean one, and the walk.
    @Param(8...120) var cycle = 24.0
    @Param(1...999, icon: "dice") var sheetSeed = 66

    override var loopDuration: Double? { cycle }

    // MARK: The program

    /// The cells of a raster `side` cells wide and high in the order `walk`
    /// visits them, as column and row with row 0 at the top.
    static func cells(of walk: Walk, side: Int) -> [(column: Int, row: Int)] {
        var order: [(column: Int, row: Int)] = []
        order.reserveCapacity(side * side)
        switch walk {
        case .diagonals:
            // From the top edge down to the right edge, the corner first...
            for start in stride(from: side - 1, through: 0, by: -1) {
                for step in 0 ..< side - start { order.append((start + step, step)) }
            }
            // ...then from the left edge down to the bottom edge.
            for start in 1 ..< side {
                for step in 0 ..< side - start { order.append((step, start + step)) }
            }
        case .hooks:
            for line in 0 ..< side {
                for column in stride(from: side - 1, through: line, by: -1) { order.append((column, line)) }
                for row in line + 1 ..< side { order.append((line, row)) }
            }
        case .rows:
            for row in 0 ..< side {
                for column in 0 ..< side { order.append((column, row)) }
            }
        case .spiral:
            for ring in 0 ..< (side + 1) / 2 {
                let last = side - 1 - ring
                for column in ring ... last { order.append((column, ring)) }
                for row in ring + 1 ..< last + 1 { order.append((last, row)) }
                if last > ring {
                    for column in stride(from: last - 1, through: ring, by: -1) { order.append((column, last)) }
                    for row in stride(from: last - 1, to: ring, by: -1) { order.append((ring, row)) }
                }
            }
        }
        return order
    }

    /// The chances of the empty sign, the vertical stroke, and the horizontal
    /// stroke at `place` along the chain, 0 at its first sign and 1 at its
    /// last, before the sign in front has its say.
    static func chances(at place: Double, swell: Double, strays: Double) -> [Double] {
        let rise = 1 - pow(abs(1 - 2 * place), swell)
        let vertical = strays + (1 - 2 * strays) * rise
        return [1 - strays - vertical, vertical, strays]
    }

    /// The row of the table for the sign after `before` at `place`: the
    /// chances there, with a share of `memory` moved onto `before` itself.
    /// The first sign of a chain has nothing in front of it and takes the
    /// chances as they are.
    static func row(after before: Sign?, at place: Double,
                    swell: Double, strays: Double, memory: Double) -> [Double] {
        var row = chances(at: place, swell: swell, strays: strays)
        guard let before else { return row }
        for sign in row.indices { row[sign] *= 1 - memory }
        row[before.rawValue] += memory
        return row
    }

    /// A chain of `count` signs, each rolled from the row its predecessor
    /// names.
    static func chain(count: Int, seed: UInt64,
                      swell: Double, strays: Double, memory: Double) -> [Sign] {
        var generator = SplitMix64(seed: seed)
        var signs: [Sign] = []
        signs.reserveCapacity(count)
        for index in 0 ..< count {
            let place = count > 1 ? Double(index) / Double(count - 1) : 0
            let odds = Self.row(after: signs.last, at: place, swell: swell, strays: strays, memory: memory)
            let roll = Double(generator.next() >> 11) * 0x1p-53
            var sign = Sign.horizontal
            var sum = 0.0
            for candidate in Sign.allCases {
                sum += odds[candidate.rawValue]
                if roll < sum { sign = candidate; break }
            }
            signs.append(sign)
        }
        return signs
    }

    /// The share of the chain laid at `lap` (0 to 1 of the cycle) and how much
    /// ink the sheet carries. The lap opens on the finished sheet, clears it,
    /// and walks it again.
    static func stage(at lap: Double) -> (laid: Double, ink: Double) {
        let hold = 0.2, clear = 0.28, done = 0.97
        if lap < hold { return (1, 1) }
        if lap < clear {
            let gone = (lap - hold) / (clear - hold)
            return (1, 1 - gone * gone * (3 - 2 * gone))
        }
        return (min(1, (lap - clear) / (done - clear)), 1)
    }

    // MARK: The sheet

    /// A line on the sheet: strokes that continue one another, drawn as a pen
    /// that stays down draws them. `cells` are the cells it is made of, as
    /// places in a picture's column-by-column list, and `canGrow` says a cell
    /// past one of its ends is still to come.
    struct Run {
        var from: Vector2
        var to: Vector2
        var cells: [Int]
        var canGrow: Bool
    }

    /// The lines made by the signs in `signs` (nil where a cell is still to
    /// come, or is left out), on a lattice one unit to the cell. A stroke lies
    /// on an edge of its cell: the vertical one on the left side, the
    /// horizontal one along the bottom.
    static func runs(of signs: [Sign?], waiting: [Bool], side: Int) -> [Run] {
        var runs: [Run] = []
        for line in 0 ..< side {
            // Down column `line`, then along row `line`.
            var column: [Int] = [], row: [Int] = []
            for place in 0 ... side {
                let down = line * side + place, along = place * side + line
                if place < side, signs[down] == .vertical {
                    column.append(down)
                } else if let first = column.first {
                    let start = first - line * side
                    runs.append(Run(from: Vector2(Double(line), Double(start)),
                                    to: Vector2(Double(line), Double(place)),
                                    cells: column,
                                    canGrow: (start > 0 && waiting[first - 1]) || (place < side && waiting[down])))
                    column = []
                }
                if place < side, signs[along] == .horizontal {
                    row.append(along)
                } else if let first = row.first {
                    let start = first / side
                    runs.append(Run(from: Vector2(Double(start), Double(line + 1)),
                                    to: Vector2(Double(place), Double(line + 1)),
                                    cells: row,
                                    canGrow: (start > 0 && waiting[first - side]) || (place < side && waiting[along])))
                    row = []
                }
            }
        }
        return runs
    }

    /// One picture: the cells in the order of its walk, its chain, and the
    /// lines that are finished.
    struct Picture {
        var order: [Int]
        var signs: [Sign]
        /// The lines the walk can no longer lengthen, recorded once and
        /// replayed, with how much of the chain they were read from and the
        /// cells they hold.
        var kept: Batch?
        var keptAt = 0
        var isKept: [Bool] = []
    }

    let paper = Color(hex: 0xF4F1EA)
    let pen = Color(hex: 0x15130F)
    let head = Color(hex: 0xD8432B)

    /// The four pictures, rolled again when a setting they depend on changes.
    /// The kept lines are recorded where the sheet puts them, so the sheet's
    /// layout is one of those settings.
    private var pictures: [Picture] = []
    private var rolledFrom: [Double] = []

    private func rollPictures() {
        let settings = [Double(cells), swell, strays, memory, Double(sheetSeed),
                        Double(Sheet.allCases.firstIndex(of: sheet) ?? 0), width, height]
        guard settings != rolledFrom else { return }
        rolledFrom = settings
        let side = cells
        pictures = Walk.allCases.map { walk in
            let order = Self.cells(of: walk, side: side)
            return Picture(order: order.map { $0.column * side + $0.row },
                           signs: Self.chain(count: order.count,
                                             seed: UInt64(sheetSeed) * 4 + UInt64(walk.rawValue),
                                             swell: swell, strays: strays, memory: memory))
        }
    }

    override func draw() {
        background(paper)
        let stage = Self.stage(at: loopProgress(over: cycle))
        rollPictures()
        let side = cells

        // Whole pixels to a cell, and the lattice on pixel centers, so every
        // line of the hatch is the same line.
        let shown: [Walk]
        let room: Double, gutter: Double
        switch sheet {
        case .fourWalks:
            shown = Walk.allCases
            gutter = (min(width, height) * 0.05).rounded()
            room = (min(width, height) * 0.89 - gutter) / 2
        case .diagonals: (shown, room, gutter) = ([.diagonals], min(width, height) * 0.8, 0)
        case .hooks: (shown, room, gutter) = ([.hooks], min(width, height) * 0.8, 0)
        case .rows: (shown, room, gutter) = ([.rows], min(width, height) * 0.8, 0)
        case .spiral: (shown, room, gutter) = ([.spiral], min(width, height) * 0.8, 0)
        }
        let cell = max(2, (room / Double(side)).rounded(.down))
        let field = cell * Double(side)
        let across = shown.count > 1 ? 2.0 : 1.0
        let span = across * field + (across - 1) * gutter
        let corner = Vector2((center.x - span / 2).rounded() + 0.5, (center.y - span / 2).rounded() + 0.5)
        let weight = max(1, cell * 0.13)

        for (slot, walk) in shown.enumerated() {
            let origin = corner + Vector2(Double(slot % 2), Double(slot / 2)) * (field + gutter)
            let order = pictures[walk.rawValue].order, signs = pictures[walk.rawValue].signs
            let laid = min(order.count, Int(Double(order.count) * stage.laid))

            func drawRuns(_ runs: [Run]) {
                noFill()
                stroke(pen)
                strokeWeight(weight)
                strokeCap(.square)
                for run in runs {
                    drawLine(origin + run.from * cell, origin + run.to * cell)
                }
            }

            // Keep the lines that are finished: now and then, read the sheet
            // as laid so far and record every line with nothing left to join
            // it. The four pictures take turns, so no frame records two.
            let block = max(1, order.count / 12), turn = walk.rawValue * block / 4
            let kept = pictures[walk.rawValue]
            if kept.kept == nil || laid < kept.keptAt || (laid + turn) / block != (kept.keptAt + turn) / block
                || (laid == order.count && kept.keptAt != laid) {
                var here = [Sign?](repeating: nil, count: order.count)
                var waiting = [Bool](repeating: true, count: order.count)
                for index in 0 ..< laid {
                    here[order[index]] = signs[index]
                    waiting[order[index]] = false
                }
                let finished = Self.runs(of: here, waiting: waiting, side: side).filter { !$0.canGrow }
                var isKept = [Bool](repeating: false, count: order.count)
                for run in finished { for place in run.cells { isKept[place] = true } }
                pictures[walk.rawValue].kept = makeBatch { drawRuns(finished) }
                pictures[walk.rawValue].keptAt = laid
                pictures[walk.rawValue].isKept = isKept
            }
            if let batch = pictures[walk.rawValue].kept { drawBatch(batch) }

            // The lines still growing are drawn fresh. A finished sheet has
            // none.
            if laid < order.count {
                let isKept = pictures[walk.rawValue].isKept
                var here = [Sign?](repeating: nil, count: order.count)
                var waiting = [Bool](repeating: true, count: order.count)
                for index in 0 ..< laid {
                    waiting[order[index]] = false
                    if !isKept[order[index]] { here[order[index]] = signs[index] }
                }
                drawRuns(Self.runs(of: here, waiting: waiting, side: side))
            }

            // Where the walk is.
            if laid < order.count {
                noStroke()
                fill(head)
                let at = order[laid]
                drawCircle(center: origin + Vector2(Double(at / side) + 0.5, Double(at % side) + 0.5) * cell,
                           radius: max(cell * 0.5, 2.5 * scale))
            }
        }

        // The sheet clears by going back to paper.
        if stage.ink < 1 {
            noStroke()
            fill(paper.withAlpha(1 - stage.ink))
            drawRect(0, 0, width, height)
        }
    }
}
