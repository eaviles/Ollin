//  Recreation after Hiroshi Kawano - "Series of Pattern: Flow", also called
//  "Patterns of Flow" (versions through the 1960s; the one of 1966 computed on
//  a HITAC 5020 in FORTRAN IV, Tama Art University Museum, Tokyo; another
//  published with his own note in "Computopia", November 1969). A homage, not
//  a reproduction, and not affiliated with or endorsed by the artist or his
//  estate.
//  https://www.rightclicksave.com/article/patterns-of-flow-revisiting-hiroshi-kawano-japanese-digital-generative-art
//
//  An original Ollin interpretation, written from his published note on the
//  procedure and from photographs of two versions. Nothing was ported: no
//  program text was read. The three data pictures below are this sketch's
//  own, not his. Reading his nine picture elements as a block of three by
//  three, with a cell decided from the four of them already settled, is this
//  sketch's reading too: the note is short and can be read another way.

import Ollin

/// Flow (Hiroshi Kawano, Tokyo, the 1960s). His own note on the version of
/// 1969 gives the whole procedure in a paragraph. Two kinds of picture
/// element, white and black, eight thousand of them, set in a format of 40
/// by 200. Their character comes by chance from a table of how nine picture
/// elements join, and the table is counted off three data works drawn by a
/// person. A line printer types the result, and a human hand draws it at the
/// end. He called the machine's parts an eye, a brain, and a hand.
///
/// This sketch lays that procedure out from top to bottom. The three data
/// pictures are written below as rows of letters, forty cells a side: black
/// leaves on white, the same leaves in white on black, and a wave that
/// changes sides halfway across. The eye scans them a line at a time. The brain counts,
/// for every cell, whether it is black after the four cells already decided
/// around it: the one before it in its line and the three nearest it in the
/// line before. That makes sixteen arrangements, and the row of counts shows
/// each with its share of black. The hand runs the counts forward: each new
/// cell is drawn from the counts of its own four, 200 lines of 40. Then the
/// strip is drawn again without its corners, as a person would trace it.
///
/// The strip lies on its side: a line is a column, read top to bottom, and
/// the lines go left to right. `data` picks which pictures are read (`all`,
/// or one alone, to see whose habits are whose), `roundness` is how far the
/// hand rounds the cells, and the seed deals the strip. Over one cycle of
/// `seconds` the pictures are scanned, the strip is typed, the hand draws
/// it, and it fades, which is also the export loop. A press deals the next.
///
/// Every typed cell exports as one square, so `--export-svg` with a frame in
/// the hold gives the strip back cell by cell.
@main
final class Flow: Sketch {
    enum Reading: String, CaseIterable, ParamOption {
        case all, first, second, third

        var pictures: [Int] {
            switch self {
            case .all: [0, 1, 2]
            case .first: [0]
            case .second: [1]
            case .third: [2]
            }
        }
    }

    @Param(icon: "square.stack") var data = Reading.all
    @Param(0 ... 1, icon: "scribble") var roundness = 0.7
    @Param(6 ... 60, icon: "clock") var seconds = 18.0

    override var canvasSize: CanvasSize { .square(1080) }
    override var loopDuration: Double? { seconds }

    /// His format: 200 lines of 40 cells.
    private static let places = 40
    private static let lines = 200

