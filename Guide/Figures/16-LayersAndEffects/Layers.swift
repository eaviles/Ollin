// figure: frame=0
//
// Guide diagram (Chapter 16): the layer graph. Two drawings land in their own
// off-screen layers, each layer runs through a filter, and the results
// composite back onto the canvas. Every thumbnail is the real texture at that
// stage of the graph.
import Ollin

final class Layers: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.45)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        textSize(16)

        // The two sources, drawn once each into their own layer.
        let backdrop = renderTarget()
        withTarget(backdrop) {
            background(Color(hex: 0x141B2B))
            noStroke()
            fill(Color(hex: 0x4656C6)); drawCircle(width * 0.36, height * 0.4, 150)
            fill(Color(hex: 0x1F8A70)); drawCircle(width * 0.64, height * 0.62, 130)
        }
        let marks = renderTarget()
        withTarget(marks) {
            noStroke()
            fill(Color(hex: 0xFFC94A)); drawCircle(width * 0.42, height * 0.5, 34)
            fill(.white); drawCircle(width * 0.6, height * 0.42, 20)
            stroke(.white); strokeWeight(7); noFill()
            drawCircle(width * 0.52, height * 0.52, 76)
        }

        let blurred = backdrop.filtered(.gaussianBlur(radius: 30))
        let glowing = marks.filtered(.bloom(threshold: 0.4, intensity: 1.6, radius: 18))

        // Lay the five stages out as a graph.
        let w = 200.0, h = 125.0
        let colA = 40.0, colB = 340.0, colC = 640.0
        let rowTop = 60.0, rowBottom = 290.0, rowMid = 175.0

        thumb(backdrop, colA, rowTop, w, h, "draw into a layer")
        thumb(marks, colA, rowBottom, w, h, "draw into another")
        thumb(blurred, colB, rowTop, w, h, ".filtered(.gaussianBlur)")
        thumb(glowing, colB, rowBottom, w, h, ".filtered(.bloom)")

        // The composite panel: both filtered layers drawn into the same rect,
        // the second added as light.
        let rect = Rectangle(x: colC, y: rowMid, width: w, height: h)
        drawImage(blurred.image, in: rect)
        blendMode(.add)
        drawImage(glowing.image, in: rect)
        blendMode(.normal)
        noFill()
        stroke(faint)
        strokeWeight(1.5)
        drawRect(rect)
        noStroke()
        fill(faint)
        textSize(16)
        textAlign(.center, .top)
        drawText("drawImage, drawImage", colC + w / 2, rowMid + h + 10)

        arrow(from: Vector2(colA + w + 8, rowTop + h / 2), to: Vector2(colB - 8, rowTop + h / 2))
        arrow(from: Vector2(colA + w + 8, rowBottom + h / 2), to: Vector2(colB - 8, rowBottom + h / 2))
        arrow(from: Vector2(colB + w + 8, rowTop + h / 2), to: Vector2(colC - 8, rowMid + h * 0.32))
        arrow(from: Vector2(colB + w + 8, rowBottom + h / 2), to: Vector2(colC - 8, rowMid + h * 0.68))

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("layers hold a drawing; filters transform it; the canvas composites", width / 2, 495)
    }

    func thumb(_ layer: RenderTarget, _ x: Double, _ y: Double,
               _ w: Double, _ h: Double, _ caption: String) {
        drawImage(layer.image, in: Rectangle(x: x, y: y, width: w, height: h))
        noFill()
        stroke(faint)
        strokeWeight(1.5)
        drawRect(x, y, w, h)
        noStroke()
        fill(faint)
        textSize(16)
        textAlign(.center, .top)
        drawText(caption, x + w / 2, y + h + 10)
    }

    func arrow(from a: Vector2, to b: Vector2) {
        let dir = (b - a).normalized
        stroke(accent)
        strokeWeight(3)
        drawLine(a, b - dir * 12)
        noStroke()
        fill(accent)
        drawPolygon([b, b - dir * 15 + dir.perpendicular * 6,
                        b - dir * 15 - dir.perpendicular * 6])
    }
}
