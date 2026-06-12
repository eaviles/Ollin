import Ollin
import OllinVision

/// What the camera sees, named: an `ImageClassifier` reads each frame against
/// its ~1,300-label vocabulary and the strongest labels race as animated bars —
/// hold up a mug, a plant, a phone, and watch the picture get re-described.
/// No boxes or positions, just *what's in the picture* and how confidently.
@main
final class SceneLabels: Sketch {
    let camera = Camera()
    lazy var classifier = ImageClassifier(camera)

    /// Displayed confidence per label, eased toward the live values so bars
    /// grow, shrink, and fade instead of popping.
    var shown: [String: Double] = [:]

    override func setup() {
        try? camera.start()
    }

    override func draw() {
        background(Color(white: 0.04))

        // The feed up top, the label bars in the band below it.
        let margin = 24 * scale
        let videoArea = Rectangle(x: margin, y: margin,
                                  width: width - margin * 2, height: height * 0.56)
        guard let rect = drawFrame(camera, in: videoArea) else { return }

        // If the model can't run on this Mac (no compute device), say so on the
        // canvas instead of silently never naming anything — in the bar band,
        // under the feed.
        if let reason = classifier.unavailableReason {
            return drawStatus(reason, style: .warning,
                              in: Rectangle(x: 0, y: height * 0.6, width: width, height: height * 0.3))
        }

        // Ease every displayed value toward its live confidence (labels that
        // dropped out ease toward zero, then leave).
        let live = Dictionary(uniqueKeysWithValues: classifier.labels.map { ($0.label, $0.confidence) })
        let blend = min(1, deltaTime * 6)
        for label in Set(shown.keys).union(live.keys) {
            let target = live[label] ?? 0
            let value = (shown[label] ?? 0) + (target - (shown[label] ?? 0)) * blend
            shown[label] = (target == 0 && value < 0.004) ? nil : value
        }

        // The six strongest, as pill bars colored by confidence.
        let bars = shown.sorted { $0.value > $1.value }.prefix(6)
        let barArea = Rectangle(x: margin, y: rect.y + rect.height + 36 * scale,
                                width: width - margin * 2, height: 0)
        let rowHeight = 48 * scale, rowGap = 14 * scale
        textSize(19 * scale)

        for (i, (label, value)) in bars.enumerated() {
            let y = barArea.y + Double(i) * (rowHeight + rowGap)

            fill(Color(white: 0.12))
            drawRect(barArea.x, y, barArea.width, rowHeight, cornerRadius: rowHeight / 2)

            let fillWidth = max(rowHeight, value * barArea.width)
            fill(Colormap.turbo.color(at: 0.15 + value * 0.7))
            drawRect(barArea.x, y, fillWidth, rowHeight, cornerRadius: rowHeight / 2)

            fill(.white)
            textAlign(.left, .middle)
            drawText(label.replacingOccurrences(of: "_", with: " "),
                     barArea.x + rowHeight * 0.6, y + rowHeight / 2)
            fill(Color(white: 0.65))
            textAlign(.right, .middle)
            drawText("\(Int((value * 100).rounded()))%",
                     barArea.x + barArea.width - rowHeight * 0.5, y + rowHeight / 2)
        }

        if bars.isEmpty {
            fill(Color(white: 0.45))
            textAlign(.center, .middle)
            drawText("Nothing recognized yet — show it something",
                     width / 2, barArea.y + 60 * scale)
        }

        drawCaption("SceneLabels — the picture, named live")
    }
}