    /// The three data pictures, as a person would look at them: W white,
    /// K black. Change a letter and the strip's habits change with it.
    private static let dataPictures: [[String]] = [
        [
            "WWWWWWWWWWWWWWWWKKKWWWWWWWWWWWWWWWWWWWWW",
            "WKKKKWWWWWWWWWWWKKKKKWWWWWWWWWWWWWWWWWWW",
            "WKKKKKKWWWWWWWWWKKKKKKWWWWWWWKKKWWWWWWWW",
            "WKKKKKKKKWWWWWWWKKKKKKKWWWWWWKKKKWWWWWWW",
            "WKKKKKKKKKWWWWWWKKKKKKKWWWWWWKKKKKKWWWWW",
            "WKKKKKKKKKKWWWWWKKKKKKKKWWWWKKKKKKKKWWWW",
            "WWKKKKKKKKKWWWWWWKKKKKKKWWWWWKKKKKKKWWWW",
            "WWKKKKKKKKKKWWWWWKKKKKKKWWWWWKKKKKKKKWWW",
            "WWWKKKKKKKKKWWWWWWKKKKKKKWWWWKKKKKKKKWWW",
            "WWWKKKKKKKKKKWWWWWWKKKKKWWWWWKKKKKKKKKWW",
            "WWWWKKKKKKKKKWWWWWWWKKKKWWWWWWKKKKKKKKWW",
            "WWWWWKKKKKKKKWWWWWWWWWWWWWWWWWKKKKKKKKWW",
            "WWWWWWWKKKKKKWWWWWWWWWWWWWWWWWWKKKKKKKWW",
            "WWWWWWWWWKKKKWKKKKKKWWWWWWWWWWWWKKKKKKWW",
            "WWWWWWWWWWWWWWKKKKKKKKWWWWWWWWWWWKKKKWWW",
            "WWWWWWWWWWWWWWKKKKKKKKKWWWWWWWWWWWWWKWWW",
            "KKKKKKWWWWWWWWKKKKKKKKKWWWWWWWWWWWWWWWWW",
            "KKKKKKKKWWWWWWKKKKKKKKKKWWWWWWKKWWWWWWWW",
            "KKKKKKKKKKWWWWKKKKKKKKKKWWWWWWKKKKWWWWWW",
            "WKKKKKKKKKKWWWWKKKKKKKKKWWWWWWKKKKKWWWWW",
            "WKKKKKKKKKKWWWWKKKKKKKKKWWWWWWKKKKKKWWWW",
            "WWKKKKKKKKKKWWWWKKKKKKKKWWWWWWKKKKKKWWWW",
            "WWWKKKKKKKKKWWWWWWKKKKKKWWWWWWKKKKKKKWWW",
            "WWWWKKKKKKKKKWWWWWWWWWWWWWWWWWKKKKKKKWWW",
            "WWWWWWKKKKKKKWWWWWWWWWWWWWWWWWWKKKKKKWWW",
            "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWKKKKKKWWW",
            "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWKKKKKWWW",
            "WWWWWWWWWWWWWWWWWWWKKKKKKWWWWWWWWKKKKWWW",
            "WWWWWWWWWWWWWWWWWWWKKKKKKKKWWWWWWWWWWWWW",
            "WWWWWKKKWWWWWWWWWWWKKKKKKKKKWWWWWWWWWWWW",
            "WWKKKKKKKKWWWWWWWWWKKKKKKKKKKWWWWWWWWWWW",
            "WWKKKKKKKKKKWWWWWWWWKKKKKKKKKWWWWWWWWWWW",
            "WWWKKKKKKKKKKWWWWWWWKKKKKKKKKKWWWWWWWWWW",
            "WWWKKKKKKKKKKKWWWWWWWKKKKKKKKKWWWWWWWWWW",
            "WWWWWKKKKKKKKKWWWWWWWWKKKKKKKKWWWWWWWWWW",
            "WWWWWWKKKKKKKKWWWWWWWWWWKKKKKKWWWWWWWWWW",
            "WWWWWWWWWKKKWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
            "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
            "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
            "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
        ],
        [
            "KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK",
            "KKKKKKKKKKKKKKKWWWKKKKKKKKKKKKKKKKKKKKKK",
            "KKKKKKKKKKKKKKKWWWWKKKKKKKKKKKKKKKKKKKKK",
            "KKWWWKKKKKKKKKKWWWWWWKKKKKKKKKKKKKKKKKKK",
            "KKWWWWWKKKKKKKWWWWWWWWKKKKWWWWWWKKKKKKKK",
            "KKWWWWWWKKKKKKKWWWWWWWKKKKWWWWWWWWKKKKKK",
            "KKWWWWWWWKKKKKKWWWWWWWWKKKWWWWWWWWWWKKKK",
            "KKWWWWWWWKKKKKKWWWWWWWWKKKKWWWWWWWWWWKKK",
            "KKWWWWWWWWKKKKKWWWWWWWWWKKKWWWWWWWWWWKKK",
            "KKKWWWWWWWKKKKKKWWWWWWWWKKKKWWWWWWWWWWKK",
            "KKKWWWWWWWKKKKKKWWWWWWWWKKKKKWWWWWWWWWKK",
            "KKKKWWWWWWWKKKKKKWWWWWWWKKKKKKWWWWWWWWWK",
            "KKKKKWWWWWKKKKKKKKWWWWWWKKKKKKKKWWWWWWWK",
            "KKKKKKWWWWKKKKKKKKKWWWWKKKKKKKKKKKKKKKKK",
            "KKKKKKKKKKKKKKKKKKKKKKWKKKKKKKKKKKKKKKKK",
            "KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKWWWKKKKKKK",
            "KKKKKKKKKKKKKKKKKKKKKKKKKKKWWWWWWWWKKKKK",
            "KKKKKKKKKKKKKKKKWWKKKKKKKKKWWWWWWWWWWKKK",
            "KWWWWWWKKKKKKKKKWWWWKKKKKKKKWWWWWWWWWWKK",
            "KWWWWWWWWKKKKKKKWWWWWKKKKKKKWWWWWWWWWWWK",
            "KWWWWWWWWWKKKKKKWWWWWWKKKKKKKKWWWWWWWWWK",
            "KWWWWWWWWWKKKKKKWWWWWWKKKKKKKKKWWWWWWWWK",
            "KWWWWWWWWWWKKKKKWWWWWWWKKKKKKKKKKKWWWKKK",
            "KWWWWWWWWWWKKKKKWWWWWWWKKKKKKKKKKKKKKKKK",
            "KKWWWWWWWWWKKKKKKWWWWWWKKKKKKKKKKKKKKKKK",
            "KKWWWWWWWWWKKKKKKWWWWWWKKKKKKKKKKKKKKKKK",
            "KKKWWWWWWWWKKKKKKKWWWWWKKKWWWWKKKKKKKKKK",
            "KKKKKWWWWWWKKKKKKKKWWWWKKKWWWWWWKKKKKKKK",
            "KKKKKKKKKKKKKKKKKKKKKKKKKKWWWWWWWWKKKKKK",
            "KKKKKKKKKKKKKKKKKKKKKKKKKKWWWWWWWWWKKKKK",
            "KKKKKWWWWWWKKKKKKKKKKKKKKKWWWWWWWWWWKKKK",
            "KKKKKWWWWWWWWKKKKKKKKKKKKKKWWWWWWWWWKKKK",
            "KKKKKWWWWWWWWWKKKKKKKKKKKKKWWWWWWWWWWKKK",
            "KKKKKWWWWWWWWWWKKKKKKKKKKKKKWWWWWWWWWKKK",
            "KKKKKKWWWWWWWWWKKKKKKKKKKKKKWWWWWWWWWWKK",
            "KKKKKKWWWWWWWWWWKKKKKKKKKKKKKWWWWWWWWWKK",
            "KKKKKKKWWWWWWWWWKKKKKKKKKKKKKKWWWWWWWWKK",
            "KKKKKKKKWWWWWWWWKKKKKKKKKKKKKKKKWWWWWWKK",
            "KKKKKKKKKKWWWWWWKKKKKKKKKKKKKKKKKKWWWWKK",
            "KKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK",
        ],
        [
            "WWWWWWWWWWWWWWWWWWWWKKKKKKKKKKKKKKKKKKKK",
            "WWWWWWWWWWWWWWWWWWWWKKKKKKKKKKKKKKKKKKKK",
            "WWWWWWWWWWWWWWWWWWWWKKKKKKKKKKKKKKKKKKKK",
            "WWWWWWWWWWWWWWWWWWWWKKKKKKKKKKKKKKKKKKKK",
            "WWWWWWWWWWWWWWWWWWWWKKKKKKKKKKKKKKKKKKKK",
            "WWWWWWWWWWWWWWWWWWWWKKKKKKKKKKKKKKKKKKKK",
            "WWWWWWWWWWWWWWWWWWWWKKKKKKKKKKKKKKKKKKKK",
            "WWWWWWWWWWWWWWKKWWWWKKKKKKKKKKKKKKWWKKKK",
            "WWWWWWWWWWWWWKKKKWWWKKKKKKKKKKKKKWWWWKKK",
            "WWWWWWWWWWWWKKKKKKWWKKKKKKKKKKKKWWWWWWKK",
            "WWWWWWWWWWWWKKKKKKWWKKKKKKKKKKKKWWWWWWKK",
            "WWWWWWWWWWWKKKKKKKKWKKKKKKKKKKKWWWWWWWWK",
            "WWWWWWWWWWKKKKKKKKKKKKKKKKKKKKWWWWWWWWWW",
            "WWWWWWWWWWKKKKKKKKKKKKKKKKKKKKWWWWWWWWWW",
            "WWWWWWWWWWKKKKKKKKKKKKKKKKKKKKWWWWWWWWWW",
            "KWWWWWWWWKKKKKKKKKKKWKKKKKKKKWWWWWWWWWWW",
            "KKWWWWWWKKKKKKKKKKKKWWKKKKKKWWWWWWWWWWWW",
            "KKWWWWWWKKKKKKKKKKKKWWKKKKKKWWWWWWWWWWWW",
            "KKKWWWWKKKKKKKKKKKKKWWWKKKKWWWWWWWWWWWWW",
            "KKKKWWKKKKKKKKKKKKKKWWWWKKWWWWWWWWWWWWWW",
            "KKKKKKKKKKKKKKWWKKKKWWWWWWWWWWWWWWKKWWWW",
            "KKKKKKKKKKKKKWWWWKKKWWWWWWWWWWWWWKKKKWWW",
            "KKKKKKKKKKKKWWWWWWKKWWWWWWWWWWWWKKKKKKWW",
            "KKKKKKKKKKKKWWWWWWKKWWWWWWWWWWWWKKKKKKWW",
            "KKKKKKKKKKKWWWWWWWWKWWWWWWWWWWWKKKKKKKKW",
            "KKKKKKKKKKWWWWWWWWWWWWWWWWWWWWKKKKKKKKKK",
            "KKKKKKKKKKWWWWWWWWWWWWWWWWWWWWKKKKKKKKKK",
            "KKKKKKKKKKWWWWWWWWWWWWWWWWWWWWKKKKKKKKKK",
            "WKKKKKKKKWWWWWWWWWWWKWWWWWWWWKKKKKKKKKKK",
            "WWKKKKKKWWWWWWWWWWWWKKWWWWWWKKKKKKKKKKKK",
            "WWKKKKKKWWWWWWWWWWWWKKWWWWWWKKKKKKKKKKKK",
            "WWWKKKKWWWWWWWWWWWWWKKKWWWWKKKKKKKKKKKKK",
            "WWWWKKWWWWWWWWWWWWWWKKKKWWKKKKKKKKKKKKKK",
            "WWWWWWWWWWWWWWWWWWWWKKKKKKKKKKKKKKKKKKKK",
            "WWWWWWWWWWWWWWWWWWWWKKKKKKKKKKKKKKKKKKKK",
            "WWWWWWWWWWWWWWWWWWWWKKKKKKKKKKKKKKKKKKKK",
            "WWWWWWWWWWWWWWWWWWWWKKKKKKKKKKKKKKKKKKKK",
            "WWWWWWWWWWWWWWWWWWWWKKKKKKKKKKKKKKKKKKKK",
            "WWWWWWWWWWWWWWWWWWWWKKKKKKKKKKKKKKKKKKKK",
            "WWWWWWWWWWWWWWWWWWWWKKKKKKKKKKKKKKKKKKKK",
        ],
    ]

