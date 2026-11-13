//  Recreation after Hiroshi Kawano - "Simulated Color Mosaic" (published 1969;
//  gouache on paper after a design computed on a HITAC 5020 in FORTRAN IV and
//  typed by a line printer; reconstructed as a print for the retrospective of
//  2011), ZKM | Center for Art and Media Karlsruhe. A homage, not a
//  reproduction, and not affiliated with or endorsed by the artist or his estate.
//  https://zkm.de/en/artworks/simulated-color-mosaic
//
//  An original Ollin interpretation, written from the published accounts of
//  the method and from photographs of the work. Nothing was ported: no
//  program text was read. The three data pictures below are this sketch's
//  own, not his. Reading his chain as the four cells already decided around a
//  place is this sketch's reading too: the accounts are short and can be read
//  another way.

import Ollin

/// Simulated Color Mosaic (Hiroshi Kawano, Tokyo, published 1969). By the
/// end of the 1960s the philosopher's experiment had a fixed shape. A few
/// pictures drawn by a person were the data. The program read them cell by
/// cell, the way a television scans, and counted how the cells sat next to
/// each other. Then it ran the counts forward with random numbers and made a
/// picture nobody had drawn, which the line printer typed and people painted
/// in gouache. This one was a long strip about a hundred cells across, in
/// black, red, blue, yellow and white, and the chain behind it ran across
/// the lines and down them together.
///
/// This sketch keeps that procedure. Its three data pictures are written
/// below as rows of letters, forty cells a side: fields held in black lines
/// with a bend or two, a few large fields, and a crowded lattice. The chain
/// counts, for every cell of them, what paint it holds after the four cells
/// already decided around it: the one before it in its line, and the three
/// nearest it in the line before. A new cell is drawn from the counts of its
/// own four. When the data never showed that arrangement, the chain forgets
/// the farthest cell and asks again. A place off the sheet counts as a paint
/// of its own, so the strip's edges behave as the pictures' edges do.
///
/// The strip lies on its side, as it hung. Each printed line is a column,
/// read top to bottom, and the lines follow one another from left to right
/// without end. The printer types a code for each cell at the right edge,
/// the gouache follows a few lines behind, and the strip travels left.
/// `data` picks which pictures the chain has read (`all`, or one alone, to
/// see whose habits are whose), `cells` is the length of a line, and `pace`
/// is lines a second. The seed deals the strip, and a press deals the next.
///
/// Every painted cell exports as one square, so `--export-svg` gives the
/// strip back cell by cell, and its transitions give back the counts.
@main
final class SimulatedColorMosaic: Sketch {
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
    @Param(40 ... 160, icon: "line.3.horizontal") var cells = 100
    @Param(1 ... 24, icon: "speedometer") var pace = 6.0

    override var canvasSize: CanvasSize { .square(1080) }

    /// The five gouaches, in the order of their letters below.
    private static let letters = Array("WKRBY")

