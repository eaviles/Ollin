import CoreGraphics
import Foundation
import Metal
import MetalKit
import Testing
@testable import Ollin

/// The canvas depth of field, `depthOfField()`: the finished 3D frame blurred by
/// its own depth through the camera's thin lens.
///
/// What a sketch is promised: a point at distance d spreads over a disc of radius
/// R·F·|1/s − 1/d| pixels (R the aperture, F the focal length in pixels, s the
/// focus), keeping its light; a highlight opens into an even disc rather than a
/// sharp core in a halo; a subject in focus keeps its edge against a blurred
/// background; a defocused foreground turns into a veil over the subject behind
/// it; what a blurred foreground hides is read from a second layer of the scene
/// rather than guessed from what shows beside it, and that layer is drawn only
/// when something stands in the near field and only where it stands; the band
/// `focusRange` holds stays sharp and `maxBlur` caps the rest; the pass runs
/// beside temporal anti-aliasing and motion blur; a pinhole or an orthographic
/// camera leaves the frame alone; and an export repeats itself.
@Suite
@MainActor
struct DepthOfFieldTests {

    // A 512 px canvas, a 45 degree field of view, the eye at z = 6 looking at the
    // origin, a lens of radius 0.3 focused 6 units out.
    static let size = 512
    static let fov = Double.pi / 4
    static let F = Double(size) / 2 / tan(fov / 2)
    static let R = 0.3
    static let s = 6.0
    static func coc(_ d: Double, focus: Double = s) -> Double { R * F * abs(1 / focus - 1 / d) }

    final class Lens: Sketch {
        enum Content {
            case bars([Double]), highlight(Double), subject(bar: Bool), ball(Double)
            /// A flat white disc facing the eye, 100 px across at its distance.
            case disc(Double)
            /// The hidden-surface scene: a white ball in front of the focus over a red floor
            /// that runs away behind it, the floor a closed box, an open plane seen from its
            /// back, or a raymarched slab.
            case ballOverFloor(Floor)
            /// A small highlight behind the focus with a sharp dark bar in front of
            /// its right half, at the focus.
            case highlightBehindBar(Double)
        }
        enum Floor { case box, planeFromBehind, marched }
        var content = Content.bars([3, 6.1, 11])
        var aperture = DepthOfFieldTests.R
        var orthographic = false
        var blurs = true
        var focusRange = 0.0
        var maxBlur = 64.0
        var quality = RenderQuality.default
        var highlightRadius = 2.5
        var temporal = false
        override var canvasSize: CanvasSize { .square(DepthOfFieldTests.size) }

        /// A point `px`, `py` pixels off the center (y up) at distance `d`.
        func at(_ px: Double, _ py: Double, _ d: Double) -> Vector3 {
            Vector3(px * d / DepthOfFieldTests.F, py * d / DepthOfFieldTests.F, 6 - d)
        }

