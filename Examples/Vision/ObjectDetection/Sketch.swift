import Foundation
import Ollin
import OllinVision

/// Objects found, boxed, and named in the live feed — a `ModelTracker` running
/// an object-detection model (YOLOv3-tiny). Where `SceneLabels` names the whole
/// picture, a detector answers *where* and *how many*: one labeled box per
/// thing it can name. Hold up a cup, a book, a phone — or step into frame
/// yourself. An honest caveat: it's a small, dated model that misses small or
/// far objects and knows only 80 everyday classes — the example shows the
/// `objects` surface, not the state of the art. The weights aren't in the
/// repo — run `Scripts/fetch-models.sh` once and relaunch (the sketch says so
/// on the canvas until then).
///
/// Model: YOLOv3-tiny (the FP16 variant) — Apple's Core ML conversion of
/// Joseph Redmon and Ali Farhadi's Darknet original (YOLO License v2, public
/// domain) — downloaded by the fetch script, never bundled. Provenance in
/// THIRD-PARTY-NOTICES.md.
/// The fetched weights live in `Models/` at the repo root. This sketch runs both
/// from there (the gallery compiles it where it sits) and from `Examples/` (a
/// direct `swift run`), so the folder is found by walking up from this file
/// instead of trusting whatever the working directory happens to be.
private func modelsPath(_ name: String) -> String {
    sketchResource(name) ?? ("Models" as NSString).appendingPathComponent(name)
}

@main
final class ObjectDetection: Sketch {
    static let modelPath = modelsPath("YOLOv3TinyFP16.mlmodel")

    let camera = Camera()
    lazy var detector = ModelTracker(camera, modelAt: URL(fileURLWithPath: Self.modelPath))

    /// Below this the model is guessing more often than seeing.
    let confidenceFloor = 0.45

    /// One steady color per class name, so a person stays one color while a cup
    /// stays another as boxes come and go.
    let tagColors = Palette.set2

    override func setup() {
        try? camera.start()
    }

    override func draw() {
        background(Color(white: 0.04))

        // The weights are fetched, not committed — point at the script instead
        // of failing silently when they aren't there yet.
        guard FileManager.default.fileExists(atPath: Self.modelPath) else {
            return drawStatus("The detector model isn't downloaded yet.\n" +
                              "Run Scripts/fetch-models.sh, then relaunch.",
                              style: .warning)
        }

        // While a notice sits over the feed, dim the feed so the text reads.
        let showsNotice = detector.unavailableReason != nil || !detector.isLoaded
        if showsNotice { tint(Color(white: 0.25)) }
        guard let rect = drawFrame(camera) else { return noTint() }
        noTint()

        if let reason = detector.unavailableReason {
            return drawStatus(reason, style: .warning)
        }
        if !detector.isLoaded {
            return drawStatus("Loading the detector…\n" +
                              "The first run prepares it for this Mac; " +
                              "after that it starts instantly.")
        }

        let found = detector.objects.filter { $0.confidence >= confidenceFloor }
        textSize(17 * scale)
        for object in found {
            let box = object.bounds(in: rect)
            let accent = tagColors[colorIndex(of: object.label)]

            noFill()
            stroke(accent)
            strokeWeight(3 * scale)
            drawRect(box)

            // The name tag, sitting on the box's top edge (inside the frame).
            let title = "\(object.label)  \(Int(object.confidence * 100))%"
            let pad = 8 * scale
            let tagHeight = 28 * scale
            let tagY = max(rect.y, box.y - tagHeight)
            noStroke()
            fill(accent)
            drawRect(box.x, tagY, textWidth(title) + pad * 2, tagHeight)
            fill(.black)
            textAlign(.left, .middle)
            drawText(title, box.x + pad, tagY + tagHeight / 2)
        }

        drawCaption(found.isEmpty
            ? "ObjectDetection — show it a cup, a book, a phone, yourself…"
            : "ObjectDetection — \(summary(of: found))")
    }

    /// A stable palette slot per class name (the wrapping subscript takes care
    /// of the range).
    private func colorIndex(of label: String) -> Int {
        label.unicodeScalars.reduce(0) { $0 &* 31 &+ Int($1.value) }
    }

    /// "2× person, cup" — what's in frame, grouped and counted.
    private func summary(of objects: [Detection]) -> String {
        var counts: [String: Int] = [:]
        for object in objects { counts[object.label, default: 0] += 1 }
        return counts.sorted { $0.value > $1.value }
            .map { $0.value > 1 ? "\($0.value)× \($0.key)" : $0.key }
            .joined(separator: ", ")
    }
}
