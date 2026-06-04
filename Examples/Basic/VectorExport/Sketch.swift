import Ollin

/// Vector (SVG) export: the same draw calls that rasterize to a PNG can instead
/// be serialized as vector paths, so a sketch can drive a pen plotter or feed any
/// vector pipeline. Export one frame with no window and no GPU:
///
/// ```sh
/// swift run Example-VectorExport --export-svg /tmp/shapes.svg
/// ```
///
/// This sampler draws a grid of the shape catalog (filled + stroked) so the SVG
/// matches what the renderer shows on screen — circles and rects become native
/// `<circle>`/`<rect>`, polygons become `<polygon>`, and the curved analytic
/// shapes are traced to `<path>` outlines.
@main
final class VectorExport: Sketch {
    private let columns = 6
    private let rows = 5
    private let labelFont = OutlineFont.systemBold   // outline fonts take fill *and* stroke

    override func draw() {
        background(.white)
        let cw = width / Double(columns)
        let ch = height / Double(rows)
        let r = min(cw, ch) * 0.3   // nominal shape radius per cell

        for index in 0..<(columns * rows) {
            let col = index % columns
            let row = index / columns
            let x = (Double(col) + 0.5) * cw
            let y = (Double(row) + 0.5) * ch
            withState {
                translate(x, y)
                fill(Color(white: 0.85))
                stroke(.black)
                strokeWeight(2 * scale)
                drawShapeNumber(index, r: r)
            }
        }
    }

    /// Draw one shape from the catalog, centered at the origin.
    private func drawShapeNumber(_ i: Int, r: Double) {
        switch i {
        case 0:  drawCircle(0, 0, r)
        case 1:  drawEllipse(0, 0, r, r * 0.66)
        case 2:  drawRect(center: Vector2(0, 0), width: r * 1.8, height: r * 1.4, cornerRadius: r * 0.3)
        case 3:  drawTriangle(0, 0, r)
        case 4:  drawNgon(0, 0, r, sides: 6)
        case 5:  drawStar(0, 0, r, r * 0.45, points: 5)
        case 6:  drawRhombus(0, 0, r * 1.8, r * 1.4, cornerRadius: r * 0.2)
        case 7:  drawVesica(0, 0, r * 1.9, r * 1.2)
        case 8:  drawMoon(0, 0, r, r * 0.95, r * 0.5)
        case 9:  drawCross(0, 0, r * 2, r * 0.7, cornerRadius: r * 0.15)
        case 10:
            // `drawRing` is fill-only (it ignores stroke), so an outlined ring is
            // two `noFill` circles instead — which is what the black stroke shows here.
            noFill()
            drawCircle(0, 0, r)
            drawCircle(0, 0, r * 0.5)
        case 11: drawTrapezoid(0, 0, r, r * 1.8, r * 1.4)
        case 12: drawParallelogram(0, 0, r * 1.6, r * 1.3, r * 0.5)
        case 13: drawEgg(0, 0, r * 0.85, r * 0.4)
        case 14: drawHeart(0, 0, r * 1.8)
        case 15: drawCutDisk(0, 0, r, r * 0.35)
        case 16: drawUnevenCapsule(Vector2(-r * 0.5, r * 0.6), Vector2(r * 0.5, -r * 0.6), r * 0.5, r * 0.25)
        case 17: drawHorseshoe(0, 0, r * 0.7, r * 0.45, gap: 1.4)
        case 18: drawParabola(0, 0, r * 1.8, r * 1.5)
        case 19: drawRoundedX(0, 0, r * 1.9, r * 0.5)
        case 20: drawBlobbyCross(0, 0, r)
        case 21: drawTunnel(0, 0, r * 1.6, r * 1.6)
        case 22: drawStairs(0, 0, r * 0.5, r * 0.45, steps: 3)
        case 23: drawCoolS(0, 0, r * 1.9)
        case 24: drawArc(0, 0, r, r, start: -.tau / 4, stop: .tau / 4 + 0.6, mode: .pie)
        case 25: drawBezier(-r, r * 0.6, 0, -r * 1.4, r, r * 0.6)
        case 26: drawLine(Vector2(-r, -r * 0.6), Vector2(r, r * 0.6))
        case 27: drawPolyline([Vector2(-r, r * 0.6), Vector2(-r * 0.3, -r * 0.6),
                               Vector2(r * 0.3, r * 0.4), Vector2(r, -r * 0.6)])
        case 28: drawPolygon([Vector2(0, -r), Vector2(r * 0.9, r * 0.6),
                              Vector2(-r * 0.9, r * 0.6)])
        default:
            // An outline font draws each glyph as a `Shape`, so the text takes both
            // `fill` and `stroke` — unlike the bitmap font, whose pixels are fill-only.
            textFont(labelFont)
            textSize(r * 0.7)
            textAlign(.center, .middle)
            drawText("Ollin", 0, 0)
        }
    }
}
