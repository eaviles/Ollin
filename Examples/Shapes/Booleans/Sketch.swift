import Ollin

/// Boolean set operations on `Shape`: the same two moving shapes — a slowly
/// turning star and an orbiting disc — combined four ways. The thin gray
/// outlines are the two sources; the filled region is what the operation
/// returns. Each result is real geometry (an ordinary `Shape`), so it strokes,
/// hatches, offsets, and exports like anything drawn by hand:
///
/// ```swift
/// let cut = star.subtracting(disc)   // a star with a bite taken out
/// drawShape(cut)
/// ```
@main
final class Booleans_Example: Sketch {
    private let labelFont = OutlineFont.system

    override func draw() {
        background(Color(white: 0.97))

        let ops: [(name: String, combine: (Shape, Shape) -> Shape, tint: Color)] = [
            ("union", { $0.union($1) }, Color(red: 0.18, green: 0.44, blue: 0.84, alpha: 0.85)),
            ("intersection", { $0.intersection($1) }, Color(red: 0.86, green: 0.39, blue: 0.16, alpha: 0.85)),
            ("subtracting", { $0.subtracting($1) }, Color(red: 0.17, green: 0.6, blue: 0.4, alpha: 0.85)),
            ("symmetricDifference", { $0.symmetricDifference($1) }, Color(red: 0.55, green: 0.3, blue: 0.75, alpha: 0.85)),
        ]

        let r = min(width, height) * 0.15
        for (i, op) in ops.enumerated() {
            let cell = Vector2((Double(i % 2) + 0.5) * width / 2,
                               (Double(i / 2) + 0.5) * height / 2 - 40 * scale)

            // The sources are *baked* into canvas coordinates (mapPoints, not
            // the transform stack): a boolean combines geometry, so both
            // shapes have to live in the same space when they meet.
            let spin = time * 0.25
            let star = Shape(starPoints(outer: r, inner: r * 0.48, points: 7))
                .mapPoints { $0.rotated(by: spin) + cell }
            let orbit = cell + Vector2(cos(time * 0.7), sin(time * 0.7)) * r * 0.85
            let disc = Shape(circlePoints(radius: r * 0.62)).mapPoints { $0 + orbit }

            let result = op.combine(star, disc)

            noStroke(); fill(op.tint)
            drawShape(result)

            noFill(); stroke(Color(white: 0.72)); strokeWeight(1.2 * scale)
            drawShape(star); drawShape(disc)

            noFill(); stroke(Color(white: 0.1)); strokeWeight(2.2 * scale)
            drawShape(result)

            // Anchored to the cell's bottom edge, not a radius multiple — the
            // bottom row's captions must land inside the canvas.
            caption(op.name, at: Vector2(cell.x, (Double(i / 2) + 1) * height / 2 - 30 * scale))
        }
    }

    /// A small label in the system font, drawn unstroked in screen space.
    private func caption(_ text: String, at p: Vector2) {
        noStroke(); fill(Color(white: 0.45))
        textFont(labelFont); textSize(24 * scale); textAlign(.center, .middle)
        drawText(text, at: p)
    }

    // MARK: - Shape outlines (centered on the origin)

    private func circlePoints(radius: Double) -> [Vector2] {
        let n = max(48, Int(radius.rounded(.up)))
        return (0..<n).map { k in
            let a = 2 * Double.pi * Double(k) / Double(n)
            return Vector2(cos(a), sin(a)) * radius
        }
    }

    private func starPoints(outer: Double, inner: Double, points: Int) -> [Vector2] {
        (0..<(2 * points)).map { j in
            let r = j % 2 == 0 ? outer : inner
            let a = Double.pi * Double(j) / Double(points)
            return Vector2(r * sin(a), -r * cos(a))
        }
    }
}
