@testable import Ollin
import CoreGraphics
import Testing

/// Packing checks for `specularAntialiasing()`: the strength the sketch asks for has to
/// arrive at the shader as the variance of the pixel filter in image space, and zero has
/// to stay zero, because zero is the gate that keeps every unfiltered frame on its exact
/// old arithmetic.
@Suite
struct SpecularAntialiasStateTests {

    private func freshDrawer() -> Drawer {
        let d = Drawer()
        d.beginFrame()
        d.camera(Camera3D(eye: Vector3(0, 0, 5), target: .zero))
        return d
    }

    @Test func strengthBecomesTheImageSpaceVariance() {
        let full = freshDrawer()
        full.specularAntialiasing()
        #expect(abs(full.makeLighting().specularFilter - 0.25) < 1e-7)

        let half = freshDrawer()
        half.specularAntialiasing(strength: 0.5)
        #expect(abs(half.makeLighting().specularFilter - 0.125) < 1e-7)
    }

    @Test func everyWayOfSayingNoLeavesTheGateDown() {
        let untouched = freshDrawer()
        #expect(untouched.makeLighting().specularFilter == 0)

        let off = freshDrawer()
        off.specularAntialiasing(false)
        #expect(off.makeLighting().specularFilter == 0)

        let stopped = freshDrawer()
        stopped.specularAntialiasing()
        stopped.noSpecularAntialiasing()
        #expect(stopped.makeLighting().specularFilter == 0)

        // A negative strength is nonsense rather than an inverse filter, so it clamps to
        // off instead of widening by a negative amount the shader would take the root of.
        let negative = freshDrawer()
        negative.specularAntialiasing(strength: -1)
        #expect(negative.makeLighting().specularFilter == 0)
    }

    @Test func itIsPerFrameStateLikeTheLights() {
        let d = freshDrawer()
        d.specularAntialiasing()
        d.beginFrame()
        d.camera(Camera3D(eye: Vector3(0, 0, 5), target: .zero))
        #expect(d.makeLighting().specularFilter == 0)
    }
}

/// Behavioral probes for `specularAntialiasing()`. The claim is temporal, so a pixel
/// snapshot cannot pin any of it: a highlight narrower than a pixel is a speck the one
/// shading sample per pixel either lands on or misses, so a shiny surface with detail
/// finer than a pixel crawls with sparkle as it turns.
///
/// The measurement is **crawl**: the mean absolute second difference over three
/// consecutive frames, in linear light, times 255. A picture that moves smoothly cancels
/// in a second difference; a speck that switches on for one frame does not. The number
/// only means something against the crawl of the *converged* sequence (the same frames
/// supersampled sixteen ways and averaged in linear light before the tone map), which is
/// how much the picture is really supposed to change. Everything above that is the
/// artifact, and that excess is what these measure.
///
/// The counterfactuals run beside it. A flat surface has no spread of normals to find,
/// so it must come back untouched, which is what separates this from a blur.
/// Metal-gated.
@Suite
@MainActor
struct SpecularAntialiasRenderTests {

    // MARK: What it is for

