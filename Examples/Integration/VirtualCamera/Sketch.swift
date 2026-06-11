import Ollin
import OllinCamera

/// Publishes the sketch to the **Ollin Camera virtual camera**, so every app
/// that takes a webcam — Photo Booth, QuickTime, Zoom, Meet, OBS, and browser
/// tools like Hydra through `getUserMedia` — reads it as a live camera. One
/// call in `setup()` does it; the canvas doubles as a broadcast-style "on air"
/// scene so the feed is obviously live on the other side.
///
/// Needs the Ollin Camera extension installed once (see `Apps/OllinCameraApp`);
/// without it the sketch still runs and explains what to do. While no sketch is
/// publishing, the camera shows its built-in "no signal" test card — run this,
/// and the picture switches to the sketch; quit, and the test card returns.
///
/// To see it: run this sketch, open Photo Booth (or QuickTime ▸ New Movie
/// Recording), and pick "Ollin Camera".
@main
final class VirtualCamera: Sketch {

    // Match the camera frame (1280×720), so the feed fills it with no bars.
    override var canvasSize: CanvasSize { .size(1280, 720) }

    var camera: VirtualCameraServer!
    let palette = CosinePalette.neon

    override func setup() {
        camera = publishVirtualCamera()
        textFont(OutlineFont.system)
        noStroke()
    }

    override func draw() {
        background(Color(white: 0.08))

        // A wavy field of colored ribbons — enough motion to read as video.
        let bands = 7
        for band in 0..<bands {
            let phase = Double(band) / Double(bands)
            var ribbon = palette.color(at: phase)
            ribbon.alpha = 0.85
            fill(ribbon)
            let baseY = height * (0.25 + 0.5 * phase)
            drawShape { path in
                path.move(to: Vector2(0, height))
                for x in stride(from: 0.0, through: width, by: 16) {
                    let y = baseY + sin(x * 0.006 + time * (0.8 + phase)) * 60
                        + cos(x * 0.013 - time * 1.4) * 24
                    path.line(to: Vector2(x, y))
                }
                path.line(to: Vector2(width, height))
                path.close()
            }
        }

        // An orbiting satellite dot, for parallax against the ribbons.
        let orbit = Vector2(width * 0.5, height * 0.42)
        let dot = orbit + Vector2(cos(time * 0.9), sin(time * 0.9)) * 230
        fill(.white)
        drawCircle(center: dot, radius: 16 + 5 * sin(time * 3))

        drawBadge()
    }

    /// The broadcast badge: ON AIR while frames reach the camera, and what to
    /// do about it when they don't.
    private func drawBadge() {
        let publishing = camera.isPublishing && camera.isAvailable
        let badge = Rectangle(x: 40, y: 40, width: 230, height: 64)
        fill(publishing ? Color(red: 0.8, green: 0.1, blue: 0.1) : Color(white: 0.25))
        drawRect(badge, cornerRadius: 14)

        // The classic blinking tally light.
        fill(publishing && sin(time * 4) > 0 ? .white : Color(white: 0.6, alpha: 0.5))
        drawCircle(badge.x + 36, badge.y + 32, 11)

        fill(.white)
        textSize(30)
        drawText(publishing ? "ON AIR" : "OFF AIR", badge.x + 64, badge.y + 42)

        if let reason = camera.unavailableReason {
            fill(Color(white: 0.75))
            textSize(20)
            drawText(reason, 40, height - 36)
        } else if publishing {
            fill(Color(white: 0.75))
            textSize(20)
            drawText("Publishing to \"\(camera.deviceName)\" — open Photo Booth and pick it.", 40, height - 36)
        }
    }
}
