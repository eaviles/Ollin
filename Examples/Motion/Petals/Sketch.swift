import Foundation
import Ollin

/// A bloom of pointed lenses over a linkage of bars: the two oriented SDF
/// primitives in one figure. An inner ring and an outer ring of points
/// counter-rotate, and `drawOrientedVesica` spans a lens between matching
/// points of each, so each petal's length and angle shift every frame as both tips
/// drift. Interleaved half a step behind them, `drawOrientedBox` spans a
/// thick bar between two rings of its own, turning at different speeds. That
/// two-endpoints placement is what the oriented forms add over `drawVesica`
/// and `drawRect`, which are centered and rotated about themselves; here
/// neither end is fixed.
///
/// The petal waists and bar thicknesses breathe with `time`. Each shape is a
/// single analytic SDF instance, so the whole figure is effectively free.
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

        // The bars first, so the petals bloom over them. Each spans its own
        // pair of counter-rotating rings, offset half a step from the petals.
        let barInner = 130.0 * scale
        let barOuter = 380.0 * scale
        let halfStep = Double.tau / Double(petals) / 2
        for (t, base) in zip(fractions(petals), angles(petals, from: halfStep)) {
            let a = polar(base + time * 0.9, barInner, around: center)
            let b = polar(base - time * 0.5, barOuter, around: center)

            let thickness = (22 + 14 * sin(time * 1.3 + base)) * scale
            fill(Colormap.turbo.color(at: t))
            drawOrientedBox(a, b, thickness: thickness)
        }

        // The petals, one lens between matching points of the two rings.
        let inner = 90.0 * scale
        let outer = 430.0 * scale
        for (t, base) in zip(fractions(petals), angles(petals)) {
            let a = polar(base + time * 0.4, inner, around: center)
            let b = polar(base - time * 0.25, outer, around: center)

            let waist = (30 + 26 * sin(time * 1.1 + base * 2)) * scale
            fill(Colormap.magma.color(at: 0.2 + 0.7 * t))
            drawOrientedVesica(a, b, width: waist)
        }
    }
}