    /// The headline. A rippled sheet far enough away that each pixel covers several
    /// ripples: measured over five frames a quarter of a degree apart, the converged
    /// sequence crawls 0.039 (that is the real motion), the unfiltered render 0.148, and
    /// the filtered one 0.112. Read as excess over the truth, the filter removes a third
    /// of the artifact at strength 1. A third rather than all of it is honest for a
    /// screen-space estimate: the derivative that measures the spread is itself sampled
    /// once per pixel.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aSurfaceFinerThanItsPixelsCrawlsLess() throws {
        let truth = crawl(try frames(strength: nil, converged: true))
        let off = crawl(try frames(strength: nil))
        let on = crawl(try frames(strength: 1))
        #expect(off > truth * 2,
                "the unfiltered sheet should crawl well past the truth (\(off) vs \(truth))")
        #expect(on < off, "the filtered sheet still crawls \(on) against \(off) unfiltered")
        let removed = (off - on) / (off - truth)
        #expect(removed > 0.2,
                "only \(removed) of the excess crawl went (truth \(truth), off \(off), on \(on))")
    }

    /// More strength buys more calm, which is what makes it a knob rather than a switch.
    /// Strength 2 is the conservative kernel of the published work, and it reads quieter
    /// again: 0.087 against 0.112 at strength 1 and 0.148 unfiltered.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theKnobKeepsBuying() throws {
        let off = crawl(try frames(strength: nil))
        let some = crawl(try frames(strength: 1))
        let more = crawl(try frames(strength: 2))
        #expect(some < off, "strength 1 (\(some)) should be quieter than off (\(off))")
        #expect(more < some, "strength 2 (\(more)) should be quieter than 1 (\(some))")
    }

    // MARK: What it must not touch

    /// The counterfactual, and the reason this is not a blur. A flat sheet holds one
    /// normal across every pixel of it, so there is no spread to widen by and the
    /// filtered frame is the unfiltered frame, to the byte. Same material and same light
    /// as the ripples, so the only difference is the surface.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aFlatSurfaceIsLeftAlone() throws {
        let plain = try #require(OllinApp.image(of: FlatSheetProbe.make(strength: nil), frame: 0))
        let filtered = try #require(OllinApp.image(of: FlatSheetProbe.make(strength: 1), frame: 0))
        #expect(maxDifference(plain, filtered) == 0)
    }

    /// Turning it off is exact, not nearly exact: the gate is read before the two
    /// derivatives are taken and before any roughness is touched, so a sketch can A/B the
    /// feature and know that what it sees is the feature.
    @Test(.enabled(if: Snapshot.hasMetal))
    func turningItOffChangesNothing() throws {
        let never = try #require(OllinApp.image(of: RippleProbe.make(strength: nil), frame: 0))
        let asked = try #require(OllinApp.image(of: RippleProbe.make(strength: 0), frame: 0))
        #expect(maxDifference(never, asked) == 0)
    }

    /// A sketch that lights nothing cannot pay for this. The unlit path returns the
    /// surface flat before any roughness is read, so the filter finds nothing to do even
    /// while the frame asks for it.
    @Test(.enabled(if: Snapshot.hasMetal))
    func anUnlitFrameIsUntouched() throws {
        let plain = try #require(OllinApp.image(of: RippleProbe.make(strength: nil, unlit: true),
                                                frame: 0))
        let filtered = try #require(OllinApp.image(of: RippleProbe.make(strength: 1, unlit: true),
                                                   frame: 0))
        #expect(maxDifference(plain, filtered) == 0)
    }

    // MARK: Measurement

    /// Five frames a quarter of a degree apart: far enough to move the picture, close
    /// enough that a highlight which stays put moves as a smooth ramp rather than a jump.
    /// `converged` renders each of them sixteen samples to a pixel with the deterministic
    /// jitter on top, averaged in linear light before the tone map, which is the sequence
    /// the other two are trying to be.
    private func frames(strength: Double?, converged: Bool = false) throws -> [[Double]] {
        OllinApp.exportRenderScale = converged ? 4 : 1
        defer { OllinApp.exportRenderScale = 1 }
        return try (0 ..< 5).map { step in
            let probe = RippleProbe.make(strength: strength, azimuth: Double(step) * 0.004,
                                         converged: converged)
            return luminance(of: try #require(OllinApp.image(of: probe, frame: 0)))
        }
    }

    /// How much the picture flickers rather than moves: the mean absolute second
    /// difference of the linear luminance over each run of three frames, times 255 so the
    /// number reads in the units of the picture it came from.
    private func crawl(_ planes: [[Double]]) -> Double {
        guard planes.count >= 3 else { return 0 }
        var sum = 0.0, count = 0
        for t in 1 ..< (planes.count - 1) {
            let a = planes[t - 1], b = planes[t], c = planes[t + 1]
            for i in 0 ..< b.count {
                sum += abs(c[i] - 2 * b[i] + a[i])
                count += 1
            }
        }
        return count > 0 ? 255 * sum / Double(count) : 0
    }

    /// One frame as linear luminance, pixel by pixel. The present pass encodes for
    /// display, and a difference between frames only means something in the space the
    /// light was added in.
    private func luminance(of image: CGImage) -> [Double] {
        let px = pixels(of: image)
        return (0 ..< (image.width * image.height)).map { i in
            0.2126 * linear(px[i * 4]) + 0.7152 * linear(px[i * 4 + 1]) + 0.0722 * linear(px[i * 4 + 2])
        }
    }

    private func linear(_ byte: UInt8) -> Double {
        let v = Double(byte) / 255
        return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    private func pixels(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    private func maxDifference(_ a: CGImage, _ b: CGImage) -> Int {
        let pa = pixels(of: a), pb = pixels(of: b)
        var worst = 0
        for i in 0 ..< min(pa.count, pb.count) {
            worst = max(worst, abs(Int(pa[i]) - Int(pb[i])))
        }
        return worst
    }
}

// MARK: - Probes

/// A sheet of small ripples in polished metal, seen from far enough away that each pixel
/// covers several of them, under a light dim enough that the highlight stays inside the
/// range the tone map keeps (a clipped white speck cannot be made to flicker less, since
/// it is already flat). The surface the temporal claims are measured on.
private final class RippleProbe: Sketch {
    /// nil never calls the feature at all; a value calls it at that strength.
    var strength: Double?
    var azimuth = 0.0
    var unlit = false
    /// The converged run also asks for the deterministic within-frame supersample, so
    /// each of its frames is the average of many jittered renders rather than one.
    var converged = false

    static func make(strength: Double?, azimuth: Double = 0, unlit: Bool = false,
                     converged: Bool = false) -> RippleProbe {
        let p = RippleProbe()
        p.strength = strength
        p.azimuth = azimuth
        p.unlit = unlit
        p.converged = converged
        return p
    }

    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.02))
        camera(.orbiting(target: .zero, radius: 30, azimuth: azimuth, elevation: 0.5,
                         fieldOfView: .pi / 3, near: 0.2, far: 400))
        if let strength { specularAntialiasing(strength: strength) }
        if converged { temporalAntialiasing() }
        if unlit {
            noLights()
        } else {
            directionalLight(.white, direction: Vector3(0.25, -0.32, 0.91).normalized,
                             intensity: 0.04)
        }
        fill(Color(white: 0.85))
        material(.metal(roughness: 0.12))
        drawMesh(RippleProbe.sheet)
    }

    /// A 12-unit sheet of one-unit ripples, 200 vertices each way (about sixteen to a
    /// ripple) and the analytic normal at each. Built once for the whole suite, since
    /// every frame draws the same surface and only the camera moves.
    static let sheet: Mesh = {
        let n = 200, span = 12.0, amp = 0.02
        let k = 2.0 * Double.pi
        var positions: [Vector3] = [], normals: [Vector3] = []
        positions.reserveCapacity(n * n)
        normals.reserveCapacity(n * n)
        for j in 0 ..< n {
            for i in 0 ..< n {
                let x = -span / 2 + span * Double(i) / Double(n - 1)
                let z = -span / 2 + span * Double(j) / Double(n - 1)
                positions.append(Vector3(x, amp * sin(k * x) * sin(k * z), z))
                let dx = amp * k * cos(k * x) * sin(k * z)
                let dz = amp * k * sin(k * x) * cos(k * z)
                normals.append(Vector3(-dx, 1, -dz).normalized)
            }
        }
        var indices: [UInt32] = []
        indices.reserveCapacity((n - 1) * (n - 1) * 6)
        for j in 0 ..< (n - 1) {
            for i in 0 ..< (n - 1) {
                let a = UInt32(j * n + i), b = a + 1
                let c = a + UInt32(n), d = c + 1
                indices.append(contentsOf: [a, c, b, b, c, d])
            }
        }
        return Mesh(positions: positions, normals: normals, indices: indices)
    }()
}

