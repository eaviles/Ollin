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

    @Test(.enabled(if: Snapshot.hasMetal))
    func strokeAlignmentMatchesReference() throws {
        let diff = try Snapshot.meanDifference(of: StrokeAligned(), against: "stroke-aligned")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func threePointShapesMatchReference() throws {
        let diff = try Snapshot.meanDifference(of: ThreePointShapes(), against: "three-point-shapes")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func orientedBoxesMatchReference() throws {
        let diff = try Snapshot.meanDifference(of: OrientedBoxes(), against: "oriented-boxes")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func orientedVesicasMatchReference() throws {
        let diff = try Snapshot.meanDifference(of: OrientedVesicas(), against: "oriented-vesicas")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func curvedPathsMatchReference() throws {
        let diff = try Snapshot.meanDifference(of: CurvedPaths(), against: "curved-paths")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func strokeJoinsAndCapsMatchReference() throws {
        let diff = try Snapshot.meanDifference(of: StrokeJoinsCaps(), against: "stroke-joins-caps")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func bitmapTextMatchesReference() throws {
        let diff = try Snapshot.meanDifference(of: TextSpecimen(), against: "bitmap-text")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func tintedImageMatchesReference() throws {
        let diff = try Snapshot.meanDifference(of: TintedImage(), against: "tinted-image")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func gradientPaintsMatchReference() throws {
        let diff = try Snapshot.meanDifference(of: GradientShapes(), against: "gradient-shapes")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func statusAndCaptionMatchReference() throws {
        let diff = try Snapshot.meanDifference(of: StatusNotices(), against: "status-notices")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func additiveBlendMatchesReference() throws {
        let diff = try Snapshot.meanDifference(of: AdditiveBlend(), against: "additive-blend")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func accumulationMatchesReference() throws {
        // Captured at frame 12, so the reference can only match if the canvas
        // accumulated across the prior frames (a single frame is a sparse scatter).
        let diff = try Snapshot.meanDifference(of: AccumulationField(), against: "accumulation", frame: 12)
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func toneMappedBloomMatchesReference() throws {
        // Additive light pushes the overlaps well past 1.0; `.aces` rolls them off
        // instead of clipping. Pins the float intermediate + the present pass's
        // tone-map (a `.clamp` render would flatten the cores to white).
        let diff = try Snapshot.meanDifference(of: ToneMappedBloom(), against: "tone-mapped-bloom")
        #expect(diff < Snapshot.tolerance, "mean per-channel difference \(diff)")
    }
}

// MARK: - Fixtures

/// A few solid SDF fills on white — large flat regions, so anti-aliased edges
/// are a small fraction of the frame. Pure SDF pipeline.
private final class SolidShapes: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

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
    override var canvasSize: CanvasSize { .square(256) }

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
    override var canvasSize: CanvasSize { .square(256) }

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

/// A disk and a region shape (rect) stroked under each `StrokeAlign` — one row
/// per alignment — so the test pins the stroke-band bias on both coverage ramps
/// (`diskCoverage` and `regionCoverage`). Static, so it's deterministic at frame 0.
private final class StrokeAligned: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.white)
        fill(Color(white: 0.6))
        stroke(.black)
        strokeWeight(12)
        let aligns: [StrokeAlign] = [.inside, .center, .outside]
        for (i, align) in aligns.enumerated() {
            strokeAlign(align)
            let y = height * (0.22 + Double(i) * 0.28)
            drawCircle(width * 0.3, y, width * 0.09)
            drawRect(center: Vector2(width * 0.7, y), width: width * 0.18, height: width * 0.18)
        }
    }
}

/// The two three-point shapes that drove the `SDFInstance` widening (the `param2`
/// slot): a general scalene `drawTriangle(a, b, c)` — filled+stroked, then drawn
/// hollow (it honors both) — and a quadratic `drawBezier` stroke, plus a Bézier
/// with collinear control points that exercises the straight-line fallback.
/// Static, so it's deterministic at frame 0.
private final class ThreePointShapes: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.white)
        // Filled + stroked scalene triangle (top-left).
        fill(Color(red: 0.2, green: 0.6, blue: 0.9))
        stroke(.black); strokeWeight(6)
        drawTriangle(Vector2(30, 95), Vector2(115, 35), Vector2(90, 135))
        // Hollow triangle — a constant-width band (top-right).
        noStroke(); fill(Color(red: 0.9, green: 0.4, blue: 0.2))
        hollow(10)
        drawTriangle(Vector2(145, 45), Vector2(228, 75), Vector2(165, 125))
        solid()
        // Quadratic Bézier curve (a smile across the middle).
        stroke(Color(red: 0.1, green: 0.5, blue: 0.2)); strokeWeight(10)
        drawBezier(Vector2(25, 205), Vector2(128, 145), Vector2(231, 205))
        // Collinear control points → the straight-line fallback (bottom).
        stroke(.black); strokeWeight(6)
        drawBezier(Vector2(25, 240), Vector2(128, 240), Vector2(231, 240))
    }
}

/// `drawOrientedBox` — a box placed by its two centerline endpoints plus a
/// thickness. Exercises the region features it inherits: a filled + stroked bar
/// (diagonal), a hollow bar (a constant-width band, top), and an outside-aligned
/// stroke (bottom). Static, so it's deterministic at frame 0.
private final class OrientedBoxes: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.white)
        // Filled + stroked diagonal bar.
        fill(Color(red: 0.2, green: 0.6, blue: 0.9))
        stroke(.black); strokeWeight(6)
        drawOrientedBox(Vector2(40, 60), Vector2(216, 130), thickness: 34)
        // Hollow bar — a constant-width band hugging the outline (top).
        noStroke(); fill(Color(red: 0.9, green: 0.4, blue: 0.2))
        hollow(8)
        drawOrientedBox(Vector2(40, 30), Vector2(216, 30), thickness: 28)
        solid()
        // Outside-aligned stroke — the outline sits fully outside the fill (bottom).
        fill(Color(red: 0.1, green: 0.5, blue: 0.2))
        stroke(.black); strokeWeight(6); strokeAlign(.outside)
        drawOrientedBox(Vector2(50, 210), Vector2(206, 226), thickness: 30)
        strokeAlign(.center)
    }
}

/// `drawOrientedVesica` — a pointed lens placed by its two tip points plus a
/// waist width. Exercises the region features it inherits: a filled + stroked lens
/// (diagonal), a hollow lens (a constant-width band, top), and an outside-aligned
/// stroke (bottom). Static, so it's deterministic at frame 0.
private final class OrientedVesicas: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.white)
        // Filled + stroked diagonal lens.
        fill(Color(red: 0.2, green: 0.6, blue: 0.9))
        stroke(.black); strokeWeight(6)
        drawOrientedVesica(Vector2(40, 70), Vector2(216, 140), width: 70)
        // Hollow lens — a constant-width band hugging the outline (top).
        noStroke(); fill(Color(red: 0.9, green: 0.4, blue: 0.2))
        hollow(8)
        drawOrientedVesica(Vector2(40, 32), Vector2(216, 32), width: 44)
        solid()
        // Outside-aligned stroke — the outline sits fully outside the fill (bottom).
        fill(Color(red: 0.1, green: 0.5, blue: 0.2))
        stroke(.black); strokeWeight(5); strokeAlign(.outside)
        drawOrientedVesica(Vector2(50, 224), Vector2(206, 224), width: 40)
        strokeAlign(.center)
    }
}

