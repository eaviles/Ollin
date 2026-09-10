// figure: frame=420
//
// Guide payoff (Chapter 30): motion paints. Optical flow measures how the
// picture in front of the camera moved since the last frame, and wherever it
// moved, a brush lays down a stroke colored by the direction. The camera here
// is the film that ships with Ollin, a dancer on a plain ground shot from a
// fixed tripod, stepped one frame at a time so the figure renders the same
// everywhere. Live, swap it for a webcam: FlowTracker(Camera()) publishes the
// same field, frame after frame.
import Ollin
import OllinSamplePhotos
import OllinVideo
import OllinVision

final class MotionBrush: Sketch {
    let performer = StageFilm()

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

        // How far a picture moves between two frames depends on what it is: a
        // hand waved at a webcam crosses tens of pixels, a dancer a few. So the
        // brush reads speed against this frame's own fastest sample, floored so
        // that a frame where nothing moved neither divides by zero nor paints
        // the sensor's noise.
        let fastest = max(field.samples(in: bounds, every: 40).map(\.flow.length).max() ?? 0, 0.001)
        let cut = max(fastest * 0.22, 3)

        // Fling brushes at random spots; paint only where the picture moved.
        for _ in 0 ..< 900 {
            let p = Vector2(random(0, width), random(0, height))
            let v = field.vector(at: p, in: bounds)
            let strength = v.length
            guard strength > cut else { continue }
            let hue = v.angle / .tau + 0.5              // direction picks the color
            stroke(Color(hue: hue, saturation: 0.75, brightness: 1)
                .withAlpha(min(0.5, strength / fastest * 0.3)))
            strokeWeight((1.2 + strength / fastest * 4) * scale)
            drawLine(p, p + v * (36 * scale / fastest))
        }
    }
}

/// A performer for a guide that can't film you: the bundled film, stepped one
/// of its own frames at a time and measured against the frame before with the
/// real Vision optical-flow request. `step()` returns the same `MotionField` a
/// live `FlowTracker` publishes; only the camera has been replaced.
@MainActor
final class StageFilm {
    private let clip = VideoPlayer(url: SampleClip.dance.url)
    private var previous: Image?
    private var frame = 0

    /// The most recent frame of the film, for drawing beside the field.
    private(set) var lastFrame: Image?

    init() { clip.isMuted = true }

    /// Advance the dance one frame and measure how the picture moved.
    func step() -> MotionField? {
        clip.seek(to: Double(frame) / 25)      // the film runs at 25 a second
        frame += 1
        guard let current = clip.snapshot() else { return nil }
        lastFrame = current
        defer { previous = current }
        guard let previous else { return nil }
        return StageFilm.measureFlow(from: previous, to: current)
    }

    /// Run the one-shot flow measurement and wait for it, so a figure renders
    /// deterministically frame by frame.
    private static func measureFlow(from a: Image, to b: Image) -> MotionField? {
        try? waitFor(a, b) { try await FlowTracker.detect(from: $0, to: $1, quality: .high) }
    }
}
