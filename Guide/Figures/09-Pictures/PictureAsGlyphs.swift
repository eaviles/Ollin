// figure: frame=0 themed
//
// Guide diagram (Chapter 9): two ways to redraw a picture as marks on a grid.
// Left, a glyph mosaic, where each cell picks the character whose measured
// ink matches the cell's darkness. Right, a halftone screen, where each cell
// keeps one dot and grows it until it covers the same fraction. The picture
// is one of the bundled photographs, an older face in a scarf, chosen for the
// tonal range the two ramps are compared on: the mosaic steps through it and
// the halftone runs smoothly.
import Ollin
import OllinDiagram
import OllinSamplePhotos

final class PictureAsGlyphs: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }
    let night = Color(hex: 0x101319)
    let glow = Color(hex: 0xF4EDE0)
    var source: Image?

    override func setup() {
        source = SamplePhoto.scarf.load().resized(width: 300, height: 300)
    }

    override func draw() {
        background(paper)
        guard let source else { return }

        let left = Rectangle(x: 110, y: 56, width: 300, height: 300)
        let right = Rectangle(x: 470, y: 56, width: 300, height: 300)

        // Light marks on a dark ground, so both treatments must grow their
        // mark with brightness. That is the mosaic's default reading and the
        // halftone's inverted one, since the halftone defaults to ink on paper.
        noStroke()
        fill(night)
        drawRect(left)
        drawRect(right)

        textFont(BitmapFont.builtIn)
        fill(glow)
        // The classic ramp, at a size where the characters stay readable and
        // with gutters wide enough that the dense end reads as marks rather
        // than a solid field.
        drawGlyphMosaic(source, columns: 40, characters: GlyphSet.classic,
                        in: left, glyphScale: 0.72)

        fill(glow)
        drawHalftone(source, pitch: 9, in: right, inverted: true)

        frame(left, title: "glyph mosaic: a character per cell")
        frame(right, title: "halftone: a dot per cell")

        noStroke()
        fill(ink)
        textFont(OutlineFont.system)
        textSize(21)
        textAlign(.center, .top)
        drawText("same picture, same question, two vocabularies of mark",
                 width / 2, 396)
    }

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textFont(OutlineFont.system)
        textSize(17)
        textAlign(.left, .middle)
        drawText(title, r.x, r.y - 20)
    }
}
