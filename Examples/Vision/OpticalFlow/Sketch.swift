import Ollin
import OllinVision

/// The camera's motion made visible: a `FlowTracker` measures optical flow —
/// how every part of the picture is moving, as a field of vectors a sketch can
/// sample anywhere — and the sketch draws it two ways. A grid of arrows shows
/// the field itself, colored by speed; a drift of particles rides it. Wave a
/// hand and the dust scatters; hold still and it settles.
@main
final class OpticalFlow: Sketch {
    let camera = Camera()
    lazy var flow = FlowTracker(camera)

    var positions: [Vector2] = []
    var velocities: [Vector2] = []

    override func setup() {
        textFont(OutlineFont.system)
        try? camera.start()
    }

    override func draw() {
        background(.black)

        guard let frame = camera.frame else {
            fill(Color(white: 1, alpha: 0.85))
            textAlign(.center, .middle)
            textSize(22 * scale)
            drawText("Waiting for camera…", width / 2, height / 2)
            return
        }
        let view = camera.fittedRect(in: bounds) ?? bounds

        // The feed, dimmed to a backdrop so the motion overlay carries the image.
        tint(Color(white: 0.4))
        drawImage(frame, in: view)
        noTint()

        if positions.isEmpty { seedParticles(in: view) }

        guard let field = flow.field else { return }

        // The field as a grid of streaks: each sample is the local motion,
        // colored by how fast the picture is moving there.
        strokeWeight(2 * scale)
        for sample in field.samples(in: view, every: 36 * scale) {
            let speed = sample.flow.length
            guard speed > 0.7 * scale else { continue }
            let t = min(speed / (18 * scale), 1)
            let tone = Colormap.turbo.color(at: t)
            stroke(Color(red: tone.red, green: tone.green, blue: tone.blue,
                         alpha: 0.35 + t * 0.65))
            drawLine(sample.position, sample.position + sample.flow * 4)
        }

        // Dust that rides the field: every particle reads the motion under
        // itself and drifts with it, settling wherever the picture holds still.
        noStroke()
        fill(Color(white: 1, alpha: 0.8))
        for i in positions.indices {
            let push = field.vector(at: positions[i], in: view)
            velocities[i] = velocities[i] * 0.88 + push * 0.5
            positions[i] += velocities[i]
            if positions[i].x < view.x || positions[i].x > view.x + view.width ||
               positions[i].y < view.y || positions[i].y > view.y + view.height {
                positions[i] = randomPoint(in: view)
                velocities[i] = .zero
            }
        }
        drawPoints(positions, size: 5 * scale)

        fill(.white)
        textAlign(.center, .bottom)
        textSize(15 * scale)
        drawText("OpticalFlow — wave at the camera; arrows show the motion, the dust rides it",
                 width / 2, height - 28 * scale)
    }

    private func seedParticles(in view: Rectangle) {
        positions = (0..<500).map { _ in randomPoint(in: view) }
        velocities = Array(repeating: .zero, count: positions.count)
    }

    private func randomPoint(in rect: Rectangle) -> Vector2 {
        Vector2(rect.x + random(rect.width), rect.y + random(rect.height))
    }
}
