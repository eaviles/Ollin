import Ollin

/// Reducing a picture to four colors, six ways.
///
/// Quantizing without dithering (the second panel) lays down flat bands: every
/// pixel jumps to its nearest palette color, and the smooth ramp becomes steps.
/// Dithering trades that banding for texture. It scatters the two colors that
/// bracket each tone so the eye, blurring them together, reads the tone that was
/// there before.
///
/// The three families are all here. `.ordered` decides by a repeating matrix, so
/// it lays down a visible crosshatch. `.blueNoise` decides by a tile with no
/// structure in it, so the grain is even and pattern-free. The error-diffusion
/// kernels carry each pixel's rounding error onto the neighbors they have not
/// visited yet: `.floydSteinberg` is the sharp, detailed one, and `.atkinson`
/// deliberately drops a quarter of the error, which is what blows its highlights
/// and shadows out to clean white and black.
///
/// Both the palette and the dithers are computed once in `setup()`. They are
/// per-pixel CPU work, not something to redo every frame.
@main
final class Dithering: Sketch {
    private let labelFont = OutlineFont.system

    private var panels: [(String, Image)] = []
    private var palette = Palette([])

    override func setup() {
        noStroke()
        let source = paint()

        // The colors the picture is mostly made of, then the picture redrawn in
        // them. Extraction and dithering are the two halves of one idea.
        palette = extractPalette(from: source, count: 4)

        panels = [
            ("original", source),
            ("none (banding)", source.dithered(.none, to: palette)),
            ("ordered, size 8", source.dithered(.ordered(size: 8), to: palette)),
            ("blue noise", source.dithered(.blueNoise, to: palette)),
            ("floyd-steinberg", source.dithered(.floydSteinberg, to: palette)),
            ("atkinson", source.dithered(.atkinson, to: palette)),
        ]
    }

    override func draw() {
        background(Color(hex: 0x101014))

        // Panels at 1:1, so a dithered pixel is a screen pixel and the grain
        // reads as it really is.
        let cols = 3, rows = 2
        let panelW = 320.0, panelH = 240.0
        let gutter = 30.0
        let plate = 26.0
        let totalW = Double(cols) * panelW + Double(cols - 1) * gutter
        let totalH = Double(rows) * (panelH + plate) + Double(rows - 1) * gutter
        let originX = (width - totalW) / 2
        let originY = (height - totalH) / 2 - 30

        for (i, panel) in panels.enumerated() {
            let x = originX + Double(i % cols) * (panelW + gutter)
            let y = originY + Double(i / cols) * (panelH + plate + gutter)
            drawImage(panel.1, in: Rectangle(x: x, y: y, width: panelW, height: panelH))

            fill(.white)
            textFont(labelFont)
            textSize(15)
            textAlign(.left, .middle)
            drawText(panel.0, x, y + panelH + plate / 2)
        }

        // The four colors every panel but the first is built from.
        let swatch = totalW / Double(palette.count)
        let swatchY = originY + totalH + 40
        for i in 0..<palette.count {
            fill(palette[i])
            drawRect(originX + Double(i) * swatch, swatchY, swatch, 34)
        }

        drawCaption("one picture, four extracted colors, six ways of spending them")
    }

    /// A single soft light falling off into darkness: the kind of gentle gradient
    /// that bands badly the moment you quantize it, which is exactly what makes
    /// the dithering visible. The falloff is spread wide enough that the dark end
    /// covers real area, so the extraction keeps a dark color instead of spending
    /// all four on the highlight.
    private func paint() -> Image {
        let w = 320, h = 240
        let image = Image(width: w, height: h)
        let deep = Color(hex: 0x14203A)
        let mid = Color(hex: 0xBF3100)
        let warm = Color(hex: 0xF7DFA5)
        for y in 0..<h {
            for x in 0..<w {
                let u = Double(x) / Double(w - 1)
                let v = Double(y) / Double(h - 1)
                let t = clamp(1 - dist(u, v, 0.28, 0.78) * 1.35, 0, 1)
                image[x, y] = t < 0.5
                    ? Color.mix(deep, mid, t: t * 2)
                    : Color.mix(mid, warm, t: (t - 0.5) * 2)
            }
        }
        return image
    }
}
