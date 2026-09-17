//  Recreation after Owen Schuh - the right page of the notebook spread
//  "Natural = Rational / Natural ≠ Real" (2022), gouache on graph paper.
//  A homage, not a reproduction, and not affiliated with or endorsed by the
//  artist.
//  https://www.owenschuh.com
//
//  An original Ollin interpretation, written from the page and from the
//  mathematics the page draws. Nothing was ported: the work is paint on
//  paper, worked out by hand with at most a pocket calculator.

import Ollin

/// "Natural ≠ Real" (Owen Schuh, 2022). The other page of the spread is the
/// count that reaches every fraction; this one is the number no count can
/// reach. Suppose somebody hands you a list of the numbers between nought and
/// one, the first, the second, the third, and so on forever. Read the first
/// number's first place, the second's second place, the third's third, down
/// the diagonal of the list, and write a new number whose nth place is
/// deliberately not what you read. That number cannot be the first on the
/// list, because they differ in the first place; nor the second, nor the nth.
/// The list was supposed to hold every number, so no such list exists, and
/// the numbers between nought and one cannot be counted off the way the
/// fractions can.
///
/// The page paints it. Every digit is a color on a scale that runs from red
/// through the spectrum to black, with white for a nought, so each row is one
/// number written across the page and the whole list is a field of color.
/// The strip at the left takes the diagonal as it is read, one cell for each
/// number, and the band under the list is the new number, laid down place by
/// place as the rule is applied. The rule is the one written at the foot, in
/// the two colors it names.
///
/// One departure from the page, on purpose. Schuh's rule sends a black digit
/// to red and everything else to black, which is the shortest way to say it;
/// but a number whose places are all nines from some point on is the same
/// number as one that ends in noughts, so a rule that can write an endless
/// tail of nines leaves the argument a crack to fall through. The rule here
/// keeps his two-color shape and picks two digits in the middle instead: red
/// for a one, blue for a seven, neither of which can be read two ways, so the
/// number that comes out is the only number with those places and the
/// argument closes.
///
/// The list is written at `pace` digits a second, then the diagonal is read
/// one place every `dwell` seconds, each cell boxed in red as it is taken, so
/// the new number is built while you watch. `list` is how many of the endless
/// list the page shows and `places` how many of each number's endless places;
/// `hold` is how long the finished page stays up and `firstPage` numbers the
/// first one, which is the seed the digits come from. A press starts the next
/// page.
///
/// Every digit exports as a rect, so `--export-svg` with a frame after the
/// diagonal is read gives the page back as marks: the list, the strip that
/// holds its diagonal, and the band whose nth cell differs from the nth row's
/// nth cell, which is the whole of the argument.
@main
final class DiagonalArgument: Sketch {
    @Param(6 ... 16, icon: "list.number") var list = 12
    @Param(8 ... 20, icon: "rectangle.split.3x1") var places = 16
    @Param(4 ... 200, icon: "paintbrush.pointed") var pace = 60.0
    @Param(0.1 ... 3, icon: "metronome") var dwell = 0.7
    @Param(0 ... 30, icon: "clock") var hold = 5.0
    @Param(1 ... 999, icon: "number") var firstPage = 1

    override var canvasSize: CanvasSize { .size(920, 1200) }

    private let paper = Color(hex: 0xE7DFD2)
    private let ruling = Color(hex: 0xD3CBB9)
    private let pencil = Color(hex: 0xB3AA98)
    private let ink = Color(hex: 0x2B2622)
    private let blue = Color(hex: 0x2775C4)
    private let red = Color(hex: 0xD93E33)

    /// The ten digits, painted. The same scale the other page weaves with.
    private nonisolated static let digits: [Color] = [
        Color(hex: 0xFBF7EC), Color(hex: 0xD93E33), Color(hex: 0xE4633C),
        Color(hex: 0xEFA23F), Color(hex: 0xF2C432), Color(hex: 0xBFCB45),
        Color(hex: 0x127F6B), Color(hex: 0x2775C4), Color(hex: 0x22386A),
        Color(hex: 0x1E1A19),
    ]

