// figure: frame=0 themed
//
// Docs diagram (Drawing/SamplePhotos.md): the four bundled sample photographs
// in a row, each under its name and its photographer, so the page shows what
// `SamplePhoto.portrait`, `.scarf`, `.profile`, and `.marigolds` load.
import Ollin
import OllinDiagram
import OllinSamplePhotos

final class SamplePhotos: Sketch {
    override var canvasSize: CanvasSize { .size(880, 300) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.55) }
    var soft: Color { theme.ink(0.12) }
    var pictures: [(SamplePhoto, Image)] = []

    override func setup() {
        pictures = SamplePhoto.all.map { ($0, $0.load().resized(width: 400, height: 400)) }
    }

    override func draw() {
        background(paper)
        let side = 190.0, gap = 22.0
        let left = (width - side * 4 - gap * 3) / 2
        for (i, (photo, picture)) in pictures.enumerated() {
            let frame = Rectangle(x: left + Double(i) * (side + gap), y: 34, width: side, height: side)
            drawImage(picture, in: frame)
            noFill()
            stroke(soft)
            strokeWeight(2)
            drawRect(frame)

            noStroke()
            fill(ink)
            textFont(OutlineFont.system)
            textAlign(.center, .top)
            textSize(17)
            drawText(".\(photo.name)", frame.x + side / 2, frame.y + side + 12)
            fill(faint)
            textSize(13)
            drawText(photo.credit.photographer, frame.x + side / 2, frame.y + side + 36)
        }
    }
}
