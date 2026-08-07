import Foundation
import Ollin
import OllinVision

/// Every pixel named and painted — a `ModelTracker` running a semantic-
/// segmentation model (DeepLabV3) over the live feed. Where `PersonSegmentation`
/// lifts *the people* and `ObjectDetection` draws *boxes*, this paints the
/// pixels themselves, one steady color per class: you in one color, the chair
/// in another, the sofa, the dog, the bottle each in theirs. A legend counts
/// what's in frame and the cursor reads the class under it. An honest caveat:
/// it's a dated research model at 513×513 — edges are coarse and it knows only
/// 21 everyday classes. The weights aren't in the repo — run
/// `Scripts/fetch-models.sh` once and relaunch (the sketch says so on the
/// canvas until then).
///
/// Model: DeepLabV3 (MobileNetV2 backbone) — Apple's Core ML conversion of the
/// TensorFlow research model (Apache-2.0) — downloaded by the fetch script,
/// never bundled. Provenance in THIRD-PARTY-NOTICES.md.
/// The fetched weights live in `Models/` at the repo root. This sketch runs both
/// from there (the gallery compiles it where it sits) and from `Examples/` (a
/// direct `swift run`), so the folder is found by walking up from this file
/// instead of trusting whatever the working directory happens to be.
private func modelsPath(_ name: String) -> String {
    var dir = (#filePath as NSString).deletingLastPathComponent
    while dir.count > 1 {
        let models = (dir as NSString).appendingPathComponent("Models")
        if FileManager.default.fileExists(atPath: models) {
            return (models as NSString).appendingPathComponent(name)
        }
        dir = (dir as NSString).deletingLastPathComponent
    }
    return ("Models" as NSString).appendingPathComponent(name)
}

@main
final class PaintByClass: Sketch {
    static let modelPath = modelsPath("DeepLabV3FP16.mlmodel")

    let camera = Camera()
    lazy var segmenter = ModelTracker(camera, modelAt: URL(fileURLWithPath: Self.modelPath))

    /// Below this share of the picture a class is probably noise.
    let coverageFloor = 0.002

    override func setup() {
        try? camera.start()
    }

    override func draw() {
        background(Color(white: 0.04))

        // The weights are fetched, not committed — point at the script instead
        // of failing silently when they aren't there yet.
        guard FileManager.default.fileExists(atPath: Self.modelPath) else {
            return drawStatus("The segmentation model isn't downloaded yet.\n" +
                              "Run Scripts/fetch-models.sh, then relaunch.",
                              style: .warning)
        }

        // While a notice sits over the feed, dim the feed so the text reads.
        let showsNotice = segmenter.unavailableReason != nil || !segmenter.isLoaded
        if showsNotice { tint(Color(white: 0.25)) }
        guard let rect = drawFrame(camera) else { return noTint() }
        noTint()

        if let reason = segmenter.unavailableReason {
            return drawStatus(reason, style: .warning)
        }
        if !segmenter.isLoaded {
            return drawStatus("Loading the segmentation model…\n" +
                              "The first run prepares it for this Mac; " +
                              "after that it starts instantly.")
        }
        guard let classes = segmenter.classMask else { return }

        // The paint: each class's pixels under its own translucent color.
        // Class 0 is the model's background — leave it as the picture.
        let present = classes.presentClasses.filter {
            $0 != 0 && classes.coverage(ofClass: $0) >= coverageFloor
        }
        for index in present {
            if let mask = classes.mask(ofClass: index) {
                tint(paint(for: index, alpha: 0.6))
                drawImage(mask, in: rect)
            }
        }
        noTint()

        // The legend: what's in frame and how much of the picture it fills.
        textSize(17 * scale)
        textAlign(.left, .middle)
        let line = 30 * scale
        var y = rect.y + line
        for index in present {
            let name = classes.labels.indices.contains(index)
                ? classes.labels[index] : "class \(index)"
            noStroke()
            fill(paint(for: index, alpha: 1))
            drawCircle(rect.x + line, y, 8 * scale)
            fill(.white)
            drawText("\(name)  \(Int(classes.coverage(ofClass: index) * 100))%",
                     rect.x + line + 18 * scale, y)
            y += line
        }

        // The cursor reads the class under it.
        let cursor = Vector2(mouseX, mouseY)
        let pointed = rect.contains(cursor) ? classes.label(at: cursor, in: rect) : nil
        drawCaption(pointed.map { "PaintByClass — under the cursor: \($0)" }
            ?? "PaintByClass — every pixel named: sit in frame with the everyday things it knows")
    }

    /// One steady, vivid color per class index, frame after frame — equal
    /// lightness and chroma in OKLCH, hues spread by the golden ratio so
    /// neighboring class indices land far apart on the wheel.
    private func paint(for index: Int, alpha: Double) -> Color {
        let hue = (Double(index) * 0.618034).truncatingRemainder(dividingBy: 1)
        var color = Color(OKLCH(l: 0.72, c: 0.17, h: hue))
        color.alpha = alpha
        return color
    }
}