    /// The two digits the rule writes: a one, painted red, and a seven,
    /// painted blue.
    private nonisolated static let plain = 1
    private nonisolated static let other = 7

    /// One page: the list somebody handed us.
    private struct Page {
        var number: Int
        var list: Int
        var places: Int
        /// `rows[number][place]`, every digit of every number on the list.
        var rows: [[Int]]
        /// A small offset and a size for every painted square, so the page is
        /// laid down by a hand and not by a printer.
        var hand: [(off: Vector2, size: Double)]

        /// How many places of the new number the diagonal can decide.
        var steps: Int { min(list, places) }

        /// The digit the diagonal reads for the `step`th number, counting
        /// from one.
        func diagonal(_ step: Int) -> Int { rows[step - 1][step - 1] }

        /// The new number's `step`th place: never what the diagonal read.
        func replacement(_ step: Int) -> Int {
            diagonal(step) == DiagonalArgument.plain ? DiagonalArgument.other : DiagonalArgument.plain
        }
    }

    private var page: Page?
    private var began = 0.0
    private var pressed = 0
    private var program = (list: 0, places: 0, first: 0)

    override func setup() {
        textFont(OutlineFont.system)
    }

    override func mousePressed() {
        pressed += 1
    }

    override func draw() {
        background(paper)

        let wanted = (list: list, places: places, first: firstPage)
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
        drawText("Natural ≠ Real", width / 2, 84, size: 42, color: ink, align: .center, .top)

        let block = 700.0
        let origin = Vector2(160, 224)
        let pitch = block / Double(current.places)
        let cell = pitch * 0.62
        let rowsDeep = Double(current.list) * pitch

        func middle(row: Int, place: Int) -> Vector2 {
            Vector2(origin.x + (Double(place) - 0.5) * pitch,
                    origin.y + (Double(row) - 0.5) * pitch)
        }
        func hand(_ index: Int) -> (off: Vector2, size: Double) {
            current.hand[index % current.hand.count]
        }
        /// One painted square, a touch off true and a touch off size.
        func paint(_ digit: Int, at place: Vector2, hand touch: (off: Vector2, size: Double)) {
            fill(Self.digits[digit])
            drawRect(center: place + touch.off * pitch, width: cell * touch.size, height: cell * touch.size)
        }

        // How far the hand has got: the list first, then the diagonal.
        let written = min(current.list * current.places, Int(max(0, time - began) * pace))
        let afterWriting = Double(current.list * current.places) / max(1, pace)
        let read = min(Double(current.steps), max(0, time - began - afterWriting) / max(0.01, dwell))
        let taken = Int(read)

        // The numbers along the edges, in pencil.
        for place in 1 ... current.places {
            drawText("\(place)", origin.x + (Double(place) - 0.5) * pitch, origin.y - 9,
                     size: min(14, pitch * 0.32), color: pencil, align: .center, .bottom)
        }
        for row in 1 ... current.list {
            drawText("\(row)", origin.x - 34, middle(row: row, place: 1).y,
                     size: min(15, pitch * 0.34), color: pencil, align: .right, .center)
        }

        // The list: every number one row of painted digits, behind a point.
        noStroke()
        for index in 0 ..< written {
            let row = index / current.places + 1
            let place = index % current.places + 1
            paint(current.rows[row - 1][place - 1], at: middle(row: row, place: place), hand: hand(index))
        }
        fill(ink)
        for row in 1 ... current.list where (row - 1) * current.places < written {
            drawCircle(center: Vector2(origin.x - 12, middle(row: row, place: 1).y), radius: 3)
        }

        // The diagonal, boxed as it is taken, carried into the strip at the
        // left, and turned by the rule into the band under the list.
        let stripX = 76.0
        let bandY = origin.y + rowsDeep + 86
        if taken > 0 {
            noFill()
            stroke(red)
            strokeWeight(2)
            for step in 1 ... taken {
                drawRect(center: middle(row: step, place: step), width: cell + 9, height: cell + 9)
            }
            noStroke()
            for step in 1 ... taken {
                let row = middle(row: step, place: step).y
                paint(current.diagonal(step), at: Vector2(stripX, row), hand: hand(step * 7))
                paint(current.replacement(step),
                      at: Vector2(middle(row: 1, place: step).x, bandY), hand: hand(step * 13))
            }
        }
        if taken < current.steps {
            let next = taken + 1
            let at = middle(row: next, place: next)
            noFill()
            stroke(red)
            strokeWeight(2)
            drawRect(center: at, width: cell + 9, height: cell + 9)
            strokeWeight(1)
            drawLine(at.x - cell / 2 - 7, at.y, stripX + cell / 2 + 3, at.y)
            noStroke()
        }

        // What the two of them are, in pencil.
        drawText("the diagonal", stripX - cell / 2 - 14, origin.y - 9,
                 size: 15, color: pencil, align: .left, .bottom)
        if taken >= current.steps {
            let after = middle(row: 1, place: current.steps).x + pitch * 2.1
            drawText("not on the list", min(after, width - 150), bandY,
                     size: 15, color: pencil, align: .left, .center)
        }

        // The loops: the list goes on, the places go on, the new number too.
        drawInfinity(at: Vector2(origin.x - 34, origin.y + rowsDeep + 30))
        drawInfinity(at: Vector2(origin.x + block + 32, middle(row: 1, place: 1).y))
        drawInfinity(at: Vector2(origin.x + block + 32, middle(row: current.list, place: 1).y))
        if taken >= current.steps {
            drawInfinity(at: Vector2(middle(row: 1, place: current.steps).x + pitch * 0.9, bandY))
        }

        drawFoot(under: bandY + 56, for: current, taken: taken)
    }