    // The paper and the inks, measured off a photograph of the 1966 version.
    private let paper = Color(hex: 0xE0DCC4)
    private let ink = Color(hex: 0x0C1010)
    private let pencil = Color(hex: 0x6E6A60)
    private let printerInk = Color(hex: 0x4A4956)

    /// A cell is five points, so the strip of 200 lines is 1000 across. The
    /// data pictures and the counts share the top band; the two strips follow.
    private let unit = 5.0
    private let left = 40.0
    private let countsLeft = 720.0
    private let dataTop = 140.0
    private let printedTop = 450.0
    private let drawnTop = 760.0

    /// The data pictures as lines, the counts after each scanned line, the
    /// strip, and the hand's drawing of it.
    private var pictures: [[[Int]]] = []
    private var counted: [[[Int]]] = []
    private var sheet: [[Int]] = []
    private var drawing = Shape([])
    private var dealtFor: (data: Reading, seed: Int, roundness: Double)?
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
        let wanted = (data: data, seed: variation, roundness: roundness)
        if dealtFor.map({ $0 != wanted }) ?? true {
            dealtFor = wanted
            deal()
        }

        // One cycle: the eye, the hand at the printer, the hand at the
        // brush, a hold, and the fade back to the data alone.
        let phase = loopProgress(over: seconds)
        let scan = clamp(phase / 0.2, 0, 1)
        let typed = clamp((phase - 0.22) / 0.3, 0, 1)
        let traced = clamp((phase - 0.55) / 0.3, 0, 1)
        let kept = 1 - smoothstep(0.94, 1, phase)

