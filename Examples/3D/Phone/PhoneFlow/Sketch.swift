import Foundation
import Ollin
import OllinPhone

/// How the phone's picture is moving, live from a tethered iPhone: the camera
/// frame dimmed to a backdrop, the motion field over it as a grid of streaks
/// colored by speed, and a drift of dust that rides the field. Wave a hand in
/// front of the rear camera and the dust scatters; hold still and it settles.
///
/// Setup: install **Ollin Capture** on an iPhone, launch it, tap **Flow** (rear
/// camera), and connect the cable. The connection retries on its own, so
/// tapping the mode (or plugging in) after this sketch is already running just
/// begins the feed. Needs no LiDAR.
///
/// The field reads the way the Mac's own optical-flow tracker's field reads,
/// through the same `MotionField`: `samples(in:every:)` lays the streaks and
/// `vector(at:in:)` pushes each grain of dust. `interval` is the time between
/// the two frames each reading was measured across, which the caption reports,
/// so a vector over it is a speed. Motion is only measurable where the picture
/// has texture: point the phone at a blank wall and the field reads noise, not
/// stillness.
@main
final class PhoneFlow: Sketch {

    let device = PhoneDevice()

    var positions: [Vector2] = []
    var velocities: [Vector2] = []

    override func setup() {
        device.start()
    }

    override func draw() {
        background(.black)

        guard let motion = device.latestFlow,
              let frame = device.latestFlowFrame else {
            return drawStatus(device.waitingMessage + "\n\n" +
                              "Open Ollin Capture on an iPhone, tap Flow (rear\n" +
                              "camera), and connect the cable.", style: .info)
        }

        // Letterbox the camera frame into the canvas, dimmed so the motion
        // overlay carries the picture; the field maps through the same rectangle.
        let frameSize = Vector2(Double(frame.width), Double(frame.height))
        let view = Rectangle(fitting: frameSize, in: canvasRectangle)
        tint(Color(white: 0.4))
        drawImage(frame, in: view)
        noTint()

        if positions.isEmpty { seedDust(in: view) }

        // The field as a grid of streaks, each the local motion colored by how
        // fast the picture is moving there. Both the length and the color read
        // against this reading's fastest motion rather than a fixed number of
        // pixels: a hand waved close to the camera crosses tens of pixels, a
        // person across the room a few, and one scale cannot suit both.
        let spacing = 36 * scale
        let samples = motion.samples(in: view, every: spacing)
        let fastest = max(samples.map(\.flow.length).max() ?? 0, 0.001)
        strokeWeight(2 * scale)
        for sample in samples {
            let speed = sample.flow.length
            guard speed > fastest * 0.06 else { continue }
            let t = min(speed / fastest, 1)
            let tone = Colormap.turbo.color(at: t)
            stroke(Color(red: tone.red, green: tone.green, blue: tone.blue,
                         alpha: 0.3 + t * 0.7))
            drawLine(sample.position,
                     sample.position + sample.flow * (spacing * 0.9 / fastest))
        }

        // Dust that rides the field: every grain reads the motion under itself
        // and drifts with it, settling wherever the picture holds still.
        for i in positions.indices {
            let push = motion.vector(at: positions[i], in: view)
            velocities[i] = velocities[i] * 0.88 + push * (0.5 * scale + push.length * 0.4)
            positions[i] += velocities[i]
            if !view.contains(positions[i]) {
                positions[i] = randomPoint(in: view)
                velocities[i] = .zero
            }
        }
        noStroke()
        fill(Color(white: 1, alpha: 0.8))
        drawPoints(positions, size: 5 * scale)

        let pace = String(format: "%.0f ms between frames", motion.interval * 1000)
        drawCaption("PhoneFlow: \(Int(motion.size.x))×\(Int(motion.size.y)) field, \(pace)"
                    + (motion.isTracked ? "" : ", finding its place"))
    }

    private func seedDust(in view: Rectangle) {
        positions = (0..<500).map { _ in randomPoint(in: view) }
        velocities = Array(repeating: .zero, count: positions.count)
    }

    private func randomPoint(in rect: Rectangle) -> Vector2 {
        Vector2(rect.x + random(rect.width), rect.y + random(rect.height))
    }
}