    /// What the page says about itself, and the key to the colors.
    private func drawFoot(under top: Double, for page: Page, taken: Int) {
        let left = 74.0
        var y = top
        let size = 20.0

        drawText("every row is one number between nought and one, place by place.", left, y,
                 size: size, color: ink, align: .left, .top)
        y += 31
        drawText("take the nth number's nth place: a red one becomes blue,", left, y,
                 size: size, color: ink, align: .left, .top)
        y += 31
        drawText("anything else becomes red. so the number under the list", left, y,
                 size: size, color: ink, align: .left, .top)
        y += 31
        drawText("differs from the nth number in the nth place, for every n.", left, y,
                 size: size, color: taken >= page.steps ? red : ink, align: .left, .top)

        y += 44
        let chip = 24.0
        for digit in 0 ... 9 {
            let x = left + Double(digit) * (chip + 11)
            fill(Self.digits[digit])
            drawRect(x, y, chip, chip)
            if digit == 0 {
                noFill()
                stroke(pencil)
                strokeWeight(1)
                drawRect(x, y, chip, chip)
                noStroke()
            }
            drawText("\(digit)", x + chip / 2, y + chip + 5, size: 14, color: pencil, align: .center, .top)
        }
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

    /// The hand-drawn loop: this one goes on forever.
    private func drawInfinity(at middle: Vector2) {
        let radius = 10.0
        noFill()
        stroke(blue)
        strokeWeight(2.5)
        drawCircle(middle.x - radius, middle.y, radius)
        drawCircle(middle.x + radius, middle.y, radius)
        noStroke()
    }

    /// Somebody hands us a list: every place of every number, picked by chance.
    private func start(page number: Int, at moment: Double) {
        randomSeed(number)
        let rows = (0 ..< list).map { _ in
            (0 ..< places).map { _ in min(9, Int(random(0, 10))) }
        }
        let hand = (0 ..< list * places).map { _ in
            (off: Vector2(random(-0.035, 0.035), random(-0.035, 0.035)), size: random(0.9, 1.08))
        }
        page = Page(number: number, list: list, places: places, rows: rows, hand: hand)
        began = moment
    }

    /// Writing the list, reading the diagonal, then holding the page.
    private func duration(of page: Page) -> Double {
        Double(page.list * page.places) / max(1, pace) + Double(page.steps) * dwell + hold
    }
}
