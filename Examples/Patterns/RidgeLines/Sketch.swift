import Ollin

/// Stacked mountain ridgelines from ridged fractal noise. Each row samples
/// `ridgedFbm` along x (the fold that gathers detail on sharp crests instead
/// of rolling hills), lifts a skyline from it, and paints an opaque panel
/// beneath so nearer ranges occlude the ones behind: a whole landscape from
/// one noise call per point, back to front. The rows share a looping field
/// (`loop:`), so the terrain drifts like weather and returns home each lap:
///
/// ```sh
/// swift run Example-Patterns-RidgeLines --export-loop /tmp/ridgelines.gif
/// ```
@main
final class RidgeLines_Example: Sketch {
    private let period = 10.0
    override var loopDuration: Double? { period }

    private let paper = Color(hex: 0xF4EFE6)
    private let ink = Color(hex: 0x2A2E3A)

    override func draw() {
        background(paper)
        let rows = 22
        let phase = loopProgress(over: period)

        for r in 0 ..< rows {
            let depth = Double(r) / Double(rows - 1)          // 0 far ... 1 near
            let baseline = map(depth * depth, 0, 1, height * 0.30, height * 0.96)
            let amplitude = map(depth, 0, 1, height * 0.06, height * 0.20)

            // The skyline: one ridged sample per step, rows staggered through
            // the field's second axis so each range is its own slice.
            var skyline: [Vector2] = []
            var x = 0.0
            while x <= width {
                let n = ridgedFbm(x * 0.0032, Double(r) * 0.83, loop: phase, radius: 0.6)
                skyline.append(Vector2(x, baseline - n * amplitude))
                x += 6
            }
            skyline.append(Vector2(width, skyline.last!.y))

            // An opaque panel under the skyline hides the ranges behind it;
            // nearer ranges ink a touch darker, the aerial-perspective cue.
            var panel = skyline
            panel.append(Vector2(width, height))
            panel.append(Vector2(0, height))
            fill(Color.mix(paper, ink, t: 0.04 + depth * 0.10))
            noStroke()
            drawPolygon(panel)

            stroke(ink)
            strokeWeight(map(depth, 0, 1, 0.8, 2.4) * scale)
            noFill()
            drawPolyline(skyline)
        }
    }
}