    /// The three data pictures, as a person would look at them: W white,
    /// K black, R red, B blue, Y yellow. Change a letter and the strip's
    /// habits change with it.
    private static let dataPictures: [[String]] = [
        [
            "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWKKKKKKKKKW",
            "WKKKKKKKKKKKKKKKWWWWWWWWWWWWWWKBBBBBBBKW",
            "WKRRRRRRRRRRRRRKWWWKKKKKKKKKWWKBBBBBBBKW",
            "WKRRRRRRRRRRRRRKWWWKRRRRRRRKWWKBBBBBBBKW",
            "WKRRRRRRRRRRRRRKWWWKRWWWWWRKWWKBBBBBBBKW",
            "WKRRRRRRRRRRRRRKWWWKRWWWWWRKWWKBBBBBBBKW",
            "WKRRRRRRRRRRRRRKWWWKRWWWWWRKWWKBBBBBBBKW",
            "WKRRRRRRRRRRRRRKKWWKRWWWWWRKWWKKKKKKKKKW",
            "WKKKKKKKKKKKKKKKWKWKRRRRRRRKWWWWWWWWWWWW",
            "WWWWWWWWWWWWWWWWWWKKRRRRRRRKWWWWWWWWWWWW",
            "WWWWWWWWWWWWWWWWWWKKRRRRRRRKWWWWKKKKKKKW",
            "WWKKKKKKKKKKKKKWWWWKRRRRRRRKWWWWKRRRRRKW",
            "WWKBBBBBBBBBBBKWWWWKRRRRRRRKWWWWKRRRRRKW",
            "WWKBBBBBBBBBBBKWWWWKRRRRRRRKWWWWKRRRRRKW",
            "WWKBBBBBBBBBBBKWWWWKKKKKKKKKWWWWKRRRRRKW",
            "WWKBBBBBBBBBBBKWWWWWWWWWWWWWWWWWKRRRRRKW",
            "WWKBBBBBBBBBBBKWWWWWWWWWWWWWWWWWKRRRRRKW",
            "WWKBBBBBBBBBBBKWWKKKKKKKKKKKKKWWKRRRRRKW",
            "WWKBBBBBBBBBBBKWWKWWWWWWWWWWWKWWKRRRRRKW",
            "WWKBBBBBBBBBBBKWWKWYYYYWWWWWWKWWKRRRRRKW",
            "WWKKKKKKKKKKKKKWWKWYYYYWWWWWWKWWKRRRRRKW",
            "WWWWWWWWWWWWWWWWWKWYYYYWWWWWWKWWKRRRRRKW",
            "WWWWWWWWWWWWWWWWWKWYYYYWWWWWWKWWKRRRRRKW",
            "WWWWWWWWWWWWWWWWWKWWWWWWWWWWWKWWKRRRRRKW",
            "KKKKKKKKKKWWWWWWWKKKKKKKKKKKKKWWKRRRRRKW",
            "KYYYYYYYYKWWWWWWWWWWWWWWWWWWWWWWKKKKKKKW",
            "KYYYYYYYYKWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
            "KYYYYYYYYKWWKKKKKKKKKKKKKKKKKWWWWWWWWWWW",
            "KYYYYYYYYKWWKYYYYYYYYYYYYYKYKWWWWWWWWWWW",
            "KYYYYYYYYKWWKYYYYYYYYYYYYYYKKWWKKKKKKKKW",
            "KYYYYYYYYKWWKYYWWWWWWYKKKKYYKKWKKKKKKKKW",
            "KYYYYYYYYKWWKYYWWWWWWKBBBBKYKWWKKYYYYKKW",
            "KYYYYYYYYKWWKYYWWWWWWKBBBBKYKWWKKYYYYKKW",
            "KYYYYYYYYKWWKYYWWWWWWKBBBBKYKWWKKYYYYKKW",
            "KYYYYYYYYKWWKYYWWWWWWKBBBBKYKWWKKKKKKKKW",
            "KYYYYYYYYKWWKYYYYYYYYYKKKKYYKWWKKKKKKKKW",
            "KYYYYYYYYKWWKYYYYYYYYYYYYYYYKWWKKKKKKKKW",
            "KYYYYYYYYKWWKYYYYYYYYYYYYYYYKWWKKKKKKKKW",
            "KKKKKKKKKKWWKKKKKKKKKKKKKKKKKWWKKKKKKKKW",
            "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
        ],
        [
            "KKKKKKKKKKKKKKKKKKKKWWWWWWWWWWWWWWWWWKWW",
            "WWWWWWWWWWWWWWWWWWWWWWKKKKKKKKKKKKKWWKWW",
            "WWWWWWWWWWWWWWWWWWWWWWKYYYYYYYYYYYKWWKWW",
            "WWWWWWWWWWWWWWWWWWWWWWKYYYYYYYYYYYKWWKWW",
            "WWWWWWWWWWWWWWWWWWWWWWKYYYYYYYYYYYKWWKWW",
            "KKKKKKKKKKKKKKKKKKKKWWKYYYYYYYYYYYKWWKWW",
            "KBBBBBBBBBBBBBBBBBBKWWKYYYYYYYYYYYKWWKWW",
            "KBBBBBBBBBBBBBBBBBBKWWKYYYYYYYYYYYKWWKWW",
            "KBBBBBBBBBBBBBBBBBBKWWKYYYYYYYYYYYKWWKWW",
            "KBBBBBBBBBBBBBBBBBBKWWKYYYYYYYYYYYKWWKWW",
            "KBBBBBBBBBBBBBBBBBBKWWKYYYYYYYYYYYKWWKWW",
            "KBBBBBBBBBBBBBBBBBBKWWKYYYYYYYYYYYKWWKWW",
            "KBBBBBBBBBBBBBBBBBBKWWKYYYYYYYYYYYKWWKWW",
            "KBBBBBBBBBBBBBBBBBBKWWKYYYYYYYYYYYKWWKWW",
            "KBBBBBBBBBBBBBBBBBBKWWKYYYYYYYYYYYKWWKWW",
            "KBBBBBBBBBBBBBBBBBBKWWKYYYYYYYYYYYKWWKWW",
            "KBBBBBBBBBBBBBBBBBBKWWKYYYYYYYYYYYKWWKWW",
            "KBBBBBBBBBBBBBBBBBBKWWKYYYYYYYYYYYKWWKWW",
            "KKKKKKKKKKKKKKKKKKKKWWKKKKKKKKKKKKKWWKWW",
            "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
            "WWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWW",
            "KKKKKKKKKKKKWWKKKKKKWWKKKKKKKKKKKKKKKKKK",
            "KRRRRRRRRRRKWWKYYYYKWWKRRRRRRRRRRRRRRRRK",
            "KRRRRRRRRRRKWWKYYYYKWWKRRRRRRRRRRRRRRRRK",
            "KRRRRRRRRRRKWWKYYYYKWWKRRRRRRRRRRRRRRRRK",
            "KRRRRRRRRRRKWWKYYYYKWWKRRRRRRRRRRRRRRRRK",
            "KRRRRRRRRRRKWWKYYYYKWWKRRRRRRRRRRRRRRRRK",
            "KRRRRRRRRRRKWWKYYYYKWWKRRRRRRRRRRRRRRRRK",
            "KRRRRRRRRRRKWWKYYYYKWWKRRRRRRRRRRRRRRRRK",
            "KRRRRRRRRRRKWWKYYYYKWWKRRRRRRRRRRRRRRRRK",
            "KRRRRRRRRRRKWWKYYYYKWWKRRRRRRRRRRRRRRRRK",
            "KRRRRRRRRRRKWWKYYYYKWWKRRRRRRRRRRRRRRRRK",
            "KKKKKKKKKKKKWWKYYYYKWWKRRRRRRRRRRRRRRRRK",
            "WWWWWWWWWWWWWWKYYYYKWWKRRRRRRRRRRRRRRRRK",
            "WWWWWWWWWWWWWWKYYYYKWWKRRRRRRRRRRRRRRRRK",
            "WWWWWWWWWWWWWWKYYYYKWWKRRRRRRRRRRRRRRRRK",
            "KKKKKKKKKKKKWWKYYYYKWWKRRRRRRRRRRRRRRRRK",
            "KKKKKKKKKKKKWWKKKKKKWWKRRRRRRRRRRRRRRRRK",
            "KKKKKKKKKKKKWWWWWWWWWWKRRRRRRRRRRRRRRRRK",
            "KKKKKKKKKKKKWWWWWWWWWWKKKKKKKKKKKKKKKKKK",
        ],
        [
            "RRRRRRKRRRRWWBBBBBKKKKKKKKKKKKKKKBBKKKKK",
            "RRRRRRKRRRRWWBBBBBKKKKKKKKKKKKKKKBBKKKKK",
            "RRRRRRKRRRRWWBBBBBKKKKKKKKKKKKKKKBBKKKKK",
            "KKKKKYKKKKKKWKKKKKKKKKKKKKKKKKKKKKRKKKKK",
            "RRRRKYKKKKKKWKKKKKKKKKKKKKKWWYYYYKRKKKKK",
            "YYYYWWKKKKKKKKKKKKKKKKKKKKKKKWWWWKKKKKKK",
            "YYYYWWRRRRRWWKRRRRKYKWWWWWWRRWWWWWWKWWWW",
            "YYYYWWRRRRRWWKRRRRKYKWWWWWWRRWWWWWWKWWWW",
            "YYYYWWRRRRRWWKRRRRKYKWWWWWWRRWWWWWWKWWWW",
            "RRRRKWKKKKKKKKKKKKKWKKKKKKKBBKWWWKKWWWWW",
            "RRRRKWKBBBBRRWWWWWKWWWWWWWWBBKWWWKRWWWWW",
            "KKKKKKKKKKKKKKBBBBKKKKKKKKKKKWWWWKKKKKKK",
            "RRRRKRBBBBBWWKBBBBKRBBBBBBBWWWWWWRRKKKKK",
            "RRRRKRBBBBBWWKBBBBKRBBBBBBBWWWWWWRRKKKKK",
            "RRRRKRBBBBBWWKBBBBKRBBBBBBBWWWWWWRRKKKKK",
            "RRRRKRBBBBBWWKBBBBKRBBBBBBBWWWWWWRRKKKKK",
            "RRRRKKRRRRRKYKKKKKKKKKKKKKKKKKKKKKWKKKKK",
            "RRRRKKRRRRRKYKWWWWKKWWWWWWWYYBBBBKWKYYYY",
            "KKKKKKKBBBBKRRRRRRKWKKKKKKKBBKWWWKKRRRRR",
            "RRRRKWKBBBBKRRRRRRKWKWWWWWWBBKWWWBBRRRRR",
            "RRRRKWKBBBBKRRRRRRKWKWWWWWWBBKWWWBBRRRRR",
            "RRRRKWKBBBBKRRRRRRKWKWWWWWWBBKWWWBBRRRRR",
            "WWWWKKKKKKKKKBBBBBKKWWWWWWWKKWWWWKYKKKKK",
            "WWWWKWKWWWWKKBBBBBKWWWWWWWWKKWWWWKYKKKKK",
            "WWWWKKRRRRRRRKKKKKRRKKKKKKKKKWWWWKWKWWWW",
            "WWWWKRRRRRRRRKKKKKRRKWWWWWWKKWWWWKWKWWWW",
            "WWWWKRRRRRRRRKKKKKRRKWWWWWWKKWWWWKWKWWWW",
            "WWWWKRRRRRRRRKKKKKRRKWWWWWWKKWWWWKWKWWWW",
            "WWWWKRRRRRRRRKKKKKRRKWWWWWWKKWWWWKWKWWWW",
            "WWWWKRRRRRRRRKKKKKRRKWWWWWWKKWWWWKWKWWWW",
            "YYYYKKWWWWWKRKKKKKKKKKKKKKKWWRRRRKKKKKKK",
            "YYYYKYWWWWWKRKKKKKYYRRRRRRRWWRRRRKKWWWWW",
            "RRRRKKKRRRRKKKKKKKWWKKKKKKKKKYYYYKBKWWWW",
            "RRRRBBKRRRRWWRRRRRWWKKKKKKKKKYYYYKBKWWWW",
            "RRRRBBKRRRRWWRRRRRWWKKKKKKKKKYYYYKBKWWWW",
            "RRRRBBKRRRRWWRRRRRWWKKKKKKKKKYYYYKBKWWWW",
            "RRRRKBKKKKKKRKKKKKKKBBBBBBBKKKRRRKKKKKKK",
            "RRRRKBKWWWWKRKWWWWKKBBBBBBBKKKRRRKKKKKKK",
            "BBBBWWKKKKKKKKBBBBWWKKKKKKKWWWWWWWWKRRRR",
            "BBBBWWWWWWWWWKBBBBWWKKKKKKKWWWWWWWWKRRRR",
        ],
    ]

