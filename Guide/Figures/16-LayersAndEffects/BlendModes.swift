// figure: frame=0 probe
//
// Guide diagram (Chapter 16): the blend modes. The same two shaded discs in
// every tile; only the mode the second disc composites with changes.
import Ollin

final class BlendModes: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    override func draw() {
        background(Color(hex: 0xF7F5F1))

        let modes: [(String, BlendMode)] = [
            (".normal", .normal), (".add", .add), (".subtract", .subtract),
            (".multiply", .multiply), (".screen", .screen),
            (".lightest", .lightest), (".darkest", .darkest),
        ]

        let cols = 4
        let gutter = 14.0
        let cellW = (width - gutter * Double(cols + 1)) / Double(cols)
        let cellH = 200.0
        for (i, mode) in modes.enumerated() {
            let x = gutter + Double(i % cols) * (cellW + gutter)
            let y = 18.0 + Double(i / cols) * (cellH + 48)
            tile(x, y, cellW, cellH, mode.0, mode.1)
        }

        noStroke()
        fill(Color(hex: 0x2B2B2B))
        textSize(21)
        textAlign(.center, .top)
        drawText("the same two discs, seven ways for new paint to meet old", width / 2, 505)
    }

    func tile(_ x: Double, _ y: Double, _ w: Double, _ h: Double,
              _ label: String, _ mode: BlendMode) {
        // A mid-gray ground, so modes that darken and modes that brighten both read.
        noStroke()
        fill(Color(hex: 0x4A5060))
        drawRect(x, y, w, h)

        let a = Vector2(x + w * 0.38, y + h * 0.4)
        let b = Vector2(x + w * 0.62, y + h * 0.6)
        let r = w * 0.3
        fill(Color(hex: 0xE8933C))
        drawPolygon(disc(a, r))
        blendMode(mode)
        fill(Color(hex: 0x4FA3D8))
        drawPolygon(disc(b, r))
        blendMode(.normal)

        fill(Color(hex: 0x2B2B2B, alpha: 0.6))
        textSize(16)
        textAlign(.center, .top)
        drawText(label, x + w / 2, y + h + 10)
    }

    func disc(_ center: Vector2, _ radius: Double) -> [Vector2] {
        (0 ..< 96).map { i in
            let a = Double(i) / 96 * .tau
            return center + Vector2(cos(a), sin(a)) * radius
        }
    }
}
