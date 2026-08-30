import Ollin
import OllinVision

/// You, lifted off the background: a `PersonSegmenter` turns the camera frame
/// into a soft people matte and the cutout it makes, and the sketch composites
/// the cutout over a drifting gradient — background replacement in a few lines.
/// The same matte, tinted dark and nudged, becomes the drop shadow underneath.
///
/// The matte and cutout are plain `Image`s, so anything a sketch can draw can
/// sit behind (or in front of) you.
@main
final class PersonSegmentation: Sketch {
    let camera = Camera()
    lazy var people = PersonSegmenter(camera)
    let backdrop = Ramp(stops: [(0.0, Color(hex: 0x16275B)),
                                (0.5, Color(hex: 0x3C6DD0)),
                                (1.0, Color(hex: 0xF7B267))], in: .oklch)

    override func setup() {
        try? camera.start()
    }

    override func draw() {
        // The replacement background: a slowly swinging linear gradient.
        let swing = sin(time * 0.3) * width * 0.35
        noStroke()
        fill(.linear(from: Vector2(width / 2 - swing, 0),
                     to: Vector2(width / 2 + swing, height), backdrop))
        drawRect(0, 0, width, height)

        // The raw frame never draws here (only its matte and cutout do), so this
        // takes the typed path — `fittedRect` for the rectangle, `drawStatus` for
        // the waiting notice — instead of `drawFrame`.
        guard let rect = camera.fittedRectangle(in: bounds) else {
            return drawStatus(camera.waitingMessage)
        }

        // If the segmentation model can't run on this Mac (no compute device),
        // say so on the canvas instead of silently showing only the gradient.
        if let reason = people.unavailableReason {
            return drawStatus(reason, style: .warning)
        }

        // Drop shadow: the matte tinted translucent black, nudged down and right.
        if let matte = people.matte {
            tint(Color(white: 0, alpha: 0.4))
            drawImage(matte, in: Rectangle(x: rect.x + 14 * scale, y: rect.y + 18 * scale,
                                           width: rect.width, height: rect.height))
            noTint()
        }

        // The cutout: you, over whatever the sketch painted.
        if let cutout = people.cutout {
            drawImage(cutout, in: rect)
        }

        drawCaption("PersonSegmentation — the camera's people over a drawn background")
    }
}
