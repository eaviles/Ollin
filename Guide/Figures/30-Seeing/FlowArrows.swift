// figure: frame=0 themed
//
// Guide diagram (Chapter 30): optical flow as a field of arrows. Left: one
// frame of the film that ships with Ollin, a dancer on a plain ground with the
// camera locked off. Right: the same frame with the measured flow drawn on
// top, one arrow per grid sample, pointing the way the picture moved since the
// frame a twenty-fifth of a second earlier. The field is measured by the real
// Vision request, so the arm that swings gets arrows and the leg that stays
// planted gets none.
import Ollin
import OllinDiagram
import OllinSamplePhotos
import OllinVideo
import OllinVision

final class FlowArrows: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    var field: MotionField?
    var picture: Image?

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.28) }
    var soft: Color { theme.ink(0.6) }
    var accent: Color { theme.accent }

    override func setup() {
        // A moment where one arm sweeps across the frame while the far leg
        // holds still: the two cases the field has to tell apart.
        let clip = VideoPlayer(url: SampleClip.dance.url)
        clip.isMuted = true
        clip.seek(to: 1.5)
        guard let before = clip.snapshot() else { return }
        clip.seek(to: 1.54)                       // the next frame, at 25 a second
        guard let after = clip.snapshot() else { return }
        picture = after
        field = try? waitFor(before, after) {
            try await FlowTracker.detect(from: $0, to: $1, quality: .high)
        }
    }

    override func draw() {
        background(paper)
        textSize(19)

        let leftPanel = Rectangle(x: 60, y: 100, width: 360, height: 360)
        let rightPanel = Rectangle(x: 460, y: 100, width: 360, height: 360)

        if let picture {
            drawImage(picture, in: leftPanel)
            drawImage(picture, in: rightPanel)
        }

        if let field {
            // How far a picture moves between two frames depends on what it is,
            // so the arrows are drawn against this frame's own fastest sample
            // rather than a fixed number of pixels.
            let samples = field.samples(in: rightPanel, every: 16)
            let fastest = max(samples.map(\.flow.length).max() ?? 0, 0.001)
            stroke(accent)
            strokeWeight(2)
            for sample in samples {
                guard sample.flow.length > fastest * 0.18 else { continue }
                let tip = sample.position + sample.flow * (13 / fastest)
                drawLine(sample.position, tip)
                let dir = (tip - sample.position).normalized
                drawLine(tip, tip - dir * 6 + dir.perpendicular * 4)
                drawLine(tip, tip - dir * 6 - dir.perpendicular * 4)
            }
        }

        noFill()
        stroke(faint)
        strokeWeight(1.5)
        drawRect(leftPanel)
        drawRect(rightPanel)

        noStroke()
        fill(ink)
        textAlign(.center, .top)
        drawText("what the camera sees", leftPanel.center.x, 472)
        drawText("how it moved since the frame before", rightPanel.center.x, 472)
        fill(soft)
        drawText("a direction and a speed at every point: Chapter 14's field, measured from the world",
                 width / 2, 512)
    }
}
