import Ollin

/// **Chromatic aberration, as a family.** One scene shown through each way a lens,
/// a printing press, or a piece of cheap glass pulls the color channels apart: a
/// per-channel scale about the center, a shaped radial slide, one flat shift, a
/// fringe that only appears at edges, and a difference in focus rather than in
/// position. The last two tiles are the two knobs that cut across the modes: the
/// spectral tap budget, which turns three hard ghosts into a continuous smear, and
/// the layer-driven `disperse` combine, which puts the split only where the mouse is.
///
/// Move the mouse over the sheet to steer the driven tile. The strength breathes,
/// so each tile passes through zero, where every mode hands the picture back
/// unchanged.
@main
final class Dispersion_Example: Sketch {
    private let labelFont = OutlineFont.system

    override func draw() {
        background(Color(white: 0.06))

        // One scene with hard edges, fine lines, and flat color, so the modes that
        // read edges have something to find and the modes that shift the whole frame
        // have somewhere flat to show it.
        let scene = renderTarget()
        withTarget(scene) {
            background(Color(hex: 0x0B1020))
            noStroke()
            fill(Color(hex: 0xF2F0E6)); drawCircle(width * 0.34, height * 0.36, width * 0.14)
            fill(Color(hex: 0xE8483C)); drawRect(width * 0.52, height * 0.18, width * 0.3, width * 0.18)
            fill(Color(hex: 0x2FD0C8)); drawTriangle(Vector2(width * 0.2, height * 0.86),
                                                     Vector2(width * 0.44, height * 0.58),
                                                     Vector2(width * 0.66, height * 0.86))
            stroke(Color(hex: 0xF2F0E6)); strokeWeight(2); noFill()
            for i in 0 ..< 9 {
                let y = height * (0.6 + Double(i) * 0.035)
                drawLine(width * 0.68, y, width * 0.94, y)
            }
        }

        // The strength breathes through zero, so the identity at zero is visible
        // rather than claimed.
        let amount = 0.016 * (0.35 + 0.65 * abs(sin(time * 0.35)))

        // The aux layer for the driven tile: white where the split should happen. One
        // disc drifts on its own so the tile reads without a mouse; a second follows
        // the pointer, so you can smear a fringe over whatever you point at.
        let drive = renderTarget()
        withTarget(drive) {
            background(.black)
            noStroke()
            blendMode(.add)
            let drift = Vector2(width * (0.5 + 0.3 * cos(time * 0.4)),
                                height * (0.5 + 0.3 * sin(time * 0.27)))
            for center in [drift, Vector2(mouseX, mouseY)] {
                fill(.radial(center: center, radius: width * 0.28, Ramp([.white, .black])))
                drawCircle(center: center, radius: width * 0.28)
            }
        }

        let tiles: [(String, RenderTarget)] = [
            ("magnify", scene.filtered(.chromaticAberration(amount: amount))),
            ("lens(0.3, 2)", scene.filtered(.chromaticAberration(
                amount: amount * 3, mode: .lens(radius: 0.3, falloff: 2)))),
            ("offset(45°)", scene.filtered(.chromaticAberration(
                amount: amount * 0.6, mode: .offset(angle: .pi / 4)))),
            ("edges", scene.filtered(.chromaticAberration(amount: amount * 2, mode: .edges))),
            ("axial +", scene.filtered(.chromaticAberration(amount: amount, mode: .axial))),
            ("axial −", scene.filtered(.chromaticAberration(amount: -amount, mode: .axial))),
            ("3 taps (default)", scene.filtered(.chromaticAberration(amount: amount * 2.5))),
            ("spectral taps", scene.filtered(.chromaticAberration(
                amount: amount * 2.5, spectral: true))),
            ("driven by a layer", scene.combined(with: drive, .disperse(amount: amount * 2.5))),
        ]

        let gutter = width * 0.012
        let cell = (width - gutter * 4) / 3
        for (i, tile) in tiles.enumerated() {
            let x = gutter + Double(i % 3) * (cell + gutter)
            let y = gutter + Double(i / 3) * (cell + gutter)
            drawImage(tile.1.image, in: Rectangle(x: x, y: y, width: cell, height: cell))
            withState {
                fill(Color(white: 0, alpha: 0.55)); noStroke()
                drawRect(x, y + cell - 26, cell, 26)
                fill(.white)
                textFont(labelFont); textSize(14); textAlign(.left, .middle)
                drawText(tile.0, x + 8, y + cell - 13)
            }
        }
    }
}
