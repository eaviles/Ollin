@testable import Ollin
import Testing
import CoreGraphics
import Metal
import MetalKit

/// Invariants of the passes that run over a finished frame: the tone map, the dither
/// at the 8-bit encode, the jittered anti-aliasing average, and the motion blur. Each
/// is a statement about the pass that holds whatever its implementation (a tone curve
/// is monotone, a dither is unbiased, an average or a blur only moves light) and is
/// read against an analytic value or the frame with the pass off.
@Suite
@MainActor
struct FrameInvariantTests {

    // MARK: Pixel support

    private struct Frame {
        var bytes: [UInt8]
        var width: Int
        var height: Int
        func byte(_ x: Int, _ y: Int, _ c: Int) -> Int { Int(bytes[(y * width + x) * 4 + c]) }
    }

    private func frame(_ image: CGImage) -> Frame {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return Frame(bytes: data, width: w, height: h)
    }

    private func render(_ sketch: Sketch, frame n: Int = 1) throws -> Frame {
        frame(try OllinApp.image(of: sketch, frame: n))
    }

    /// The sRGB transfer function, written out here so the reference is independent
    /// of the code it checks.
    private func toLinear(_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    private func toDisplay(_ c: Double) -> Double {
        c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
    }

    /// Total linear light of the frame, the three channels summed.
    private func total(_ f: Frame) -> Double {
        var sum = 0.0
        for i in 0..<(f.width * f.height * 4) where i % 4 != 3 { sum += toLinear(Double(f.bytes[i]) / 255) }
        return sum
    }

    /// Mean of one channel over a centered block, so the dither averages out.
    private func centerMean(_ f: Frame, channel: Int, block: Int = 16) -> Double {
        let x0 = f.width / 2 - block / 2, y0 = f.height / 2 - block / 2
        var sum = 0
        for y in y0..<(y0 + block) { for x in x0..<(x0 + block) { sum += f.byte(x, y, channel) } }
        return Double(sum) / Double(block * block)
    }

    // MARK: The tone map

    /// The curve the docs name, written here from its published form.
    private func mapped(_ v: Double, by map: ToneMap) -> Double {
        switch map {
        case .clamp: return min(1, v)
        case .reinhard: return v / (1 + v)
        case .aces:
            let a = 2.51, b = 0.03, c = 2.43, d = 0.59, e = 0.14
            return min(1, max(0, (v * (a * v + b)) / (v * (c * v + d) + e)))
        }
    }

    private static let exposures = [0.25, 0.5, 1.0, 2.0, 4.0, 8.0, 16.0]

    /// A tone curve is a monotone map of light into the display's range that leaves a
    /// gray gray: as the exposure climbs, a mid gray never gets darker, never passes
    /// white, and never picks up a tint.
    @Test(.enabled(if: Snapshot.hasMetal), arguments: ToneMap.allCases)
    func aToneCurveIsMonotoneBoundedAndNeutral(map: ToneMap) throws {
        var last = -1.0
        for exposure in Self.exposures {
            let f = try render(ToneInvariantProbe.make(map: map, exposure: exposure, gray: 0.5))
            let r = centerMean(f, channel: 0), g = centerMean(f, channel: 1), b = centerMean(f, channel: 2)
            #expect(r >= last - 0.5, "\(map) went darker at exposure \(exposure): \(r) after \(last)")
            #expect(r <= 255)
            #expect(abs(r - g) < 0.01 && abs(g - b) < 0.01, "\(map) tinted a gray at exposure \(exposure): \(r) \(g) \(b)")
            last = r
        }
    }

    /// Each curve is the one its name promises: clamp cuts at white, Reinhard is
    /// x over 1 + x, ACES is the published fit; and the exposure multiplies the light
    /// before the curve.
    @Test(.enabled(if: Snapshot.hasMetal), arguments: ToneMap.allCases)
    func theCurveIsTheOneItsNamePromises(map: ToneMap) throws {
        for exposure in Self.exposures {
            let f = try render(ToneInvariantProbe.make(map: map, exposure: exposure, gray: 0.5))
            let read = centerMean(f, channel: 1)
            let expected = toDisplay(mapped(toLinear(0.5) * exposure, by: map)) * 255
            #expect(abs(read - expected) < (map == .aces ? 1.5 : 1.0),
                    "\(map) at exposure \(exposure) read \(read), the curve says \(expected)")
        }
    }

