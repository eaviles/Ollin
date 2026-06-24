import Ollin

/// Previous-frame feedback: a layer that **remembers itself** across frames. Each
/// frame is built from the *last* frame (zoomed, spun, and faded) with a fresh
/// mark drawn on top. That read-transform-write loop is the whole effect: it's how
/// you get trails, tunnels, and the video-feedback look of a camera pointed at its
/// own screen. It's distinct from the accumulation surface (`noClear`), which can
/// only pile new draws onto an unchanging canvas; feedback hands you the previous
/// frame as an *image you can transform* before drawing it back.
///
/// The pieces: `feedback()` makes a persistent layer (made once in `setup()` and
/// held, its identity carrying state from frame to frame); `withFeedback`
/// redirects drawing into it and hands in last frame as `prev`; `feedback.image`
/// composites the result onto the canvas.
///
/// Try it: change `scale(0.98)` (above 1 zooms outward into a different tunnel),
/// the `rotate` amount (0 = straight trails), or the decay alpha (lower = shorter
/// trails).
@main
final class Feedback_Example: Sketch {
    var trail: Feedback!

    override func setup() {
        trail = feedback()
    }

    override func draw() {
        background(Color(white: 0.02))   // clear the canvas first (it resets the frame)

        withFeedback(trail) { prev in
            // Draw last frame back, transformed about the canvas centre so it
            // spirals inward into a tunnel, and faded a little so trails decay.
            withState {
                translate(width / 2, height / 2)
                rotate(0.06)
                scale(0.98)
                translate(-width / 2, -height / 2)
                tint(Color(white: 1, alpha: 0.94))
                drawImage(prev, 0, 0)
            }
            // A fresh dot tracing a Lissajous path, time-driven so it's the same
            // every run (and deterministic for the snapshot test).
            noStroke()
            let x = width * 0.5 + sin(time * 1.1) * width * 0.32
            let y = height * 0.5 + sin(time * 1.7 + 1) * height * 0.32
            fill(Color(hue: (time * 0.05).truncatingRemainder(dividingBy: 1),
                       saturation: 0.7, brightness: 1))
            drawCircle(x, y, 26)
        }

        drawImage(trail.image, 0, 0)
        drawCaption("previous-frame feedback: last frame, zoomed + spun + faded, plus a new dot")
    }
}
