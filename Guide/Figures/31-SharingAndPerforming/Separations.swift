// figure: frame=0 themed
//
// Guide diagram (Chapter 31): separating artwork into printable inks. One
// picture, a bundled photograph with almost nothing in it any of the three
// inks can carry alone, the three masters a print shop would need (black means
// full ink), and the overprint preview showing how those three drums will read
// together.
import Ollin
import OllinDiagram
import OllinSamplePhotos

final class Separations: Sketch {
    override var canvasSize: CanvasSize { .size(880, 400) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }

    var plates: [Image] = []
    var preview: Image?
    var names: [String] = []

    override func setup() {
        // A photograph rather than flat shapes: every pixel is a hard pixel
        // for the search, which is the case a print shop actually brings it.
        let artwork = SamplePhoto.marigolds.load().resized(width: 240, height: 240)
        let inks: [Ink] = [.fluorescentPink, .blue, .yellow]
        let separation = artwork.separated(into: inks)
        plates = separation.layers.map(\.master)
        names = inks.map(\.name)
        preview = separation.preview()
    }

    override func draw() {
        background(paper)

        for (i, plate) in plates.enumerated() {
            let panel = Rectangle(x: 25 + Double(i) * 200, y: 62,
                                  width: 180, height: 180)
            drawImage(plate, in: panel)
            frame(panel, title: names[i].lowercased())
        }
        if let preview {
            let panel = Rectangle(x: 655, y: 62, width: 180, height: 180)
            drawImage(preview, in: panel)
            frame(panel, title: "overprinted")
        }

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("one picture, one grayscale master per drum, and the result",
                 width / 2, 288)
    }

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textSize(16)
        textAlign(.left, .middle)
        drawText(title, r.x, r.y - 18)
    }
}
