// figure: frame=0 probe themed
//
// Guide diagram (Chapter 9): pixel sorting. A Guanajuato alley, one of the
// bundled photographs, and the same picture with each column's mid-tone runs
// reordered by brightness. The deepest doorways and the brightest clouds
// survive because they fall outside the threshold, which is what keeps the
// picture readable while the walls and the sky pour.
import Ollin
import OllinDiagram
import OllinSamplePhotos

final class SortedPixels: Sketch {
    override var canvasSize: CanvasSize { .size(880, 480) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var soft: Color { theme.ink(0.12) }
    var source: Image?
    var sorted: Image?

    override func setup() {
        let picture = SamplePhoto.alley.load().resized(width: 300, height: 300)
        source = picture
        sorted = picture.pixelSorted(.vertical, by: .brightness, threshold: 0.2 ... 0.75)
    }

    override func draw() {
        background(paper)
        guard let source, let sorted else { return }

        let left = Rectangle(x: 110, y: 56, width: 300, height: 300)
        let right = Rectangle(x: 470, y: 56, width: 300, height: 300)

        drawImage(source, in: left)
        drawImage(sorted, in: right)

        frame(left, title: "the picture")
        frame(right, title: "columns sorted by brightness")

        noStroke()
        fill(ink)
        textSize(21)
        textAlign(.center, .top)
        drawText("a threshold picks which runs move, and the rest holds still",
                 width / 2, 396)
    }

    func frame(_ r: Rectangle, title: String) {
        noFill()
        stroke(soft)
        strokeWeight(2)
        drawRect(r)
        noStroke()
        fill(ink)
        textSize(17)
        textAlign(.left, .middle)
        drawText(title, r.x, r.y - 20)
    }
}
