// figure: frame=0
//
// Guide figure (Chapter 18): the three material textures painted from nothing.
// A rust bloom and a verdigris patina over scatters the sketch holds, and a
// terrazzo floor, each at a fixed seed and light.
import Ollin

final class MaterialTextures: Sketch {
    override var canvasSize: CanvasSize { .size(880, 330) }

    override func draw() {
        background(Color(hex: 0x0C0E13))
        let tile = 268.0, gap = 12.0, top = 14.0
        let left = (width - tile * 3 - gap * 2) / 2
        let region = Rectangle(x: 0, y: 0, width: tile, height: tile)
        let side = Int(tile)

        let blooms = Patina.scatter(in: region, count: 9, radius: 30 ... 76, seed: 6)
        let tiles: [(String, RenderTarget)] = [
            ("rust", generate(.rust(blobs: blooms, lightAngle: -2.1), width: side, height: side)),
            ("verdigris", generate(.verdigris(count: 10, radius: 26 ... 70, seed: 3, lightAngle: 2.4),
                                   width: side, height: side)),
            ("terrazzo", generate(.terrazzo(chipRadius: 24, density: 0.6, gap: 2, seed: 2),
                                  width: side, height: side)),
        ]

        textFont(.system)
        for (i, item) in tiles.enumerated() {
            let x = left + Double(i) * (tile + gap)
            drawImage(item.1.image, x, top)
            noStroke()
            fill(Color(white: 0.5))
            textSize(17)
            textAlign(.center, .top)
            drawText(item.0, x + tile / 2, top + tile + 10)
        }
    }
}
