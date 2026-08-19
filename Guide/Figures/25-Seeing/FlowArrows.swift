// figure: frame=156
//
// Guide diagram (Chapter 25): optical flow as a field of arrows. Left: one
// frame from the pretend performer (two speckled hands on a dim speckled
// backdrop). Right: the same frame with the measured flow drawn on top, one
// arrow per grid sample, pointing the way the picture moved since the frame
// before. The field is measured by the real Vision request.
import Ollin
import OllinVision

final class FlowArrows: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    let performer = StagePerformer()
    var field: MotionField?
    var picture: Image?

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.28)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.6)
    let accent = Color(hex: 0xE4572E)

    override func draw() {
        field = performer.step()
        picture = performer.lastFrame

        background(Color(hex: 0xF7F5F1))
        textSize(19)

        let leftPanel = Rectangle(x: 60, y: 100, width: 360, height: 360)
        let rightPanel = Rectangle(x: 460, y: 100, width: 360, height: 360)

        if let picture {
            drawImage(picture, in: leftPanel)
            drawImage(picture, in: rightPanel)
        }

        if let field {
            stroke(accent)
            for sample in field.samples(in: rightPanel, every: 14) {
                let v = sample.flow
                guard v.length > 0.5 else { continue }
                let tip = sample.position + v.limited(to: 4) * 12
                strokeWeight(2)
                drawLine(sample.position, tip)
                let dir = (tip - sample.position).normalized
                drawLine(tip, tip - dir * 6 + dir.perpendicular * 4)
                drawLine(tip, tip - dir * 6 - dir.perpendicular * 4)
            }
        }

        noFill()
        stroke(faint)
        strokeWeight(1.5)
        drawRect(leftPanel)
        drawRect(rightPanel)

        noStroke()
        fill(ink)
        textAlign(.center, .top)
        drawText("what the camera sees", leftPanel.center.x, 472)
        drawText("how it moved since the frame before", rightPanel.center.x, 472)
        fill(soft)
        drawText("a direction and a speed at every point: Chapter 12's field, measured from the world",
                 width / 2, 512)
    }
}

/// A pretend performer for a guide that can't film you: two speckled "hands"
/// wave along looping paths in a small dark frame, and each new frame is
/// measured against the previous one with the real Vision optical-flow
/// request. `step()` returns the same `MotionField` a live `FlowTracker`
/// publishes; only the camera has been replaced.
final class StagePerformer {
    private let size = 240
    private var previous: Image?
    private var frame = 0

    /// The most recent synthesized frame, for drawing beside the field.
    private(set) var lastFrame: Image?

    /// Advance the dance one frame and measure how the picture moved.
    func step() -> MotionField? {
        let t = Double(frame) / 60
        frame += 1
        let current = render(t: t)
        lastFrame = current
        defer { previous = current }
        guard let previous else { return nil }
        return StagePerformer.measureFlow(from: previous, to: current)
    }

    /// Draw the two hands into a small CPU pixel buffer. Each hand carries a
    /// speckle texture that moves with it, so the flow request has something
    /// to grab onto (motion is only measurable where the picture has texture).
    private func render(t: Double) -> Image {
        let n = size
        var bytes = [UInt8](repeating: 0, count: n * n * 4)
        let hands = [
            Vector2(120 + sin(t * 0.9) * 74, 120 + sin(t * 1.4 + 1.1) * 62),
            Vector2(120 + sin(t * 1.1 + 2.6) * 68, 120 + cos(t * 0.7) * 70),
        ]
        for y in 0 ..< n {
            for x in 0 ..< n {
                // A dim, static speckle: flow needs texture even where nothing
                // moves, or the empty background reads as noise.
                var value = 14.0 + 14.0 * Self.hash(x / 2, y / 2)
                for hand in hands {
                    let dx = Double(x) - hand.x
                    let dy = Double(y) - hand.y
                    let d = (dx * dx + dy * dy).squareRoot()
                    guard d < 26 else { continue }
                    let falloff = 1 - d / 26
                    let speckle = 0.55 + 0.45 * Self.hash(Int(dx / 3), Int(dy / 3))
                    value = max(value, 235 * falloff * speckle)
                }
                let i = (y * n + x) * 4
                let v = UInt8(min(255, value))
                bytes[i] = v; bytes[i + 1] = v; bytes[i + 2] = v; bytes[i + 3] = 255
            }
        }
        return Image(width: n, height: n, premultipliedRGBA: bytes)!
    }

    private static func hash(_ x: Int, _ y: Int) -> Double {
        var h = UInt64(truncatingIfNeeded: x &* 374_761_393 &+ y &* 668_265_263)
        h = (h ^ (h >> 13)) &* 1_274_126_177
        return Double((h ^ (h >> 16)) % 1000) / 999
    }

    /// Run the one-shot flow measurement and wait for it, so a figure renders
    /// deterministically frame by frame.
    private static func measureFlow(from a: Image, to b: Image) -> MotionField? {
        try? waitFor(a, b) { try await FlowTracker.flow(from: $0, to: $1, accuracy: .high) }
    }
}