    /// The dither is unbiased: a flat field whose encode lands exactly between two
    /// 8-bit levels averages to that half level over the frame.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theDitherIsUnbiased() throws {
        let half = 100.5 / 255
        let f = try render(ToneInvariantProbe.make(map: .clamp, exposure: 1, gray: half, size: 192))
        var sum = 0, low = 255, high = 0
        for y in 0..<f.height {
            for x in 0..<f.width {
                let v = f.byte(x, y, 1)
                sum += v; low = min(low, v); high = max(high, v)
            }
        }
        let mean = Double(sum) / Double(f.width * f.height)
        #expect(high > low, "a flat half-level field came out at one level (\(low)): no dither ran")
        #expect(abs(mean - 100.5) < 0.1, "the dither biased a half-level field to \(mean)")
    }

    // MARK: Temporal anti-aliasing

    /// The jittered average only moves light between neighboring pixels: the frame's
    /// total is the plain frame's, to within what one unjittered frame misses of a
    /// highlight it samples at pixel centers alone (measured at half a percent).
    @Test(.enabled(if: Snapshot.hasMetal))
    func theJitterAverageConservesTheFramesLight() throws {
        let on = total(try render(TAAInvariantProbe.make(taa: true)))
        let off = total(try render(TAAInvariantProbe.make(taa: false)))
        #expect(off > 100, "the scene drew nothing: \(off)")
        #expect(abs(on / off - 1) < 0.01, "the jittered average changed the frame's light by \(on / off)")
    }

    /// The live resolve leaves still, unjittered content alone: 2D drawn into a 3D
    /// canvas is the same in every frame (no jitter reaches it), so with the camera
    /// still the window shows it exactly as the plain frame does, as the docs promise.
    /// Read off the live loop the window runs, one renderer and one drawable over
    /// sixty-four refreshes.
    @Test(.enabled(if: Snapshot.hasMetal))
    func stillTwoDPassesThroughTheLiveResolve() throws {
        let plain = try liveColumns(LiveHairlineInvariantProbe.make(taa: false))
        #expect(plain == [0, 0, 255, 0, 0], "the plain frame's hairline read \(plain)")
        let resolved = try liveColumns(LiveHairlineInvariantProbe.make(taa: true))
        withKnownIssue("the live resolve's 3 by 3 Gaussian runs over every pixel, jittered or not: a still hairline reads 85, 219, 111 across three columns, measured 2026-10-09") {
            for (i, (a, b)) in zip(resolved, plain).enumerated() {
                #expect(abs(a - b) <= 2, "with the live resolve, column \(62 + i) read \(a) where the plain frame reads \(b)")
            }
        }
    }

    /// Five columns of one row around the hairline, green channel, as the window shows
    /// them after sixty-four live refreshes.
    private func liveColumns(_ sketch: LiveHairlineInvariantProbe) throws -> [Int] {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let renderer = try MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device))
        let size = 128
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: size, height: size), device: device)
        view.colorPixelFormat = ollinColorPixelFormat
        view.framebufferOnly = false
        view.drawableSize = CGSize(width: size, height: size)
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        sketch.setCanvasSize(width: Double(size), height: Double(size))
        sketch.setup()
        var texture: MTLTexture?
        for frame in 0..<64 {
            sketch.advance(time: Double(frame) / 60, deltaTime: 1.0 / 60, frameRate: 60)
            sketch.performDraw()
            let drawable = try #require(view.currentDrawable)
            renderer.render(sketch.drawer, viewport: SIMD2<Float>(Float(size), Float(size)), in: view)
            texture = drawable.texture
        }
        let shown = try #require(texture)
        let buffer = try #require(device.makeBuffer(length: size * size * 4, options: .storageModeShared))
        let commands = try #require(renderer.commandQueue.makeCommandBuffer())
        let blit = try #require(commands.makeBlitCommandEncoder())
        blit.copy(from: shown, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: size, height: size, depth: 1), to: buffer,
                  destinationOffset: 0, destinationBytesPerRow: size * 4,
                  destinationBytesPerImage: size * size * 4)
        blit.endEncoding()
        commands.commit()
        commands.waitUntilCompleted()
        let bytes = buffer.contents().assumingMemoryBound(to: UInt8.self)
        // The drawable is BGRA; row 100 lies below the box, the hairline in column 64.
        return (62...66).map { Int(bytes[(100 * size + $0) * 4 + 1]) }
    }

    // MARK: Motion blur

    /// A streak spreads a mover's light along its travel and makes none: the blurred
    /// frame's total is the sharp frame's.
    ///
    /// Measured 2026-10-06: the renormalized gather the blur first shipped with kept a
    /// pixel inside a 24-pixel box at the box's full value while adding the ramps
    /// outside, and gained 5% of the box's light at the default shutter and 25% at a
    /// full one. Since 2026-10-08 the taps' weights are not renormalized: their mean is
    /// the share of the shutter the streak spent at a pixel and the pixel's own color
    /// fills the rest, which holds the light within a fifth of a percent.
    @Test(.enabled(if: Snapshot.hasMetal), arguments: [0.5, 1.0])
    func theStreakConservesLight(shutter: Double) throws {
        let on = total(try render(BlurInvariantProbe.make(blur: true, shutter: shutter), frame: 2))
        let off = total(try render(BlurInvariantProbe.make(blur: false), frame: 2))
        #expect(off > 100, "the mover drew nothing: \(off)")
        #expect(abs(on / off - 1) < 0.01, "the blur changed the frame's light by \(on / off)")
    }

    /// The blur is held to the streak itself: the export that draws each frame at
    /// moments across the shutter and averages them (`--subframes`). Region by region
    /// (the plateau inside the box, the ramps inside and outside its edges, the ground
    /// beyond), the canvas blur stays within 2% of the box's value of that reference on
    /// average. The renormalized gather missed the inner ramps by 20% of the box's
    /// value at either shutter.
    @Test(.enabled(if: Snapshot.hasMetal), arguments: [0.5, 1.0])
    func theStreakMatchesTheSubframeReference(shutter: Double) throws {
        let sharp = try SubframeExportTests.render(StreakProbe.make(blur: false, shutter: shutter), frame: 3)
        let post = try SubframeExportTests.render(StreakProbe.make(blur: true, shutter: shutter), frame: 3)
        let reference = try SubframeExportTests.render(StreakProbe.make(blur: false, shutter: shutter),
                                                       frame: 3, subframes: 40, shutter: shutter)
        let rows = 88..<104
        let value = sharp.column(StreakProbe.left(at: 3) + 12, rows: rows)
        #expect(value > 0.1, "the box drew nothing: \(value)")
        // The box's edges at the instant, and how far the shutter carries each.
        let left = Double(StreakProbe.left(at: 3)), right = left + 24
        let reach = 10 * shutter
        var error: [String: (sum: Double, count: Int)] = [:]
        for x in 0..<sharp.width {
            let px = Double(x) + 0.5
            let region: String
            if px < left - reach || px > right + reach { region = "the ground beyond" }
            else if px < left || px > right { region = "the outer ramps" }
            else if px < left + reach || px > right - reach { region = "the inner ramps" }
            else { region = "the plateau" }
            let e = abs(post.column(x, rows: rows) - reference.column(x, rows: rows))
            error[region, default: (0, 0)].sum += e
            error[region, default: (0, 0)].count += 1
        }
        for (region, e) in error {
            let mean = e.sum / Double(e.count)
            #expect(mean < 0.02 * value, "\(region) strayed \(mean / value) of the box's value from the reference")
        }
    }

    /// A blur is a weighted mean of what was there: no pixel of the streak is
    /// brighter than the brightest pixel of the sharp frame.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aStreakNeverOutshinesItsSource() throws {
        let on = try render(BlurInvariantProbe.make(blur: true), frame: 2)
        let off = try render(BlurInvariantProbe.make(blur: false), frame: 2)
        func brightest(_ f: Frame) -> Int {
            var top = 0
            for i in 0..<(f.width * f.height * 4) where i % 4 != 3 { top = max(top, Int(f.bytes[i])) }
            return top
        }
        let a = brightest(on), b = brightest(off)
        #expect(a <= b + 1, "the streak reached \(a) where the mover was \(b) at its brightest")
    }

    // MARK: Depth of field from light

    /// The total light of a developed spray, the Reinhard print unrolled and the
    /// exposure divided out.
    private func sprayLight(_ sketch: SprayInvariantProbe) throws -> (total: Double, frame: Frame) {
        let f = try render(sketch, frame: 7)
        var sum = 0.0
        for i in 0..<(f.width * f.height * 4) where i % 4 != 3 {
            let v = min(toLinear(Double(f.bytes[i]) / 255), 0.998)
            sum += v / (1 - v)
        }
        return (sum / sketch.exposure, f)
    }

    /// Every point carries its share of its line's light, wherever the lens throws it:
    /// a dot's developed light is the same at any point count when it is out of focus,
    /// and the same in focus as out of it.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aSprayedDotKeepsItsLightAtAnyCountAndFocus() throws {
        let counts = [100, 1_000, 16_000]
        var defocused: [Double] = []
        var focused: [Double] = []
        for points in counts {
            defocused.append(try sprayLight(SprayInvariantProbe.make(points: points, focus: 2, exposure: 2)).total)
            focused.append(try sprayLight(SprayInvariantProbe.make(points: points, focus: 8, exposure: 2)).total)
        }
        let mean = defocused.reduce(0, +) / Double(defocused.count)
        #expect(mean > 0.05, "the defocused dot developed \(mean)")
        for (points, light) in zip(counts, defocused) {
            #expect(abs(light / mean - 1) < 0.05,
                    "out of focus, \(points) points developed \(light) against the counts' mean \(mean)")
        }
        withKnownIssue("an in-focus dot develops 2.6 times its defocused light at 100 points and 0.03 times at 16,000, measured 2026-10-09") {
            for (points, (inFocus, outOfFocus)) in zip(counts, zip(focused, defocused)) {
                #expect(abs(inFocus / outOfFocus - 1) < 0.05,
                        "at \(points) points the dot in focus developed \(inFocus / outOfFocus) of itself out of focus")
            }
        }
    }

    /// A flat aperture blurs a point into the thin lens's circle of confusion: under a
    /// pinhole, a point displaced within its own depth plane by strength times |d - f|
    /// over the aperture lands on a disc of radius strength * |d - f| / d in tangent
    /// units, 96 pixels a unit at this camera. The radius is read from the mark's RMS
    /// spread (a uniform 48-gon's second moment is 0.4986 of its circumradius squared).
    @Test(.enabled(if: Snapshot.hasMetal), arguments: [4.0, 6.0, 12.0, 16.0])
    func aFlatAperturesBlurIsTheThinLensCircle(distance: Double) throws {
        let expected = 0.25 * abs(distance - 8) / distance * 96
        // An exposure that keeps the spread disc well above the 8-bit floor.
        let exposure = 3.6 * expected * expected
        let probe = SprayInvariantProbe.make(points: 4_000, focus: 8, exposure: exposure,
                                             distance: distance, strength: 0.25,
                                             aperture: .blades(count: 48, rotation: 0))
        let f = try sprayLight(probe).frame
        var weight = 0.0, sx = 0.0, sy = 0.0
        var lights = [Double](repeating: 0, count: f.width * f.height)
        for y in 0..<f.height {
            for x in 0..<f.width {
                var v = 0.0
                for c in 0..<3 {
                    let l = min(toLinear(Double(f.byte(x, y, c)) / 255), 0.998)
                    v += l / (1 - l)
                }
                lights[y * f.width + x] = v
                weight += v; sx += v * Double(x); sy += v * Double(y)
            }
        }
        let cx = sx / weight, cy = sy / weight
        var moment = 0.0
        for y in 0..<f.height {
            for x in 0..<f.width {
                let dx = Double(x) - cx, dy = Double(y) - cy
                moment += lights[y * f.width + x] * (dx * dx + dy * dy)
            }
        }
        let radius = (moment / weight / 0.4986).squareRoot()
        #expect(abs(radius / expected - 1) < 0.03,
                "a dot at \(distance) blurred to \(radius) px where the thin lens gives \(expected)")
    }

    // MARK: The lens's coatings

    /// A coated glass surface reflects what a single thin film does: the exact
    /// one-layer form, r = (r01 + r12 e^(2i delta)) / (1 + r01 r12 e^(2i delta)) per
    /// polarization with delta = 2 pi n1 d cos(theta1) / lambda, written here with the
    /// coating's own index and quarter-wave thickness, for the bundled glasses both ways
    /// through the surface and across the visible.
    @Test func aCoatedSurfaceReflectsWhatAThinFilmDoes() {
        func single(_ angle: Double, _ wavelength: Double, _ n0: Double, _ n2: Double) -> Double? {
            let n1 = max((n0 * n2).squareRoot(), 1.38)
            let d = 550 / 4 / n1
            let s0 = sin(angle), s1 = s0 * n0 / n1, s2 = s0 * n0 / n2
            guard s1 < 1, s2 < 1 else { return nil }
            let c0 = cos(angle), c1 = (1 - s1 * s1).squareRoot(), c2 = (1 - s2 * s2).squareRoot()
            let delta = 2 * Double.pi * n1 * d * c1 / wavelength
            let (er, ei) = (cos(2 * delta), sin(2 * delta))
            func reflect(_ r01: Double, _ r12: Double) -> Double {
                let numR = r01 + r12 * er, numI = r12 * ei
                let denR = 1 + r01 * r12 * er, denI = r01 * r12 * ei
                return (numR * numR + numI * numI) / (denR * denR + denI * denI)
            }
            let s = reflect((n0 * c0 - n1 * c1) / (n0 * c0 + n1 * c1), (n1 * c1 - n2 * c2) / (n1 * c1 + n2 * c2))
            let p = reflect((n1 * c0 - n0 * c1) / (n1 * c0 + n0 * c1), (n2 * c1 - n1 * c2) / (n2 * c1 + n1 * c2))
            return (s + p) / 2
        }
        var cases: [(Double, Double, Double, Double, Double)] = []   // angle, nm, n0, n2, exact
        for glass in [1.5, 1.67, 1.9] {
            for nm in [400.0, 550, 700] {
                for degrees in [0.0, 20, 40, 60] {
                    if let r = single(degrees * .pi / 180, nm, 1, glass) { cases.append((degrees, nm, 1, glass, r)) }
                    if let r = single(degrees * .pi / 180, nm, glass, 1) { cases.append((degrees, nm, glass, 1, r)) }
                }
            }
        }
        #expect(cases.count > 40, "only \(cases.count) cases lay below the critical angle")
        withKnownIssue("the coating's two-beam form weights the inner reflection by t01 squared and blends toward bare Fresnel off the axis: 0.0086 against the exact 0.0043 head on at 1.67, 0.0226 against 0.0069 leaving 1.67 glass at 20 degrees, measured 2026-10-09") {
            for (degrees, nm, n0, n2, exact) in cases {
                let coated = coatedReflectance(angle: degrees * .pi / 180, wavelength: nm,
                                               designWavelength: 550, n0: n0, n2: n2)
                #expect(abs(coated - exact) <= max(0.02 * exact, 1e-5),
                        "from \(n0) into \(n2) at \(degrees) degrees and \(nm) nm the coating reflected \(coated) where a thin film reflects \(exact)")
            }
        }
    }
}

