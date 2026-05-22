import Foundation
import Ollin

/// One circle per row, with color, horizontal position, and size all driven by
/// `sin` — of the row index (a static vertical color gradient) and of
/// `time + index` (the flowing left↔right motion and pulsing size). Ported
/// from a p5.js sketch.
///
/// Two p5→Ollin conversions, still no new features required:
///
/// - p5's `fill(r, g, b)` takes `0...255` components; Ollin's `Color` is
///   `0...1`. So p5's `127 + 127 * sin(…)` becomes `0.5 + 0.5 * sin(…)` — the
///   same "midpoint plus half-amplitude," just normalized.
/// - p5 sizes circles by diameter; Ollin uses radius, hence `diameter / 2`.
///
/// `setup()` sets `noStroke()` once; the loop count and offsets read live
/// `width`/`height`, so it stays full-bleed on resize.
@main
final class ColorWaves: Sketch {
    override func setup() {
        noStroke()
    }

    override func draw() {
        background(.black)
        for row in 0..<Int(height) {
            let i = Double(row)
            fill(Color(red:   0.5 + 0.5 * sin(i * 0.010),
                       green: 0.5 + 0.5 * sin(i * 0.011),
                       blue:  0.5 + 0.5 * sin(i * 0.012)))
            let x = width / 2 + width / 4 * sin(time + i * 0.02)
            let diameter = 50 + 50 * sin(time + i * 0.01)
            circle(x: x, y: i, radius: diameter / 2)
        }
    }
}