        override func draw() {
            background(.black)
            if orthographic {
                ortho(eye: Vector3(0, 0, 6), target: .zero, height: 8, near: 1, far: 20)
            } else {
                var lens = Camera3D.perspective(eye: Vector3(0, 0, 6), target: .zero,
                                                fieldOfView: DepthOfFieldTests.fov, near: 1, far: 20)
                lens.aperture = aperture
                lens.focusDistance = DepthOfFieldTests.s
                camera(lens)
            }
            if temporal { temporalAntialiasing(); motionBlur() }
            if blurs { depthOfField(focusRange: focusRange, maxBlur: maxBlur, quality: quality) }
            noLights()
            fill(.white)
            switch content {
            case .bars(let depths):
                // Thin glowing bars, 1.2 px wide and 150 tall, side by side.
                for (i, d) in depths.enumerated() {
                    let p = at(-180 + Double(i) * 180, 0, d)
                    let w = 1.2 * d / DepthOfFieldTests.F, h = 150 * d / DepthOfFieldTests.F
                    withState { translate(p.x, p.y, p.z); drawMesh(Mesh.box(width: w, height: h, depth: w).glowing(4)) }
                }
            case .highlight(let d):
                let p = at(0, 0, d)
                withState { translate(p.x, p.y, p.z); drawMesh(Mesh.sphere(radius: highlightRadius * d / DepthOfFieldTests.F).glowing(40)) }
            case .highlightBehindBar(let d):
                let p = at(0, 0, d)
                withState { translate(p.x, p.y, p.z); drawMesh(Mesh.sphere(radius: 2.5 * d / DepthOfFieldTests.F).glowing(40)) }
                // The bar: 8 px wide at the focus, its left edge 4 px right of the
                // highlight's center, so it stands over the disc's right half.
                let s = DepthOfFieldTests.s
                let b = at(8, 0, s)
                fill(Color(white: 0.2))
                withState {
                    translate(b.x, b.y, b.z)
                    drawMesh(Mesh.box(width: 8 * s / DepthOfFieldTests.F, height: 150 * s / DepthOfFieldTests.F,
                                      depth: 0.02))
                }
            case .ball(let d):
                // A white ball in front of the focus, its middle `d` from the eye.
                let p = at(0, 0, d)
                withState { translate(p.x, p.y, p.z); drawMesh(Mesh.sphere(radius: 0.5, segments: 96, rings: 48).glowing(1)) }
            case .disc(let d):
                // A flat disc facing the eye, 100 px across at `d`: a cylinder a hair
                // thick, turned to stand on the view axis.
                let p = at(0, 0, d)
                let r = 100 * d / DepthOfFieldTests.F
                withState {
                    translate(p.x, p.y, p.z); rotateX(.pi / 2)
                    drawMesh(Mesh.cylinder(radius: r, height: 0.002, segments: 256).glowing(1))
                }
            case .ballOverFloor(let floor):
                // The hidden-surface case: a white ball in front of the focus, its
                // top a few pixels above the far edge of a red floor that runs away
                // behind it, so in the pinhole view the backdrop stands above the
                // ball's top and the floor is hidden behind it. A lens looking past
                // the ball's top sees that hidden floor.
                let p = at(0, 0, 3.5)
                withState { translate(p.x, p.y - 0.45, p.z); drawMesh(Mesh.sphere(radius: 0.5, segments: 96, rings: 48).glowing(1)) }
                fill(Color(red: 1, green: 0, blue: 0))   // unlit, so every floor is the same red
                switch floor {
                case .box:
                    withState {
                        translate(0, -0.3, 6 - 12.25)
                        drawMesh(Mesh.box(width: 12, height: 0.02, depth: 15.5))
                    }
                case .planeFromBehind:
                    // The same floor as a one-sided plane turned to face away from
                    // the eye: a surface the lens sees from its back.
                    withState {
                        translate(0, -0.3, 6 - 12.25)
                        rotateX(.pi)
                        drawMesh(Mesh.plane(width: 12, depth: 15.5))
                    }
                case .marched:
                    // The same floor as a raymarched slab.
                    union {
                        withState {
                            translate(0, -0.3, 6 - 12.25)
                            drawBox(width: 12, height: 0.02, depth: 15.5)
                        }
                    }
                }
            case .subject(let bar):
                // A checker far behind, a ball in focus, and a bar near the eye.
                let tile = 32.0, d = 16.0
                for gy in -8 ..< 8 {
                    for gx in -8 ..< 8 where (gx + gy) & 1 == 0 {
                        let p = at((Double(gx) + 0.5) * tile, (Double(gy) + 0.5) * tile, d)
                        let w = tile * d / DepthOfFieldTests.F
                        withState { translate(p.x, p.y, p.z); drawMesh(Mesh.box(width: w, height: w, depth: 0.01).glowing(1)) }
                    }
                }
                fill(Color(red: 0.9, green: 0.35, blue: 0.2))
                drawMesh(Mesh.sphere(radius: 0.9, segments: 96, rings: 48).glowing(1))
                if bar {
                    let b = at(-60, 0, 3)
                    fill(Color(red: 0.2, green: 0.45, blue: 1.0))
                    withState {
                        translate(b.x, b.y, b.z)
                        drawMesh(Mesh.box(width: 40 * 3 / DepthOfFieldTests.F,
                                          height: 400 * 3 / DepthOfFieldTests.F, depth: 0.05).glowing(1))
                    }
                }
            }
        }
    }

