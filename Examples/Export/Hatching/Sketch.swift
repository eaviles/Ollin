import Ollin

/// Hatching: a filled shape rendered as pen line work. A pen plotter has no fill,
/// so a solid region has to be shaded with parallel (or cross-hatch) lines clipped
/// to its outline — the spacing carrying its tone. This sketch shows the transform
/// both ways at once: the **left** column is solid fills (what you draw); the
/// **right** is the same shapes shaded with `Hatching.lines(filling:)` (what a
/// plotter draws). Darker fills hatch denser.
///
/// The SVG exporter does the left → right step for you with `--hatch`, so the
/// solid fills plot straight to a pen:
///
/// ```sh
/// swift run Example-Export-Hatching --export-svg /tmp/hatched.svg --hatch
/// swift run Example-Export-Hatching --export-svg /tmp/hatched.svg --cross-hatch --hatch-angle 30
/// ```
///
/// The whole arrangement turns slowly, because in Ollin motion is the default.
@main
final class Hatching_Example: Sketch {
    private let ink = Color(red: 0.1, green: 0.12, blue: 0.42)
    private let labelFont = OutlineFont.system

    /// Each row: a shape (as a fillable outline) and the tone it's shaded in.
    private var rows: [(shape: Shape, tone: Double)] {
        let r = min(width, height) * 0.13
        return [
            (Shape(circlePoints(radius: r)), 0.85),               // dark  → dense
            (Shape(starPoints(outer: r, inner: r * 0.45, points: 5)), 0.55),
            (Shape(heartPoints(size: r * 1.7)), 0.3),             // light → sparse
        ]
    }

    override func draw() {
        background(Color(white: 0.97))
        let leftX = width * 0.3, rightX = width * 0.7
        let spin = time * 0.2

        for (i, row) in rows.enumerated() {
            let y = (Double(i) + 0.5) * height / 3

            withState {                                  // left: the solid fill
                translate(leftX, y); rotate(spin)
                noStroke(); fill(Color(white: 1 - row.tone))
                drawShape(row.shape)
            }
            withState {                                  // right: shaded as line work
                translate(rightX, y); rotate(spin)
                let hatching = Hatching(spacing: (4 * scale) / row.tone, angle: -.pi / 4)
                stroke(ink); strokeWeight(1.4 * scale)
                for line in hatching.lines(filling: row.shape) { drawPolyline(line) }
                noFill(); stroke(.black); strokeWeight(2 * scale)
                drawShape(row.shape)
            }
        }

        caption("fill", at: Vector2(leftX, height - 40 * scale))
        caption("plotter", at: Vector2(rightX, height - 40 * scale))
    }

    /// A small label in the system font, drawn unstroked in screen space.
    private func caption(_ text: String, at p: Vector2) {
        noStroke(); fill(Color(white: 0.45))
        textFont(labelFont); textSize(22 * scale); textAlign(.center, .middle)
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

    /// A heart traced from the classic implicit curve, scaled to `size` tall.
    private func heartPoints(size: Double) -> [Vector2] {
        (0..<96).map { k in
            let t = 2 * Double.pi * Double(k) / 96
            let x = 16 * pow(sin(t), 3)
            let y = 13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t)
            return Vector2(x, -y) * (size / 34)
        }
    }
}
