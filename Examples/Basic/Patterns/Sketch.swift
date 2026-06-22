import Ollin

/// Procedural pattern `Generator`s: sources filled from math alone, no input layer.
/// `generate(_:)` hands back a `RenderTarget` you draw, filter, or feed into another
/// effect: the seed of the live-coding / shader-mixing direction.
///
/// Six tiles: the four generators, then two showing they flow into the rest of the
/// chain (noise mapped through a colormap, and that same field gridded with a
/// `multiply` blend). Try changing a `scale`, or chaining another `.filtered(...)`.
@main
final class Patterns_Example: Sketch {
    private let labelFont = OutlineFont.system

    override func draw() {
        background(Color(white: 0.06))

        let s = 4 + sin(time * 0.4) * 2          // a gently breathing feature scale

        // Build each tile's layer up front, then lay them out below.
        let checkers = generate(.checkers(scale: s * 2, foreground: Color(hex: 0xF2C14E),
                                          background: Color(hex: 0x222B3A)))
        let grid = generate(.gridLines(scale: s * 3, weight: 0.12,
                                       foreground: Color(hex: 0x55D6BE), background: Color(hex: 0x12161F)))
        let bars = generate(.bars(scale: s * 3, foreground: Color(hex: 0xE85D75),
                                  background: Color(hex: 0x1B1F2A)))
        let clouds = generate(.noise(scale: s, sharpness: 0))
        let mapped = generate(.noise(scale: s)).filtered(.gradientMap(.turbo))

        // The mix: that colormapped noise, gridded over it with a multiply blend,
        // a layered composition built from two generators and a filter.
        let mixGrid = generate(.gridLines(scale: s * 4, weight: 0.08,
                                          foreground: Color(white: 0.1), background: .white))

        let labelled: [(String, RenderTarget)] = [
            ("checkers", checkers), ("gridLines", grid), ("bars", bars),
            ("noise", clouds), ("noise → turbo", mapped), ("mix: noise × grid", mapped),
        ]

        let cols = 3, rows = 2
        let gutter = width * 0.015
        let cellW = (width - gutter * Double(cols + 1)) / Double(cols)
        let cellH = (height - gutter * Double(rows + 1)) / Double(rows)
        for (i, item) in labelled.enumerated() {
            let r = i / cols, c = i % cols
            let x = gutter + Double(c) * (cellW + gutter)
            let y = gutter + Double(r) * (cellH + gutter)
            let rect = Rectangle(x: x, y: y, width: cellW, height: cellH)
            drawImage(item.1.image, in: rect)
            if i == 5 {                                  // the last tile multiplies a grid over the field
                withState { blendMode(.multiply); drawImage(mixGrid.image, in: rect) }
            }
            withState {
                blendMode(.normal)
                fill(Color(white: 0, alpha: 0.55)); noStroke()
                drawRect(x, y + cellH - 32, cellW, 32)
                fill(.white)
                textFont(labelFont); textSize(18); textAlign(.left, .middle)
                drawText(item.0, x + 10, y + cellH - 16)
            }
        }
    }
}