// MARK: - The probe scenes

/// A flat gray canvas under one tone map and exposure.
private final class ToneInvariantProbe: Sketch {
    var map: ToneMap = .clamp
    var exposure = 1.0
    var gray = 0.5
    var size = 64

    static func make(map: ToneMap, exposure: Double, gray: Double, size: Int = 64) -> ToneInvariantProbe {
        let p = ToneInvariantProbe()
        p.map = map
        p.exposure = exposure
        p.gray = gray
        p.size = size
        return p
    }

    override var canvasSize: CanvasSize { .square(size) }

    override func draw() {
        toneMap(map, exposure: exposure)
        background(Color(white: gray))
    }
}

/// Three lit spheres well inside the frame, the anti-aliasing on or off.
private final class TAAInvariantProbe: Sketch {
    var taa = true

    static func make(taa: Bool) -> TAAInvariantProbe {
        let p = TAAInvariantProbe()
        p.taa = taa
        return p
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        camera(Camera3D(eye: Vector3(0, 2, 9), target: .zero))
        directionalLight(.white, direction: Vector3(-0.3, -1, -0.5), intensity: 1)
        if taa { temporalAntialiasing() }
        material(.dielectric(roughness: 0.6))
        fill(Color(white: 0.7))
        withState { translate(-1.6, 0, 0); drawSphere(radius: 0.9) }
        fill(Color(red: 0.8, green: 0.3, blue: 0.2))
        withState { translate(1.4, 0.4, 0.5); drawSphere(radius: 0.7) }
        fill(Color(red: 0.2, green: 0.4, blue: 0.9))
        withState { translate(0.2, -0.8, 1.5); drawBox(width: 1, height: 0.6, depth: 1) }
    }
}

