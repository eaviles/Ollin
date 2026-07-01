import Ollin

/// Streamlines through a flow field: a noise field gives a direction at every
/// point, and each line follows that flow. They're traced *evenly spaced* (a
/// line stops when it nears one already drawn), so they fan out into smooth,
/// non-crossing curves, the flow-field look.
///
/// The blue-noise seed set and the field are a pure function of the seed, so the
/// lines are computed once and held; what moves is a hue that drifts along the
/// field over time. Each streamline is an ordinary point list, so the same
/// line-work feeds stroking, the shape booleans, hatching, and SVG export for the
/// pen plotter.
@main
final class Streamlines: Sketch {
    private var lines: [[Vector2]] = []

    override func draw() {
        if lines.isEmpty {
            seed(7)
            let field = flowField(scale: 0.0016)
            let seeds = poissonDisk(radius: 10 * scale)
            lines = field.streamlines(from: seeds, stepLength: 4 * scale, steps: 260,
                                      bounds: bounds, separation: 14 * scale)
        }

        background(Color(hex: 0x0F1117))
        strokeCap(.round)
        strokeJoin(.round)
        noFill()

        for line in lines {
            let mid = line[line.count / 2]
            // A per-line value from the field's own noise sets the width and hue,
            // so neighboring lines vary together; time drifts the hue along it.
            let v = (signedNoise(mid.x * 0.0011, mid.y * 0.0011) + 1) * 0.5
            strokeWeight((2 + v * 5.5) * scale)
            let hue = (0.52 + v * 0.34 + time * 0.02).truncatingRemainder(dividingBy: 1)
            stroke(Color(hue: hue, saturation: 0.5, brightness: 0.96))
            drawPolyline(line)
        }
    }
}
