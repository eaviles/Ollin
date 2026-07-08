// figure: frame=0
//
// Guide diagram (Appendix B): offsetting a region. A peanut made from two
// fused circles, grown outward twice and shrunk inward three times; the
// deepest inset splits the waist into two islands.
import Ollin

final class Offsets: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.28)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        textSize(19)

        let center = Vector2(400, 265)
        let peanut = lobe(at: center + Vector2(-62, 0)).union(lobe(at: center + Vector2(62, 0)))

        noFill()
        for delta in [26.0, 52.0] {
            stroke(faint)
            strokeWeight(2)
            outline(peanut.offset(by: delta, join: .round))
        }
        for delta in [-30.0, -60.0, -85.0] {
            stroke(accent)
            strokeWeight(2.5)
            outline(peanut.offset(by: delta, join: .round))
        }
        stroke(ink)
        strokeWeight(3.5)
        outline(peanut)

        // A ruler through the right lobe's center, ticking each ring.
        let rulerX = center.x + 62
        stroke(faint)
        strokeWeight(1.5)
        drawLine(rulerX, center.y - 175, rulerX, center.y)
        noStroke()
        textAlign(.left, .middle)
        for (delta, label) in [(52.0, "+52"), (26.0, "+26"), (0.0, "0"),
                               (-30.0, "-30"), (-60.0, "-60"), (-85.0, "-85")] {
            let y = center.y - (100 + delta)
            fill(delta == 0 ? ink : (delta > 0 ? faint : accent))
            drawCircle(rulerX, y, 4)
            drawText(label, rulerX + 14, y)
        }

        fill(ink)
        textAlign(.center, .top)
        drawText("offset(by:) grows or shrinks the region evenly; shrink past the waist and it splits in two",
                 width / 2, 500)
    }

    func lobe(at center: Vector2) -> Shape {
        Shape((0 ..< 64).map { k in
            center + Vector2(angle: Double(k) / 64 * .tau, length: 100)
        })
    }

    func outline(_ shape: Shape) {
        for contour in shape.contours { drawPolygon(contour.points) }
    }
}
