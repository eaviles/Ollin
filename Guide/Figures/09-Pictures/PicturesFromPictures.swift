// figure: frame=0 themed
//
// Guide diagram (Chapter 9): a photo mosaic. The target on the left (one of
// the bundled sample photographs), the mosaic built from a hundred small
// pictures cut from all four photographs in the middle, and a piece of it
// enlarged on the right so the cells read as pictures again.
import Ollin
import OllinDiagram
import OllinSamplePhotos

final class PicturesFromPictures: Sketch {
    override var canvasSize: CanvasSize { .size(880, 460) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }
    var note: Color { darkTheme ? Color(hex: 0xE8E5E1, alpha: 0.62) : Color(hex: 0x6E6A63) }

    var target = Image(width: 1, height: 1)
    var library: [Image] = []
    var mosaic: PhotoMosaic?

    override func setup() {
        target = SamplePhoto.portrait.load().resized(width: 144, height: 144)
        library = SamplePhoto.all.flatMap { tiles(of: $0.load(), across: 5, side: 10) }
        mosaic = target.mosaic(of: library, columns: 24, rows: 24)
    }

    override func draw() {
        background(paper)
        guard let mosaic else { return }

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

    /// The library: `picture` shrunk to `across` tiles a side, then sliced into
    /// `across` by `across` pieces of `side` pixels, so every cell is a real
    /// piece of a real photograph.
    func tiles(of picture: Image, across: Int, side: Int) -> [Image] {
        let small = picture.resized(width: across * side, height: across * side)
        var pieces: [Image] = []
        for row in 0 ..< across {
            for column in 0 ..< across {
                let piece = Image(width: side, height: side, color: .black)
                for y in 0 ..< side {
                    for x in 0 ..< side {
                        piece[x, y] = small[column * side + x, row * side + y]
                    }
                }
                pieces.append(piece)
            }
        }
        return pieces
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
