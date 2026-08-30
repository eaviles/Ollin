import Foundation
import Ollin
import OllinVision

/// Typed phrases as live knobs: two phrases pull on one rope. A
/// `ConceptTracker` embeds the camera frame and both phrases in one shared
/// space, and each phrase's share of the picture pulls the knot its way.
/// Point the camera at what one phrase describes and watch it win; rewrite
/// either phrase in the inspector (press ⌘/) and the rope re-anchors to
/// whatever you typed. The model weights aren't in the repo: run
/// `Scripts/fetch-models.sh` once and relaunch (the sketch says so on the
/// canvas until then).
///
/// Model: MobileCLIP-S0, Apple's official Core ML export of the paired
/// image and text encoders (Pavan Kumar Anasosalu Vasu et al., CVPR 2024),
/// under Apple's permissive weights license,
/// https://huggingface.co/apple/coreml-mobileclip (downloaded by the fetch
/// script, never bundled). The tokenizer vocabulary is OpenAI's CLIP merges
/// file (MIT), https://github.com/openai/CLIP, fetched by the same script.

/// The fetched weights live in `Models/` at the repo root. This sketch runs
/// both from there (the gallery compiles it where it sits) and from
/// `Examples/` (a direct `swift run`), so the folder is found by walking up
/// from this file instead of trusting the working directory.
private func modelsPath(_ name: String) -> String {
    sketchResource(name) ?? ("Models" as NSString).appendingPathComponent(name)
}

@main
final class TugOfWords: Sketch {
    static let imageModelPath = modelsPath("mobileclip_s0_image.mlpackage")
    static let textModelPath = modelsPath("mobileclip_s0_text.mlpackage")
    static let vocabPath = modelsPath("bpe_simple_vocab_16e6.txt")

    @Param(icon: "text.bubble", group: "Phrases") var left = "a person smiling at the camera"
    @Param(icon: "text.bubble.fill", group: "Phrases") var right = "an empty room"

    let camera = Camera()
    lazy var ideas = ConceptTracker(
        camera,
        imageModelAt: URL(fileURLWithPath: Self.imageModelPath),
        textModelAt: URL(fileURLWithPath: Self.textModelPath),
        vocabularyAt: URL(fileURLWithPath: Self.vocabPath),
        concepts: [left, right])

    /// Where the knot sits, `0…1` left-to-right, eased so it slides rather
    /// than pops.
    var knot = 0.5

    let leftColor = Color(red: 0.72, green: 0.45, blue: 1.0, alpha: 1)
    let rightColor = Color(red: 1.0, green: 0.72, blue: 0.25, alpha: 1)

    override func setup() {
        try? camera.start()
    }

    override func draw() {
        background(Color(white: 0.04))

        // The weights are fetched, not committed; point at the script instead
        // of failing silently when they aren't there yet.
        let missing = [Self.imageModelPath, Self.textModelPath, Self.vocabPath]
            .filter { !FileManager.default.fileExists(atPath: $0) }
        guard missing.isEmpty else {
            return drawStatus("The phrase-scoring models aren't downloaded yet.\n" +
                              "Run Scripts/fetch-models.sh, then relaunch.",
                              style: .warning)
        }

        // A rewritten phrase joins the set here; only a phrase the tracker
        // hasn't seen before costs a text-encoder run.
        ideas.concepts = [left, right]

        let margin = 24 * scale
        let videoArea = Rectangle(x: margin, y: margin,
                                  width: width - margin * 2, height: height * 0.62)
        guard let rect = drawFrame(camera, in: videoArea) else { return }

        if let reason = ideas.unavailableReason {
            return drawStatus(reason, style: .warning,
                              in: Rectangle(x: 0, y: height * 0.7, width: width, height: height * 0.2))
        }

        // Shares over the two phrases (they sum to 1 once both encodings have
        // landed); ease the knot toward the left phrase's share.
        let leftShare = ideas.confidence(of: left)
        let rightShare = ideas.confidence(of: right)
        let scored = leftShare + rightShare > 0
        if scored {
            let target = leftShare / (leftShare + rightShare)
            knot += (target - knot) * min(1, deltaTime * 5)
        }

        // Side washes: the winning side's color creeps in from its edge.
        noStroke()
        fill(leftColor.withAlpha(max(0, knot - 0.5)))
        drawRect(0, 0, margin, height)
        fill(rightColor.withAlpha(max(0, 0.5 - knot)))
        drawRect(width - margin, 0, margin, height)

        // The rope, anchored under the feed.
        let ropeY = rect.y + rect.height + height * 0.14
        let ropeLeft = margin * 3
        let ropeRight = width - margin * 3
        stroke(Color(white: 0.3)); strokeWeight(6 * scale)
        drawLine(ropeLeft, ropeY, ropeRight, ropeY)

        // Each side's half, inked in its color, weighted by its pull.
        let knotX = ropeLeft + (ropeRight - ropeLeft) * knot
        strokeWeight(10 * scale)
        stroke(leftColor); drawLine(ropeLeft, ropeY, knotX, ropeY)
        stroke(rightColor); drawLine(knotX, ropeY, ropeRight, ropeY)
        noStroke()
        fill(.white)
        drawCircle(knotX, ropeY, 16 * scale)

        // While nothing is scored yet, say which wait this is.
        if !scored {
            fill(Color(white: 0.45))
            textAlign(.center, .middle)
            textSize(19 * scale)
            drawText(ideas.isLoaded ? "Scoring the first frame…"
                                    : "Loading the models (the first-ever run takes a few seconds)…",
                     width / 2, ropeY - 44 * scale)
        }

        // The phrases at their anchors, each scaled a little by its pull.
        textAlign(.left, .top)
        textSize((17 + knot * 8) * scale)
        fill(leftColor)
        drawText(left, ropeLeft, ropeY + 28 * scale)
        textAlign(.right, .top)
        textSize((17 + (1 - knot) * 8) * scale)
        fill(rightColor)
        drawText(right, ropeRight, ropeY + 28 * scale)

        // The shares as percentages, and under them the raw cosine that
        // `similarity(of:)` reads, for mapping the space yourself.
        textSize(15 * scale)
        fill(Color(white: 0.65))
        textAlign(.left, .top)
        drawText(scored ? "\(Int((leftShare * 100).rounded()))%   cos \(String(format: "%.2f", ideas.similarity(of: left)))" : "…",
                 ropeLeft, ropeY + 70 * scale)
        textAlign(.right, .top)
        drawText(scored ? "\(Int((rightShare * 100).rounded()))%   cos \(String(format: "%.2f", ideas.similarity(of: right)))" : "…",
                 ropeRight, ropeY + 70 * scale)

        drawCaption("TugOfWords: two phrases pull on what the camera sees")
    }
}
