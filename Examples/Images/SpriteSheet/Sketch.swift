import Ollin

/// A sprite sheet is many pictures in one image: here eight frames of a turning
/// coin, each in a 128-pixel cell of a 512 by 256 sheet the sketch paints for
/// itself in `setup()`. `drawImage` with a source rectangle draws one cell at a
/// time, straight from the sheet with nothing cropped first, at whatever size the
/// box asks for. The sheet sits at the top at its own size with the frame being
/// drawn outlined, and below it the same eight frames turn three coins at three
/// sizes, each a few frames behind the last.
///
/// A cell reads only inside its rectangle, so the coin drawn twice its size never
/// picks up the edge of the coin beside it on the sheet. The coins also keep a
/// margin inside their cells, which is what keeps the half-size one clean: drawn
/// smaller than itself, a picture reads its smaller levels, and those average
/// across the edges between cells.
///
/// See Docs/Drawing/Images.md.
@main
final class SpriteSheet: Sketch {
    static let cell = 128, columns = 4, frames = 8
    private var sheet = Image(width: 1, height: 1)

    let paper = Color(hex: 0xF2EDE6)
    let ink = Color(hex: 0x24262E)
    let accent = Color(hex: 0xE4572E)

    override func setup() {
        textFont(OutlineFont.system)
        sheet = SpriteSheet.paintSheet()
    }

    override func draw() {
        background(paper)
        let frame = Int(time * 12) % SpriteSheet.frames     // twelve frames a second
        drawTitle()
        drawSheet(highlighting: frame)
        drawCoins(frame)
        drawCall()
    }

    /// Where frame `index` sits on the sheet, in the sheet's own pixels.
    static func source(of index: Int) -> Rectangle {
        let c = Double(cell)
        return Rectangle(x: Double(index % columns) * c, y: Double(index / columns) * c, width: c, height: c)
    }

    // MARK: The sheet at its own size

    static let sheetCorner = Vector2(284, 210)

    func drawSheet(highlighting frame: Int) {
        let corner = SpriteSheet.sheetCorner
        noStroke()
        fill(Color(hex: 0xE2DACD))
        drawRect(corner: corner, width: 512, height: 256)
        drawImage(sheet, corner: corner)

        // The cells, and the one being drawn this frame.
        noFill()
        stroke(ink.withAlpha(0.18))
        strokeWeight(1)
        for i in 0 ..< SpriteSheet.frames {
            let cell = SpriteSheet.source(of: i)
            drawRect(corner: corner + cell.corner, width: cell.width, height: cell.height)
        }
        let current = SpriteSheet.source(of: frame)
        stroke(accent)
        strokeWeight(3)
        drawRect(corner: corner + current.corner, width: current.width, height: current.height)

        noStroke()
        fill(ink.withAlpha(0.5))
        textSize(21)
        textAlign(.center, .top)
        drawText("the sheet, 512 by 256, one frame in each 128-pixel cell", 540, corner.y + 272)
    }

    // MARK: Three coins from the same eight frames

    func drawCoins(_ frame: Int) {
        let coins: [(side: Double, center: Double, behind: Int, label: String)] = [
            (64, 230, 0, "half its size"),
            (128, 410, 2, "its own size"),
            (256, 700, 5, "twice its size"),
        ]
        let baseline = 830.0
        for coin in coins {
            let source = SpriteSheet.source(of: (frame + SpriteSheet.frames - coin.behind) % SpriteSheet.frames)
            let box = Rectangle(x: coin.center - coin.side / 2, y: baseline - coin.side,
                                width: coin.side, height: coin.side)
            drawImage(sheet, box.x, box.y, box.width, box.height,
                      source.x, source.y, source.width, source.height)
            noStroke()
            fill(ink.withAlpha(0.5))
            textSize(21)
            textAlign(.center, .top)
            drawText(coin.label, coin.center, baseline + 18)
        }
    }

