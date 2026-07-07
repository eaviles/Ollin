import Ollin

/// **Relight**: read a layer as a height map (bright = raised) and light it as
/// embossed physical matter. One drifting noise field, shown raw and through the
/// five material finishes: matte clay, metal, wet glass, grainy sand, and liquid.
/// A finish keeps the layer's own color unless `color:` picks the material's.
///
/// Try it: raise `height` for deeper relief, lower `elevation` for a grazing
/// rake of light, or relight a simulation (`Simulation/GrayScott`) instead of
/// noise so the pattern reads as grown matter.
@main
final class Relight_Example: Sketch {
    @Param(0.2...4, icon: "arrow.up.and.down") var relief = 2.4
    @Param(0.15...1.5, icon: "sun.max") var lightElevation = 0.8

    private let labelFont = OutlineFont.system

    override func draw() {
        background(Color(white: 0.06))

        // The height map: a slowly drifting fbm cloud (bright = raised).
        let field = generate(.noise(scale: 3.2,
                                    foreground: Color(hex: 0xB8C4D6),
                                    background: Color(hex: 0x1C2330)))
            .filtered(.perturb(amount: 0.05, scale: 2.4, phase: time * 0.25))

        let tiles: [(String, Filter?)] = [
            ("height field", nil),
            ("matte", .relight(.matte, elevation: lightElevation, height: relief,
                               color: Color(hex: 0xC96F4A))),
            ("metal", .relight(.metal, elevation: lightElevation, height: relief,
                               color: Color(hex: 0xD8A93F))),
            ("glass", .relight(.glass, elevation: lightElevation, height: relief)),
            ("sand", .relight(.sand, elevation: lightElevation, height: relief,
                              color: Color(hex: 0xD9BE8C))),
            ("liquid", .relight(.liquid, elevation: lightElevation, height: relief)),
        ]
        drawRelightSheet(self, field, tiles, font: labelFont)
    }
}

/// Tile the finishes into a labelled grid. (Each family example carries its own
/// copy so the file stays standalone.)
@MainActor
func drawRelightSheet(_ s: Sketch, _ scene: RenderTarget,
                      _ tiles: [(String, Filter?)], font: OutlineFont) {
    let cols = 3
    let rows = (tiles.count + cols - 1) / cols
    let gutter = s.width * 0.012
    let cellW = (s.width - gutter * Double(cols + 1)) / Double(cols)
    let cellH = (s.height - gutter * Double(rows + 1)) / Double(rows)
    for (i, tile) in tiles.enumerated() {
        let r = i / cols, c = i % cols
        let x = gutter + Double(c) * (cellW + gutter)
        let y = gutter + Double(r) * (cellH + gutter)
        let layer = tile.1.map { scene.filtered($0) } ?? scene
        s.drawImage(layer.image, in: Rectangle(x: x, y: y, width: cellW, height: cellH))
        s.withState {
            s.fill(Color(white: 0, alpha: 0.55)); s.noStroke()
            s.drawRect(x, y + cellH - 26, cellW, 26)
            s.fill(.white)
            s.textFont(font); s.textSize(14); s.textAlign(.left, .middle)
            s.drawText(tile.0, x + 8, y + cellH - 13)
        }
    }
}
