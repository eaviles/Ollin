// figure: frame=0
//
// Docs diagram (Drawing/Drawing.md): the three stroke placement controls in
// one sheet. Top row, strokeAlign: the same heavy outline straddling the
// shape edge, held inside it, and pushed outside it, the true edge marked.
// Middle row, strokeJoin: the same bend turned with a miter, a bevel, and a
// round. Bottom row, strokeCap: the same segment ended flat, rounded, and
// squared, with the true endpoints marked so the overshoot shows.
import Ollin

final class StrokeAnatomy: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.28)
    let wash = Color(hex: 0x2B2B2B, alpha: 0.10)
    let accent = Color(hex: 0xE4572E)

    let columns = [230.0, 480.0, 730.0]

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        rowTitle("strokeAlign: where the weight sits on the shape edge", 40)
        let alignY = 118.0
        let aligns: [(StrokeAlign, String)] = [(.center, ".center"), (.inside, ".inside"), (.outside, ".outside")]
        for (i, (align, name)) in aligns.enumerated() {
            let x = columns[i]
            fill(wash)
            stroke(ink)
            strokeWeight(16)
            strokeAlign(align)
            drawCircle(x, alignY, 44)
            strokeAlign(.center)
            // The true outline, so the three placements read against one edge.
            noFill()
            stroke(accent)
            strokeWeight(2)
            drawCircle(x, alignY, 44)
            label(name, x, alignY + 74)
        }

        rowTitle("strokeJoin: how a path turns its corner", 218)
        let joinY = 322.0
        let joins: [(StrokeJoin, String)] = [(.miter, ".miter"), (.bevel, ".bevel"), (.round, ".round")]
        for (i, (join, name)) in joins.enumerated() {
            let x = columns[i]
            noFill()
            stroke(ink)
            strokeWeight(22)
            strokeJoin(join)
            drawPolyline([Vector2(x - 66, joinY), Vector2(x, joinY - 62), Vector2(x + 66, joinY)])
            strokeJoin(.miter)
            label(name, x, joinY + 30)
        }

        rowTitle("strokeCap: how an open end finishes", 402)
        let capY = 484.0
        let caps: [(StrokeCap, String)] = [(.butt, ".butt"), (.round, ".round"), (.square, ".square")]
        for (i, (cap, name)) in caps.enumerated() {
            let x = columns[i]
            stroke(ink)
            strokeWeight(22)
            strokeCap(cap)
            drawLine(x - 60, capY, x + 60, capY)
            strokeCap(.butt)
            // The true endpoints, so the half-weight overshoot shows.
            stroke(accent)
            strokeWeight(2)
            drawLine(x - 60, capY - 22, x - 60, capY + 22)
            drawLine(x + 60, capY - 22, x + 60, capY + 22)
            label(name, x, capY + 40)
        }
    }

    func rowTitle(_ text: String, _ y: Double) {
        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.left, .top)
        drawText(text, 84, y)
    }

    func label(_ text: String, _ x: Double, _ y: Double) {
        noStroke()
        fill(ink)
        textSize(19)
        textAlign(.center, .top)
        drawText(text, x, y)
    }
}
