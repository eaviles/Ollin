// figure: frame=0 format=png
//
// Guide figure (Chapter 31): the export supersample, demonstrating itself. One
// small probe, a fan of wedges meeting at a point, is rendered twice through
// OllinApp.image(of:), at render scale 1 and at 4, and both results are read
// back and drawn one pixel per square, so the magnification is exact instead of
// smoothed. The panels are therefore the real exported pixels, not a picture of
// them.
//
// SamplingFiner is declared first on purpose: the sketch loader compiles the
// first `class …: Sketch` it finds, so the probe has to come after it.
import Ollin

final class SamplingFiner: Sketch {
    override var canvasSize: CanvasSize { .size(880, 462) }

    override func setup() { noLoop() }

    override func draw() {
        background(Color(hex: 0xF7F5F1))

        let cell = 9.0, gap = 46.0
        let panel = cell * Double(EdgeProbe.side)
        let left = (width - panel * 2 - gap) / 2

        textFont(.system)
        for (index, scale) in [1, 4].enumerated() {
            let x = left + Double(index) * (panel + gap)
            drawPanel(pixels(atScale: scale), at: Vector2(x, 58), cell: cell)

            noStroke()
            fill(Color(hex: 0x2B2B2B))
            textSize(19)
            textAlign(.center, .bottom)
            drawText("--render-scale \(scale)", x + panel / 2, 44)

            fill(Color(hex: 0x2B2B2B, alpha: 0.62))
            textSize(16)
            textAlign(.center, .top)
            drawText(scale == 1 ? "one sample per pixel" : "sixteen, averaged",
                     x + panel / 2, 58 + panel + 12)
        }

        fill(Color(hex: 0x2B2B2B))
        textSize(19)
        textAlign(.center, .top)
        drawText("the same exported pixels, one square each", width / 2, 424)
    }

    /// Draw a grid of read-back pixels, one square per pixel, with a hairline
    /// around the whole block so the panel reads as one picture.
    private func drawPanel(_ rows: [[Color]], at origin: Vector2, cell: Double) {
        noStroke()
        for (y, row) in rows.enumerated() {
            for (x, color) in row.enumerated() {
                fill(color)
                drawRect(origin.x + Double(x) * cell, origin.y + Double(y) * cell, cell, cell)
            }
        }
        noFill()
        stroke(Color(hex: 0x2B2B2B, alpha: 0.35))
        strokeWeight(1)
        drawRect(origin.x, origin.y,
                 cell * Double(rows.first?.count ?? 0), cell * Double(rows.count))
    }

    /// Render the probe at `scale` and read the exported frame back as rows of
    /// colors, top row first. The dial is a global, so it goes back where it was
    /// before the figure's own render continues.
    private func pixels(atScale scale: Int) -> [[Color]] {
        let previous = OllinApp.exportRenderScale
        OllinApp.exportRenderScale = scale
        let exported = OllinApp.image(of: EdgeProbe())
        OllinApp.exportRenderScale = previous
        guard let exported else { return [] }

        let w = exported.width, h = exported.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return [] }
        bytes.withUnsafeMutableBytes { raw in
            guard let context = CGContext(data: raw.baseAddress, width: w, height: h,
                                          bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return }
            context.draw(exported, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return (0..<h).map { y in
            (0..<w).map { x in
                let i = (y * w + x) * 4
                return Color(red: Double(bytes[i]) / 255,
                             green: Double(bytes[i + 1]) / 255,
                             blue: Double(bytes[i + 2]) / 255)
            }
        }
    }
}

/// The probe: a fan of wedges meeting at a point, filled through the
/// triangulated path. Detail this fine is the hardest thing a pixel grid has to
/// describe, which is why the two panels differ at all.
final class EdgeProbe: Sketch {
    static let side = 36

    override var canvasSize: CanvasSize { .square(EdgeProbe.side) }

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        noStroke()
        fill(Color(hex: 0x1E4FD8))
        let center = Vector2(Double(EdgeProbe.side) / 2, Double(EdgeProbe.side) * 0.92)
        let wedges = 18, radius = Double(EdgeProbe.side) * 1.4
        for k in 0..<wedges {
            let a0 = Double(k) * 2 * .pi / Double(wedges)
            let a1 = a0 + .pi / Double(wedges)
            drawShape(Shape([center,
                             center + Vector2(cos(a0), sin(a0)) * radius,
                             center + Vector2(cos(a1), sin(a1)) * radius]))
        }
    }
}
