// figure: frame=0 themed
//
// Guide diagram (Chapter 30): what a sketch shows on a Mac with no camera, and
// what the same sketch shows once a photograph stands in for one. The left
// panel is the notice drawFrame puts up while it waits, drawn here through the
// same drawStatus call it uses, since this machine does have a camera and a
// figure may not depend on that. The right panel is a real StillFrames feed,
// which is the feed Camera.orStill hands back where there is no camera: the
// picture is drawn by the same drawFrame call, which is the whole point.
import Ollin
import OllinDiagram
import OllinSamplePhotos

final class StandingIn: Sketch {
    override var canvasSize: CanvasSize { .size(880, 500) }

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var stills: StillFrames?

    let leftPanel = Rectangle(x: 40, y: 128, width: 380, height: 254)
    let rightPanel = Rectangle(x: 460, y: 128, width: 380, height: 254)

    override func setup() {
        let feed = StillFrames(SamplePhoto.reaching.load())
        feed.start()
        stills = feed
    }

    override func draw() {
        let theme = self.theme
        background(theme.paper)
        noStroke()
        textFont(.system)

        drawText("Not every Mac has a camera. The sketch does not have to care.",
                 40, 26, size: 17, color: theme.ink, align: .left, .top)
        drawText("both of these are a feed, so everything after the first line is the same code",
                 40, 52, size: 12, color: theme.muted, align: .left, .top)

        textFont(.systemMono)
        drawText("let feed = Camera()", leftPanel.x, 92,
                 size: 12, color: theme.ink, align: .left, .top)
        drawText("let feed = Camera.orStill(SamplePhoto.reaching.load())", rightPanel.x, 92,
                 size: 12, color: theme.accent, align: .left, .top)
        textFont(.system)

        // Nothing to draw, and it says so rather than showing black.
        fill(.black)
        drawRect(leftPanel)
        drawStatus("Waiting for camera…", in: leftPanel)

        // The same call, with a picture behind it.
        fill(.black)
        drawRect(rightPanel)
        if let stills { drawFrame(stills, in: rightPanel) }

        stroke(theme.border)
        strokeWeight(1)
        noFill()
        drawRect(leftPanel)
        drawRect(rightPanel)
        noStroke()

        drawText("on a Mac with no camera, this waits forever", leftPanel.x, leftPanel.y + leftPanel.height + 12,
                 size: 12, color: theme.muted, align: .left, .top)
        drawText("one of twenty bundled pictures, letterboxed by drawFrame",
                 rightPanel.x, rightPanel.y + rightPanel.height + 12,
                 size: 12, color: theme.muted, align: .left, .top)

        drawText("A tracker attaches to either one and reads it the same way, which is why the vision",
                 40, 432, size: 13, color: theme.ink, align: .left, .top)
        drawText("examples run on a machine with nothing plugged in. --photo takes the picture even",
                 40, 454, size: 13, color: theme.ink, align: .left, .top)
        drawText("where a camera would have worked.", 40, 476,
                 size: 13, color: theme.ink, align: .left, .top)
    }
}
