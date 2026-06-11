import Ollin
import OllinVision
import CoreGraphics
import Foundation
import os

/// Arcs found, not followed. Where `ObjectTracking` follows a patch you point
/// at, a `TrajectoryTracker` watches for *ballistic motion* on its own: anything
/// small flying along a parabola gets reported as an arc of points, with the
/// fitted curve telling you where it's headed.
///
/// There's no ball to throw at a webcam here, so the example brings its own
/// scene: `BallFeed` below is a tiny frame source of our own — a simulation
/// that launches balls and renders each frame on its own thread, conforming to
/// `FrameSource` the same way `Camera` and `VideoPlayer` do. The tracker
/// attaches to it identically, which is the point: a tracker runs over *any*
/// source of frames, including one you write yourself. The overlay draws each
/// detected arc (dots), its fitted path (solid), and the parabola extended
/// ahead of the ball (faint) — detection is classical, so it runs on any Mac.
@main
final class TrajectoryTracking: Sketch {
    let feed = BallFeed()
    lazy var tracker = TrajectoryTracker(feed, trajectoryLength: 8)

    /// Arcs linger a moment after their last sighting, fading out, so the
    /// overlay doesn't flicker frame to frame.
    struct Trail {
        var trajectory: DetectedTrajectory
        var lastSeen: Double
    }
    var trails: [UUID: Trail] = [:]
    let linger = 1.2

    override func setup() {
        textFont(OutlineFont.system)
        feed.start()
    }

    override func draw() {
        background(Color(white: 0.06))

        guard let frame = feed.frame else { return }
        let view = VisionSpace.fittedRect(imageSize: BallFeed.size, in: bounds)
        drawImage(frame, in: view)

        // Fold this frame's detections into the lingering trails, keyed by the
        // arc's stable identity, and drop the ones gone stale.
        for trajectory in tracker.trajectories {
            trails[trajectory.id] = Trail(trajectory: trajectory, lastSeen: time)
        }
        trails = trails.filter { time - $0.value.lastSeen < linger }

        for trail in trails.values {
            let arc = trail.trajectory
            let fade = (1 - (time - trail.lastSeen) / linger) * arc.confidence

            // Where the arc is headed: the fitted parabola, extended past the
            // last observed point in the direction of travel.
            let ahead = predictedPoints(of: arc, in: view)
            if ahead.count > 1 {
                stroke(Color(red: 1.0, green: 0.85, blue: 0.3, alpha: fade * 0.45))
                strokeWeight(3 * scale)
                drawPolyline(ahead)
            }

            // The path so far: the fitted curve, then the raw sightings on top.
            let fitted = arc.projectedPoints(in: view)
            if fitted.count > 1 {
                stroke(Color(red: 0.35, green: 1.0, blue: 0.6, alpha: fade))
                strokeWeight(4 * scale)
                drawPolyline(fitted)
            }
            fill(Color(white: 1, alpha: fade))
            noStroke()
            for point in arc.detectedPoints(in: view) {
                drawCircle(center: point, radius: 5 * scale)
            }
        }

        fill(.white)
        noStroke()
        textAlign(.center, .bottom)
        textSize(15 * scale)
        drawText("TrajectoryTracking — ballistic arcs detected in a synthetic feed (a FrameSource of our own)",
                 width / 2, height - 28 * scale)
    }

    /// Sample the arc's fitted parabola (`y = ax² + bx + c`, normalized space)
    /// from its last observed point onward, mapped into `view`.
    func predictedPoints(of arc: DetectedTrajectory, in view: Rectangle) -> [Vector2] {
        let points = arc.detectedPointsNormalized
        guard let first = points.first, let last = points.last, first.x != last.x else { return [] }
        let direction: Double = last.x > first.x ? 1 : -1
        let coefficients = arc.equationCoefficients
        var sampled: [Vector2] = []
        for step in 0...24 {
            let x = last.x + direction * 0.4 * Double(step) / 24
            guard x >= 0, x <= 1 else { break }
            let y = coefficients.x * x * x + coefficients.y * x + coefficients.z
            guard y >= 0, y <= 1 else { break }
            sampled.append(VisionSpace.point(x, y, in: view))
        }
        return sampled
    }
}

// MARK: - The synthetic frame source

