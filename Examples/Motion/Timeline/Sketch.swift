import Ollin

/// `Timeline` sequences a value through timed keyframes, each leg with its own
/// easing: start here, glide there, hold, glide on. Where `@Eased` chases a
/// single target, a timeline follows a script. Here a `Timeline<Vector2>`
/// walks a dot around a square, every side on a different curve with a pause
/// at each corner, while a shorter `Timeline<Double>` breathes the dot's size
/// in counterpoint (four breaths per lap, so the pair loops together). Stored
/// timelines advance themselves once per frame, so `draw()` only reads
/// `.value`; the bar underneath tracks `progress`, with a tick per keyframe.
@main
final class TimelineTour: Sketch {
    static let corners = [
        Vector2(280, 300), Vector2(800, 300),
        Vector2(800, 820), Vector2(280, 820),
    ]

    /// The script's segment lengths, in order: travel a side, hold a corner.
    static let segments = [1.0, 0.3, 1.0, 0.3, 1.0, 0.3, 1.0, 0.3]

    // One lap of the square (5.2s), a different character per side.
    let path = Timeline(TimelineTour.corners[0])
        .to(TimelineTour.corners[1], in: 1.0, ease: .easeInOut)
        .hold(for: 0.3)
        .to(TimelineTour.corners[2], in: 1.0, ease: .easeOutBounce)
        .hold(for: 0.3)
        .to(TimelineTour.corners[3], in: 1.0, ease: .easeOutBack)
        .hold(for: 0.3)
        .to(TimelineTour.corners[0], in: 1.0, ease: .easeOutElastic)
        .hold(for: 0.3)

    // A breath every 1.3s: four per lap, so both timelines loop in step.
    let size = Timeline(26.0)
        .to(40, in: 0.65, ease: .easeInOut)
        .to(26, in: 0.65, ease: .easeInOut)

    override func setup() {
        path.loops = true
        size.loops = true
    }

    override func draw() {
        background(.white)

        // The route: the square being traveled, corners marked.
        stroke(Color(white: 0.88)); strokeWeight(2 * scale); noFill()
        drawPolyline(Self.corners, closed: true)
        for corner in Self.corners {
            drawCircle(center: corner, radius: 9 * scale)
        }

        // Each side's easing, labeled at its midpoint.
        noStroke(); fill(Color(white: 0.62)); textSize(21 * scale)
        textAlign(.center, .middle)
        drawText("easeInOut", width / 2, 252)
        drawText("easeOutBack", width / 2, 868)
        textAlign(.left, .middle)
        drawText("easeOutBounce", 828, height / 2)
        textAlign(.right, .middle)
        drawText("easeOutElastic", 252, height / 2)

        // Progress through the whole script, a tick at every keyframe.
        let barY = 972.0
        let barLeft = Self.corners[0].x, barRight = Self.corners[1].x
        stroke(Color(white: 0.88)); strokeWeight(3 * scale)
        drawLine(barLeft, barY, barRight, barY)
        var elapsed = 0.0
        for segment in Self.segments {
            elapsed += segment
            let x = lerp(barLeft, barRight, elapsed / path.duration)
            drawLine(x, barY - 7 * scale, x, barY + 7 * scale)
        }
        stroke(.coral)
        drawLine(barLeft, barY, lerp(barLeft, barRight, path.progress), barY)

        // The performer, script-positioned and script-sized.
        noStroke(); fill(.coral)
        drawCircle(center: path.value, radius: size.value * scale)
    }
}
