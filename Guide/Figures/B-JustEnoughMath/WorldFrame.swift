// figure: frame=0
//
// Guide diagram (Appendix B): the two coordinate frames side by side. The
// canvas counts pixels down from the top left; the 3D world counts units up
// from its center, with z coming toward the viewer.
import Ollin

final class WorldFrame: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.28)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        textSize(21)

        // Left: the canvas frame.
        let corner = Vector2(100, 120)
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(corner.x, corner.y, 270, 270)

        arrow(from: corner, to: corner + Vector2(160, 0))
        arrow(from: corner, to: corner + Vector2(0, 160))
        noStroke()
        fill(accent)
        drawCircle(center: corner, radius: 7)
        fill(ink)
        textAlign(.center, .bottom)
        drawText("(0, 0)", corner.x, corner.y - 14)
        textAlign(.left, .middle)
        drawText("x", corner.x + 178, corner.y)
        textAlign(.center, .top)
        drawText("y", corner.x, corner.y + 178)
        drawText("the canvas: pixels, y grows down", corner.x + 135, corner.y + 292)

        // Right: the world frame.
        let origin = Vector2(640, 255)
        arrow(from: origin, to: origin + Vector2(150, 0))
        arrow(from: origin, to: origin + Vector2(0, -150))
        dashedArrow(from: origin, to: origin + Vector2(-95, 105))
        noStroke()
        fill(accent)
        drawCircle(center: origin, radius: 7)
        fill(ink)
        textAlign(.left, .middle)
        drawText("x", origin.x + 168, origin.y)
        textAlign(.center, .bottom)
        drawText("y", origin.x, origin.y - 164)
        textAlign(.center, .top)
        drawText("z, toward you", origin.x - 108, origin.y + 124)
        drawText("the 3D world: units, y grows up", origin.x, origin.y + 292 - 135)

        textAlign(.center, .top)
        drawText("same x, opposite y: pixel rows count down, world units count up",
                 width / 2, 500)
    }

    func arrow(from a: Vector2, to b: Vector2) {
        stroke(ink)
        strokeWeight(3)
        drawLine(a, b)
        chevron(at: b, pointing: (b - a).normalized)
    }

    func dashedArrow(from a: Vector2, to b: Vector2) {
        stroke(ink)
        strokeWeight(3)
        let step = (b - a).normalized * 14
        var p = a
        while (p - a).length + 14 < (b - a).length {
            drawLine(p, p + step * 0.6)
            p = p + step
        }
        chevron(at: b, pointing: (b - a).normalized)
    }

    func chevron(at tip: Vector2, pointing dir: Vector2) {
        let side = Vector2(-dir.y, dir.x)
        drawLine(tip, tip - dir * 16 + side * 8)
        drawLine(tip, tip - dir * 16 - side * 8)
    }
}
