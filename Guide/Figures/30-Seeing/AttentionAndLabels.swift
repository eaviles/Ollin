// figure: frame=0 themed
//
// Guide diagram (Chapter 30): the two trackers that read a picture as a whole,
// both run on one bundled photograph, a woman standing before a wall of
// marigolds. Left: the saliency heat map tinted over the picture, plus the
// region it peaks in. Right: what the classifier called the picture, every
// label it returned above a very low floor, so the tail below the default cut
// is visible. Both detections are the real Vision requests, run once on the
// still image.
import Ollin
import OllinDiagram
import OllinSamplePhotos
import OllinVision

final class AttentionAndLabels: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    /// The classifier's own default floor, drawn as a line so it can be seen.
    static let defaultFloor = 0.1
    /// The floor this figure asks for instead, low enough to show the tail.
    static let openFloor = 0.005
    /// Bar-chart scale: the longest bar a confidence can draw.
    static let fullScale = 1.0

    var scene: Image?
    var heat: Image?
    var regions: [Rectangle] = []
    var labels: [(name: String, confidence: Double)] = []

    @Param var darkTheme = false
    var theme: DiagramTheme { DiagramTheme(dark: darkTheme) }

    var paper: Color { theme.paper }
    var ink: Color { theme.ink }
    var faint: Color { theme.ink(0.28) }
    var soft: Color { theme.ink(0.6) }
    var accent: Color { theme.accent }

    let leftPanel = Rectangle(x: 60, y: 100, width: 360, height: 360)
    let rightPanel = Rectangle(x: 460, y: 100, width: 360, height: 360)

    override func setup() {
        let image = SamplePhoto.marigolds.load()
        scene = image

        if let saliency = try? waitFor(image, { try await SaliencyTracker.detect(in: $0) }) {
            heat = saliency.heatMap
            regions = saliency.regions.map { $0.bounds(in: leftPanel) }
        }

        // The floor is read out here on purpose: `waitFor` parks this thread,
        // so reading a property of the sketch from inside the closure would
        // wait on a thread that is already waiting.
        let floor = AttentionAndLabels.openFloor
        let found = (try? waitFor(image) {
            try await ImageClassifier.detect(in: $0, minConfidence: floor)
        }) ?? []
        labels = found.prefix(8).map { ($0.name, $0.confidence) }
    }

    override func draw() {
        background(paper)
        textFont(.systemMedium)
        textSize(19)

        if let scene { drawImage(scene, in: leftPanel) }
        // The picture is dimmed under the map so the warm parts read as heat
        // rather than as a haze over an already-bright card.
        noStroke()
        fill(Color(hex: 0x14141A, alpha: 0.6))
        drawRect(leftPanel)
        if let heat {
            // The map is white with salience in its alpha, so a tint turns it
            // into a glow over the picture underneath.
            tint(accent)
            drawImage(heat, in: leftPanel)
            noTint()
        }
        noFill()
        stroke(ink.withAlpha(0.8))
        strokeWeight(2)
        for region in regions { drawRect(region) }

        drawLabelChart()

        noFill()
        stroke(faint)
        strokeWeight(1.5)
        drawRect(leftPanel)

        noStroke()
        fill(ink)
        textAlign(.center, .top)
        drawText("where an eye would go", leftPanel.center.x, 472)
        drawText("what it says the picture is", rightPanel.center.x, 472)
        fill(soft)
        drawText("the dashed line is the confidence floor, below which labels are dropped",
                 width / 2, 512)
    }

    /// The labels as a bar chart, with the default floor marked.
    private func drawLabelChart() {
        let barLeft = rightPanel.x + 168.0
        let barWidth = 172.0
        let top = 128.0
        let step = 36.0
        textSize(17)

        for (i, label) in labels.enumerated() {
            let y = top + Double(i) * step
            noStroke()
            fill(ink)
            textAlign(.right, .center)
            drawText(label.name, barLeft - 12, y)

            let length = barWidth * min(1, label.confidence / AttentionAndLabels.fullScale)
            fill(label.confidence >= AttentionAndLabels.defaultFloor
                 ? accent : accent.withAlpha(0.35))
            drawRect(barLeft, y - 7, max(1.5, length), 14)

            fill(soft)
            textAlign(.left, .center)
            drawText("\(Int((label.confidence * 100).rounded()))%", barLeft + barWidth + 10, y)
        }

        // Where the default `minConfidence` would have cut the list.
        let floorX = barLeft + barWidth * (AttentionAndLabels.defaultFloor
                                           / AttentionAndLabels.fullScale)
        stroke(ink.withAlpha(0.5))
        strokeWeight(1.5)
        let bottom = top + Double(max(labels.count, 1) - 1) * step
        for y in stride(from: top - 22, to: bottom + 22, by: 10) {
            drawLine(floorX, y, floorX, y + 5)
        }
    }
}
