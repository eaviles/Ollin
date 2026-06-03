import Ollin

/// `strokeJoin(_:)` styles a stroked path's corners; `strokeCap(_:)` styles its
/// open ends. The top three rows turn the same sharp zigzag with each join —
/// `.miter` (a crisp point), `.bevel` (cut flat), `.round` (arced). The bottom
/// three end a straight segment with each cap — `.butt` (flat at the endpoint),
/// `.round` (a half-disk tip), `.square` (a flat extension half the weight past
/// the end). A thin white centerline and dots mark the true path under each thick
/// stroke, so you can watch the round and square caps reach past their endpoints
/// while butt stops on them, and the join reshape the peaks. The weight pulses
/// with `time`.
@main
final class StrokeJoinsAndCaps: Sketch {
    let joins: [StrokeJoin] = [.miter, .bevel, .round]
    let caps: [StrokeCap] = [.butt, .round, .square]

    override func draw() {
        background(Color(white: 0.1))

        let pulse = 0.5 - 0.5 * cos(time * 1.6)
        let weight = (10 + 34 * pulse) * scale
        let rows = joins.count + caps.count
        let rowGap = height / Double(rows + 1)
        let margin = width * 0.16

        // Joins — a sharp zigzag, so the corner style shapes each peak.
        for (i, join) in joins.enumerated() {
            let cy = rowGap * Double(i + 1)
            let amp = rowGap * 0.34
            let pts = [
                Vector2(margin, cy + amp),
                Vector2(width * 0.36, cy - amp),
                Vector2(width * 0.5, cy + amp),
                Vector2(width * 0.64, cy - amp),
                Vector2(width - margin, cy + amp),
            ]
            stroke(rowColor(i, of: rows)); strokeWeight(weight); strokeJoin(join)
            drawPolyline(pts)
            drawReference(pts)
        }

        // Caps — a straight segment, so the end style is what changes.
        for (j, cap) in caps.enumerated() {
            let i = joins.count + j
            let cy = rowGap * Double(i + 1)
            let pts = [Vector2(width * 0.32, cy), Vector2(width * 0.68, cy)]
            stroke(rowColor(i, of: rows)); strokeWeight(weight); strokeCap(cap)
            drawPolyline(pts)
            drawReference(pts)
        }
    }

    func rowColor(_ i: Int, of rows: Int) -> Color {
        Colormap.turbo.color(at: Double(i) / Double(rows - 1))
    }

    /// A thin white centerline plus vertex dots, marking the true path under the
    /// thick stroke so the cap extension and join shape read clearly. Scoped so it
    /// doesn't leak its style into the next row.
    func drawReference(_ pts: [Vector2]) {
        withState {
            stroke(.white); strokeWeight(1.5 * scale); strokeJoin(.miter); strokeCap(.butt)
            drawPolyline(pts)
            fill(.white)
            for p in pts { drawCircle(p.x, p.y, 3 * scale) }
        }
    }
}
