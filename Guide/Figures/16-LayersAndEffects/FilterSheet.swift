// figure: frame=0
//
// Guide figure (Chapter 16): one scene through a sample of the filter catalog,
// one tile per family. The scene is drawn once into a layer; every tile is
// that same layer through a different filter.
import Ollin

final class FilterSheet: Sketch {
    override func draw() {
        background(Color(hex: 0x0C0E13))

        // A small landscape with smooth tone, color, and crisp edges, so every
        // filter family has something to bite on.
        let scene = renderTarget()
        withTarget(scene) {
            noStroke()
            fill(.linear(from: Vector2(0, 0), to: Vector2(0, height),
                         Ramp([Color(hex: 0x2A2E5E), Color(hex: 0xC65B7C), Color(hex: 0xF2B36A)])))
            drawRect(0, 0, width, height)
            fill(Color(hex: 0xFFE9B8)); drawCircle(width * 0.62, height * 0.38, 130)
            fill(Color(hex: 0x2E2440))
            drawTriangle(Vector2(-60, height), Vector2(width * 0.38, height * 0.52),
                         Vector2(width * 0.78, height))
            fill(Color(hex: 0x1A1430))
            drawTriangle(Vector2(width * 0.4, height), Vector2(width * 0.85, height * 0.62),
                         Vector2(width + 80, height))
            stroke(.white); strokeWeight(9); noFill()
            drawCircle(width * 0.62, height * 0.38, 190)
        }

        let tiles: [(String, Filter?)] = [
            ("the layer", nil),
            ("gaussianBlur", .gaussianBlur(radius: 22)),
            ("bloom", .bloom(threshold: 0.5, intensity: 1.6, radius: 22)),
            ("posterize", .posterize(levels: 4)),
            ("duotone", .duotone(dark: Color(hex: 0x1B1040), light: Color(hex: 0xFFD98A))),
            ("halftone", .halftone(scale: 52)),
            ("pixelate", .pixelate(size: 26)),
            ("edges", .edges(intensity: 2.2)),
            ("oilPaint", .oilPaint(radius: 5)),
            ("glitch", .glitch(amount: 0.12, seed: 3)),
            ("swirl", .swirl(angle: 2.6, radius: 0.55)),
            ("crosshatch", .crosshatch(scale: 90, foreground: Color(hex: 0x1B1040),
                                       background: Color(hex: 0xF3EBDD))),
        ]

        let cols = 3, rows = 4
        let gutter = width * 0.012
        let cellW = (width - gutter * Double(cols + 1)) / Double(cols)
        let cellH = (height - gutter * Double(rows + 1)) / Double(rows)
        let font = OutlineFont.system
        for (i, tile) in tiles.enumerated() {
            let x = gutter + Double(i % cols) * (cellW + gutter)
            let y = gutter + Double(i / cols) * (cellH + gutter)
            let layer = tile.1.map { scene.filtered($0) } ?? scene
            drawImage(layer.image, in: Rectangle(x: x, y: y, width: cellW, height: cellH))
            withState {
                blendMode(.normal)
                noStroke()
                fill(Color(white: 0, alpha: 0.55))
                drawRect(x, y + cellH - 26, cellW, 26)
                fill(.white)
                textFont(font); textSize(14); textAlign(.left, .middle)
                drawText(tile.0, x + 8, y + cellH - 13)
            }
        }
    }
}