        background(paper)
        let span = Double(Self.lines) * unit
        let side = Double(Self.places) * unit
        label("DATA", left, dataTop)
        label("COUNTS", countsLeft, dataTop)
        label("TYPED  40 \u{00D7} 200", left, printedTop)
        label("DRAWN BY HAND", left, drawnTop)
        drawText("SEED \(variation)", left + span, printedTop - 26, size: 15, color: pencil, align: .right, .top)

        // The eye: each picture that is read, in turn, a line at a time. A
        // line not yet scanned shows faintly, and a picture left out fainter.
        let steps = data.pictures.count * Self.places
        let seen = Int(Double(steps) * scan)
        let faint = Color.mix(paper, ink, 0.2), fainter = Color.mix(paper, ink, 0.07)
        let read = Color.mix(faint, ink, kept)
        var before = 0
        noStroke()
        for (index, lines) in pictures.enumerated() {
            let x = left + Double(index) * (side + 20)
            let chosen = data.pictures.contains(index)
            for (l, line) in lines.enumerated() {
                fill(!chosen ? fainter : before + l < seen ? read : faint)
                for (p, value) in line.enumerated() where value == 1 {
                    drawRect(x + Double(l) * unit, dataTop + Double(p) * unit, unit, unit)
                }
            }
            outline(Rectangle(x: x, y: dataTop, width: side, height: side))
            guard chosen else { continue }
            if seen > before, seen < before + lines.count {
                stroke(pencil)
                strokeWeight(1.5)
                let at = x + Double(seen - before) * unit
                drawLine(at, dataTop - 6, at, dataTop + side + 6)
                noStroke()
            }
            before += lines.count
        }