    // The paper and the gouaches, measured off photographs of the strip.
    private let paper = Color(hex: 0xDDD6C4)
    private let printerInk = Color(hex: 0x5B5A66)
    private let gouache: [Color] = [
        Color(hex: 0xE8E4D9), Color(hex: 0x201918), Color(hex: 0xCF3936),
        Color(hex: 0x3B4A93), Color(hex: 0xF6CF48),
    ]

    /// How many lines the printer is ahead of the brush, and how many more
    /// arrive while the brush works down one.
    private let wait = 8.0
    private let brush = 6.0

    /// A line of the strip: its cells, and the printer's codes for them,
    /// recorded once and replayed while the line waits for the brush.
    private struct Line {
        var cells: [Int]
        var codes: Batch?
    }

    private var chain = MosaicChain(values: 5)
    private var random = SplitMix64(seed: 0)
    private var strip: [Line] = []
    private var written = 0
    private var dealtAt = 0.0
    private var dealtFor: (data: Reading, seed: Int, cells: Int)?
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
        let cell = height / Double(cells)
        let across = width / cell
        let wanted = (data: data, seed: variation, cells: cells)
        if let dealt = dealtFor, dealt != wanted {
            // A new strip starts with the canvas full, from this moment.
            dealtAt = time
            dealtFor = nil
        }

