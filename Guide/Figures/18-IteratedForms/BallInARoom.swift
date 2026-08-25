// figure: frame=0 themed
//
// Guide diagram (Chapter 18): the same bouncing rule in four rooms. Two rooms
// keep a pattern and two destroy it, and nothing changes but the wall.
// Nothing here uses randomness.
import Ollin

final class BallInARoom: Sketch {
    override var canvasSize: CanvasSize { .size(880, 300) }

    @Param var darkTheme = false

    var paper: Color { Color(hex: darkTheme ? 0x1E1B18 : 0xF7F5F1) }
    var ink: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x232020) }
    var soft: Color { Color(hex: darkTheme ? 0xE8E5E1 : 0x2B2B2B, alpha: 0.22) }
    var accent: Color { Color(hex: darkTheme ? 0xEF6A3E : 0xE4572E) }
    var calm: Color { Color(hex: darkTheme ? 0x5E96C8 : 0x2E6B9E) }

    override func draw() {
        background(paper)

        let radius = 92.0
        let circle = Vector2(112, 120), ellipse = Vector2(330, 120)
        let stadium = Vector2(560, 120), square = Vector2(772, 120)
        let half = radius * 0.86

        room(Billiard(.circle(Circle(center: circle, radius: radius))),
             from: circle + Vector2(0, -radius * 0.62), ink: calm, caption: "a circle", at: circle)
        room(Billiard(.ellipse(center: ellipse, radii: Vector2(radius * 1.1, radius * 0.66))),
             from: ellipse + Vector2(0, -radius * 0.34), ink: calm, caption: "an ellipse", at: ellipse)
        room(Billiard(.stadium(center: stadium, straight: radius * 0.9, radius: radius * 0.8)),
             from: stadium + Vector2(0, -radius * 0.4), ink: accent, caption: "a stadium", at: stadium)
        room(Billiard(.polygon(Contour([square + Vector2(-half, -half), square + Vector2(half, -half),
                                        square + Vector2(half, half), square + Vector2(-half, half)],
                                       closed: true)),
                      obstacles: [Circle(center: square, radius: radius * 0.3)]),
             from: square + Vector2(-half * 0.62, -half * 0.44), ink: accent,
             caption: "a square with a post", at: square)

        textSize(14)
        textAlign(.center)
        fill(ink.withAlpha(0.6))
        drawText("the same rule throughout: go straight, then leave at the angle you arrived at",
                 440, 288)
    }

    func room(_ room: Billiard, from start: Vector2, ink color: Color, caption: String, at center: Vector2) {
        noFill()
        stroke(soft)
        strokeWeight(1.2)
        let outline = room.outline()
        drawPolyline(outline.points, closed: outline.isClosed)
        for post in room.obstacles { drawCircle(post) }
        noStroke()
        fill(ink.withAlpha(0.5))
        for focus in room.foci { drawCircle(focus.x, focus.y, 2.4) }

        noFill()
        strokeWeight(0.5)
        for ball in 0 ..< 3 {
            let heading = 0.31 * .tau + (Double(ball) / 2 - 0.5) * 0.06
            let path = room.path(from: start, heading: heading, bounces: 200)
            guard path.count > 2 else { continue }
            stroke(Color.mix(color, ink, t: Double(ball) / 6).withAlpha(0.32))
            drawPolyline(path)
        }

        textSize(14)
        textAlign(.center)
        fill(ink)
        drawText(caption, center.x, center.y + 132)
    }
}