/// The `Path` builder and `drawCurve` (sample-to-points curved contours): a
/// closed, filled blob whose outline is a smooth Catmull-Rom `curve` run; an open
/// outline built from an explicit `quadCurve` + `cubicCurve`; and an open
/// `drawCurve` wiggle straight from points. Static, so it's deterministic at
/// frame 0.
private final class CurvedPaths: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.white)
        // Closed filled blob through points (curve = Catmull-Rom) + stroked outline.
        fill(Color(red: 0.2, green: 0.6, blue: 0.9)); stroke(.black); strokeWeight(4)
        drawShape { p in
            p.move(to: Vector2(55, 45))
            p.curve(to: Vector2(150, 55))
            p.curve(to: Vector2(165, 120))
            p.curve(to: Vector2(85, 110))
            p.close()
        }
        // Open outline from an explicit quadratic + cubic Bézier, stroke-only.
        noFill(); stroke(Color(red: 0.9, green: 0.3, blue: 0.2)); strokeWeight(6)
        drawShape { p in
            p.move(to: Vector2(28, 158))
            p.quadCurve(to: Vector2(128, 150), control: Vector2(78, 100))
            p.cubicCurve(to: Vector2(230, 165), control1: Vector2(168, 120), control2: Vector2(188, 205))
        }
        // A smooth open wiggle straight from a list of points.
        stroke(.black); strokeWeight(4)
        drawCurve([Vector2(25, 228), Vector2(80, 200), Vector2(130, 236),
                   Vector2(180, 200), Vector2(232, 230)])
    }
}

