// figure: frame=0
//
// Guide diagram: the color kits on one shelf. A discrete palette, a harmony
// built from one base color, a smooth ramp, and two ready-made ramps.
import Ollin

final class PaletteShelf: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let label = Color(hex: 0x2B2B2B, alpha: 0.55)

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        noStroke()
        textSize(20)
        textAlign(.left, .middle)

        let left = 70.0, right = 810.0
        let barHeight = 46.0

        // A discrete built-in palette, one swatch per color.
        caption("Palette(.set2)", 55)
        let set2 = Palette.set2
        for i in 0..<8 {
            fill(set2[i])
            drawRect(left + Double(i) * 93, 85, 87, barHeight)
        }

        // A harmony built from one base color.
        caption("Palette.triadic(of: coral)", 150)
        let triad = Palette.triadic(of: .coral)
        for i in 0..<3 {
            fill(triad[i])
            drawRect(left + Double(i) * 250, 180, 244, barHeight)
        }

        // A smooth ramp from a color list, sampled continuously.
        caption("Ramp([navy, violet, coral, gold, cream]).color(at: t)", 245)
        let ramp = Ramp([
            Color(hex: 0x14213D), Color(hex: 0x5E60CE),
            Color(hex: 0xE56B6F), Color(hex: 0xFFB703), Color(hex: 0xFFF3E0),
        ])
        sweep(ramp.color(at:), y: 275)

        // Two ready-made continuous ramps.
        caption("Colormap.viridis", 340)
        sweep(Colormap.viridis.color(at:), y: 370)

        caption("CosinePalette.sunset", 435)
        sweep(CosinePalette.sunset.color(at:), y: 465)

        func sweep(_ colorAt: (Double) -> Color, y: Double) {
            let slices = 240
            let sliceWidth = (right - left) / Double(slices)
            for i in 0..<slices {
                fill(colorAt(Double(i) / Double(slices - 1)))
                drawRect(left + Double(i) * sliceWidth, y, sliceWidth + 0.6, barHeight)
            }
        }
    }

    func caption(_ text: String, _ y: Double) {
        fill(label)
        drawText(text, 70, y + 12)
    }
}
