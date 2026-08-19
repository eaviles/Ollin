// figure: frame=0
//
// Guide diagram (Chapter 30): two classical detectors reading a made-up scene.
// Left: a printed card lying at an angle on a speckled desk, built pixel by
// pixel (the type is Ollin's own glyph outlines, rasterized into the picture,
// so the figure needs no photograph). Right: the quad RectangleDetector found,
// its four corners in perspective, and the boxes TextRecognizer put around the
// lines it read. The right-hand label is built from the words that came back,
// so the figure states its own result. Both detections are the real Vision
// requests, run once on the still image.
import Ollin
import OllinVision

final class ReadingACard: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    static let sceneSize = 320
    static let tiltAngle = 0.12

    var scene: Image?
    var card: [Vector2] = []
    var lines: [(text: String, box: Rectangle)] = []

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
        let sub = tilted(textToShapes("chapter 30", 0, 0), centeredOn: Vector2(160, 188))

        let image = ReadingACard.render(glyphs: title + sub)
        scene = image

        // One detector finds the card, the other reads what is printed on it.
        let found = (try? waitFor(image) { try await RectangleDetector.detect(in: $0) }) ?? []
        card = found.first?.corners(in: rightPanel) ?? []

        let read = (try? waitFor(image) { try await TextRecognizer.detect(in: $0) }) ?? []
        lines = read
            .map { ($0.text, $0.bounds(in: rightPanel)) }
            .sorted { $0.box.y < $1.box.y }
    }

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        textFont(.systemMedium)
        textSize(19)

        if let scene {
            drawImage(scene, in: leftPanel)
            drawImage(scene, in: rightPanel)
        }

        // The card's four corners, in the perspective the detector reported.
        if card.count == 4 {
            noFill()
            stroke(accent)
            strokeWeight(2.5)
            drawPolygon(card)
            noStroke()
            fill(accent)
            for corner in card { drawCircle(center: corner, radius: 5) }
        }

        // A box around each line of text it read.
        noFill()
        stroke(ink.withAlpha(0.75))
        strokeWeight(1.5)
        for line in lines { drawRect(line.box) }

        stroke(faint)
        drawRect(leftPanel)
        drawRect(rightPanel)

        noStroke()
        fill(ink)
        textAlign(.center, .top)
        drawText("a printed card on a desk", leftPanel.center.x, 472)
        drawText(readBack(), rightPanel.center.x, 472)
        fill(soft)
        drawText("one detector found the card, another read the words inside it",
                 width / 2, 512)
    }

    /// The right-hand label, written from what the reader actually returned.
    private func readBack() -> String {
        guard !lines.isEmpty else { return "nothing read" }
        return "it read " + lines.map { "\"\($0.text)\"" }.joined(separator: " and ")
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
            shape.mapPoints { ReadingACard.tilt($0 + offset) }
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

    /// Fill one glyph outline, four samples per pixel so the letter edges are
    /// smooth enough for the reader to make them out.
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
