// figure: frame=0
//
// Docs catalog figure (Drawing/Drawing.md, drawPolyline): the same run of
// points stroked open, and joined back to its start with closed: true. The
// vertices are dotted, and the open path's two ends are marked.
import Ollin

final class DrawPolyline: Sketch {
    override var canvasSize: CanvasSize { .size(880, 320) }

    let paper = Color(hex: 0xF7F5F1)
    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.35)
    let accent = Color(hex: 0xE4572E)

    let run = [Vector2(-118, 62), Vector2(-70, -58), Vector2(-14, 12),
               Vector2(38, -66), Vector2(96, -24), Vector2(118, 46),
               Vector2(20, 74)]

    override func draw() {
        background(paper)
        textFont(OutlineFont.system)

        let cy = 140.0
        panel(cx: 300, cy: cy, closed: false)
        panel(cx: 580, cy: cy, closed: true)

        // The open path's ends, where strokeCap applies.
        noStroke()
        fill(accent)
        if let first = run.first, let last = run.last {
            drawCircle(300 + first.x, cy + first.y, 5)
            drawCircle(300 + last.x, cy + last.y, 5)
        }

        fill(ink)
        textSize(18)
        textAlign(.center, .top)
        drawText("open, the default", 300, 262)
        drawText("closed: true", 580, 262)
    }

    func panel(cx: Double, cy: Double, closed: Bool) {
        let points = run.map { Vector2(cx + $0.x, cy + $0.y) }
        noFill()
        stroke(ink)
        strokeWeight(4)
        drawPolyline(points, closed: closed)
        noStroke()
        fill(faint)
        for p in points { drawCircle(center: p, radius: 3) }
    }
}