        // The strip's place: how many lines have gone by the right edge. It
        // starts a canvas ahead, so the first frame is already full.
        let position = across + max(0, time - dealtAt) * pace
        let begun = Int(position) + 1
        if dealtFor == nil || begun < written - strip.count {
            dealtFor = wanted
            deal()
        }
        let kept = Int(across.rounded(.up)) + 2
        while written < begun {
            let next = chain.line(after: strip.last?.cells, places: cells, using: &random)
            strip.append(Line(cells: next))
            written += 1
            if strip.count > kept { strip.removeFirst() }
        }

        background(paper)
        noStroke()
        for i in strip.indices {
            // A line's age is how many lines have come in since it did. The
            // brush starts `wait` lines behind the printer and works down a
            // line while `brush` more arrive.
            let age = position - Double(written - strip.count + i)
            let x = width - age * cell
            guard x < width, x + cell > 0 else { continue }
            let line = strip[i].cells
            withState {
                translate(x, 0)
                if age < wait + brush {
                    if strip[i].codes == nil { strip[i].codes = codes(for: line, cell: cell) }
                    drawBatch(strip[i].codes!)
                } else {
                    strip[i].codes = nil
                }
                // The gouache, as far down the line as the brush has come.
                for (p, value) in line.enumerated() where age - wait - brush * Double(p) / Double(line.count) >= 0 {
                    fill(gouache[value])
                    drawRect(0, Double(p) * cell, cell, cell)
                }
            }
        }
    }

    /// The printer's line: a code for each cell, 1 to 5, recorded once.
    private func codes(for cells: [Int], cell: Double) -> Batch {
        var codes: Batch!
        withState {
            textSize(100)
            textSize(0.62 * cell * 100 / textWidth("M"))
            textAlign(.center, .middle)
            textMode(.atlas)
            fill(printerInk)
            codes = makeBatch {
                for (p, value) in cells.enumerated() {
                    drawText(String(value + 1), cell / 2, (Double(p) + 0.5) * cell)
                }
            }
        }
        return codes
    }

    /// Reads the chosen data pictures and starts the strip over.
    private func deal() {
        chain = MosaicChain(values: Self.letters.count)
        for index in data.pictures {
            // A picture is scanned as the strip is written: a line is one of
            // its columns, read top to bottom, and the lines go left to right.
            let rows = Self.dataPictures[index].map { row in
                row.map { Self.letters.firstIndex(of: $0) ?? 0 }
            }
            let lines = rows[0].indices.map { x in rows.map { $0[x] } }
            chain.learn(lines)
        }
        random = SplitMix64(seed: UInt64(bitPattern: Int64(variation)))
        strip = []
        written = 0
    }
}

/// A chain over a sheet of cells. What a cell holds is drawn from the counts
/// of what held that place, in the data, after the same cells around it.
private struct MosaicChain {
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

    /// Counts a data picture, given as its lines. Every cell is counted
    /// under its whole arrangement and under each shorter one, so the walk
    /// can forget the farthest cell when it has to.
    mutating func learn(_ lines: [[Int]]) {
        for (l, line) in lines.enumerated() {
            for (p, value) in line.enumerated() {
                let cells = around(p, in: line, after: l > 0 ? lines[l - 1] : nil)
                for n in 0 ... cells.count {
                    counts[Array(cells.prefix(n)), default: Array(repeating: 0, count: values)][value] += 1
                }
            }
        }
    }

    /// The line after `before`, `places` cells long.
    func line(after before: [Int]?, places: Int, using random: inout SplitMix64) -> [Int] {
        var line: [Int] = []
        for p in 0 ..< places {
            var cells = around(p, in: line, after: before)
            // An arrangement the data never showed: forget the farthest cell
            // and ask again. With none left, the counts are the paints' shares.
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
