import Foundation
import Ollin

/// A bloom of pointed lenses. An inner ring and an outer ring of points
/// counter-rotate, and `drawOrientedVesica` spans a lens between point `i` of
/// each — so each petal's length and angle shift every frame as both tips drift.
/// That two-tips placement is what the oriented vesica adds over `drawVesica`,
/// which is centered and rotated about itself; here neither tip is fixed.
///
/// The waist width breathes with `time`, so the petals swell and narrow. Each is
/// a single analytic SDF instance, so the whole bloom is effectively free.
@main
final class Petals: Sketch {
    let petals = 14

    override func setup() {
        stroke(Color(white: 0.1))
        strokeWeight(2 * scale)
    }

    override func draw() {
        background(Color(white: 0.06))
        let center = center
        let inner = 90.0 * scale
        let outer = 430.0 * scale

        for i in 0..<petals {
            let t = Double(i) / Double(petals)
            let base = t * .tau
            let a = center + Vector2(angle: base + time * 0.4) * inner
            let b = center + Vector2(angle: base - time * 0.25) * outer

            let waist = (30 + 26 * sin(time * 1.1 + base * 2)) * scale
            fill(Colormap.magma.color(at: 0.2 + 0.7 * t))
            drawOrientedVesica(a, b, width: waist)
        }
    }
}
