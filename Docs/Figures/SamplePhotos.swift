// figure: frame=0 themed
//
// Docs diagram (Drawing/SamplePhotos.md): the eight bundled sample photographs,
// the four faces above and the four figures below, each under its name and its
// photographer, so the page shows what every `SamplePhoto` loads.
import Ollin
import OllinDiagram
import OllinSamplePhotos

final class SamplePhotos: Sketch {
    override var canvasSize: CanvasSize { .size(880, 580) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.55) }
    var soft: Color { theme.ink(0.12) }
    var pictures: [(SamplePhoto, Image)] = []

    override func setup() {
        // Each is drawn into a square cell, so a figure's upright frame is fitted
        // rather than cropped: the picture is what the page is showing.
        pictures = SamplePhoto.all.map { ($0, $0.load().resized(width: 400, height: 400)) }
    }

    override func draw() {
        background(paper)
        let side = 190.0, gap = 22.0
        let left = (width - side * 4 - gap * 3) / 2
        for (i, (photo, _)) in pictures.enumerated() {
            let row = Double(i / 4), column = Double(i % 4)
            let frame = Rectangle(x: left + column * (side + gap),
                                  y: 34 + row * (side + 84), width: side, height: side)
            let picture = photo.load()
            let fitted = Rectangle(fitting: picture.size, in: frame)
            noFill()
            stroke(soft)
            strokeWeight(2)
            drawRect(fitted)
            noStroke()
            drawImage(picture, in: fitted)

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