/// A frame source of our own: a little launcher that lobs balls across a
/// 640×480 scene and renders each simulation step to a `CGImage` on its own
/// thread — the same contract `Camera` and `VideoPlayer` fulfill. The tracker
/// taps it without knowing (or caring) that the "camera" is made up.
@MainActor
final class BallFeed: FrameSource {

    nonisolated static let size = Vector2(640, 480)

    /// The analysis tap (`FrameSource`). The simulation thread reads it per
    /// frame, so the live value crosses through a locked box.
    var frameTap: FrameTap? {
        didSet {
            let tap = frameTap
            engine.tapStore.withLock { $0 = tap }
        }
    }

    /// The latest rendered frame as a drawable `Image`, like `camera.frame`.
    var frame: Image? {
        guard let rendered = engine.frameStore.withLock({ $0 })?.image else { return nil }
        if cachedFrameID != ObjectIdentifier(rendered) {
            cachedImage = Image(cgImage: rendered)
            cachedFrameID = ObjectIdentifier(rendered)
        }
        return cachedImage
    }

    private let engine = BallEngine()
    private var started = false
    private var cachedImage: Image?
    private var cachedFrameID: ObjectIdentifier?

    /// Begin simulating and publishing frames at 30 fps, on the feed's own
    /// thread (given a roomy stack; the tap hand-off rides it, analysis doesn't).
    func start() {
        guard !started else { return }
        started = true
        let engine = engine
        let thread = Thread {
            while true {
                let nextFrame = Date(timeIntervalSinceNow: 1.0 / 30.0)
                engine.step()
                Thread.sleep(until: nextFrame)
            }
        }
        thread.name = "co.eavl.ollin.example.ballfeed"
        thread.stackSize = 4 << 20
        thread.start()
    }
}

/// A frame crossing threads; the `CGImage` is immutable once made.
private struct RenderedFrame: @unchecked Sendable {
    let image: CGImage
}

/// The simulation + renderer. All mutable state is owned by the feed's thread
/// (`step()` is only ever called there); the locked boxes are the two hand-offs
/// out — the latest frame to the main thread, the tap to whoever analyzes.
private final class BallEngine: @unchecked Sendable {

    let tapStore = OSAllocatedUnfairLock<FrameTap?>(initialState: nil)
    let frameStore = OSAllocatedUnfairLock<RenderedFrame?>(initialState: nil)

    private struct Ball {
        var position: Vector2
        var velocity: Vector2
    }
    private var balls: [Ball] = []
    private var frameCount = 0
    private let width = Int(BallFeed.size.x)
    private let height = Int(BallFeed.size.y)
    private let dt = 1.0 / 30.0
    private let gravity = 620.0

    /// One simulation step: launch, integrate, render, publish.
    func step() {
        // Lob a fresh ball every couple of seconds, alternating corners.
        if frameCount % 70 == 0 {
            let fromLeft = (frameCount / 70) % 2 == 0
            balls.append(Ball(
                position: Vector2(fromLeft ? 30 : Double(width) - 30, Double(height) - 24),
                velocity: Vector2((fromLeft ? 1 : -1) * Double.random(in: 170...290),
                                  -Double.random(in: 420...520))))
        }
        frameCount += 1

        for i in balls.indices {
            balls[i].velocity = balls[i].velocity + Vector2(0, gravity * dt)
            balls[i].position = balls[i].position + balls[i].velocity * dt
        }
        balls.removeAll { $0.position.y > Double(height) + 30 }

        guard let image = render() else { return }
        frameStore.withLock { $0 = RenderedFrame(image: image) }
        tapStore.withLock { $0 }?(image)
    }

    /// Draw the scene — a dark court, a floor line, the balls — in top-left
    /// pixel coordinates (the context is lower-left, so y flips).
    private func render() -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }

        ctx.setFillColor(CGColor(red: 0.07, green: 0.08, blue: 0.11, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.setFillColor(CGColor(red: 0.13, green: 0.15, blue: 0.19, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: 18))

        for ball in balls {
            let flippedY = Double(height) - ball.position.y
            ctx.setFillColor(CGColor(red: 0.55, green: 0.62, blue: 0.72, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ball.position.x - 11, y: flippedY - 11,
                                       width: 22, height: 22))
            ctx.setFillColor(CGColor(red: 0.95, green: 0.96, blue: 1.0, alpha: 1))
            ctx.fillEllipse(in: CGRect(x: ball.position.x - 8, y: flippedY - 8,
                                       width: 16, height: 16))
        }
        return ctx.makeImage()
    }
}
