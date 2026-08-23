import Ollin

/// Six versions of one piece, on one canvas, at the same time.
///
/// `withViewBox` runs a block inside a rectangle as if that rectangle were the
/// whole window: drawing is clipped to it and the coordinates are remapped, so
/// `petals()` below is written as though it owned the canvas and never learns
/// otherwise. Each box seeds itself differently, so the sheet is a contact sheet
/// of the same piece under six seeds.
///
/// Two things are remapped for the block so that code needs no changes. Its
/// `background` fills its own box rather than the frame, which belongs to all
/// six at once. And the mouse arrives in the box's own coordinates, which is why
/// the pale ring follows the pointer inside whichever box it is over and sits
/// out at the edge of the others.
///
/// Labels are drawn outside the boxes, in canvas coordinates, so they keep one
/// size while the pieces are scaled down.
///
/// See Docs/Core/Canvas.md.
@main
final class ViewBoxes: Sketch {
    static let columns = 3, rows = 2
    static let boxSize = 300.0, gap = 40.0, top = 300.0, rowGap = 100.0

    let paper = Color(hex: 0xF2EFE8)
    let ink = Color(hex: 0x22242C)

    static let palettes: [(Color, Color)] = [
        (Color(hex: 0xF6E7D8), Color(hex: 0xC1553C)),
        (Color(hex: 0xE7EDF2), Color(hex: 0x2F5D7C)),
        (Color(hex: 0xEDE9F2), Color(hex: 0x59417E)),
        (Color(hex: 0xF3EFE0), Color(hex: 0x6B7A3A)),
        (Color(hex: 0xF7E9E9), Color(hex: 0xA33B52)),
        (Color(hex: 0xE6EEEA), Color(hex: 0x2C6B5B)),
    ]

    override func setup() {
        textFont(OutlineFont.system)
    }

    override func draw() {
        background(paper)
        drawTitle()
        for seed in 0..<(ViewBoxes.columns * ViewBoxes.rows) {
            let frame = box(seed)
            withViewBox(frame) { petals(seed: seed) }
            label(seed, under: frame)
        }
    }

    func box(_ index: Int) -> Rectangle {
        let column = index % ViewBoxes.columns, row = index / ViewBoxes.columns
        let spanned = Double(ViewBoxes.columns) * ViewBoxes.boxSize
            + Double(ViewBoxes.columns - 1) * ViewBoxes.gap
        return Rectangle(x: (1080 - spanned) / 2 + Double(column) * (ViewBoxes.boxSize + ViewBoxes.gap),
                         y: ViewBoxes.top + Double(row) * (ViewBoxes.boxSize + ViewBoxes.rowGap),
                         width: ViewBoxes.boxSize, height: ViewBoxes.boxSize)
    }

    /// Drawn in canvas coordinates, outside the box, so it keeps its size.
    func label(_ seed: Int, under frame: Rectangle) {
        noStroke()
        fill(ink.withAlpha(0.5))
        textSize(22)
        textAlign(.center, .top)
        drawText("seed \(seed)", frame.center.x, frame.y + frame.height + 20)
    }

    func drawTitle() {
        noStroke()
        fill(ink)
        textSize(44)
        textAlign(.center, .top)
        drawText("One piece, six seeds, one window", 540, 130)
        fill(ink.withAlpha(0.45))
        textSize(22)
        drawText("each box is drawn as though it owned the canvas", 540, 192)
    }

    // MARK: The piece, written as though it owned the window

    /// A ring of petals over a wash. Nothing in here knows it is in a box: it
    /// reads `width`, `height` and `mouseX` and draws at canvas scale.
    func petals(seed: Int) {
        randomSeed(seed)
        noiseSeed(seed)
        let (wash, mark) = ViewBoxes.palettes[seed % ViewBoxes.palettes.count]
        background(wash)

        let count = 5 + seed % 6
        let turn = sway(over: 14, in: 0...(.tau), phase: Double(seed) / 12)

        withState {
            translate(center)
            rotate(turn)
            for i in 0..<count {
                withState {
                    rotate(Double(i) / Double(count) * .tau)
                    petal(mark, index: i)
                }
            }
        }

        // A ring on the pointer, in this box's own coordinates.
        noFill()
        stroke(mark.withAlpha(0.45))
        strokeWeight(6)
        drawCircle(mouseX, mouseY, 70)
    }

    func petal(_ mark: Color, index: Int) {
        let length = height * (0.22 + random(0.16))
        let waist = width * (0.05 + random(0.05))
        noStroke()
        fill(mark.withAlpha(0.55))
        drawShape { path in
            path.move(to: Vector2(0, 0))
            path.cubicCurve(to: Vector2(0, -length),
                            control1: Vector2(waist, -length * 0.25),
                            control2: Vector2(waist * 0.6, -length * 0.85))
            path.cubicCurve(to: Vector2(0, 0),
                            control1: Vector2(-waist * 0.6, -length * 0.85),
                            control2: Vector2(-waist, -length * 0.25))
            path.close()
        }
        fill(mark)
        drawCircle(0, -length, waist * 0.35)
    }
}
