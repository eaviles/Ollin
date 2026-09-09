import Ollin
import OllinSamplePhotos
import OllinVideo
import OllinVision

/// Motion made visible: a `FlowTracker` measures optical flow, how every part
/// of the picture is moving, as a field of vectors a sketch can sample
/// anywhere, and the sketch draws it two ways. A grid of arrows shows the field
/// itself, colored by speed; a drift of particles rides it. Wave a hand at the
/// camera and the dust scatters; hold still and it settles.
///
/// Where there is no camera it reads the film that ships with Ollin instead, a
/// dancer on a plain ground with the camera locked off, which is what flow
/// wants: nearly two thirds of that frame never moves, so every vector the
/// field reports belongs to him rather than to a wobbling lens. `--photo` takes
/// the film even where a camera would have worked.
@main
final class OpticalFlow: Sketch {
    let feed: any FrameSource & VideoFeed = {
        if !CommandLine.arguments.contains("--photo") {
            let camera = Camera()
            if (try? camera.start()) != nil, camera.isRunning { return camera }
        }
        let film = VideoPlayer(url: SampleClip.dance.url)
        film.loops = true
        film.isMuted = true
        film.play()
        return film
    }()

    lazy var flow = FlowTracker(feed)

    var positions: [Vector2] = []
    var velocities: [Vector2] = []

    override func draw() {
        background(.black)

        // The feed, dimmed to a backdrop so the motion overlay carries the image.
        tint(Color(white: 0.4))
        guard let view = drawFrame(feed) else { return noTint() }
        noTint()

        if positions.isEmpty { seedParticles(in: view) }

        // The field needs two analyzed frames, so it's nil for the first beat;
        // the dust and caption still draw, just unmoved.
        if let field = flow.field {
            // The field as a grid of streaks: each sample is the local motion,
            // colored by how fast the picture is moving there. Both the length
            // and the color read against *this frame's* fastest motion rather
            // than a fixed number of pixels, because how far a picture moves
            // between two frames depends on what it is: a hand waved at a
            // camera crosses tens of pixels, a dancer a few, and a fixed scale
            // that suits one draws nothing for the other.
            let spacing = 36 * scale
            let samples = field.samples(in: view, every: spacing)
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

            // Dust that rides the field: every particle reads the motion under
            // itself and drifts with it, settling wherever the picture holds still.
            for i in positions.indices {
                let push = field.vector(at: positions[i], in: view)
                velocities[i] = velocities[i] * 0.88 + push * (0.5 * scale + push.length * 0.4)
                positions[i] += velocities[i]
                if positions[i].x < view.x || positions[i].x > view.x + view.width ||
                   positions[i].y < view.y || positions[i].y > view.y + view.height {
                    positions[i] = randomPoint(in: view)
                    velocities[i] = .zero
                }
            }
        }
        noStroke()
        fill(Color(white: 1, alpha: 0.8))
        drawPoints(positions, size: 5 * scale)

        drawCaption("optical flow: arrows show the motion, the dust rides it")
    }

    private func seedParticles(in view: Rectangle) {
        positions = (0..<500).map { _ in randomPoint(in: view) }
        velocities = Array(repeating: .zero, count: positions.count)
    }

    private func randomPoint(in rect: Rectangle) -> Vector2 {
        Vector2(rect.x + random(rect.width), rect.y + random(rect.height))
    }
}
