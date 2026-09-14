//  Recreation after Ryszard Winiarski - the "Obszary" (Areas) and the series
//  "Próby wizualnej prezentacji rozkładów statystycznych" (Attempts at the
//  Visual Representation of Statistical Distributions, from 1965), fields of
//  black and white squares whose every square a coin or a die decided. A
//  homage, not a reproduction, and not affiliated with or endorsed by the
//  artist or his estate.
//  https://zacheta.art.pl/pl/kolekcja/artysci/ryszard-winiarski
//
//  An original Ollin interpretation written from the works and from what
//  Winiarski wrote about how he made them. Nothing was ported: the areas are
//  acrylic on canvas and board, and the chance in them was thrown by hand.

import Ollin

/// "Próby wizualnej prezentacji rozkładów statystycznych" (Ryszard Winiarski,
/// from 1965): attempts at the visual representation of statistical
/// distributions. Winiarski was an engineer before he was a painter, and in
/// 1965 he set down a program he kept to for the rest of his life. A work is
/// a square ruled into a grid of small squares, each one black or white, the
/// two colors standing for the 0 and 1 of probability. He did not call them
/// paintings but areas, "obszary", numbered them, and hung the rule beside
/// them or wrote it on the back. He described the method himself: "I first of
/// all establish the rules of procedure, the rules of the game, and then I
/// invite chance to take part in carrying it out. The source of chance may be
/// a coin, a die, a roulette wheel, a table of random numbers, or a suitably
/// programmed computer."
///
/// The program fixed what it fixed and left the rest to the throw. Bożena
/// Kowalska, who followed his work for decades, described one: the program
/// offered two sizes of square for the canvas to be ruled into, and a coin
/// chose between them; the corner the filling would start from was drawn the
/// same way; and then, square after square, a coin toss decided whether a
/// field turned black or stayed white. Later areas changed the variable
/// rather than the rule. A die in place of the coin puts black on some of its
/// faces and the field thins or thickens; and in "Przejście" (Transition,
/// 1975) and the twenty-six panels of "Od 0 do 100% czerni" (From 0 to 100%
/// of Black, 1975) the probability itself moves across the area, so one grid
/// runs from empty to solid with no square placed by hand.
///
/// This sketch is the program, with the throwing left to the machine. An area
/// is painted one field at a time from the drawn corner at `pace` fields a
/// second, the rule written under it the way he hung it beside the work, and
/// the count of black so far against what the distribution promised. When
/// the area is complete it holds for `hold` seconds, then the next area
/// begins under the same rule with new throws, numbered on from the last.
/// `variable` is the source of chance: a coin, black on heads; a die, black
/// on the faces up to `blackFaces`; or the transition, where the share of
/// black rises from nothing at the first field to everything at the last.
/// `cells` is the larger of the two grids the coin chooses between, and
/// `firstArea` the number of the first area. A press starts the next area
/// now.
///
/// Every black field exports as one square, so `--export-svg` with a frame
/// after the area is complete gives the area back as the record it is, and
/// counting the squares in the file is counting the throws.
@main
final class Obszar: Sketch {
    /// The source of chance, the "random variable" his titles name.
    enum Variable: CaseIterable, ParamOption {
        case coin, die, transition

        var optionLabel: String {
            switch self {
            case .coin: "Coin"
            case .die: "Die"
            case .transition: "Transition"
            }
        }
    }

    @Param(icon: "dice") var variable = Variable.coin
    @Param(1 ... 5, icon: "die.face.2") var blackFaces = 2
    @Param(8 ... 64, icon: "square.grid.3x3") var cells = 40
    @Param(20 ... 2000, icon: "paintbrush") var pace = 200.0
    @Param(0 ... 30, icon: "clock") var hold = 4.0
    @Param(1 ... 999, icon: "number") var firstArea = 1

    private let paper = Color(hex: 0xF3F0E9)
    private let ink = Color(hex: 0x141414)
    private let pencil = Color(hex: 0xD6D0C3)
    private let handwriting = Color(hex: 0x4A4640)

    /// One area: what the program drew for it, and every throw.
    private struct Area {
        var number: Int
        /// Squares on a side, the one of the two sizes the coin chose.
        var across: Int
        /// The corner the filling starts from: top left, top right, bottom
        /// right, bottom left.
        var corner: Int
        /// Black or white, in the order the fields are painted.
        var fields: [Bool]

        /// Where the field painted `index`th sits, counting rows away from
        /// the drawn corner and columns away from its side.
        func place(of index: Int) -> (column: Int, row: Int) {
            let row = index / across, column = index % across
            switch corner {
            case 0: return (column, row)
            case 1: return (across - 1 - column, row)
            case 2: return (across - 1 - column, across - 1 - row)
            default: return (column, across - 1 - row)
            }
        }
    }

