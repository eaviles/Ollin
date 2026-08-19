// figure: frame=420
//
// Guide payoff (Chapter 22): motion paints. Optical flow measures how the
// picture in front of the camera moved since the last frame, and wherever it
// moved, a brush lays down a stroke colored by the direction. The "camera"
// here is StagePerformer, the chapter's pretend dancer (two textured hands
// waving through a dark frame, measured by the real Vision flow request), so
// the figure renders the same everywhere. Live, swap it for a webcam:
// FlowTracker(Camera()) publishes the same field, frame after frame.
import Ollin
import OllinVision

final class MotionBrush: Sketch {
    let performer = StagePerformer()

    override func setup() {
        seed(21)                    // the brush dabs land the same way every run
        noClear()
        background(Color(hex: 0x0A0A14))
    }

    override func draw() {
        // A faint veil each frame, so old strokes sink slowly into the dark.
        noStroke()
        fill(Color(hex: 0x0A0A14, alpha: 0.007))
        drawRect(0, 0, width, height)

        // Live version: `flow.field` from a FlowTracker on a Camera.
        guard let field = performer.step() else { return }

        // Fling brushes at random spots; paint only where the picture moved.
        for _ in 0 ..< 900 {
            let p = Vector2(random(0, width), random(0, height))
            let v = field.vector(at: p, in: bounds)
            let strength = v.length
            guard strength > 4 else { continue }
            let hue = v.angle / .tau + 0.5              // direction picks the color
            stroke(Color(hue: hue, saturation: 0.75, brightness: 1)
                .withAlpha(min(0.5, strength * 0.02)))
            strokeWeight((1.2 + min(5, strength * 0.07)) * scale)
            drawLine(p, p + v.limited(to: 110 * scale) * 3)
        }
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
