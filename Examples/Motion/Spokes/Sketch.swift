import Ollin

/// A sunburst of fat, round-capped lines — the showcase for the capsule SDF
/// behind `drawLine`. Spokes radiate from the center over a gap, so both ends
/// are visible; each spoke's length and weight pulse with `time` and its angle,
/// and the round caps round off both tips for free. Every spoke is a single
/// capsule instance, crisp at any weight.
@main
final class Spokes: Sketch {
    let palette = CosinePalette.neon
    let count = 64

    override func draw() {
        background(.black)
        let c = center
        let maxLen = shortSide * 0.42
        let inner = maxLen * 0.18
        for (i, t) in fractions(count).enumerated() {
            let a = t * .tau + time * 0.1
            // A 0...1 pulse per spoke, phase-offset around the ring.
            let pulse = wave(1.5, amplitude: 0.5, around: 0.5, phase: Double(i) * 0.3)
            let outer = inner + maxLen * map(pulse, 0, 1, 0.25, 1)

            strokeWeight(map(pulse, 0, 1, 6, 26))
            stroke(palette.color(at: t + time * 0.05))
            drawLine(polar(a, inner, around: c), polar(a, outer, around: c))
        }
    }
}
