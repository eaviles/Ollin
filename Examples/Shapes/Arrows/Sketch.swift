import Ollin

/// One call draws the whole mark: `drawArrow(from:to:)` puts a stroked shaft
/// and a solid triangular head on the canvas, the tip landing exactly on `to`,
/// and a single `stroke(...)` colors both. The field of small arrows leans
/// toward the cursor with its heads at their defaults, which scale with
/// `strokeWeight`; the turning ring sweeps `headLength:` and `headWidth:`
/// from slim dart to broad barb.
///
/// The ring is translucent on purpose: the shaft stops at the head's base, so
/// each arrow lays one even coat of ink with no darker band where shaft meets
/// head, and the ink deepens only where two arrows actually cross.
@main
final class Arrows: Sketch {
    override func draw() {
        background(Color(hex: 0x0E1116))
        let s = shortSide

        // A field of arrows aimed at the cursor: direction and brightness both
        // read from the pointer, so the whole sheet turns as the mouse moves.
        let reach = s * 0.5
        let g = grid(columns: 11, rows: 11, padding: .all(s * 0.06), distribution: .spanning)
        strokeWeight(2.5 * scale)
        for dot in g.points {
            let p = dot.position
            let toward = (mouse - p).normalized
            let closeness = map(dist(p.x, p.y, mouseX, mouseY), 0, reach, 1, 0, clamp: true)
            let half = (14 + 10 * closeness) * scale
            stroke(Color(white: 0.3 + 0.55 * closeness))
            drawArrow(from: p - toward * half, to: p + toward * half)
        }

        // A ring of thick translucent arrows radiating from one hub, the head
        // geometry sweeping around it. The shafts pile up near the hub and the
        // ink deepens there; along each arrow the coat stays even, head
        // included, because the shaft ends where the head begins.
        let count = 10
        strokeWeight(7 * scale)
        stroke(Color(hex: 0xFFB703, alpha: 0.45))
        for (i, angle) in angles(count).enumerated() {
            let t = Double(i) / Double(count - 1)
            let turn = angle + time * 0.12
            drawArrow(from: center, to: center + Vector2(angle: turn, length: s * 0.26),
                      headLength: lerp(18, 64, t) * scale,
                      headWidth: lerp(12, 58, t) * scale)
        }

        drawCaption("the ring sweeps headLength and headWidth · translucent ink deepens only where arrows cross: each arrow is one even coat")
    }
}
