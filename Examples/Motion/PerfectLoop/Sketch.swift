import Ollin

/// A sketch that repeats exactly, and says so. `loopDuration` declares the
/// period (6 seconds here); every moving part is driven by `loopProgress` and
/// looping `signedNoise`, so the frame one period later is identical to frame
/// zero. That declaration is what powers the perfect-loop export:
///
///     swift run Example-Motion-PerfectLoop --export-loop loop.gif
///
/// renders exactly one lap, and the GIF (or .mp4/.mov) cycles seamlessly.
/// Three nested blobs sample loop noise on a circle, closed in angle by the
/// circular sample path and closed in time by the loop phase; a comet rides
/// the outer edge, one full turn per period, to make the lap visible.
@main
final class PerfectLoop: Sketch {
    let period = 6.0
    override var loopDuration: Double? { period }

    override func setup() {
        seed(11)   // pin the noise field, so every run loops the same lap
    }

    override func draw() {
        background(Color(hex: 0x0E1420))
        let phase = loopProgress(over: period)
        let center = center

        // Nested blobs, each wobbling on its own slice of the looping field.
        let layers: [(scale: Double, color: Color)] = [
            (1.00, Color(hex: 0x27446B)),
            (0.68, Color(hex: 0x4E8098)),
            (0.40, Color(hex: 0xA8D0B0)),
        ]
        noStroke()
        for (l, layer) in layers.enumerated() {
            var points: [Vector2] = []
            for i in 0 ..< 220 {
                let a = Double(i) / 220 * .tau
                points.append(center + Vector2(angle: a, length: edgeRadius(a, layer: l)) * layer.scale)
            }
            fill(layer.color)
            drawPolygon(points)
        }

        // The lap made visible: a comet takes one full turn per period.
        let head = phase * .tau
        for k in stride(from: 24, through: 0, by: -1) {
            let a = head - Double(k) * 0.045
            let p = center + Vector2(angle: a, length: edgeRadius(a, layer: 0))
            let fade = 1 - Double(k) / 25
            fill(Color(hex: 0xFFD98A, alpha: 0.12 + 0.88 * fade * fade))
            drawCircle(center: p, radius: 4 + 12 * fade)
        }
    }

    /// The outer edge of a blob layer at angle `a`: a base radius plus loop
    /// noise sampled on a circle, so the wobble closes in angle and in time.
    func edgeRadius(_ a: Double, layer l: Int) -> Double {
        let wobble = signedNoise(cos(a) * 0.8 + Double(l) * 3.7, sin(a) * 0.8,
                                 loop: loopProgress(over: period) + Double(l) * 0.33,
                                 radius: 1.4)
        return 356 + wobble * 72
    }
}