/// Each `strokeJoin` on a sharp chevron (top three) and each `strokeCap` on an
/// open segment (bottom three), so the corner and end geometry are exercised on
/// the tessellated stroke path. Static, so it's deterministic at frame 0.
private final class StrokeJoinsCaps: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.white)
        stroke(.black); strokeWeight(22)

        let joins: [StrokeJoin] = [.miter, .bevel, .round]
        for (i, join) in joins.enumerated() {
            let cy = 32.0 + Double(i) * 36
            strokeJoin(join)
            drawPolyline([Vector2(40, cy + 14), Vector2(128, cy - 14), Vector2(216, cy + 14)])
        }

        let caps: [StrokeCap] = [.butt, .round, .square]
        strokeJoin(.miter)
        for (i, cap) in caps.enumerated() {
            let cy = 160.0 + Double(i) * 32
            strokeCap(cap)
            drawPolyline([Vector2(70, cy), Vector2(186, cy)])
        }
    }
}

/// The bitmap-font `drawText` with the bundled Cozette font: capitals, lowercase,
/// digits, the Spanish set (accented vowels, ñ/ü, inverted punctuation), Japanese
/// kana (hiragana + katakana), descenders (`g j p q y`), the alignments, and a
/// rotated line that exercises text on the transform stack. Black on white, static.
private final class TextSpecimen: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.white)
        fill(.black)
        textFont(BitmapFont.builtin)   // the fixture is about Cozette, not the default font
        textAlign(.left, .top)
        textSize(24)
        drawText("¡Hola! Ñ", 14, 12)
        textSize(22)
        drawText("ABCxyz 0123", 14, 42)
        drawText("áéíóú ñ ü ¿?", 14, 70)
        textSize(20)
        drawText("こんにちは", 14, 98)        // hiragana
        drawText("ハロー gjpqy", 14, 126)      // katakana + descenders
        // Centered + rotated, through the transform stack.
        textAlign(.center, .middle)
        drawText("centered", width / 2, 172)
        withState {
            translate(width / 2, 212)
            rotate(0.16)
            drawText("rotated", 0, 0)
        }
    }
}

/// An image authored from scratch (`Image(width:height:)` + pixel `set`), drawn
/// once untinted and once under `tint(_:)`, with a row of `get`-sampled swatches
/// below. Pins the whole image-extras path: the texture upload from edited pixels,
/// the tint multiply, top-left pixel orientation (the black corner marker), and
/// that `get` reads the authored colors regardless of tint. Static at frame 0.
private final class TintedImage: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    var img: Image?

    override func setup() {
        let n = 16
        let image = Image(width: n, height: n)
        for y in 0..<n {
            for x in 0..<n {
                image[x, y] = (x + y) % 2 == 0
                    ? Color(red: 0.9, green: 0.35, blue: 0.2)
                    : Color(red: 0.2, green: 0.45, blue: 0.9)
            }
        }
        image[0, 0] = .black   // top-left marker — must land at the drawn top-left
        img = image
    }

    override func draw() {
        background(.white)
        guard let img else { return }
        noTint()
        drawImage(img, 18, 18, 100, 100)
        tint(Color(red: 1, green: 0.7, blue: 0.3, alpha: 0.85))
        drawImage(img, 138, 18, 100, 100)
        // get-sampled swatches of the top row, in true (untinted) color.
        noTint()
        noStroke()
        for i in 0..<8 {
            fill(img[i * 2, 0])
            drawRect(18 + Double(i) * 28, 150, 24, 80)
        }
    }
}

/// Gradient paint across both pipelines: linear and radial SDF fills, a conic
/// (along-path) stroke sweeping a circle outline, a per-vertex linear fill on a
/// tessellated polygon, and along-path ramps on a line capsule and a Bézier.
/// Gradients are smooth fields, so the mean-difference metric stays tight.
private final class GradientShapes: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.1))
        noStroke()
        // Linear fill on the SDF box path.
        fill(.linear(from: Vector2(20, 20), to: Vector2(236, 20),
                     [Color(hex: 0xFF8A3D), Color(hex: 0x2BB3A3)]))
        drawRect(20, 20, 216, 60)
        // Radial fill plus a conic (along-path) stroke on the same circle.
        fill(.radial(center: Vector2(70, 160), radius: 40,
                     [.white, Color(hex: 0xD03060)]))
        stroke(.alongPath([Color(hex: 0xFFF3C4), Color(hex: 0x3C6DD0)]))
        strokeWeight(6)
        drawCircle(70, 160, 40)
        noStroke()
        // Per-vertex linear fill on the tessellated path.
        fill(.linear(from: Vector2(130, 120), to: Vector2(230, 210),
                     [Color(hex: 0x0B1A40), Color(hex: 0xFFB36B)]))
        drawPolygon([Vector2(180, 120), Vector2(230, 210), Vector2(130, 210)])
        // Along-path ramps on a line capsule and a quadratic Bézier.
        stroke(.alongPath([Color(hex: 0xFFF3C4), Color(hex: 0xD03060)]))
        strokeWeight(8)
        drawLine(Vector2(20, 234), Vector2(236, 234))
        drawBezier(Vector2(20, 108), Vector2(128, 86), Vector2(118, 108))
        noStroke()
    }
}