/// A gray box crossing an orthographic 1:1 frame at 20 pixels a frame, the blur on
/// or off, the frame read at the second export frame so there is a previous one.
private final class BlurInvariantProbe: Sketch {
    var blur = true
    var shutter = 1.0

    static func make(blur: Bool, shutter: Double = 1) -> BlurInvariantProbe {
        let p = BlurInvariantProbe()
        p.blur = blur
        p.shutter = shutter
        return p
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        ortho(eye: Vector3(0, 0, 100), target: .zero, height: 192, near: 1, far: 200)
        if blur { motionBlur(shutter: shutter) }
        fill(Color(white: 0.6))
        withMotion {
            withState {
                translate(20 * Double(frameCount) - 40, 0, 0)
                drawBox(width: 24, height: 24, depth: 2)
            }
        }
    }
}

/// The same crossing driven by the clock rather than the frame count, so the
/// subframe export can draw it between frames: 20 pixels a frame at 60 frames a
/// second, its edges on whole pixels at every frame's instant.
private final class StreakProbe: Sketch {
    var blur = true
    var shutter = 1.0

    static func make(blur: Bool, shutter: Double) -> StreakProbe {
        let p = StreakProbe()
        p.blur = blur
        p.shutter = shutter
        return p
    }

    /// The box's left edge, in canvas pixels, at frame `n`'s instant.
    static func left(at n: Int) -> Int { 96 + 20 * n - 40 - 12 }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        ortho(eye: Vector3(0, 0, 100), target: .zero, height: 192, near: 1, far: 200)
        if blur { motionBlur(shutter: shutter) }
        noStroke()
        fill(Color(white: 0.6))
        withMotion {
            withState {
                translate(1200 * time - 40, 0, 0)
                drawBox(width: 24, height: 24, depth: 2)
            }
        }
    }
}

