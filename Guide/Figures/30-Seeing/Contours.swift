// figure: frame=0 probe themed
//
// Guide diagram (Chapter 30): a picture becomes geometry. Left: a bundled
// photograph, two open palms lit against a black ground, which is the kind of
// high-contrast subject the tracer wants. Right: what ContourDetector traces
// out of it, drawn as stroked vector shapes, the creases of each palm coming
// back as holes inside the hand. The subject is the light half of this picture
// rather than the dark one, which is what `detectsDarkOnLight: false` says.
// The detection is the real Vision request, run once on the still image.
import Ollin
import OllinDiagram
import OllinSamplePhotos
import OllinVision

final class Contours: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    var picture: Image?
    var traced: [Shape] = []

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.28) }
    var soft: Color { theme.ink(0.6) }
    var accent: Color { theme.accent }

    let rightPanel = Rectangle(x: 460, y: 100, width: 360, height: 360)

    override func setup() {
        // Cut square first, so the traced shapes land on the panel exactly
        // where the picture beside them does.
        let image = SamplePhoto.hands.load().cropped(toAspect: 1)
        picture = image
        traced = Contours.trace(image, into: rightPanel)
    }

    override func draw() {
        background(paper)
        textSize(19)

        let leftPanel = Rectangle(x: 60, y: 100, width: 360, height: 360)
        if let picture { drawImage(picture, in: leftPanel) }

        fill(accent.withAlpha(0.12))
        stroke(accent)
        strokeWeight(2)
        for shape in traced { drawShape(shape) }

        noFill()
        stroke(faint)
        strokeWeight(1.5)
        drawRect(leftPanel)
        drawRect(rightPanel)

        noStroke()
        fill(ink)
        textAlign(.center, .top)
        drawText("the picture", leftPanel.center.x, 472)
        drawText("the traced shapes, holes and all", rightPanel.center.x, 472)
        fill(soft)
        drawText("closed vector contours: ready for booleans, hatching, warping, or a plotter",
                 width / 2, 512)
    }

    /// Run the one-shot contour detection and wait for it, mapping the result
    /// into the panel where the figure draws it.
    static func trace(_ image: Image, into panel: Rectangle) -> [Shape] {
        let result = try? waitFor(image) {
            try await ContourDetector.detect(in: $0, detectsDarkOnLight: false)
        }
        return result?.shapes(in: panel) ?? []
    }
}
