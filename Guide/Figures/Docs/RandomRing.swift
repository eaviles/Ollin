// figure: frame=0
//
// Docs diagram (Generators/Random.md): what ring(innerRadius:outerRadius:)
// hands back. Left, the geometry: a band between two circles around the
// origin, the hole inside the inner radius empty. Right, seeded samples
// landing uniformly over that band and nowhere else.
import Ollin

final class RandomRing: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x2B2B2B)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.12)
    let accent = Color(hex: 0xD96C2C)

    override func draw() {
        seed(7)
        background(paper)

        let leftCenter = Vector2(240, 230)
        let rightCenter = Vector2(640, 230)
        let inner = 62.0
        let outer = 138.0

        // Left: the geometry. The band is washed, the hole stays paper.
        noStroke()
        fill(Color(hex: 0xD96C2C, alpha: 0.14))
        drawRing(center: leftCenter, innerRadius: inner, outerRadius: outer)
        noFill()
        stroke(ink)
        strokeWeight(2)
        drawCircle(center: leftCenter, radius: inner)
        drawCircle(center: leftCenter, radius: outer)

        // The two radii, drawn on separate rays so the labels stay clear.
        stroke(accent)
        strokeWeight(2.5)
        let innerEnd = leftCenter + Vector2(inner, 0).rotated(by: -0.6)
        let outerEnd = leftCenter + Vector2(outer, 0).rotated(by: 0.5)
        drawLine(leftCenter, innerEnd)
        drawLine(leftCenter, outerEnd)

        noStroke()
        fill(ink)
        drawCircle(center: leftCenter, radius: 4)
        textFont(OutlineFont.system)
        textSize(17)
        textAlign(.left, .middle)
        drawText("inner", innerEnd.x + 8, innerEnd.y - 4)
        drawText("outer", outerEnd.x + 8, outerEnd.y + 4)
        textAlign(.center, .middle)
        drawText("no points", leftCenter.x, leftCenter.y - 24)

        // Right: the same band receiving uniform samples.
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawCircle(center: rightCenter, radius: inner)
        drawCircle(center: rightCenter, radius: outer)
        noStroke()
        fill(accent)
        for _ in 0 ..< 1500 {
            let p = rightCenter + ring(innerRadius: inner, outerRadius: outer)
            drawCircle(center: p, radius: 2.2)
        }

        noStroke()
        fill(ink)
        textSize(17)
        textAlign(.center, .top)
        drawText("the band between two radii", leftCenter.x, 390)
        drawText("1,500 samples, uniform over the band", rightCenter.x, 390)
        textSize(21)
        drawText("center + ring(innerRadius:outerRadius:) places it anywhere",
                 width / 2, 432)
    }
}