/// The standard notices and caption helpers, plus a closed polyline: an `.info`
/// status filling the canvas, a `.warning` status scoped to a sub-rectangle,
/// captions on both edges, and `drawPolyline(closed:)` joining its seam. Pins
/// the helpers' look and that they leave the drawing state untouched (the
/// rectangle after them still draws with the sketch's own fill).
private final class StatusNotices: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.06))
        drawStatus("Waiting for camera…")
        drawStatus("Model unavailable", style: .warning,
                   in: Rectangle(x: 0, y: 150, width: width, height: 90))
        drawCaption("StatusNotices — a caption")
        drawCaption("top caption", edge: .top)
        // State untouched by the helpers: this still draws white, stroke-free.
        fill(.white)
        noStroke()
        drawRect(10, 118, 20, 20)
        // A closed polyline turns its seam with the join (vs. an open V).
        stroke(.white)
        strokeWeight(6)
        drawPolyline([Vector2(200, 110), Vector2(236, 140), Vector2(200, 140)], closed: true)
    }
}

/// Three translucent primary-color disks on black, drawn with `blendMode(.add)`
/// so they sum as light: each pair overlaps in a secondary and all three meet in
/// a white core. Pins the additive blend factors (and that `.add` rides the SDF
/// path). Deterministic — no time dependence.
private final class AdditiveBlend: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.black)
        blendMode(.add)
        noStroke()
        let r = width * 0.3
        let cx = width * 0.5, cy = height * 0.52, off = width * 0.17
        fill(Color(red: 1, green: 0, blue: 0, alpha: 0.85))
        drawCircle(cx, cy - off, r)
        fill(Color(red: 0, green: 1, blue: 0, alpha: 0.85))
        drawCircle(cx - off * 0.92, cy + off * 0.6, r)
        fill(Color(red: 0, green: 0, blue: 1, alpha: 0.85))
        drawCircle(cx + off * 0.92, cy + off * 0.6, r)
    }
}

/// A persistent (`noClear`) canvas: each frame scatters a seeded ring of faint
/// additive dots that rotates slowly, so by the captured frame the canvas holds
/// the accumulated, overlapping trails — not a single frame's sparse scatter.
/// Pins the accumulation surface (don't-clear + the persistent-target read-back),
/// and that it builds up across frames. Deterministic via the seed + fixed timestep.
private final class AccumulationField: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    private var seeds: [(angle: Double, radius: Double)] = []

    override func setup() {
        seed(3)
        background(Color(white: 0.02))     // the one base wipe; then accumulate
        noClear()
        for _ in 0 ..< 200 {
            seeds.append((random(.tau), random(40, 110)))
        }
    }

    override func draw() {
        blendMode(.add)
        noStroke()
        fill(Color(red: 0.5, green: 0.72, blue: 1, alpha: 0.12))
        let cx = width / 2, cy = height / 2
        let spin = time * 0.6
        for s in seeds {
            let a = s.angle + spin
            drawCircle(cx + cos(a) * s.radius, cy + sin(a) * s.radius, 2.2)
        }
    }
}

/// Bright additive disks overlapping past full brightness, mapped down by ACES.
/// The center stacks three saturated colors into a high-dynamic-range core that a
/// clamp would flatten to white; this pins that the linear-float frame is
/// tone-mapped in the present pass (not clipped). Deterministic (no time/random).
private final class ToneMappedBloom: Sketch {
    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(hex: 0x05060A))
        toneMap(.aces, exposure: 1.6)
        blendMode(.add)
        noStroke()
        let r = width * 0.32
        let cx = width * 0.5, cy = height * 0.5, off = width * 0.14
        fill(Color(red: 1, green: 0.2, blue: 0.1, alpha: 0.95))
        drawCircle(cx, cy - off, r)
        fill(Color(red: 0.1, green: 1, blue: 0.3, alpha: 0.95))
        drawCircle(cx - off, cy + off * 0.7, r)
        fill(Color(red: 0.2, green: 0.4, blue: 1, alpha: 0.95))
        drawCircle(cx + off, cy + off * 0.7, r)
    }
}
