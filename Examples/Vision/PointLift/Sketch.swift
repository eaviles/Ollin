import Foundation
import Ollin
import OllinVision

/// Click a thing and it lifts out of the live feed: a `PointSegmenter` segments
/// whatever sits under the click, any thing, and hands back its matte and
/// cutout. Where `SubjectLift` lets the model decide what stands out, this one
/// takes direction: click the mug, not the person holding it. Shift-click a
/// stray region the mask caught and it retreats; press C to let the pick go.
/// The weights aren't in the repo: run `Scripts/fetch-models.sh` once and
/// relaunch (the sketch says so on the canvas until then).
///
/// Model: Segment Anything 2.1 (small), Meta AI's promptable segmentation
/// model in Apple's official Core ML conversion (Apache-2.0), in three parts:
/// image encoder, prompt encoder, mask decoder. Downloaded by the fetch
/// script, never bundled. Provenance in THIRD-PARTY-NOTICES.md.
/// The fetched weights live in `Models/` at the repo root. This sketch runs both
/// from there (the gallery compiles it where it sits) and from `Examples/` (a
/// direct `swift run`), so the folder is found by walking up from this file
/// instead of trusting whatever the working directory happens to be.
private func modelsPath(_ name: String) -> String {
    sketchResource(name) ?? ("Models" as NSString).appendingPathComponent(name)
}

@main
final class PointLift: Sketch {
    static let modelPaths = ["SAM2_1SmallImageEncoderFLOAT16.mlpackage",
                             "SAM2_1SmallPromptEncoderFLOAT16.mlpackage",
                             "SAM2_1SmallMaskDecoderFLOAT16.mlpackage"].map(modelsPath)

    let camera = Camera()
    lazy var picker = PointSegmenter(
        camera,
        imageEncoderAt: URL(fileURLWithPath: Self.modelPaths[0]),
        promptEncoderAt: URL(fileURLWithPath: Self.modelPaths[1]),
        maskDecoderAt: URL(fileURLWithPath: Self.modelPaths[2]))

    /// Where the last click landed, for the little pulse while the answer is
    /// on its way.
    var lastClick: Vector2?

    override func setup() {
        try? camera.start()
    }

    override func mousePressed() {
        guard let rect = camera.fittedRectangle(in: bounds) else { return }
        let point = mouse
        if modifiers.contains(.shift) {
            picker.exclude(point, in: rect)
        } else {
            picker.pick(at: point, in: rect)
        }
        lastClick = point
    }

    override func keyPressed() {
        if key == "c" || key == "C" {
            picker.reset()
            lastClick = nil
        }
    }

    override func draw() {
        background(Color(white: 0.04))

        // The weights are fetched, not committed: point at the script instead
        // of failing silently when they aren't there yet.
        guard Self.modelPaths.allSatisfy(FileManager.default.fileExists(atPath:)) else {
            return drawStatus("The segmentation models aren't downloaded yet.\n" +
                              "Run Scripts/fetch-models.sh, then relaunch.",
                              style: .warning)
        }

        // The room, dimmed to a murmur; the picked thing gets the light.
        tint(Color(white: 0.3))
        guard let rect = drawFrame(camera) else { return noTint() }
        noTint()

        if let reason = picker.unavailableReason {
            return drawStatus(reason, style: .warning)
        }

        if let pick = picker.pick {
            // A cool halo from the matte, slightly enlarged, then the thing
            // itself at full color.
            let grow = 6 * scale
            tint(Color(red: 0.35, green: 0.8, blue: 1.0, alpha: 0.45))
            drawImage(pick.matte, in: Rectangle(x: rect.x - grow, y: rect.y - grow,
                                                width: rect.width + grow * 2,
                                                height: rect.height + grow * 2))
            noTint()
            drawImage(pick.cutout, in: rect)

            // Its bounds, framed.
            withState {
                noFill()
                stroke(Color(red: 0.35, green: 0.8, blue: 1.0, alpha: 0.8))
                strokeWeight(2 * scale)
                let box = pick.bounds(in: rect)
                drawRect(box.x, box.y, box.width, box.height)
            }
            drawCaption(String(format: "PointLift: confidence %.0f%%. " +
                               "Click picks, shift-click trims, C clears.",
                               pick.score * 100))
        } else {
            drawCaption("PointLift: click a thing to lift it out")
        }

        // A pulse where the click landed, while the model is thinking.
        if picker.isWorking, let click = lastClick {
            withState {
                noFill()
                stroke(Color(white: 1, alpha: 0.8))
                strokeWeight(2 * scale)
                let r = (8 + 6 * sin(time * 8)) * scale
                drawCircle(click.x, click.y, r)
            }
        }
    }
}
