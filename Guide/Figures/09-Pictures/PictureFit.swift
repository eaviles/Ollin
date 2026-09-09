// figure: frame=0 themed
//
// Guide diagram: one 3:2 photograph into three 2:3 boxes, one per ImageFit.
// Stretched, the round dome goes narrow. Contained, the whole picture is there
// and the box shows above and below it. Covered, the box is full and only the
// middle four ninths of the width is left.
import Ollin
import OllinDiagram
import OllinSamplePhotos

final class PictureFit: Sketch {
    override var canvasSize: CanvasSize { .size(880, 520) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.45) }
    var box: Color { theme.card }

    private var picture = Image(width: 1, height: 1)

    static let modes: [(ImageFit, String)] = [(.stretch, ".stretch"),
                                              (.contain, ".contain"),
                                              (.cover, ".cover")]

    override func setup() {
        textFont(OutlineFont.system)
        picture = SamplePhoto.city.load().cropped(toAspect: 3.0 / 2)
    }

    override func draw() {
        background(paper)
        for (i, mode) in PictureFit.modes.enumerated() {
            let frame = Rectangle(x: 104 + Double(i) * 236, y: 70, width: 200, height: 300)
            noStroke()
            fill(box)
            drawRect(corner: frame.corner, width: frame.width, height: frame.height)
            drawImage(picture, in: frame, fit: mode.0)
            noFill()
            stroke(ink.withAlpha(0.3))
            strokeWeight(1.5)
            drawRect(corner: frame.corner, width: frame.width, height: frame.height)
            noStroke()
            fill(ink)
            textSize(22)
            textAlign(.center, .top)
            drawText(mode.1, frame.center.x, 388)
        }
        fill(faint)
        textSize(18)
        textAlign(.center, .top)
        drawText("the picture is 3:2, every box is 2:3", 440, 424)
        drawText("the dome is round, so a stretch shows at once", 440, 452)
        drawText("cover keeps only the middle 44% of the width", 440, 480)
    }
}
