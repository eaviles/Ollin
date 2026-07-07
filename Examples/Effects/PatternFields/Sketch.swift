import Ollin

/// The **pattern fields**: closed-form animated fields, each a few lines of
/// per-pixel math with a strong signature look. Quasicrystal wave sums, moiré
/// ring interference, a gyroid slice, the Vogel phyllotaxis spiral, and
/// per-cell pulses on a hexagonal lattice; the sixth tile chains a field into
/// a filter (the gyroid relit as liquid).
///
/// See the sibling sets: `Effects/Patterns` (the basics) and
/// `Effects/DesignPatterns` (the designer catalog).
@main
final class PatternFields_Example: Sketch {
    private let labelFont = OutlineFont.system

    override func draw() {
        background(Color(white: 0.06))

        let cols = 3
        let gutter = width * 0.012
        let cellW = (width - gutter * Double(cols + 1)) / Double(cols)
        let cellH = (height - gutter * 3) / 2

        // Generate each field at its tile's own size, so cells stay square.
        let w = Int(cellW), h = Int(cellH)
        let tiles: [(String, RenderTarget)] = [
            ("quasicrystal", generate(.quasicrystal(phase: time * 0.6), width: w, height: h)),
            ("moire", generate(.moire(phase: time), width: w, height: h)),
            ("gyroid", generate(.gyroid(phase: time * 0.5), width: w, height: h)),
            ("phyllotaxis", generate(.phyllotaxis(phase: time * 0.05), width: w, height: h)),
            ("hexPulse", generate(.hexPulse(phase: time * 2), width: w, height: h)),
            ("gyroid + relight", generate(.gyroid(foreground: .white, background: .black,
                                                  thickness: 0.5, phase: time * 0.5),
                                          width: w, height: h)
                .filtered(.gaussianBlur(radius: 6))
                .filtered(.relight(.liquid, height: 3, color: Color(hex: 0x2B6C8C)))),
        ]
        for (i, tile) in tiles.enumerated() {
            let x = gutter + Double(i % cols) * (cellW + gutter)
            let y = gutter + Double(i / cols) * (cellH + gutter)
            drawImage(tile.1.image, in: Rectangle(x: x, y: y, width: cellW, height: cellH))
            withState {
                noStroke()
                fill(Color(white: 0, alpha: 0.55))
                drawRect(x, y + cellH - 26, cellW, 26)
                fill(.white)
                textFont(labelFont); textSize(14); textAlign(.left, .middle)
                drawText(tile.0, x + 8, y + cellH - 13)
            }
        }
    }
}
