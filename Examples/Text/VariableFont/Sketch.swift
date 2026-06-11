import Foundation
import Ollin

/// Variable fonts. An `OutlineFont` exposes a variable font's continuous design
/// axes — weight, width, optical size — and `variation(_:)` sets them live, so a
/// word can morph from thin to heavy and narrow to wide every frame. This is a
/// specimen for **Skia**'s weight (`wght`) and width (`wdth`) axes; the big word
/// animates both, with a static weight ramp beneath. (Axis values are in the
/// font's own units — Skia's `wght` runs 0.48…3.2, `wdth` 0.62…1.3.)
@main
final class VariableFont: Sketch {
    let base = OutlineFont(name: "Skia") ?? .system
    let weights = [0.55, 1.0, 1.8, 3.0]
    var ramp: [OutlineFont] = []
    let palette = CosinePalette.dusk

    override func setup() {
        textAlign(.center, .middle)
        ramp = weights.map { base.weight($0) }   // built once; reused each frame
    }

    override func draw() {
        background(Color(white: 0.07))
        textAlign(.center, .middle)
        noStroke()

        // The headline morphs along both axes.
        let wght = map(sin(time * 0.9), -1, 1, 0.5, 3.1)
        let wdth = map(sin(time * 0.55), -1, 1, 0.65, 1.3)
        textFont(base.variation(["wght": wght, "wdth": wdth]))
        textSize(300 * scale)
        fill(.white)
        drawText("ollin", width / 2, height * 0.42)

        // A static ramp of discrete weights, thin to heavy.
        textSize(96 * scale)
        for (i, font) in ramp.enumerated() {
            textFont(font)
            fill(palette.color(at: Double(i) / Double(ramp.count - 1)))
            drawText("Aa", map(Double(i), 0, Double(ramp.count - 1), width * 0.22, width * 0.78),
                     height * 0.74)
        }
    }
}
