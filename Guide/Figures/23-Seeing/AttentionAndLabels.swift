// figure: frame=0
//
// Guide diagram (Chapter 23): the two trackers that read a picture as a whole,
// both run on the same made-up card scene as the reading figure. Left: the
// saliency heat map tinted over the picture, plus the region it peaks in.
// Right: what the classifier called the picture, every label it returned above
// a very low floor, so the tail below the default cut is visible. Both
// detections are the real Vision requests, run once on the still image.
import Ollin
import OllinVision

final class AttentionAndLabels: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    static let sceneSize = 320
    static let tiltAngle = 0.12

    /// The classifier's own default floor, drawn as a line so it can be seen.
    static let defaultFloor = 0.1
    /// The floor this figure asks for instead, low enough to show the tail.
    static let openFloor = 0.005
    /// Bar-chart scale: the longest bar a confidence can draw.
    static let fullScale = 0.2

    var scene: Image?
    var heat: Image?
    var regions: [Rectangle] = []
    var labels: [(name: String, confidence: Double)] = []

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.28)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.6)
    let accent = Color(hex: 0xE4572E)

    let leftPanel = Rectangle(x: 60, y: 100, width: 360, height: 360)
    let rightPanel = Rectangle(x: 460, y: 100, width: 360, height: 360)

    override func setup() {
        textFont(.systemMedium)
        textSize(40)
        let title = tilted(textToShapes("SEEING", 0, 0), centeredOn: Vector2(160, 132))
        textSize(22)
        let sub = tilted(textToShapes("chapter 21", 0, 0), centeredOn: Vector2(160, 188))

        let image = AttentionAndLabels.render(glyphs: title + sub)
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
            try await ImageClassifier.detect(in: $0, minimumConfidence: floor)
        }) ?? []
        labels = found.prefix(8).map { ($0.name, $0.confidence) }
    }

    override func draw() {
        background(Color(hex: 0xF7F5F1))
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

        // Where the default `minimumConfidence` would have cut the list.
        let floorX = barLeft + barWidth * (AttentionAndLabels.defaultFloor
                                           / AttentionAndLabels.fullScale)
        stroke(ink.withAlpha(0.5))
        strokeWeight(1.5)
        let bottom = top + Double(max(labels.count, 1) - 1) * step
        for y in stride(from: top - 22, to: bottom + 22, by: 10) {
            drawLine(floorX, y, floorX, y + 5)
        }
    }

    // MARK: The made-up scene

    /// Re-center a run of glyph outlines on a point, then tilt them with the card.
    private func tilted(_ shapes: [Shape], centeredOn target: Vector2) -> [Shape] {
        var lo = Vector2(1e9, 1e9), hi = Vector2(-1e9, -1e9)
        for shape in shapes {
            for contour in shape.contours {
                for p in contour.points {
                    lo = Vector2(min(lo.x, p.x), min(lo.y, p.y))
                    hi = Vector2(max(hi.x, p.x), max(hi.y, p.y))
                }
            }
        }
        let offset = target - (lo + hi) * 0.5
        return shapes.map { shape in
            shape.mapPoints { AttentionAndLabels.tilt($0 + offset) }
        }
    }

    /// Turn a point about the middle of the scene, the tilt the card lies at.
    static func tilt(_ p: Vector2) -> Vector2 {
        let pivot = Vector2(Double(sceneSize) / 2, Double(sceneSize) / 2)
        let q = p - pivot
        return pivot + Vector2(q.x * cos(tiltAngle) - q.y * sin(tiltAngle),
                               q.x * sin(tiltAngle) + q.y * cos(tiltAngle))
    }

    /// The card's four corners in the scene's own pixels.
    static func cardCorners() -> [Vector2] {
        [Vector2(50, 85), Vector2(272, 85), Vector2(272, 235), Vector2(50, 235)].map(tilt)
    }

    /// Paint the scene: a speckled desk, a bright card lying on it, and the
    /// glyph outlines filled in as ink.
    static func render(glyphs: [Shape]) -> Image {
        let n = sceneSize
        var bytes = [UInt8](repeating: 255, count: n * n * 4)
        for y in 0 ..< n {
            for x in 0 ..< n {
                let v = 96 + 22 * hash(x / 2, y / 2)
                let i = (y * n + x) * 4
                bytes[i] = UInt8(v)
                bytes[i + 1] = UInt8(v * 0.97)
                bytes[i + 2] = UInt8(v * 0.92)
            }
        }
        let corners = cardCorners()
        for y in 0 ..< n {
            for x in 0 ..< n {
                guard inside(Vector2(Double(x) + 0.5, Double(y) + 0.5), corners) else { continue }
                let i = (y * n + x) * 4
                bytes[i] = 246; bytes[i + 1] = 244; bytes[i + 2] = 238
            }
        }
        for shape in glyphs { fill(shape, into: &bytes, size: n) }
        return Image(width: n, height: n, premultipliedRGBA: bytes)!
    }

    /// Fill one glyph outline, four samples per pixel so the letter edges stay
    /// smooth.
    private static func fill(_ shape: Shape, into bytes: inout [UInt8], size n: Int) {
        var lo = Vector2(1e9, 1e9), hi = Vector2(-1e9, -1e9)
        for contour in shape.contours {
            for p in contour.points {
                lo = Vector2(min(lo.x, p.x), min(lo.y, p.y))
                hi = Vector2(max(hi.x, p.x), max(hi.y, p.y))
            }
        }
        let x0 = max(0, Int(lo.x) - 1), x1 = min(n - 1, Int(hi.x) + 1)
        let y0 = max(0, Int(lo.y) - 1), y1 = min(n - 1, Int(hi.y) + 1)
        guard x0 <= x1, y0 <= y1 else { return }
        for y in y0 ... y1 {
            for x in x0 ... x1 {
                var hits = 0.0
                for sy in 0 ..< 2 {
                    for sx in 0 ..< 2 {
                        let p = Vector2(Double(x) + 0.25 + Double(sx) * 0.5,
                                        Double(y) + 0.25 + Double(sy) * 0.5)
                        if shape.contains(p) { hits += 1 }
                    }
                }
                guard hits > 0 else { continue }
                let coverage = hits / 4
                let i = (y * n + x) * 4
                for channel in 0 ..< 3 {
                    bytes[i + channel] = UInt8(Double(bytes[i + channel]) * (1 - coverage)
                                               + 34 * coverage)
                }
            }
        }
    }

    /// Point inside a convex quad, by the sign of the edge cross products.
    private static func inside(_ p: Vector2, _ quad: [Vector2]) -> Bool {
        for i in 0 ..< quad.count {
            let a = quad[i], b = quad[(i + 1) % quad.count]
            if (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x) < 0 { return false }
        }
        return true
    }

    private static func hash(_ x: Int, _ y: Int) -> Double {
        var h = UInt64(truncatingIfNeeded: x &* 374_761_393 &+ y &* 668_265_263)
        h = (h ^ (h >> 13)) &* 1_274_126_177
        return Double((h ^ (h >> 16)) % 1000) / 999
    }
}
