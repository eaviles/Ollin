import Ollin
import OllinVision

/// Whatever stands out to the camera, lifted: a `SubjectSegmenter` finds the
/// salient foreground — the thing you hold up, you yourself — and hands back
/// its matte and cutout. The live frame draws dimmed, the lifted subjects at
/// full color on top: an instant spotlight, with a halo from the tinted matte.
@main
final class SubjectLift: Sketch {
    let camera = Camera()
    lazy var subjects = SubjectSegmenter(camera)

    override func setup() {
        try? camera.start()
    }

    override func draw() {
        background(Color(white: 0.04))

        // The room, dimmed to a murmur.
        tint(Color(white: 0.3))
        guard let rect = drawFrame(camera) else { return noTint() }
        noTint()

        // If the model can't run on this Mac (no compute device), say so on the
        // canvas instead of silently never lifting anything.
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
        drawCaption("SubjectLift — \(n) \(n == 1 ? "subject" : "subjects") in the spotlight")
    }
}
