import Ollin

/// A grid chain, `MarkovGrid`: show it a small picture and it writes more
/// like it, without end.
///
/// Each motif below is a picture drawn by hand as rows of letters. The chain
/// reads it the way a page is read and counts, for every cell, what it held
/// beside the cells already settled around it: the one before it in its row,
/// the one above, the one above and before, and the one above and after.
/// Then it runs the counts forward a row at a time, and the strip travels up
/// the canvas as it is written. The card in the corner holds the picture it
/// learned from, and under it the cells it reads, numbered nearest first.
///
/// `order` is how many of those four cells are read. At 1 a row only
/// remembers along itself, so the town is loose stripes. At 2 the rows line
/// up under one another, but nothing holds a street open and the buildings
/// run together. At 3 a block keeps its far side straight, and at 4 its near
/// side too, because the cell above and after is the only one that can tell
/// a row a block begins just ahead. Only then does the town keep the streets
/// its picture has. Nothing here counts or plans: a block is as long as the
/// rolls make it, which is why no two are the same.
///
/// `motif` picks the picture (a town of blocks, parks and ponds; a maze; a
/// wall of bricks), `pace` is rows a second, the seed deals the strip, and a
/// press deals the next. Change a letter in a picture and the habits of the
/// whole strip change with it.
@main
final class MarkovGridSketch: Sketch {
    enum Motif: String, CaseIterable, ParamOption {
        case town, maze, wall
    }

    @Param(icon: "square.grid.3x3") var motif = Motif.town
    @Param(1 ... 4, icon: "scope") var order = 4
    @Param(1 ... 20, icon: "speedometer") var pace = 5.0

    override var canvasSize: CanvasSize { .square(1080) }

    /// How many cells a written row holds.
    private static let columns = 60

    /// A town seen from above: `#` a building, `p` a park, `w` a pond, and
    /// `.` the street between them.
    private static let town = [
        "........................",
        ".####.######.ppppp.####.",
        ".####.######.ppppp.####.",
        ".####.######.ppppp.####.",
        ".####........ppppp.####.",
        "......#####.........####",
        ".###..#####.######......",
        ".###..#####.######.####.",
        ".###........######.####.",
        ".###.wwwww.........####.",
        ".....wwwww.#######.####.",
        ".###.wwwww.#######......",
        ".###.......#######.###..",
        ".###.#####.........###..",
        ".....#####.pppppp..###..",
        ".###.#####.pppppp.......",
        ".###.......pppppp.#####.",
        ".###.####..........#####",
        ".....####.#######..#####",
        ".###.####.#######.......",
        ".###......#######.####..",
        ".###.####.........####..",
        ".....####.######..####..",
        "........................",
    ]

    /// A maze: `#` a wall, `.` a passage, each one cell wide.
    private static let maze = [
        "#################",
        "#...#.....#.....#",
        "#.#.#.###.#.###.#",
        "#.#...#...#...#.#",
        "#.#####.#####.#.#",
        "#.....#.....#.#.#",
        "#####.#####.#.#.#",
        "#.....#...#...#.#",
        "#.#####.#.#####.#",
        "#.#.....#.....#.#",
        "#.#.#########.#.#",
        "#.#.#.......#.#.#",
        "#.#.#.#####.#.#.#",
        "#...#.....#...#.#",
        "#.#######.#####.#",
        "#...............#",
        "#################",
    ]

    /// A wall in running bond: `#` brick and `.` mortar, each course two
    /// cells high and set half a brick along from the one under it.
    private static let wall = [
        "..............................",
        "#####.#####.#####.#####.#####.",
        "#####.#####.#####.#####.#####.",
        "..............................",
        "##.#####.#####.#####.#####.###",
        "##.#####.#####.#####.#####.###",
        "..............................",
        "#####.#####.#####.#####.#####.",
        "#####.#####.#####.#####.#####.",
        "..............................",
        "##.#####.#####.#####.#####.###",
        "##.#####.#####.#####.#####.###",
        "..............................",
        "#####.#####.#####.#####.#####.",
        "#####.#####.#####.#####.#####.",
        "..............................",
        "##.#####.#####.#####.#####.###",
        "##.#####.#####.#####.#####.###",
    ]

    private var picture: [[Character]] {
        switch motif {
        case .town: Self.town.map(Array.init)
        case .maze: Self.maze.map(Array.init)
        case .wall: Self.wall.map(Array.init)
        }
    }

    /// What each letter is painted with. The first is the ground, which the
    /// canvas is cleared to, so only the other letters are drawn.
    private var paints: [(letter: Character, color: Color)] {
        switch motif {
        case .town:
            [(".", Color(hex: 0xEFE7D6)), ("#", Color(hex: 0xC65A3E)),
             ("p", Color(hex: 0x86AE6C)), ("w", Color(hex: 0x5E93BD))]
        case .maze:
            [(".", Color(hex: 0xF0E9DA)), ("#", Color(hex: 0x26315C))]
        case .wall:
            [(".", Color(hex: 0xE4DBC9)), ("#", Color(hex: 0xB4543A))]
        }
    }

