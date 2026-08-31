import Ollin
import OllinVision

/// Something lifted off the background, two ways. A `PersonSegmenter` turns the
/// camera frame into a soft people matte and the cutout it makes; a
/// `SubjectSegmenter` finds whatever stands out instead (the thing you hold up,
/// or you yourself). The `segmenter` knob (in the inspector, press ⌘/) switches
/// between them, and each keeps its own composite: people land over a drifting
/// gradient with the matte, tinted dark and nudged, as the drop shadow
/// underneath (background replacement in a few lines), while subjects glow at
/// full color over the dimmed room, with a warm halo from the tinted matte.
///
/// The matte and cutout are plain `Image`s, so anything a sketch can draw can
/// sit behind (or in front of) whatever was lifted.
@main
final class Lift: Sketch {
    enum Segmenter: String, CaseIterable, ParamOption { case person, subject }

    let camera = Camera()
    lazy var people = PersonSegmenter(camera)
    lazy var subjects = SubjectSegmenter(camera)
    let backdrop = Ramp(stops: [(0.0, Color(hex: 0x16275B)),
                                (0.5, Color(hex: 0x3C6DD0)),
                                (1.0, Color(hex: 0xF7B267))], in: .oklch)

    @Param var segmenter = Segmenter.person

    override func setup() {
        try? camera.start()
    }

    override func draw() {
        switch segmenter {
        case .person: drawPeople()
        case .subject: drawSubjects()
        }
    }

    /// The person mode: the camera's people composited over a drawn background,
    /// with the matte doubling as their drop shadow.
    func drawPeople() {
        // The replacement background: a slowly swinging linear gradient.
        let swing = sin(time * 0.3) * width * 0.35
        noStroke()
        fill(.linear(from: Vector2(width / 2 - swing, 0),
                     to: Vector2(width / 2 + swing, height), backdrop))
        drawRect(0, 0, width, height)

        // The raw frame never draws here (only its matte and cutout do), so this
        // takes the typed path: `fittedRectangle` for the rectangle and
        // `drawStatus` for the waiting notice, instead of `drawFrame`.
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

        drawCaption("Lift: the camera's people over a drawn background")
    }

    /// The subject mode: whatever stands out to the camera, lifted into a
    /// spotlight against the dimmed room.
    func drawSubjects() {
        background(Color(white: 0.04))

        // The room, dimmed to a murmur.
        tint(Color(white: 0.3))
        guard let rect = drawFrame(camera) else { return noTint() }
        noTint()

        // The same guard as the person mode: name the reason on the canvas.
        if let reason = subjects.unavailableReason {
            return drawStatus(reason, style: .warning)
        }

        // A warm halo: the matte tinted and drawn slightly enlarged behind the
        // cutout, so the subjects glow against the dimmed room.
        if let matte = subjects.matte {
            let grow = 8 * scale
            tint(Color(red: 1.0, green: 0.78, blue: 0.3, alpha: 0.5))
            drawImage(matte, in: Rectangle(x: rect.x - grow, y: rect.y - grow,
                                           width: rect.width + grow * 2,
                                           height: rect.height + grow * 2))
            noTint()
        }

        // The lifted subjects at full color.
        if let cutout = subjects.cutout {
            drawImage(cutout, in: rect)
        }

        let n = subjects.count
        drawCaption("Lift: \(n) \(n == 1 ? "subject" : "subjects") in the spotlight")
    }
}
