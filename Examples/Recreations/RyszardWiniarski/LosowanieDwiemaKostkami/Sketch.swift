//  Recreation after Ryszard Winiarski - "Losowanie dwiema kostkami" (Drawing
//  Lots with Two Dice, 1977), the grid of black and white runs whose every
//  length is the sum of two dice, with the casts written under it. A homage,
//  not a reproduction, and not affiliated with or endorsed by the artist or
//  his estate.
//  https://zacheta.art.pl/pl/kolekcja/katalog/winiarski-ryszard-losowanie-dwiema-kostkami-2
//
//  An original Ollin interpretation written from the painting. Nothing was
//  ported: the work is acrylic on canvas, and the dice were thrown by hand.

import Ollin

/// "Losowanie dwiema kostkami" (Ryszard Winiarski, 1977), drawing lots with
/// two dice. From 1976 Winiarski went back to the simplest pairings of a
/// program and a throw, the series he called games, and this is one of the
/// plainest: a square canvas ruled into a fine grid inside a black frame, and
/// along its rows black runs and white runs taking turns, the length of each
/// one the sum of two dice. A run that reaches the right edge carries on at
/// the left of the next row, so the sheet reads like a page. Under the field,
/// in his hand, he wrote the rule and the first casts, "4+5, 6+3, 5+5, 6+4,
/// 1+1, 5+2...", and left the rest to be read off the picture.
///
/// Two dice make a distribution the eye can learn. Seven is the likeliest sum
/// and two and twelve the rarest, so most runs are five to nine squares long,
/// a run of two is a rare short tick and a run of twelve a rare long bar, and
/// black covers half the field in the long run because the two colors take
/// the same casts in turn. Nothing is placed; the histogram of two dice is
/// painted out as bars.
///
/// This sketch casts the dice and lays the runs at `pace` casts a second
/// from the top left, the two dice under the field showing the throw being
/// laid and the caption growing throw by throw until its line is full. A
/// finished sheet holds for `hold` seconds and the next one begins with new
/// casts. `cells` is the grid across the field and `firstSheet` the number
/// of the first sheet. A press starts the next sheet now.
///
/// Every black square exports as one square, so `--export-svg` with a frame
/// after the sheet is complete gives the runs back, and reading them off the
/// file gives the casts back: every run between two and twelve long, black
/// and white in turn, their mean near seven.
@main
final class LosowanieDwiemaKostkami: Sketch {
    @Param(10 ... 60, icon: "square.grid.3x3") var cells = 40
    @Param(1 ... 120, icon: "dice") var pace = 16.0
    @Param(0 ... 30, icon: "clock") var hold = 4.0
    @Param(1 ... 999, icon: "number") var firstSheet = 1

    private let border = Color(hex: 0x111111)
    private let paper = Color(hex: 0xEEE7D6)
    private let ruling = Color(hex: 0xC9A97C)
    private let ink = Color(hex: 0x111111)
    private let chalk = Color(hex: 0xEEE7D6)

    /// How many casts the caption has room for before it trails off.
    private let captioned = 11

    /// One sheet: the grid and every throw, in order.
    private struct Sheet {
        var number: Int
        var across: Int
        var casts: [(Int, Int)]
        /// The field each run ends before, cumulative, the last one cut at
        /// the end of the sheet.
        var ends: [Int]

        var count: Int { across * across }

        func start(of run: Int) -> Int { run == 0 ? 0 : ends[run - 1] }
    }

    private var sheet: Sheet?
    /// When the current sheet's first throw was laid.
    private var began = 0.0
    private var pressed = 0
    private var program = (cells: 0, first: 0)

    override func setup() {
        textFont(OutlineFont.systemMono)
    }

    override func mousePressed() {
        pressed += 1
    }

