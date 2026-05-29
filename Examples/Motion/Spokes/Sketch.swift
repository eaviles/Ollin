import Ollin

/// A sunburst of fat, round-capped lines — the showcase for the capsule SDF
/// behind `drawLine`. Spokes radiate from the center over a gap, so both ends
/// are visible; each spoke's length and weight pulse with `time` and its angle,
/// and the round caps round off both tips for free. Every spoke is a single
/// capsule instance, crisp at any weight.
@main
final class Spokes: Sketch {
    let palette = Palette.neon
    let count = 64

    override func draw() {
        background(.black)
        let c = Vector2(width / 2, height / 2)
        let maxLen = min(width, height) * 0.42
        let inner = maxLen * 0.18
        for i in 0..<count {
            let a = Double(i) / Double(count) * .tau + time * 0.1
            let pulse = 0.5 + 0.5 * sin(time * 1.5 + Double(i) * 0.3)
            let dir = Vector2(cos(a), sin(a))
            let outer = inner + maxLen * map(pulse, 0, 1, 0.25, 1)

            strokeWeight(map(pulse, 0, 1, 6, 26))
            stroke(palette.color(at: Double(i) / Double(count) + time * 0.05))
            drawLine(c + dir * inner, c + dir * outer)
        }
    }
}