    /// The frame in linear light, one luminance per pixel, row 0 at the top.
    struct Frame {
        let size: Int
        let rgb: [SIMD3<Float>]
        func lum(_ x: Int, _ y: Int) -> Double {
            let c = rgb[y * size + x]
            return Double(0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z)
        }
        func red(_ x: Int, _ y: Int) -> Double { Double(rgb[y * size + x].x) }
    }

    private func render(_ sketch: Lens, frame: Int = 0) throws -> Frame {
        try renderKeepingRenderer(sketch, frame: frame).frame
    }

    /// The frame, and the renderer that drew it (for what it reports of the pass).
    private func renderKeepingRenderer(_ sketch: Lens, frame: Int = 0) throws -> (frame: Frame, renderer: MetalRenderer) {
        let renderer = try OllinApp.headlessRenderer(for: sketch)
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        renderer.capturesLinearFrame = true
        _ = try OllinApp.renderImage(of: sketch, frame: frame, fps: 60, renderer: renderer)
        let linear = try #require(renderer.lastLinearFrame)
        let n = linear.width * linear.height
        let halfs = linear.color.contents().bindMemory(to: Float16.self, capacity: n * 4)
        var rgb = [SIMD3<Float>](repeating: .zero, count: n)
        for i in 0 ..< n { rgb[i] = SIMD3(Float(halfs[i * 4]), Float(halfs[i * 4 + 1]), Float(halfs[i * 4 + 2])) }
        return (Frame(size: linear.width, rgb: rgb), renderer)
    }

    private func lens(_ configure: (Lens) -> Void = { _ in }) -> Lens {
        let sketch = Lens()
        configure(sketch)
        return sketch
    }

    // MARK: Measures

    /// The horizontal profile of the bar centered at `cx`, averaged over its middle rows.
    private func profile(_ f: Frame, _ cx: Int) -> [Double] {
        (cx - 60 ... cx + 60).map { x in (206 ... 306).reduce(0.0) { $0 + max(f.lum(x, $1), 0) } / 101 }
    }

    /// The radius of the disc that spreads a line into `p`, from the profile's
    /// second moment (a disc of radius r spreads a line to a moment of r²/4),
    /// less the sharp line's own.
    private func radius(_ p: [Double], sharp: [Double]) -> Double {
        func moment(_ p: [Double]) -> Double {
            let total = p.reduce(0, +)
            let mean = p.enumerated().reduce(0.0) { $0 + Double($1.offset) * $1.element } / total
            return p.enumerated().reduce(0.0) { $0 + pow(Double($1.offset) - mean, 2) * $1.element } / total
        }
        return 2 * sqrt(max(moment(p) - moment(sharp), 0))
    }

    private func barCenter(_ i: Int) -> Int { 256 - 180 + i * 180 }

    // MARK: The lens