        // The brain: the sixteen arrangements, from all white around to all
        // black, each with its share of black so far and how often it came.
        let counts = counted[seen]
        let order = (0 ..< 16).sorted { ($0.nonzeroBitCount, $0) < ($1.nonzeroBitCount, $1) }
        let small = 13.0
        for (slot, arrangement) in order.enumerated() {
            let x = countsLeft + Double(slot % 4) * 80
            let y = dataTop + Double(slot / 4) * 50 + 5
            // Drawn as it sits on the strip: the line before is the column
            // on the left, with its three cells; the cell before is above
            // the heavy box, which is the cell being decided.
            let around = (0 ..< 4).map { (arrangement >> $0) & 1 }
            let spots = [(1.0, 0.0, around[0]), (0.0, 1.0, around[1]), (0.0, 0.0, around[2]), (0.0, 2.0, around[3])]
            for (column, row, value) in spots {
                let box = Rectangle(x: x + column * small, y: y + row * small, width: small, height: small)
                noStroke()
                fill(value == 1 ? ink : paper)
                drawRect(box)
                outline(box)
            }
            noFill()
            stroke(pencil)
            strokeWeight(2)
            drawRect(x + small, y + small, small, small)
            noStroke()

            let tally = counts[arrangement]
            let total = tally[0] + tally[1]
            let bar = Rectangle(x: x + 34, y: y, width: 9, height: 3 * small)
            if total > 0 {
                let share = Double(tally[1]) / Double(total)
                fill(ink.withAlpha(kept))
                drawRect(bar.x, bar.y + bar.height * (1 - share), bar.width, bar.height * share)
                drawText("\(total)", bar.x + 15, y + 1.5 * small, size: 11,
                         color: pencil.withAlpha(kept), align: .left, .middle)
            }
            outline(bar)
        }

