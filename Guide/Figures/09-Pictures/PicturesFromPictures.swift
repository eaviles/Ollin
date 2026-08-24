// figure: frame=0 themed
//
// Guide diagram (Chapter 9): a photo mosaic. The target on the left, the mosaic
// built from a hundred small pictures in the middle, and a piece of it enlarged
// on the right so the cells read as pictures again.
import Ollin

final class PicturesFromPictures: Sketch {
    override var canvasSize: CanvasSize { .size(880, 460) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B) }
    var soft: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.12) }
    var note: Color { darkTheme ? Color(hex: 0xE8E5E1, alpha: 0.62) : Color(hex: 0x6E6A63) }

    override func draw() {
        background(paper)

        let target = Image(width: 144, height: 144, color: .black)
        paint(target)
        let library = (0 ..< 100).map { tile(index: $0) }
        let mosaic = target.mosaic(of: library, columns: 24, rows: 24)

        let left = Rectangle(x: 64, y: 66, width: 230, height: 230)
        let middle = Rectangle(x: 324, y: 66, width: 230, height: 230)
        let right = Rectangle(x: 584, y: 66, width: 230, height: 230)

        drawImage(target, in: left, fit: .cover)
        drawMosaic(mosaic, of: library, in: middle, tint: 0.25)

        // Seven by seven cells from the middle of the same mosaic, enlarged, where
        // the light is: a dark corner would only show that dark tiles are dark.
        withClip(right) {
            // Seven of the mosaic's twenty-four columns, filling the panel.
            let scale = 24.0 / 7
            let cell = right.width / 7
            let big = Rectangle(x: right.x - 7 * cell, y: right.y - 8 * cell,
                                width: right.width * scale, height: right.height * scale)
            for tile in mosaic.tiles where (7 ... 13).contains(tile.column) && (8 ... 14).contains(tile.row) {
                let frame = mosaic.frame(of: tile, in: big)
                drawImage(library[tile.picture], in: frame, fit: .cover)
            }
        }

        frame(left, title: "the target")
        frame(middle, title: "one picture per cell")
        frame(right, title: "seven cells across, enlarged")

        fill(ink)
        noStroke()
        textSize(21)
        textAlign(.center, .top)
        drawText("each cell takes the picture whose average color is nearest",
                 width / 2, 336)
        textSize(17)
        fill(note)
        drawText("averaged in linear light, where half black and half white really is middle gray",
                 width / 2, 370)
    }

    /// One picture for the library: a colored ground with a mark on it.
    func tile(index: Int) -> Image {
        let side = 10
        let picture = Image(width: side, height: side, color: .black)
        let hue = Double(index % 10) / 10
        let level = 0.12 + Double(index / 10) / 9
        let ground = CosinePalette.rainbow.color(at: hue)
        for y in 0 ..< side {
            for x in 0 ..< side {
                let u = Double(x) / Double(side - 1), v = Double(y) / Double(side - 1)
                var lift = 0.0
                switch index % 4 {
                case 0: lift = (u + v) < 0.7 ? 0.35 : 0
                case 1: lift = abs(u - 0.5) < 0.18 ? 0.3 : 0
                case 2: lift = (u - 0.5) * (u - 0.5) + (v - 0.5) * (v - 0.5) < 0.06 ? 0.4 : 0
                default: lift = ((x + y) % 4 < 2) ? 0.18 : 0
                }
                picture[x, y] = Color(red: clamp(ground.red * level + lift, 0, 1),
                                      green: clamp(ground.green * level + lift, 0, 1),
                                      blue: clamp(ground.blue * level + lift, 0, 1))
            }
        }
        return picture
    }

    /// The target: a lit blob over a ground that shifts across the frame, so every
    /// cell asks for a different color.
    func paint(_ target: Image) {
        let n = target.width
        for y in 0 ..< n {
            for x in 0 ..< n {
                let u = (Double(x) + 0.5) / Double(n) * 2 - 1
                let v = (Double(y) + 0.5) / Double(n) * 2 - 1
                let field = exp(-((u + 0.2) * (u + 0.2) + (v - 0.1) * (v - 0.1)) * 5)
                    + 0.7 * exp(-((u - 0.5) * (u - 0.5) + (v + 0.45) * (v + 0.45)) * 12)
                let tone = clamp(1 - exp(-1.6 * field), 0, 1)
                let ground = 0.22 + 0.2 * (u * 0.5 + 0.5) + 0.14 * (v * 0.5 + 0.5)
                let hue = clamp(0.08 + (u * 0.5 + 0.5) * 0.35 + (v * 0.5 + 0.5) * 0.2 + tone * 0.3, 0, 1)
                let paint = CosinePalette.rainbow.color(at: hue)
                let level = ground + tone * 0.85
                target[x, y] = Color(red: clamp(paint.red * level, 0, 1),
                                     green: clamp(paint.green * level, 0, 1),
                                     blue: clamp(paint.blue * level, 0, 1))
            }
        }
    }

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textSize(17)
        textAlign(.left, .middle)
        drawText(title, r.x, r.y - 20)
    }
}
