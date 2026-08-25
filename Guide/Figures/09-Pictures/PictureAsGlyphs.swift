// figure: frame=0 themed
//
// Guide diagram (Chapter 9): two ways to redraw a picture as marks on a grid.
// Left, a glyph mosaic, where each cell picks the character whose measured
// ink matches the cell's darkness. Right, a halftone screen, where each cell
// keeps one dot and grows it until it covers the same fraction.
import Ollin
import OllinDiagram

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
        noiseSeed(3)
        source = makeSunset(size: 160)
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

        textFont(BitmapFont.builtin)
        fill(glow)
        // The classic ramp, at a size where the characters stay readable and
        // with gutters wide enough that the dense end reads as marks rather
        // than a solid field.
        drawGlyphMosaic(source, columns: 20, characters: GlyphSet.classic,
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

    /// The chapter's authored sunset, so every treatment reads the same image.
    func makeSunset(size: Int) -> Image {
        let image = Image(width: size, height: size)
        let sky = Ramp([Color(hex: 0x14213D), Color(hex: 0x5E60CE),
                        Color(hex: 0xE56B6F), Color(hex: 0xFFB703)])
        let horizon = 0.62
        let sunX = 0.58, sunY = 0.47
        for py in 0..<size {
            for px in 0..<size {
                let u = Double(px) / Double(size - 1)
                let v = Double(py) / Double(size - 1)
                var color: Color
                if v < horizon {
                    color = sky.color(at: v / horizon)
                    let d = ((u - sunX) * (u - sunX) + (v - sunY) * (v - sunY)).squareRoot()
                    let disk = 1 - smoothstep(0.075, 0.095, d)
                    let glow = (1 - smoothstep(0.04, 0.4, d)) * 0.5
                    color = Color.mix(color, Color(hex: 0xFFF3D6), t: min(1, disk + glow))
                } else {
                    let w = (v - horizon) / (1 - horizon)
                    let reflected = sky.color(at: max(0, 0.92 - w * 0.9))
                    let dark = Color.mix(reflected, Color(hex: 0x0B1020), t: 0.45 + w * 0.4)
                    let streak = noise(u * 5, v * 120)
                    let path = 1 - smoothstep(0.02, 0.16 + w * 0.3, abs(u - sunX))
                    color = Color.mix(dark, Color(hex: 0xFFD98A),
                                      t: min(1, path * (0.2 + streak * 0.8)))
                }
                image[px, py] = color
            }
        }
        return image
    }
}
