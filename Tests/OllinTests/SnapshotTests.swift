import CoreGraphics
import Ollin
import Testing

/// Render-correctness snapshot tests: each renders a small, deterministic sketch
/// off-screen and checks it against a committed reference image. They exercise
/// both render pipelines (the instanced SDF path and the tessellated-triangle
/// path) and the front-to-back batch ordering between them.
///
/// Serialized because they share the GPU and the reference directory; gated on a
/// Metal device so they skip on a GPU-less machine instead of failing.
@Suite(.serialized)
@MainActor
struct SnapshotTests {

    @Test(.enabled(if: Snapshot.hasMetal))
    func solidShapesMatchReference() throws {
        let diff = try Snapshot.meanDifference(of: SolidShapes(), against: "solid-shapes")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func mixedPipelinesMatchReference() throws {
        let diff = try Snapshot.meanDifference(of: MixedPipelines(), against: "mixed-pipelines")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func easedValuesMatchReference() throws {
        // Rendered mid-tween (frame 30), so the per-frame auto-advance has run and
        // the three curves have pulled the dots to different positions.
        let diff = try Snapshot.meanDifference(of: EasedDots(), against: "eased-dots", frame: 30)
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }
}

// MARK: - Fixtures

/// A few solid SDF fills on white — large flat regions, so anti-aliased edges
/// are a small fraction of the frame. Pure SDF pipeline.
private final class SolidShapes: Sketch {
    override var canvasSize: CGSize { CGSize(width: 256, height: 256) }

    override func draw() {
        background(.white)
        noStroke()
        fill(.black)
        drawRect(center: Vector2(width / 2, height / 2), width: width * 0.6, height: height * 0.6)
        fill(Color(red: 0.9, green: 0.2, blue: 0.2))
        drawCircle(width * 0.28, height * 0.28, width * 0.16)
        fill(Color(red: 0.2, green: 0.5, blue: 0.95))
        drawRect(corner: Vector2(width * 0.6, height * 0.6), width: width * 0.28, height: height * 0.28)
    }
}

/// A tessellated triangle (the triangle pipeline) with an SDF star drawn over it
/// (the SDF pipeline), so the test covers both paths and that they composite in
/// draw order.
private final class MixedPipelines: Sketch {
    override var canvasSize: CGSize { CGSize(width: 256, height: 256) }

    override func draw() {
        background(Color(white: 0.1))
        noStroke()
        fill(Color(red: 0.2, green: 0.6, blue: 0.9))
        drawPolygon([Vector2(40, 40), Vector2(220, 70), Vector2(120, 220)])
        fill(Color(red: 1.0, green: 0.85, blue: 0.2))
        drawStar(width * 0.5, height * 0.46, width * 0.22, width * 0.1, points: 5)
    }
}

/// Three `@Eased` values easing toward the same target (set in `setup`) on
/// different curves, so mid-tween the dots sit at different positions. Exercises
/// the sketch's per-frame auto-advance and that each curve shapes motion its own
/// way. Large flat white field, so edge pixels stay a small fraction.
private final class EasedDots: Sketch {
    override var canvasSize: CGSize { CGSize(width: 256, height: 256) }

    @Eased(duration: 1, curve: .linear)  var a = 0.0
    @Eased(duration: 1, curve: .easeIn)  var b = 0.0
    @Eased(duration: 1, curve: .easeOut) var c = 0.0

    override func setup() { a = 1; b = 1; c = 1 }

    override func draw() {
        background(.white)
        noStroke()
        fill(.black)
        let left = width * 0.18, right = width * 0.82
        for (i, t) in [a, b, c].enumerated() {
            let y = height * (0.3 + Double(i) * 0.2)
            drawCircle(left + (right - left) * t, y, width * 0.06)
        }
    }
}
