// figure: frame=0
//
// Guide diagram: six easing curves from the catalog, each with its spacing
// strip. The top row stays inside 0...1; the bottom row's back, elastic, and
// bounce personalities overshoot or settle in hops on purpose.
import Ollin

final class EasingFamilies: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.28)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        textSize(19)

        drawPanel(x: 80, y: 60, name: "easeInQuad", curve: Easing.easeInQuad)
        drawPanel(x: 365, y: 60, name: "easeOutQuad", curve: Easing.easeOutQuad)
        drawPanel(x: 650, y: 60, name: "easeInOutCubic", curve: Easing.easeInOutCubic)
        drawPanel(x: 80, y: 320, name: "easeOutBack", curve: Easing.easeOutBack)
        drawPanel(x: 365, y: 320, name: "easeOutElastic", curve: Easing.easeOutElastic)
        drawPanel(x: 650, y: 320, name: "easeOutBounce", curve: Easing.easeOutBounce)
    }

    func drawPanel(x: Double, y: Double, name: String, curve: Easing) {
        let size = 150.0
        let top = y + 26, bottom = top + size

        noFill()
        stroke(faint)
        strokeWeight(2)
        drawRect(x, top, size, size)
        drawLine(x, bottom, x + size, top)

        var points: [Vector2] = []
        var t = 0.0
        while t <= 1.0001 {
            points.append(Vector2(x + t * size, bottom - curve(t) * size))
            t += 0.004
        }
        stroke(ink)
        strokeWeight(3)
        drawPolyline(points)

        noStroke()
        fill(ink)
        textAlign(.center, .bottom)
        drawText(name, x + size / 2, top - 8)

        let stripY = bottom + 26
        stroke(faint)
        strokeWeight(2)
        drawLine(x, stripY, x + size, stripY)
        noStroke()
        fill(accent)
        for i in 0...12 {
            drawCircle(x + curve(Double(i) / 12) * size, stripY, 5.5)
        }
    }
}