    @Test(.enabled(if: Snapshot.hasMetal))
    func barsSpreadByTheThinLensAndKeepTheirLight() throws {
        // One in front of the focus, one a hair behind it (a blur under half a
        // pixel), one well behind. The middle one stands against the backdrop,
        // which blurs as the far plane: a sharp line keeps its light only while
        // that blur is held back from reaching across it.
        let depths = [3.0, 6.1, 11.0]
        let sharp = try render(lens { $0.content = .bars(depths); $0.blurs = false })
        let blurred = try render(lens { $0.content = .bars(depths) })
        for (i, d) in depths.enumerated() {
            let p = profile(blurred, barCenter(i)), q = profile(sharp, barCenter(i))
            let r = radius(p, sharp: q)
            #expect(abs(r - Self.coc(d)) < 1, "bar at \(d): radius \(r) against the lens's \(Self.coc(d))")
            let light = p.reduce(0, +) / q.reduce(0, +)
            #expect(light > 0.95 && light < 1.03, "bar at \(d) kept \(light) of its light")
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aHighlightOpensIntoAnEvenDisc() throws {
        let d = 9.0
        let sharp = try render(lens { $0.content = .highlight(d); $0.blurs = false })
        let blurred = try render(lens { $0.content = .highlight(d) })
        var total = 0.0, sharpTotal = 0.0, moment = 0.0, peak = 0.0
        for y in 196 ... 316 {
            for x in 196 ... 316 {
                let v = max(blurred.lum(x, y), 0)
                total += v
                sharpTotal += max(sharp.lum(x, y), 0)
                moment += v * Double((x - 256) * (x - 256) + (y - 256) * (y - 256))
                peak = max(peak, v)
            }
        }
        let r = sqrt(2 * moment / total)   // a disc of radius r has a mean squared radius of r²/2
        #expect(abs(r - Self.coc(d)) < 1, "radius \(r) against the lens's \(Self.coc(d))")
        #expect(total / sharpTotal > 0.9 && total / sharpTotal < 1.05, "kept \(total / sharpTotal) of its light")
        // An even disc's mean over its own area: a sharp core left in a halo peaks far above it.
        let mean = total / (Double.pi * r * r)
        #expect(peak / mean < 2, "peak \(peak) against a mean of \(mean)")
    }

    /// At the lowest tier the taps are few, and a small highlight drawn as a disc of
    /// its own keeps its light and its evenness all the same.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aSmallHighlightIsEvenAtTheLowestTier() throws {
        let d = 9.0
        let sharp = try render(lens { $0.content = .highlight(d); $0.blurs = false })
        let blurred = try render(lens { $0.content = .highlight(d); $0.quality = .performance })
        var total = 0.0, sharpTotal = 0.0, moment = 0.0, peak = 0.0
        var inside = [Double]()
        let coc = Self.coc(d)
        for y in 196 ... 316 {
            for x in 196 ... 316 {
                let v = max(blurred.lum(x, y), 0)
                total += v
                sharpTotal += max(sharp.lum(x, y), 0)
                let r2 = Double((x - 256) * (x - 256) + (y - 256) * (y - 256))
                moment += v * r2
                peak = max(peak, v)
                if r2 < (coc - 2) * (coc - 2) { inside.append(v) }
            }
        }
        let r = sqrt(2 * moment / total)
        #expect(abs(r - coc) < 1, "radius \(r) against the lens's \(coc)")
        #expect(total / sharpTotal > 0.95 && total / sharpTotal < 1.05, "kept \(total / sharpTotal) of its light")
        let mean = total / (Double.pi * r * r)
        #expect(peak / mean < 1.3, "peak \(peak) against a mean of \(mean)")
        // Inside the disc the light is even: no pixel more than a quarter from the mean.
        let insideMean = inside.reduce(0, +) / Double(inside.count)
        let spread = inside.map { abs($0 - insideMean) }.max() ?? 0
        #expect(spread / insideMean < 0.25, "the disc's interior strays \(spread / insideMean) of its mean")
    }

    /// A sharp bar in focus in front of a far highlight cuts its disc at the bar's
    /// own edge: the disc shows on one side and not over the bar.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aSharpBarCutsTheDiscOfAHighlightBehindIt() throws {
        let f = try render(lens { $0.content = .highlightBehindBar(11) })
        let overBar = f.lum(266, 256), beside = f.lum(246, 256)
        #expect(beside > 0.5, "the disc's uncovered side reads \(beside)")
        #expect(overBar < 0.15, "the disc reads \(overBar) over the bar in front of it")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aSubjectInFocusKeepsItsEdge() throws {
        let f = try render(lens { $0.content = .subject(bar: false) })
        // The ball's right edge, 0.9 units at distance 6, against the blurred checker behind it.
        let edge = Int(256 + 0.9 * Self.F / 6)
        var rim = 0.0, middle = 0.0
        for y in 240 ..< 272 {
            for x in edge - 8 ..< edge - 2 { rim += f.lum(x, y) / 6 }
            for x in 290 ..< 310 { middle += f.lum(x, y) / 20 }
        }
        #expect(abs(rim / middle - 1) < 0.01, "the ball's edge reads \(rim / middle) of its middle")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aNearBarIsAVeilOverTheSubject() throws {
        let sharp = try render(lens { $0.content = .subject(bar: true); $0.blurs = false })
        let veiled = try render(lens { $0.content = .subject(bar: true) })
        // How much of the ball the bar covers across it, from the red channel (the
        // ball is red, the bar blue): a 40 px bar under a disc of the lens's radius
        // covers 0.76 of a pixel at its middle, half at its edges, 0.30 ten pixels
        // out and nothing past the disc.
        let r = Self.coc(3)
        func expected(_ x: Double) -> Double {
            // The share of a disc centered x pixels from the bar's middle inside |x| < 20.
            func below(_ a: Double) -> Double {
                let t = max(-1, min(1, a / r))
                return 0.5 + (asin(t) + t * sqrt(1 - t * t)) / .pi
            }
            return below(20 - x) - below(-20 - x)
        }
        let ball = (250 ... 262).reduce(0.0) { $0 + sharp.red(300, $1) } / 13
        let bar = (250 ... 262).reduce(0.0) { $0 + sharp.red(196, $1) } / 13
        for x in [196, 216, 226, 250] {
            let seen = (250 ... 262).reduce(0.0) { $0 + veiled.red(x, $1) } / 13
            let cover = (ball - seen) / (ball - bar)
            #expect(abs(cover - expected(Double(x - 196))) < 0.08,
                    "at \(x): the bar covers \(cover), the lens \(expected(Double(x - 196)))")
        }
    }

    /// A flat disc in front of the focus over the backdrop comes out as the lens shows
    /// it: whole from one blur inside its silhouette, half at the silhouette, gone
    /// one blur outside, the overlap of two circles in between (`lensDiscCover`).
    /// The radial mean over every angle, against the disc's own inside level.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aDiscFollowsTheLensAtEveryRadius() throws {
        let d = 3.5
        let profile = try LinearLuminanceFrame(of: lens { $0.content = .disc(d) })
            .radialProfile(center: (256, 256), maxRadius: 160)
        let inside = (20 ... 40).reduce(0.0) { $0 + profile[$1] } / 21
        let r = Self.coc(d)
        for x in stride(from: 20, through: 160, by: 4) {
            let expected = lensDiscCover(subject: 100, kernel: r, at: Double(x))
            #expect(abs(profile[x] / inside - expected) < 0.015,
                    "\(x) px out: \(profile[x] / inside) against the lens's \(expected)")
        }
    }

    /// A ball in front of the focus comes out as the lens shows it. The reference is
    /// the thin lens's own geometry, with nothing of the gather in it: at each radius
    /// from the ball's center, the share of lens points whose ray through that
    /// pixel's point on the focal plane meets the sphere, the integral the
    /// accumulation lens renders. Spread by its own blur alone, the rim (nearer than
    /// the center, so blurred wider than the lens blurs the silhouette) read a
    /// thirtieth too opaque outside and a twentieth too transparent inside; the
    /// Jacobian of the blur's slope in each tap's weight, and the surface's share read
    /// as that density, close it.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aBlurredBallsEdgeFollowsTheLens() throws {
        let d = 3.5, ball = 0.5
        let profile = try LinearLuminanceFrame(of: lens { $0.content = .ball(d) })
            .radialProfile(center: (256, 256), maxRadius: 150)
        let inside = (20 ... 40).reduce(0.0) { $0 + profile[$1] } / 21
        let silhouette = Self.F * ball / (d * d - ball * ball).squareRoot()
        var worst = 0.0
        for x in stride(from: Int(silhouette - 30), through: Int(silhouette + Self.coc(d) + 4), by: 2) {
            let expected = Self.thinLensSphereCover(pixelRadius: Double(x), sphereDistance: d, sphereRadius: ball)
            let error = abs(profile[x] / inside - expected)
            worst = max(worst, error)
            #expect(error < 0.02, "\(x) px out: \(profile[x] / inside) against the lens's \(expected)")
        }
        // Measured 0.017 at its worst, 15 to 20 px inside the rim; 0.072 on the old
        // gather, outside the rim.
        #expect(worst < 0.02, "the ball's edge sits \(worst) from the lens at its worst")
    }

    /// The thin lens's own cover of a sphere on the view axis, at a pixel
    /// `pixelRadius` from its center: the share of points on the lens (radius `R`,
    /// at the eye) whose ray through the pixel's point on the focal plane (the plane
    /// `s` from the eye, held still as the lens point moves, which is what keeps the
    /// focus sharp) passes within the sphere's radius of its center. 4096 lens points
    /// on a Vogel disc.
    static func thinLensSphereCover(pixelRadius x: Double, sphereDistance d: Double, sphereRadius: Double) -> Double {
        let focal = SIMD3<Double>(x * s / F, 0, -s)          // the pixel's point on the focal plane
        let center = SIMD3<Double>(0, 0, -d)
        let n = 4096
        var hits = 0
        for i in 0 ..< n {
            let rr = R * ((Double(i) + 0.5) / Double(n)).squareRoot()
            let a = Double(i) * 2.399963229728653
            let p = SIMD3<Double>(rr * cos(a), rr * sin(a), 0)
            let dir = simd_normalize(focal - p)
            let toCenter = center - p
            let along = simd_dot(toCenter, dir)
            let miss = simd_length(toCenter - along * dir)
            if miss < sphereRadius { hits += 1 }
        }
        return Double(hits) / Double(n)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aBlurredBallHasNoOutline() throws {
        // Across the edge of a ball in front of the focus, its cover falls smoothly:
        // no pixel to the next steps by more than a disc of the ball's blur allows
        // (a blur of radius r spreads an edge over 2r, its steepest slope about
        // 2 / (pi r) a pixel). A surface whose nearer half counted twice inside its
        // edge drew a step there, an outline.
        let d = 3.5
        let f = try render(lens { $0.content = .ball(d) })
        let row = (250 ... 262).map { y in (256 ... 400).map { f.lum($0, y) } }
        let profile = (0 ..< row[0].count).map { x in row.reduce(0.0) { $0 + $1[x] } / Double(row.count) }
        let inside = profile[0]
        var steepest = 0.0
        for x in 1 ..< profile.count { steepest = max(steepest, abs(profile[x] - profile[x - 1]) / inside) }
        let r = Self.coc(d)
        #expect(steepest < 2.5 * 2 / (.pi * r), "the cover steps by \(steepest) a pixel; a blur of \(r) px falls by at most \(2 / (.pi * r))")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aBlurredBallShowsTheFloorHiddenBehindIt() throws {
        // The ball's top band stands over the backdrop in the pinhole view, with
        // the red floor hidden behind it. Read from the frame alone, what shows
        // through the ball there is the backdrop; read from the hidden layer, it is
        // the floor, and the band carries red the ball (white) and the backdrop
        // (black) cannot give. The floor's far edge projects 9 px below the center
        // and the ball's top 9 px above it.
        let sharp = try render(lens { $0.content = .ballOverFloor(.box); $0.blurs = false })
        let (f, renderer) = try renderKeepingRenderer(lens { $0.content = .ballOverFloor(.box) })
        #expect(renderer.hiddenLayerDrawnLastFrame, "the frame has a near-field ball and drew no hidden layer")
        // The pinhole band is the white ball alone (no red beyond white's own).
        #expect(abs(redness(sharp)) < 0.01, "the pinhole band reads \(redness(sharp)) red over green")
        let seen = redness(f)
        #expect(seen > 0.02, "the floor hidden behind the ball's top shows \(seen) red over green through it")
        // What the lens shows above the ball is still the backdrop and the ball's
        // own veil, never the floor: the hidden layer joins only under the near field.
        var above = 0.0, m = 0.0
        for y in 180 ... 200 { for x in 216 ... 296 { let c = f.rgb[y * f.size + x]; above += Double(c.x - c.y); m += 1 } }
        #expect(abs(above / m) < 0.01, "above the ball reads \(above / m) red over green")
    }

    /// The band through the ball's top, red over green, averaged (the floor is red,
    /// the ball white, the backdrop black).
    private func redness(_ frame: Frame) -> Double {
        var sum = 0.0, n = 0.0
        for y in 247 ... 265 {
            for x in 216 ... 296 {
                let c = frame.rgb[y * frame.size + x]
                sum += Double(c.x - c.y); n += 1
            }
        }
        return sum / n
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func anOpenSurfaceSeenFromItsBackJoinsTheHiddenLayer() throws {
        // The floor as a plane facing away from the eye: a closed shape's back
        // face is its inside and stays out of the layer, but an open surface's
        // back face is the surface, and the lens sees it behind the ball.
        let f = try render(lens { $0.content = .ballOverFloor(.planeFromBehind) })
        let seen = redness(f)
        #expect(seen > 0.02, "the plane hidden behind the ball's top shows \(seen) red over green through it")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aRaymarchedFieldBehindTheBallJoinsTheHiddenLayer() throws {
        // The floor as a raymarched slab: the march starts behind the first layer,
        // so under the ball it finds the slab.
        let f = try render(lens { $0.content = .ballOverFloor(.marched) })
        let seen = redness(f)
        #expect(seen > 0.02, "the marched floor hidden behind the ball's top shows \(seen) red over green through it")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theHiddenLayerIsDrawnOnlyWhenAndWhereTheNearFieldIs() throws {
        // Nothing in front of the focus: no second pass at all.
        let (_, far) = try renderKeepingRenderer(lens { $0.content = .bars([6.1, 11]) })
        #expect(!far.hiddenLayerDrawnLastFrame, "a frame with nothing in the near field drew the hidden layer")
        // A ball in front of the focus: the pass, over the ball's own pixels and a
        // margin, not the whole frame (the ball is 88 px across at its distance).
        let (_, near) = try renderKeepingRenderer(lens { $0.content = .ball(3.5) })
        #expect(near.hiddenLayerDrawnLastFrame, "a frame with a near-field ball drew no hidden layer")
        let extent = near.hiddenLayerExtentLastFrame
        #expect(extent.width < Self.size / 2 && extent.height < Self.size / 2,
                "the layer covered \(extent.width) by \(extent.height) of \(Self.size)")
        #expect(extent.x <= 256 - 88 && extent.x + extent.width >= 256 + 88,
                "the layer's columns \(extent.x) to \(extent.x + extent.width) miss the ball")
        // The pinhole camera draws none either (the pass belongs to the lens).
        let (_, pinhole) = try renderKeepingRenderer(lens { $0.content = .ball(3.5); $0.aperture = 0 })
        #expect(!pinhole.hiddenLayerDrawnLastFrame)
    }

    // MARK: The settings

    @Test(.enabled(if: Snapshot.hasMetal))
    func focusRangeHoldsABandSharpAndMaxBlurCapsTheRest() throws {
        let depths = [6.4, 8.0]
        let sharp = try render(lens { $0.content = .bars(depths); $0.blurs = false })
        let banded = try render(lens { $0.content = .bars(depths); $0.focusRange = 0.5 })
        let held = radius(profile(banded, barCenter(0)), sharp: profile(sharp, barCenter(0)))
        #expect(held < 0.5, "a bar inside the band spread \(held) px")
        // Past the band the blur grows from its edge.
        let past = radius(profile(banded, barCenter(1)), sharp: profile(sharp, barCenter(1)))
        let fromEdge = Self.coc(8, focus: 6.5)
        #expect(abs(past - fromEdge) < 1, "radius \(past) against \(fromEdge) from the band's edge")

        let near = [2.5]
        let nearSharp = try render(lens { $0.content = .bars(near); $0.blurs = false })
        let capped = try render(lens { $0.content = .bars(near); $0.maxBlur = 12 })
        let r = radius(profile(capped, barCenter(0)), sharp: profile(nearSharp, barCenter(0)))
        #expect(abs(r - 12) < 1, "capped at 12 points, spread \(r) (the lens alone: \(Self.coc(2.5)))")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func itRunsBesideTemporalAntialiasingAndMotionBlur() throws {
        let depths = [3.0, 11.0]
        let sharp = try render(lens { $0.content = .bars(depths); $0.temporal = true; $0.blurs = false }, frame: 3)
        let blurred = try render(lens { $0.content = .bars(depths); $0.temporal = true }, frame: 3)
        for (i, d) in depths.enumerated() {
            let r = radius(profile(blurred, barCenter(i)), sharp: profile(sharp, barCenter(i)))
            #expect(abs(r - Self.coc(d)) < 1, "bar at \(d) under both: radius \(r) against \(Self.coc(d))")
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theWindowShowsWhatTheExportWrites() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let renderer = try MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device))
        // An export lifts `.default` to `.detail`; the window takes the same tier
        // here so the two run the same taps.
        renderer.automaticQuality = .detail
        let side = Self.size
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: side, height: side), device: device)
        view.colorPixelFormat = ollinColorPixelFormat
        view.framebufferOnly = false
        view.drawableSize = CGSize(width: side, height: side)
        view.isPaused = true
        view.enableSetNeedsDisplay = true

        final class Delivery { var image: CGImage? }
        /// One refresh of the window, and the frame it showed.
        func live(_ sketch: Lens) -> [UInt8]? {
            sketch.setCanvasSize(width: Double(side), height: Double(side))
            sketch.setup()
            sketch.performDraw()
            let delivery = Delivery()
            let request = MetalRenderer.FrameGrabRequest(width: side, height: side, wantsImage: true,
                                                         wantsTexture: false) { image, _ in delivery.image = image }
            renderer.render(sketch.drawer, viewport: SIMD2<Float>(Float(side), Float(side)),
                            in: view, grab: request)
            let deadline = Date().addingTimeInterval(20)
            while delivery.image == nil {
                RunLoop.main.run(until: Date().addingTimeInterval(0.01))
                if Date() > deadline { break }
            }
            return delivery.image.map(bytes)
        }
        let window = try #require(live(lens()))
        let sharpWindow = try #require(live(lens { $0.blurs = false }))
        let export = bytes(try OllinApp.image(of: lens(), frame: 0))
        func difference(_ a: [UInt8], _ b: [UInt8]) -> Double {
            Double(zip(a, b).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }) / Double(a.count)
        }
        let blurred = difference(window, sharpWindow)
        #expect(blurred > 0.5, "the window's frame barely moved under the lens: \(blurred)")
        #expect(window == export, "the window and the export differ by \(difference(window, export)) a byte")
    }

    private func bytes(_ image: CGImage) -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aPinholeOrAnOrthographicCameraLeavesTheFrameAlone() throws {
        let plain = try render(lens { $0.blurs = false })
        let pinhole = lens { $0.aperture = 0 }
        let pinholeFrame = try render(pinhole)
        #expect(pinholeFrame.rgb == plain.rgb)
        #expect(pinhole.drawer.drawerNotes.contains { $0.contains("aperture is 0") })

        let flatPlain = try render(lens { $0.orthographic = true; $0.blurs = false })
        let flat = lens { $0.orthographic = true }
        let flatFrame = try render(flat)
        #expect(flatFrame.rgb == flatPlain.rgb)
        #expect(flat.drawer.drawerNotes.contains { $0.contains("orthographic") })
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func anExportRepeatsItself() throws {
        func export() throws -> [UInt8] {
            bytes(try OllinApp.image(of: lens { $0.content = .subject(bar: true) }, frame: 0))
        }
        #expect(try export() == export())
    }
}