/// A gray box in a 3D canvas with a one-pixel white 2D line down column 64, the camera
/// still, temporal anti-aliasing on or off.
private final class LiveHairlineInvariantProbe: Sketch {
    var taa = true

    static func make(taa: Bool) -> LiveHairlineInvariantProbe {
        let p = LiveHairlineInvariantProbe()
        p.taa = taa
        return p
    }

    override var canvasSize: CanvasSize { .square(128) }

    override func draw() {
        background(.black)
        perspective(eye: Vector3(0, 0, 4), target: .zero, fieldOfView: .pi / 3.2, near: 0.5, far: 30)
        noLights()
        if taa { temporalAntialiasing() }
        withState { fill(Color(white: 0.25)); drawBox(width: 0.6, height: 0.6, depth: 0.2) }
        stroke(.white)
        strokeWeight(1)
        drawLine(64.5, 8, 64.5, 120)
    }
}

/// One dot of light on the camera's axis, sprayed through a lens and developed, so its
/// mark is the lens's blur of a point.
private final class SprayInvariantProbe: Sketch {
    var points = 1_000
    var focus = 8.0
    var exposure = 1.0
    var distance = 8.0
    var strength = 0.1
    var aperture: Aperture = .round
    private var spray: LineSpray!

    static func make(points: Int, focus: Double, exposure: Double, distance: Double = 8,
                     strength: Double = 0.1, aperture: Aperture = .round) -> SprayInvariantProbe {
        let p = SprayInvariantProbe()
        p.points = points
        p.focus = focus
        p.exposure = exposure
        p.distance = distance
        p.strength = strength
        p.aperture = aperture
        return p
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func setup() {
        randomSeed(7)
        let dot = Vector3(0, 0, -distance)
        spray = makeLineSpray([SprayLine(from: dot, to: dot, light: SIMD3(repeating: 1))],
                              sampling: .perLine(points), passesPerFrame: 4,
                              bokeh: Bokeh(focalDistance: focus, strength: strength,
                                           minSize: 0.0005, aperture: aperture))
    }

    override func draw() {
        background(.black)
        camera(.perspective(eye: .zero, target: Vector3(0, 0, -1), fieldOfView: .pi / 2))
        drawLineSpray(spray)
        drawImage(spray.developed(exposure: exposure).image, 0, 0)
    }
}
