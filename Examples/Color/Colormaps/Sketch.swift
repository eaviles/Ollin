import Ollin

/// The two ramp families Ollin ships, one labeled section each. Above: the
/// eight perceptual `Colormap` ramps, each drawn as a horizontal band from
/// `0` on the left to `1` on the right. These map a value to color in a way
/// the eye reads evenly, so reach for one whenever a number needs to become
/// color. Below: the seven cosine-gradient `CosinePalette` presets (Inigo
/// Quilez's example palettes), each swept across its band and scrolled slowly
/// over time; a cosine palette wraps seamlessly, which is why the scroll
/// never shows a seam. Build your own with `CosinePalette(a:b:c:d:)`.
@main
final class Colormaps: Sketch {
    let maps = Colormap.allCases
    let presets: [CosinePalette] = [.rainbow, .dusk, .blush, .meadow, .sunset, .neon, .melon]

    override func setup() {
        noStroke()
        textSize(22 * scale)
    }

    override func draw() {
        background(.black)
        let labelInk = Color(hex: 0x9AA3AD)
        let labelH = 44 * scale
        let sectionH = (height - labelH * 2) / 2

        // Perceptual colormaps: a fixed ramp, value 0 on the left to 1 on
        // the right.
        drawText("Colormap (perceptual, value to color)",
                 16 * scale, labelH * 0.7, color: labelInk)
        let top = Grid(in: Rectangle(x: 0, y: labelH, width: width, height: sectionH),
                       columns: 256, rows: maps.count, gutter: 0)
        for cell in top.cells {
            let t = Double(cell.column) / Double(top.columns - 1)
            fill(maps[cell.row].color(at: t))
            drawRect(cell.frame)
        }

        // Cosine palettes: the same bands, scrolled slowly with time.
        let mid = labelH + sectionH
        drawText("CosinePalette (cosine gradients, scrolling)",
                 16 * scale, mid + labelH * 0.7, color: labelInk)
        let bottom = Grid(in: Rectangle(x: 0, y: mid + labelH, width: width, height: sectionH),
                          columns: 160, rows: presets.count, gutter: 0)
        for cell in bottom.cells {
            let t = Double(cell.column) / Double(bottom.columns) + time * 0.1
            fill(presets[cell.row].color(at: t))
            drawRect(cell.frame)
        }
    }
}
