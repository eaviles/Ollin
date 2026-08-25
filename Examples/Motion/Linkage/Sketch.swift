import Foundation
import Ollin

/// Bars connecting two rings of orbiting points. An inner ring and an outer ring
/// rotate at different speeds, and `drawOrientedBox` draws a thick bar between
/// point `i` of each — so every bar's length *and* angle change every frame as
/// its two endpoints drift independently. That two-endpoints framing is what the
/// oriented box adds over `drawRect`, which is axis-aligned and rotated about its
/// own center; here neither end is fixed.
///
/// The bars take a `fill` from the turbo colormap and a thin dark outline; their
/// thickness breathes with `time`. Each is a single analytic SDF instance, so the
/// whole linkage is effectively free.
@main
final class Linkage: Sketch {
    let bars = 9

    override func setup() {
        stroke(Color(white: 0.08))
        strokeWeight(2 * scale)
    }

    override func draw() {
        background(Color(white: 0.97))
        let center = center
        let inner = 130.0 * scale
        let outer = 380.0 * scale

        for i in 0..<bars {
            let t = Double(i) / Double(bars)
            let base = t * .tau
            let a = center + Vector2(angle: base + time * 0.9) * inner
            let b = center + Vector2(angle: base - time * 0.5) * outer

            let thickness = (22 + 14 * sin(time * 1.3 + base)) * scale
            fill(Colormap.turbo.color(at: t))
            drawOrientedBox(a, b, thickness: thickness)
        }
    }
}