    private let card = Color(hex: 0xFBF8F1)
    private let pencil = Color(hex: 0x4A463E)

    private var chain = MarkovGrid<Character>()
    private var strip: [[Character]] = []
    private var written = 0
    private var dealtAt = 0.0
    private var dealtFor: (motif: Motif, order: Int, seed: Int)?
    private var pressed = false

    override func setup() {
        textFont(OutlineFont.system)
    }

    override func mousePressed() {
        pressed = true
    }

    override func draw() {
        if pressed {
            pressed = false
            seed(variation + 1)
        }
        let cell = width / Double(Self.columns)
        let down = height / cell
        let wanted = (motif: motif, order: order, seed: variation)
        if let dealt = dealtFor, dealt != wanted {
            // A new strip starts with the canvas full, from this moment.
            dealtAt = time
            dealtFor = nil
        }

        // The strip's place: how many rows have come in at the bottom edge.
        // It starts a canvas ahead, so the first frame is already full.
        let position = down + max(0, time - dealtAt) * pace
        let begun = Int(position) + 1
        if dealtFor == nil || begun < written - strip.count {
            dealtFor = wanted
            deal()
        }
        let kept = Int(down.rounded(.up)) + 2
        while written < begun {
            strip.append(chain.nextRow(columns: Self.columns))
            written += 1
            if strip.count > kept { strip.removeFirst() }
        }

        let paints = paints
        background(paints[0].color)
        noStroke()
        for (i, row) in strip.enumerated() {
            // A row's age is how many rows have come in since it did.
            let age = position - Double(written - strip.count + i)
            let y = height - age * cell
            guard y < height, y + cell > 0 else { continue }
            paint(row, paints, x: 0, y: y, cell: cell)
        }
        drawCard(paints)
    }

    /// One row of cells, each run of a letter as a single four-cornered
    /// polygon. Polygons that share an edge meet without a seam at any
    /// place between pixels, which a strip in motion needs.
    private func paint(_ row: [Character], _ paints: [(letter: Character, color: Color)],
                       x: Double, y: Double, cell: Double) {
        var start = 0
        while start < row.count {
            var end = start + 1
            while end < row.count, row[end] == row[start] { end += 1 }
            if row[start] != paints[0].letter, let paint = paints.first(where: { $0.letter == row[start] }) {
                let left = x + Double(start) * cell, right = x + Double(end) * cell
                fill(paint.color)
                drawPolygon([Vector2(left, y), Vector2(right, y), Vector2(right, y + cell), Vector2(left, y + cell)])
            }
            start = end
        }
    }

    /// The picture the chain learned from, and the cells it reads around a
    /// place: the heavy box is the cell being decided, and the numbered
    /// cells are the ones within `order`, nearest first.
    private func drawCard(_ paints: [(letter: Character, color: Color)]) {
        let picture = picture
        let side = 168.0
        let unit = side / Double(picture[0].count)
        let tall = unit * Double(picture.count)
        let box = 22.0
        let frame = Rectangle(x: 30, y: 30, width: side + 28, height: tall + 2 * box + 74)

        fill(card)
        stroke(pencil.withAlpha(0.55))
        strokeWeight(1.5)
        drawRect(frame, cornerRadius: 8)
        noStroke()

        let left = frame.x + 14
        var top = frame.y + 14
        fill(paints[0].color)
        drawRect(left, top, side, tall)
        for (r, row) in picture.enumerated() {
            paint(row, paints, x: left, y: top + Double(r) * unit, cell: unit)
        }
        top += tall + 12
        drawText("drawn by hand, \(picture[0].count) \u{00D7} \(picture.count)", left, top,
                 size: 13, color: pencil, align: .left, .top)

        // Above and before, above, above and after; then before, and the
        // cell itself.
        top += 26
        let spots = [(0.0, 1.0, 1), (1.0, 0.0, 2), (0.0, 0.0, 3), (2.0, 0.0, 4)]
        for (column, row, rank) in spots {
            let cell = Rectangle(x: left + column * box, y: top + row * box, width: box, height: box)
            let read = rank <= order
            fill(read ? pencil : card)
            stroke(pencil.withAlpha(read ? 1 : 0.35))
            strokeWeight(1)
            drawRect(cell)
            noStroke()
            if read {
                drawText("\(rank)", cell.x + box / 2, cell.y + box / 2, size: 12, color: card, align: .center, .middle)
            }
        }
        noFill()
        stroke(pencil)
        strokeWeight(2.5)
        drawRect(left + box, top + box, box, box)
        noStroke()
        drawText("order \(order)", left + 3 * box + 12, top + box, size: 13, color: pencil, align: .left, .middle)
    }

    /// Reads the picture and starts the strip over. The chain is told its
    /// letters before it reads anything, so a seed deals the same strip
    /// however the picture happens to begin.
    private func deal() {
        chain = MarkovGrid(vocabulary: paints.map(\.letter), order: order, seed: variation)
        // The pictures are written above, every row of one length.
        try! chain.learn(picture)
        strip = []
        written = 0
    }
}