        // The hand at the printer: a mark for every black cell, line by line.
        let shown = Int(Double(Self.lines) * typed)
        let mark = unit * 0.76
        fill(printerInk.withAlpha(kept))
        for l in 0 ..< shown {
            for (p, value) in sheet[l].enumerated() where value == 1 {
                drawRect(left + Double(l) * unit + (unit - mark) / 2,
                         printedTop + Double(p) * unit + (unit - mark) / 2, mark, mark)
            }
        }
        outline(Rectangle(x: left, y: printedTop, width: span, height: side))

        // The hand at the brush: the same strip without its corners.
        if traced > 0 {
            withClip(Rectangle(x: left, y: drawnTop, width: span * traced, height: side)) {
                fill(ink.withAlpha(kept))
                drawShape(drawing)
            }
        }
        outline(Rectangle(x: left, y: drawnTop, width: span, height: side))
    }

    private func label(_ text: String, _ x: Double, _ top: Double) {
        drawText(text, x, top - 26, size: 15, color: pencil, align: .left, .top)
    }

    private func outline(_ box: Rectangle) {
        noFill()
        stroke(pencil.withAlpha(0.6))
        strokeWeight(1)
        drawRect(box)
        noStroke()
    }

    /// Reads the chosen data pictures, keeping the counts after every line,
    /// runs the strip, and draws it by hand.
    private func deal() {
        // A picture is scanned as the strip is written: a line is one of its
        // columns, read top to bottom, and the lines go left to right.
        pictures = Self.dataPictures.map { picture in
            let rows = picture.map { row in row.map { $0 == "K" ? 1 : 0 } }
            return rows[0].indices.map { x in rows.map { $0[x] } }
        }
        var chain = FlowChain(values: 2)
        counted = [Self.table(of: chain)]
        for index in data.pictures {
            for (l, line) in pictures[index].enumerated() {
                chain.learn(line, after: l > 0 ? pictures[index][l - 1] : nil)
                counted.append(Self.table(of: chain))
            }
        }

        var random = SplitMix64(seed: UInt64(bitPattern: Int64(variation)))
        sheet = []
        for _ in 0 ..< Self.lines {
            sheet.append(chain.line(after: sheet.last, places: Self.places, using: &random))
        }
        drawing = trace()
    }

    /// The counts of the sixteen arrangements that lie wholly on the sheet,
    /// indexed by their four cells as bits.
    private static func table(of chain: FlowChain) -> [[Int]] {
        (0 ..< 16).map { arrangement in
            chain.tally(after: (0 ..< 4).map { (arrangement >> $0) & 1 }) ?? [0, 0]
        }
    }

    /// The strip as a person would trace it: the cells softened into their
    /// neighbors, and an outline run where black and white balance. A single
    /// cell alone in the other tone is left out, as a hand would leave it.
    private func trace() -> Shape {
        let soft = softened(softened(sheet.map { $0.map { Double($0) } }))
        let tone = sheet.indices.map { l in
            sheet[l].indices.map { p in lerp(Double(sheet[l][p]), soft[l][p], roundness) }
        }
        // The tone at a point, between cell centers; past the strip's edge
        // it holds for one cell, so a form runs out through the frame.
        func value(_ l: Int, _ p: Int) -> Double {
            guard (-1 ... Self.lines).contains(l), (-1 ... Self.places).contains(p) else { return 0 }
            return tone[clamp(l, 0, Self.lines - 1)][clamp(p, 0, Self.places - 1)]
        }
        let origin = Vector2(left, drawnTop)
        let rings = isolines(at: 0.5,
                             in: Rectangle(x: left - 2 * unit, y: drawnTop - 2 * unit,
                                           width: Double(Self.lines + 4) * unit,
                                           height: Double(Self.places + 4) * unit),
                             resolution: 3 * (Self.lines + 4)) { point in
            let l = (point.x - origin.x) / self.unit - 0.5
            let p = (point.y - origin.y) / self.unit - 0.5
            let l0 = Int(l.rounded(.down)), p0 = Int(p.rounded(.down))
            let fl = l - Double(l0), fp = p - Double(p0)
            let upper = lerp(value(l0, p0), value(l0 + 1, p0), fl)
            let lower = lerp(value(l0, p0 + 1), value(l0 + 1, p0 + 1), fl)
            return lerp(upper, lower, fp)
        }
        return Shape(contours: rings, winding: .evenOdd)
    }

    /// Each cell averaged with its eight neighbors, the near ones weighing
    /// more; the strip's edge repeats.
    private func softened(_ cells: [[Double]]) -> [[Double]] {
        let weights = [1.0, 2.0, 1.0]
        return cells.indices.map { l in
            cells[l].indices.map { p in
                var sum = 0.0
                for dl in -1 ... 1 {
                    for dp in -1 ... 1 {
                        let line = cells[clamp(l + dl, 0, cells.count - 1)]
                        sum += weights[dl + 1] * weights[dp + 1] * line[clamp(p + dp, 0, line.count - 1)]
                    }
                }
                return sum / 16
            }
        }
    }
}

