import Ollin
import OllinSamplePhotos

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
        // One of the bundled sample photographs, at the size the panels are
        // drawn: a dithered pixel has to land on one screen pixel to read.
        let source = SamplePhoto.scarf.load().resized(width: 320, height: 320)

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
        let panelW = 320.0, panelH = 320.0
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
}
