import Ollin

/// A ringed planet drawn with one unbroken line.
///
/// `singleLine(of:points:)` stipples an image (dots packed by darkness) and
/// then tours the dots into a single continuous path, the traveling-salesman
/// rendering: shadow pulls the line into tight meanders, light lets it
/// stride, and the one line reads as the picture. `cutoff` rounds the bright
/// paper up to empty, so the sky stays genuinely blank instead of collecting
/// a thin wandering thread.
///
/// The tour is computed once in `setup()` and the drawing plays out as a
/// reveal: the line draws itself forward, holds, and unwinds. Because the
/// output is a plain `Contour`, the same sketch exports clean vector line
/// work: try `--export-svg out.svg --frame 900` (the reveal's full-line
/// moment), the friendliest thing a pen plotter can be handed.
@main
final class SingleLine: Sketch {
    override var loopDuration: Double? { 30 }

    private var line: Contour = Contour([], closed: false)

    override func setup() {
        seed(4)
        let frame = canvasRectangle.inset(by: 96)
        line = singleLine(of: paint(), points: 3600, in: frame,
                          iterations: 45, cutoff: 0.9)
    }

    override func draw() {
        background(Color(hex: 0xF5F2EA))
        guard line.points.count > 2 else { return }

        // Draw in, hold, unwind: an eased out-and-back sweep over the loop.
        let sweep = Easing.smoothstep(pingPong(over: 30))
        let visible = max(2, Int(Double(line.points.count) * sweep))

        noFill()
        stroke(Color(hex: 0x1A1B26))
        strokeWeight(1.7 * scale)
        strokeJoin(.round)
        drawPolyline(Array(line.points.prefix(visible)),
                     closed: visible == line.points.count)

        drawCaption("3,600 stipples, one continuous line")
    }

    /// The picture the line reproduces: a shaded planet with a tilted ring
    /// and a small moon, painted on white so the cutoff leaves the sky empty.
    private func paint() -> Image {
        let n = 340
        let image = Image(width: n, height: n, color: .white)
        let light = Vector3(-0.6, -0.5, 0.62).normalized
        for y in 0 ..< n {
            for x in 0 ..< n {
                let u = (Double(x) + 0.5) / Double(n) * 2 - 1
                let v = (Double(y) + 0.5) / Double(n) * 2 - 1
                var tone = 1.0

                // The planet: a lit sphere, slightly above center.
                let radius = 0.46
                let pu = u, pv = v + 0.08
                let d2 = pu * pu + pv * pv
                if d2 < radius * radius {
                    let normal = Vector3(pu / radius, pv / radius,
                                         (1 - d2 / (radius * radius)).squareRoot())
                    let diffuse = max(normal.dot(light), 0)
                    tone = clamp(0.12 + diffuse * 0.85, 0, 1)
                }

                // The ring: a tilted ellipse band, in front of the planet on
                // the lower half only.
                let ru = (u * 0.94 + v * 0.34) / 0.88
                let rv = (v * 0.94 - u * 0.34) / 0.30
                let ringDistance = (ru * ru + rv * rv).squareRoot()
                if ringDistance > 0.78, ringDistance < 1.06,
                   d2 >= radius * radius || v > -u * 0.2 {
                    tone = min(tone, 0.42 + (1.06 - ringDistance) * 1.6)
                }

                // A small moon, upper right.
                let md = dist(u, v, 0.66, -0.62)
                if md < 0.09 { tone = min(tone, 0.25 + md * 6) }

                image[x, y] = Color(white: tone)
            }
        }
        return image
    }
}
