// figure: frame=110 themed
//
// Guide figure (Chapter 19): a sketch reading its own drawing. Left, a scene
// of three discs over drifting bands, as drawn; middle, the same layer
// slit-scanned on the GPU through a LayerHistory, the left edge now and the
// right edge the oldest frame held; right, a word drawn into a layer and read
// back as a glyph mosaic, its cells averaged on the GPU a frame late.
import Ollin
import OllinDiagram

final class ScannedByItself: Sketch {
    override var canvasSize: CanvasSize { .size(880, 300) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }

    var history: LayerHistory!

    override func setup() {
        history = makeLayerHistory(capacity: 60)
        textFont(OutlineFont.systemBold)
        textAlign(.center, .middle)
    }

    override func draw() {
        background(paper)
        let w = 278.0, h = 236.0, top = 22.0

        // The scene the first two panels share.
        let scene = makeRenderTarget(width: Int(w), height: Int(h))
        withTarget(scene) {
            background(Color(hex: 0x10141D))
            let t = Double(frameCount) * 0.05
            noStroke()
            for i in 0..<5 {
                let f = Double(i) / 5
                fill(Color(hue: 0.55 + f * 0.25, saturation: 0.55, brightness: 0.45))
                let y = ((f + t * 0.03).truncatingRemainder(dividingBy: 1)) * h
                for wrap in [-h, 0, h] { drawRect(0, y + wrap - h / 10, w, h / 5) }
            }
            let orbits: [(Double, Double, Double)] = [(1, 0.3, 0.2), (1.7, 0.18, 0.34), (2.3, 0.26, 0.12)]
            for (k, (speed, rx, ry)) in orbits.enumerated() {
                let a = t * speed + Double(k) * 2.1
                let x = w * (0.5 + rx * sin(a)), y = h * (0.5 + ry * sin(a * 2 + Double(k)))
                fill(.white)
                drawCircle(x, y, 14 + 5 * Double(k))
                fill(Color(hue: Double(k) / 3, saturation: 0.8, brightness: 1))
                drawCircle(x, y, 6 + 3 * Double(k))
            }
        }
        let scanned = scene.filtered(.slitScan(history, delay: .across))

        // The word the third panel reads.
        let word = makeRenderTarget(width: Int(w), height: Int(h))
        withTarget(word) {
            background(.clear)              // an empty cell stays empty
            noStroke()
            fill(.white)
            textSize(h * 0.36)
            textAlign(.center, .middle)
            withState {
                translate(w / 2 + sin(Double(frameCount) * 0.05) * w * 0.1, h / 2)
                rotate(sin(Double(frameCount) * 0.1) * 0.08)
                drawText("OLLIN", 0, 0)
            }
        }

        let x = [12.0, 12 + w + 10, 12 + (w + 10) * 2]
        drawImage(scene.image, in: Rectangle(x: x[0], y: top, width: w, height: h))
        drawImage(scanned.image, in: Rectangle(x: x[1], y: top, width: w, height: h))
        noStroke()
        fill(Color(hex: 0x10141D))
        drawRect(x[2], top, w, h)
        fill(.white)
        drawGlyphMosaic(word.image, columns: 36, characters: GlyphSet.classic,
                        in: Rectangle(x: x[2], y: top, width: w, height: h))

        fill(theme.ink)
        textSize(15)
        textAlign(.left, .bottom)
        for (i, label) in ["the layer, as drawn", "slit-scanned, left is now", "its word read as glyphs"].enumerated() {
            drawText(label, x[i], top + h + 26)
        }
    }
}