    override func draw() {
        background(border)

        let wanted = (cells: cells, first: firstSheet)
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

        let side = min(width, height) * 0.8
        let field = Rectangle(center: Vector2(width / 2, height / 2 - side * 0.055),
                              width: side, height: side)
        let cell = field.width / Double(current.across)

        noStroke()
        fill(paper)
        drawRect(field)
        noFill()
        stroke(ruling)
        strokeWeight(1)
        for k in 0 ... current.across {
            let along = Double(k) * cell
            drawLine(field.x + along, field.y, field.x + along, field.y + field.height)
            drawLine(field.x, field.y + along, field.x + field.width, field.y + along)
        }

        // How far the throwing has got: whole runs, then the run under the
        // hand as far as it has been laid.
        let thrown = (time - began) * pace
        let whole = min(current.casts.count, Int(thrown))
        var painted = whole == 0 ? 0 : current.ends[whole - 1]
        if whole < current.casts.count {
            let length = current.ends[whole] - current.start(of: whole)
            painted += Int(Double(length) * (thrown - Double(whole)))
        }

        noStroke()
        fill(ink)
        for run in stride(from: 0, to: current.casts.count, by: 2) {
            let from = current.start(of: run)
            guard from < painted else { break }
            for i in from ..< min(current.ends[run], painted) {
                drawRect(field.x + Double(i % current.across) * cell,
                         field.y + Double(i / current.across) * cell, cell, cell)
            }
        }

        // The casts written under the field, as many as the line holds, and
        // the dice showing the one being laid.
        let shown = min(whole + (whole < current.casts.count ? 1 : 0), current.casts.count)
        var caption = "drawing lots with two dice: "
        caption += current.casts.prefix(min(shown, captioned)).map { "\($0.0)+\($0.1)" }.joined(separator: ", ")
        if shown > captioned { caption += "..." }
        let size = side * 0.0165
        let baseline = field.y + field.height + side * 0.03
        drawText(caption, field.x, baseline, size: size, color: chalk, align: .left, .top)

        let sum = current.casts.prefix(shown).reduce(0) { $0 + $1.0 + $1.1 }
        let mean = shown > 0 ? Double(sum) / Double(shown) : 0
        let tenths = Int((mean * 10).rounded())
        let tally = "sheet \(current.number), \(shown) casts, mean \(tenths / 10).\(tenths % 10)"
        drawText(tally, field.x, baseline + side * 0.034, size: size, color: chalk, align: .left, .top)

        if shown > 0 {
            let throwing = current.casts[shown - 1]
            let die = side * 0.052
            let middle = baseline + side * 0.03
            drawDie(throwing.0, center: Vector2(field.x + field.width - die * 1.7, middle), size: die)
            drawDie(throwing.1, center: Vector2(field.x + field.width - die * 0.5, middle), size: die)
        }
    }

    /// Throw the dice for one whole sheet, until the runs cover it.
    private func start(sheet number: Int, at moment: Double) {
        randomSeed(number)
        let count = cells * cells
        var casts: [(Int, Int)] = []
        var ends: [Int] = []
        var covered = 0
        while covered < count {
            let pair = (die(), die())
            casts.append(pair)
            covered += pair.0 + pair.1
            ends.append(min(count, covered))
        }
        sheet = Sheet(number: number, across: cells, casts: casts, ends: ends)
        began = moment
    }

    private func die() -> Int {
        min(6, Int(random(0, 6)) + 1)
    }

    /// Throwing the sheet at `pace`, then holding it.
    private func duration(of sheet: Sheet) -> Double {
        Double(sheet.casts.count) / max(1, pace) + hold
    }

    /// One die face, pips in their usual places.
    private func drawDie(_ value: Int, center: Vector2, size: Double) {
        noStroke()
        fill(chalk)
        drawRect(center: center, width: size, height: size, cornerRadius: size * 0.18)
        fill(ink)
        let d = size * 0.27
        let pips: [Vector2] = switch value {
        case 1: [.zero]
        case 2: [Vector2(-d, -d), Vector2(d, d)]
        case 3: [Vector2(-d, -d), .zero, Vector2(d, d)]
        case 4: [Vector2(-d, -d), Vector2(d, -d), Vector2(-d, d), Vector2(d, d)]
        case 5: [Vector2(-d, -d), Vector2(d, -d), .zero, Vector2(-d, d), Vector2(d, d)]
        default: [Vector2(-d, -d), Vector2(-d, 0), Vector2(-d, d), Vector2(d, -d), Vector2(d, 0), Vector2(d, d)]
        }
        for pip in pips {
            drawCircle(center: center + pip, radius: size * 0.08)
        }
    }
}