    private var area: Area?
    /// When the current area's first field was painted.
    private var began = 0.0
    private var pressed = 0
    /// The program the current area was thrown under, so a changed parameter
    /// starts a new area rather than repainting this one under another rule.
    private var program = (variable: Variable.coin, faces: 0, cells: 0, first: 0)

    private static let corners = ["top left", "top right", "bottom right", "bottom left"]

    override func setup() {
        textFont(OutlineFont.system)
    }

    override func mousePressed() {
        pressed += 1
    }

    override func draw() {
        background(paper)

        let wanted = (variable: variable, faces: blackFaces, cells: cells, first: firstArea)
        if area == nil || program != wanted {
            program = wanted
            start(area: firstArea, at: time)
        }
        while pressed > 0 {
            pressed -= 1
            start(area: (area?.number ?? firstArea) + 1, at: time)
        }
        while let current = area, time - began >= duration(of: current) {
            start(area: current.number + 1, at: began + duration(of: current))
        }
        guard let current = area else { return }

        let side = min(width, height) * 0.8
        let field = Rectangle(center: Vector2(width / 2, height / 2 - side * 0.055),
                              width: side, height: side)
        let cell = field.width / Double(current.across)

        // The pencil ruling first, so the black fields cover it.
        noFill()
        stroke(pencil)
        strokeWeight(1)
        for k in 0 ... current.across {
            let along = Double(k) * cell
            drawLine(field.x + along, field.y, field.x + along, field.y + field.height)
            drawLine(field.x, field.y + along, field.x + field.width, field.y + along)
        }

        let count = current.fields.count
        let painted = min(count, Int((time - began) * pace))
        var black = 0
        noStroke()
        fill(ink)
        for i in 0 ..< painted where current.fields[i] {
            black += 1
            let (column, row) = current.place(of: i)
            drawRect(field.x + Double(column) * cell, field.y + Double(row) * cell, cell, cell)
        }

        // The rule beside the work, and the count against the promise.
        let rule: String
        let promised: Double
        switch variable {
        case .coin:
            rule = "a coin, black on heads"
            promised = 0.5
        case .die:
            rule = blackFaces == 1 ? "a die, black on 1" : "a die, black on 1 to \(blackFaces)"
            promised = Double(blackFaces) / 6
        case .transition:
            rule = "chance rising from 0 to 100% black"
            promised = 0.5
        }
        let title = "Obszar \(current.number). Random variable: \(rule). "
            + "From the \(Obszar.corners[current.corner]) corner, \(current.across) by \(current.across)."
        let share = painted > 0 ? Double(black) / Double(painted) : 0
        let tally = painted < count
            ? "\(painted) of \(count) fields, \(black) black (\(Obszar.percent(share)))"
            : "\(count) fields, \(black) black (\(Obszar.percent(share))), \(Obszar.percent(promised)) expected"
        let baseline = field.y + field.height + side * 0.026
        drawText(title, field.x, baseline, size: side * 0.0175, color: handwriting, align: .left, .top)
        drawText(tally, field.x, baseline + side * 0.032, size: side * 0.0175, color: handwriting, align: .left, .top)
    }

    /// Throw one whole area: the coin picks the grid, two more throws pick
    /// the corner, then the variable decides every field in painting order.
    private func start(area number: Int, at moment: Double) {
        randomSeed(number)
        let across = random(0, 1) < 0.5 ? cells : max(4, cells * 3 / 4)
        let corner = (random(0, 1) < 0.5 ? 0 : 1) + (random(0, 1) < 0.5 ? 0 : 2)
        let count = across * across
        var fields: [Bool] = []
        fields.reserveCapacity(count)
        for i in 0 ..< count {
            switch variable {
            case .coin:
                fields.append(random(0, 1) < 0.5)
            case .die:
                fields.append(min(5, Int(random(0, 6))) < blackFaces)
            case .transition:
                fields.append(random(0, 1) < Double(i) / Double(max(1, count - 1)))
            }
        }
        area = Area(number: number, across: across, corner: corner, fields: fields)
        began = moment
    }

    /// Painting the area at `pace`, then holding it.
    private func duration(of area: Area) -> Double {
        Double(area.fields.count) / max(1, pace) + hold
    }

    private static func percent(_ share: Double) -> String {
        let tenths = Int((share * 1000).rounded())
        return "\(tenths / 10).\(tenths % 10)%"
    }
}
