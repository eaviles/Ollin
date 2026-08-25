// figure: frame=0
//
// Docs figure (Drawing/Text.md, drawStatus & drawCaption): a real canvas
// carrying both overlays where they actually land. The whole figure is the
// depicted canvas (dark, as a sketch waiting on a feed is), so it renders
// once for both page themes; only the pointer labels are annotation.
import Ollin

final class StatusAndCaption: Sketch {
    let accent = Color(hex: 0xEF6A3E)

    override func draw() {
        // The canvas itself: a sketch that has nothing to show yet.
        background(Color(hex: 0x141417))

        // The two overlays, exactly as a sketch calls them.
        drawStatus("Waiting for camera…")
        drawCaption("FaceTracking · 3 faces")

        // Annotation: name the call that put each line there.
        textFont(OutlineFont.system)
        noStroke()
        fill(accent)
        textSize(30)
        textAlign(.center, .bottom)
        drawText("drawStatus, centered in the canvas", 540, 395)
        drawText("drawCaption, along the bottom edge", 540, 925)
        arrow(from: Vector2(540, 410), to: Vector2(540, 500))
        arrow(from: Vector2(540, 940), to: Vector2(540, 1020))
    }

    func arrow(from a: Vector2, to b: Vector2) {
        let dir = (b - a).normalized
        stroke(accent)
        strokeWeight(3)
        drawLine(a, b - dir * 12)
        noStroke()
        fill(accent)
        drawPolygon([b, b - dir * 15 + dir.perpendicular * 6,
                        b - dir * 15 - dir.perpendicular * 6])
    }
}