/// The same sheet with the ripples taken out: one flat plane, one normal, the same
/// material and the same light. Nothing here has a spread of normals to find.
private final class FlatSheetProbe: Sketch {
    var strength: Double?

    static func make(strength: Double?) -> FlatSheetProbe {
        let p = FlatSheetProbe(); p.strength = strength; return p
    }

    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(Color(white: 0.02))
        camera(.orbiting(target: .zero, radius: 30, azimuth: 0, elevation: 0.5,
                         fieldOfView: .pi / 3, near: 0.2, far: 400))
        if let strength { specularAntialiasing(strength: strength) }
        directionalLight(.white, direction: Vector3(0.25, -0.32, 0.91).normalized,
                         intensity: 0.04)
        fill(Color(white: 0.85))
        material(.metal(roughness: 0.12))
        drawMesh(FlatSheetProbe.sheet)
    }

    static let sheet: Mesh = {
        let h = 6.0
        let positions = [Vector3(-h, 0, -h), Vector3(h, 0, -h),
                         Vector3(-h, 0, h), Vector3(h, 0, h)]
        let normals = [Vector3(0, 1, 0), Vector3(0, 1, 0), Vector3(0, 1, 0), Vector3(0, 1, 0)]
        return Mesh(positions: positions, normals: normals, indices: [0, 2, 1, 1, 2, 3])
    }()
}
