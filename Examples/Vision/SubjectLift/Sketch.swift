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
        textFont(OutlineFont.system)
        try? camera.start()
    }

    override func draw() {
        background(Color(white: 0.04))

        guard let frame = camera.frame else {
            fill(Color(white: 0.5))
            textAlign(.center, .middle)
            textSize(22 * scale)
            drawText("Waiting for camera…", width / 2, height / 2)
            return
        }
        let rect = camera.fittedRect(in: bounds) ?? bounds

        // The room, dimmed to a murmur.
        tint(Color(white: 0.3))
        drawImage(frame, in: rect)
        noTint()

        // If the model can't run on this Mac (no compute device), say so on the
        // canvas instead of silently never lifting anything.
        if let reason = subjects.unavailableReason {
            fill(Color(red: 1.0, green: 0.5, blue: 0.4))
            textAlign(.center, .middle)
            textSize(18 * scale)
            drawText(reason, in: Rectangle(x: width * 0.1, y: height / 2 - 60 * scale,
                                           width: width * 0.8, height: 120 * scale))
            return
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

        fill(.white)
        textAlign(.center, .bottom)
        textSize(15 * scale)
        let n = subjects.count
        drawText("SubjectLift — \(n) \(n == 1 ? "subject" : "subjects") in the spotlight",
                 width / 2, height - 28 * scale)
    }
}