/// A chain over a sheet of cells. What a cell holds is drawn from the counts
/// of what held that place, in the data, after the same cells around it.
private struct FlowChain {
    /// How many values a cell can hold. A place off the sheet reads as one more.
    let values: Int
    private var counts: [[Int]: [Int]] = [:]

    init(values: Int) {
        self.values = values
    }

    /// The cells already decided around place `p` of a line, nearest first:
    /// the one before it in its line, then the same place, the place before,
    /// and the place after in the line before.
    func around(_ p: Int, in line: [Int], after before: [Int]?) -> [Int] {
        func value(_ cells: [Int]?, _ i: Int) -> Int {
            guard let cells, cells.indices.contains(i) else { return values }
            return cells[i]
        }
        return [value(line, p - 1), value(before, p), value(before, p - 1), value(before, p + 1)]
    }

    /// Counts one line of a data picture. Every cell is counted under its
    /// whole arrangement and under each shorter one, so the walk can forget
    /// the farthest cell when it has to.
    mutating func learn(_ line: [Int], after before: [Int]?) {
        for (p, value) in line.enumerated() {
            let cells = around(p, in: line, after: before)
            for n in 0 ... cells.count {
                counts[Array(cells.prefix(n)), default: Array(repeating: 0, count: values)][value] += 1
            }
        }
    }

    /// How often each value followed these cells, if they ever came up.
    func tally(after cells: [Int]) -> [Int]? {
        counts[cells]
    }

    /// The line after `before`, `places` cells long.
    func line(after before: [Int]?, places: Int, using random: inout SplitMix64) -> [Int] {
        var line: [Int] = []
        for p in 0 ..< places {
            var cells = around(p, in: line, after: before)
            // An arrangement the data never showed: forget the farthest cell
            // and ask again. With none left, the counts are the tones' shares.
            while counts[cells] == nil, !cells.isEmpty { cells.removeLast() }
            guard let tally = counts[cells] else {
                line.append(0)
                continue
            }
            var roll = Int(random.next() % UInt64(tally.reduce(0, +)))
            var value = 0
            while roll >= tally[value] {
                roll -= tally[value]
                value += 1
            }
            line.append(value)
        }
        return line
    }
}