    // MARK: Words

    func drawTitle() {
        noStroke()
        fill(ink)
        textSize(44)
        textAlign(.center, .top)
        drawText("Eight coins on one sheet", 540, 80)
        fill(ink.withAlpha(0.45))
        textSize(23)
        drawText("each frame drawn straight from its cell, at any size", 540, 140)
    }

    func drawCall() {
        noStroke()
        fill(ink.withAlpha(0.7))
        textFont(OutlineFont.systemMono)
        textSize(20)
        textAlign(.center, .top)
        drawText("drawImage(sheet, x, y, size, size, cell.x, cell.y, 128, 128)", 540, 945)
        textFont(OutlineFont.system)
    }

    // MARK: Painting the sheet

    /// Eight frames of a coin turning half a turn about its upright, painted pixel
    /// by pixel with antialiased edges: the far face and the rim between the two
    /// faces in a darker gold, the near face over them with a ring and a highlight
    /// that slides across as it turns. Half a turn is a whole loop, because the
    /// coin's two faces are alike.
    static func paintSheet() -> Image {
        let sheet = Image(width: cell * columns, height: cell * frames / columns)
        let radius = 50.0, thickness = 9.0
        let gold = SIMD3(0.91, 0.70, 0.23), shade = SIMD3(0.62, 0.42, 0.10), ring = SIMD3(0.70, 0.50, 0.14)
        for index in 0 ..< frames {
            let angle = Double(index) / Double(frames) * .pi
            let turn = cos(angle), lean = sin(angle)
            let across = max(radius * abs(turn), 0.6)       // the face's half-width as seen
            let origin = source(of: index).corner
            for y in 0 ..< cell {
                for x in 0 ..< cell {
                    let px = Double(x) + 0.5 - Double(cell) / 2, py = Double(y) + 0.5 - Double(cell) / 2
                    // The rim: the face swept back through the coin's thickness, in
                    // steps under half a pixel apart so the edge-on frame stays solid.
                    var rim = 0.0
                    for step in 1 ... 24 {
                        let back = thickness * lean * Double(step) / 24
                        rim = max(rim, coverage(px - back, py, across, radius))
                    }
                    let face = coverage(px, py, across, radius)
                    // On the face: a ring at three quarters of the radius, and a
                    // highlight band whose place follows the turn.
                    let inner = coverage(px, py, across * 0.78, radius * 0.78)
                        - coverage(px, py, across * 0.68, radius * 0.68)
                    let u = px / max(across, 1)
                    let light = max(0, 1 - abs(u + 0.35 - 0.5 * turn) / 0.22) * 0.35
                    var faceColor = gold * (0.9 + 0.1 * (1 - u)) + SIMD3(repeating: light)
                    faceColor = faceColor * (1 - inner) + ring * inner
                    let alpha = face + rim * (1 - face)
                    guard alpha > 0 else { continue }
                    let color = (faceColor * face + shade * rim * (1 - face)) / alpha
                    sheet[Int(origin.x) + x, Int(origin.y) + y] =
                        Color(red: min(color.x, 1), green: min(color.y, 1), blue: min(color.z, 1), alpha: alpha)
                }
            }
        }
        return sheet
    }

    /// How much of the pixel centered at `(x, y)` an ellipse of half-width `a` and
    /// half-height `b` about the origin covers: its signed distance, estimated from
    /// the gradient, turned into a one-pixel ramp.
    static func coverage(_ x: Double, _ y: Double, _ a: Double, _ b: Double) -> Double {
        let q = ((x / a) * (x / a) + (y / b) * (y / b)).squareRoot()
        guard q > 0 else { return 1 }
        let gradient = ((x / (a * a)) * (x / (a * a)) + (y / (b * b)) * (y / (b * b))).squareRoot() / q
        let distance = gradient > 0 ? (q - 1) / gradient : -b
        return min(max(0.5 - distance, 0), 1)
    }
}
