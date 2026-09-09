// figure: frame=0 themed
//
// Docs diagram (Drawing/Halftone.md): the print dot screen at work. Left,
// the source picture, one of the bundled sample photographs. Right, its
// ink-on-paper halftone: round dots on the 45-degree grid, each sized so its
// ink area matches the tone beneath it, the shadows overrunning their cells
// and merging into checkered diamonds.
import Ollin
import OllinDiagram
import OllinSamplePhotos

final class HalftoneScreen: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }
    var source: Image?

    override func setup() {
        source = SamplePhoto.scarf.load().resized(width: 300, height: 300)
    }

    override func draw() {
        background(paper)
        guard let source else { return }

        let left = Rectangle(x: 110, y: 56, width: 300, height: 300)
        let right = Rectangle(x: 470, y: 56, width: 300, height: 300)

        drawImage(source, in: left)

        // The default reading: ink on paper, the classic 45-degree screen.
        noStroke()
        fill(ink)
        drawHalftone(source, pitch: 9, in: right)

        frame(left, title: "the picture")
        frame(right, title: "the screen: one dot per cell")

        noStroke()
        fill(ink)
        textFont(OutlineFont.system)
        textSize(21)
        textAlign(.center, .top)
        drawText("dot area tracks tone, so the grays ride through unchanged",
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
