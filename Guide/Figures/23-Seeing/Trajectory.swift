// figure: frame=0 unstable
//
// Guide diagram (Chapter 23): the trajectory detector. Left: every fourth
// frame the detector was shown, laid over each other, so the ball's flight
// reads as a run of blobs. Right: the newest frame of the clip, with the
// sightings the detector reported, the parabola it fitted through them, and
// that same curve sampled past the last sighting. The pale rings are where the
// ball actually went in the rest of the made-up clip, frames the detector was
// never shown, so the prediction can be checked by eye. The detection is the
// real Vision request, run once over the frame sequence.
//
// Unstable because the detection is Vision's own model: the fitted parabola's
// low-order bits drift across environments (byte-identical within a session,
// not across model or OS updates), which nudges the dashed arc by a hair. No
// seed exists to pin; the runner verifies the render without rewriting it.
import Ollin
import OllinVision

final class Trajectory: Sketch {
    override var canvasSize: CanvasSize { .size(880, 550) }

    /// Frames handed to the detector. The flight carries on well past these.
    static let shownFrames = 24
    /// How long the whole flight runs, so the prediction has something to hit.
    static let flightFrames = 60
    static let frameSize = 300.0

    var trail: Image?
    var newest: Image?
    var sightings: [Vector2] = []
    var fit = SIMD3<Double>()
    var found = false

    let ink = Color(hex: 0x2B2B2B)
    let faint = Color(hex: 0x2B2B2B, alpha: 0.28)
    let soft = Color(hex: 0x2B2B2B, alpha: 0.6)
    let accent = Color(hex: 0xE4572E)
    let chalk = Color(hex: 0xF7F5F1, alpha: 0.8)

    let leftPanel = Rectangle(x: 60, y: 100, width: 360, height: 360)
    let rightPanel = Rectangle(x: 460, y: 100, width: 360, height: 360)

    override func setup() {
        let clip = (0 ..< Trajectory.shownFrames).map { Trajectory.frame(at: $0) }
        newest = clip.last
        trail = Trajectory.exposure(of: Array(stride(from: 0, to: Trajectory.shownFrames, by: 4)))

        // The real detector, run over the sequence. It reports per frame, so the
        // last frame's report is the arc as it stands at the end of the clip.
        let perFrame = (try? waitFor(clip) {
            try await TrajectoryTracker.detect(across: $0, frameRate: 30)
        }) ?? []
        guard let arc = perFrame.last?.first else { return }
        found = true
        sightings = arc.detectedPointsNormalized
        fit = arc.equationCoefficients
    }

    override func draw() {
        background(Color(hex: 0xF7F5F1))
        textSize(19)

        if let trail { drawImage(trail, in: leftPanel) }
        if let newest { drawImage(newest, in: rightPanel) }

        if found {
            withClip(rightPanel) {
                drawPrediction()
                drawTruth()
                drawSightings()
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
        drawText("six of the clip's frames, overlaid", leftPanel.center.x, 472)
        drawText("the arc it fitted, carried forward", rightPanel.center.x, 472)
        fill(soft)
        drawText("the dots are sightings, the dashes a guess, the rings where it really went",
                 width / 2, 512)
    }

    /// The fitted parabola, drawn through the sightings and on past the last one.
    private func drawPrediction() {
        guard let last = sightings.last else { return }
        noFill()
        stroke(accent.withAlpha(0.85))
        strokeWeight(2)
        drawPolyline(curve(from: sightings[0].x, to: last.x))

        // Past the last sighting the same curve is a claim about the future, so
        // it is drawn as a dashed line.
        let ahead = curve(from: last.x, to: 1)
        strokeWeight(2.5)
        for i in stride(from: 0, to: ahead.count - 1, by: 2) {
            drawLine(ahead[i], ahead[i + 1])
        }
    }

    /// Sample the fitted parabola between two normalized x positions.
    private func curve(from x0: Double, to x1: Double) -> [Vector2] {
        stride(from: x0, through: x1, by: 0.005).map { x in
            VisionSpace.point(x, fit.x * x * x + fit.y * x + fit.z, in: rightPanel)
        }
    }

    /// Where the ball actually was in the frames the detector never saw.
    private func drawTruth() {
        noFill()
        stroke(chalk)
        strokeWeight(1.5)
        let scale = rightPanel.width / Trajectory.frameSize
        for index in stride(from: Trajectory.shownFrames, to: Trajectory.flightFrames, by: 3) {
            let ball = Trajectory.ball(at: index)
            drawCircle(center: Vector2(rightPanel.x + ball.x * scale,
                                       rightPanel.y + ball.y * scale),
                       radius: 7)
        }
    }

    /// The sightings themselves, as the detector reported them.
    private func drawSightings() {
        noStroke()
        fill(accent)
        for point in sightings {
            drawCircle(center: VisionSpace.point(point, in: rightPanel), radius: 4)
        }
    }

    // MARK: The made-up clip

    /// Where the ball is at a given frame, in the clip's pixel coordinates: a
    /// steady sideways drift, and a parabola in the fall.
    static func ball(at index: Int) -> Vector2 {
        let t = Double(index) / 30
        return Vector2(20 + 130 * t, 280 - 300 * t + 150 * t * t)
    }

    /// One frame: a small bright ball on a dim speckled backdrop. The speckle
    /// matters, because a detector that works by comparing frames needs a
    /// background that stays put.
    static func frame(at index: Int) -> Image {
        exposure(of: [index])
    }

    /// Several frames as one picture, the way a long camera exposure keeps
    /// every position a moving light passed through.
    static func exposure(of indices: [Int]) -> Image {
        let n = Int(frameSize)
        var bytes = [UInt8](repeating: 0, count: n * n * 4)
        for y in 0 ..< n {
            for x in 0 ..< n {
                let v = UInt8(16 + 18 * hash(x / 3, y / 3))
                let i = (y * n + x) * 4
                bytes[i] = v; bytes[i + 1] = v; bytes[i + 2] = v; bytes[i + 3] = 255
            }
        }
        for index in indices { stamp(ball(at: index), into: &bytes, size: n) }
        return Image(width: n, height: n, premultipliedRGBA: bytes)!
    }

    /// Paint one soft-edged ball into a pixel buffer.
    private static func stamp(_ center: Vector2, into bytes: inout [UInt8], size n: Int) {
        let r = 7.0
        for y in max(0, Int(center.y - r) - 1) ... min(n - 1, Int(center.y + r) + 1) {
            for x in max(0, Int(center.x - r) - 1) ... min(n - 1, Int(center.x + r) + 1) {
                let d = dist(Double(x), Double(y), center.x, center.y)
                guard d < r else { continue }
                let i = (y * n + x) * 4
                let v = UInt8(min(250, 250 * (1 - max(0, d - r + 2) / 2)))
                bytes[i] = max(bytes[i], v)
                bytes[i + 1] = max(bytes[i + 1], v)
                bytes[i + 2] = max(bytes[i + 2], v)
            }
        }
    }

    private static func hash(_ x: Int, _ y: Int) -> Double {
        var h = UInt64(truncatingIfNeeded: x &* 374_761_393 &+ y &* 668_265_263)
        h = (h ^ (h >> 13)) &* 1_274_126_177
        return Double((h ^ (h >> 16)) % 1000) / 999
    }
}
