import CoreGraphics
import Foundation
import simd
import Testing
@testable import Ollin

/// Behavioral probes for temporal anti-aliasing. The export path is the deterministic
/// one (N jittered renders averaged within the frame), so every claim runs there;
/// the live hysteresis loop restarts under every deterministic probe and is verified
/// by live frame-diff measurement instead (the artificial-life honesty rule), recorded
/// in ARCHITECTURE.md. Each claim is measured against its counterfactual twin: the
/// same frame with TAA off, a flat interior where the average must change nothing,
/// a supersampled reference the jittered average must approach.
@Suite
@MainActor
struct TAATests {

    // MARK: Pixel support

    private func pixels(_ image: CGImage) -> (data: [UInt8], w: Int, h: Int) {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return (data, w, h)
    }

    /// sRGB byte → linear light. Averaging (and therefore judging) anti-aliasing
    /// must happen in linear light: the renderer's MSAA resolve and the TAA average
    /// both work there, and a gamma-space reference reads systematically dark at
    /// bright-on-dark edges (the measure-coverage-in-linear-light rule).
    private func linear(_ v: UInt8) -> Double {
        let s = Double(v) / 255
        return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4)
    }

    /// The image's RGB as linear-light values (alpha dropped; the frames are opaque).
    private func linearRGB(_ image: CGImage) -> [Double] {
        let (data, w, h) = pixels(image)
        var out = [Double](repeating: 0, count: w * h * 3)
        for p in 0..<(w * h) {
            for c in 0..<3 { out[p * 3 + c] = linear(data[p * 4 + c]) }
        }
        return out
    }

    /// Box-downsample a linear-light image by an integer factor, the sampling
    /// window shifted by whole high-res pixels: `shift` (in high-res pixels) moves
    /// the window *against* the image shift a projection jitter produces, so the
    /// shifted reduction reconstructs what a jittered render sees.
    private func boxDownsampledLinearRGB(_ big: [Double], bigWidth: Int, factor: Int,
                                         shift: SIMD2<Int> = .zero) -> [Double] {
        let w = bigWidth / factor
        var out = [Double](repeating: 0, count: w * w * 3)
        let norm = 1.0 / Double(factor * factor)
        for y in 0..<w {
            for x in 0..<w {
                var sum = SIMD3<Double>()
                for sy in 0..<factor {
                    for sx in 0..<factor {
                        let bx = min(max(x * factor + sx + shift.x, 0), bigWidth - 1)
                        let by = min(max(y * factor + sy + shift.y, 0), bigWidth - 1)
                        let i = (by * bigWidth + bx) * 3
                        sum += SIMD3(big[i], big[i + 1], big[i + 2])
                    }
                }
                let o = (y * w + x) * 3
                out[o] = sum.x * norm; out[o + 1] = sum.y * norm; out[o + 2] = sum.z * norm
            }
        }
        return out
    }

    /// Mean absolute difference in linear light, scaled onto 0...255 for
    /// readability, over the frame minus a border margin (in low-res pixels), so a
    /// shifted reduction's clamped edge never enters the measurement.
    private func meanAbsDiff(_ a: [Double], _ b: [Double], width: Int, margin: Int) -> Double {
        precondition(a.count == b.count)
        var total = 0.0
        var count = 0
        for y in margin..<(width - margin) {
            for x in margin..<(width - margin) {
                let i = (y * width + x) * 3
                for c in 0..<3 { total += abs(a[i + c] - b[i + c]) }
                count += 3
            }
        }
        return total / Double(count) * 255
    }

    // MARK: The claims

    /// The headline: the export average must equal its own analytic construction.
    /// From one 8x-supersampled reference render, rebuild both kernels: the plain
    /// box reduction (what MSAA approximates) and the jitter-set reduction (the
    /// box reduction shifted by each declared jitter offset, averaged), then
    /// cross-discriminate: the TAA frame must match the jitter-set truth better
    /// than the box truth, and the plain frame the box truth better than the
    /// jitter-set one. This pins the jitter offsets (magnitude, sign, and
    /// sequence), the equal 1/N weights, and the projection plumbing all at once;
    /// a zeroed jitter, a flipped sign, or a wrong weight breaks a side of it.
    /// (A plain closer-to-box-truth comparison is deliberately not the claim: the
    /// jitter average's effective kernel is the pixel box convolved with the
    /// jitter set, wider than the pixel, so a box-filtered ground truth penalizes
    /// exactly the reconstruction it is supposed to certify.)
    @Test(.enabled(if: Snapshot.hasMetal))
    func theJitterAverageMatchesItsAnalyticConstruction() throws {
        let size = 96
        let factor = 8
        let reference = try #require(OllinApp.image(of: TAAEdgeProbe.make(taa: false,
                                                                          size: size * factor),
                                                    frame: 1))
        let big = linearRGB(reference)
        let boxTruth = boxDownsampledLinearRGB(big, bigWidth: size * factor, factor: factor)
        // The jitter-set truth: a jitter of j pixels shifts the rendered image by
        // +j, so the window into the unjittered reference shifts by -j (rounded to
        // the reference grid; at 8x the sequence's offsets land within 1/16 px).
        // `image(of:)` exports at `.detail`, which resolves to the sequence's full
        // 16 offsets.
        var taaTruth = [Double](repeating: 0, count: boxTruth.count)
        let samples = 16
        for s in 0..<samples {
            let px = MetalRenderer.taaJitterOffsets[s]
            let shift = SIMD2(Int((-px.x * Float(factor)).rounded()),
                              Int((-px.y * Float(factor)).rounded()))
            let shifted = boxDownsampledLinearRGB(big, bigWidth: size * factor,
                                                  factor: factor, shift: shift)
            for i in taaTruth.indices { taaTruth[i] += shifted[i] / Double(samples) }
        }
        let off = linearRGB(try #require(
            OllinApp.image(of: TAAEdgeProbe.make(taa: false, size: size), frame: 1)))
        let on = linearRGB(try #require(
            OllinApp.image(of: TAAEdgeProbe.make(taa: true, size: size), frame: 1)))
        let onVsTaa = meanAbsDiff(on, taaTruth, width: size, margin: 2)
        let onVsBox = meanAbsDiff(on, boxTruth, width: size, margin: 2)
        let offVsBox = meanAbsDiff(off, boxTruth, width: size, margin: 2)
        let offVsTaa = meanAbsDiff(off, taaTruth, width: size, margin: 2)
        print("TAA kernel discrimination: onVsTaa \(onVsTaa), onVsBox \(onVsBox), "
              + "offVsBox \(offVsBox), offVsTaa \(offVsTaa)")
        // The margins are set from measurement (normal: onVsTaa 0.29, onVsBox 1.04,
        // offVsBox 1.08, offVsTaa 1.63) and tight enough that even a full sign flip
        // of the jitter (whose point-reflected set has a similar kernel, the
        // subtlest sabotage: measured onVsTaa 0.77) reads red.
        #expect(onVsTaa < onVsBox * 0.5,
                "the TAA frame must match its own kernel, not the box: \(onVsTaa) vs \(onVsBox)")
        #expect(offVsBox < offVsTaa * 0.8,
                "the plain frame must match the box kernel, not the jitter set: \(offVsBox) vs \(offVsTaa)")
    }

    /// Energy conservation: on a flat interior (a facing surface with no edges under
    /// the jitter), averaging N sub-pixel-shifted renders must reproduce the single
    /// render, so the accumulation weights must sum to exactly one. A missing or
    /// wrong 1/N shows up as a brightness shift far past the 1-step tolerance.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theAverageConservesAFlatInterior() throws {
        let on = try #require(OllinApp.image(of: TAAFlatProbe.make(taa: true), frame: 1))
        let off = try #require(OllinApp.image(of: TAAFlatProbe.make(taa: false), frame: 1))
        let (a, w, h) = pixels(on)
        let (b, _, _) = pixels(off)
        var worst = 0
        for py in (h * 3 / 8)..<(h * 5 / 8) {
            for px in (w * 3 / 8)..<(w * 5 / 8) {
                let i = (py * w + px) * 4
                for c in 0..<3 { worst = max(worst, abs(Int(a[i + c]) - Int(b[i + c]))) }
            }
        }
        #expect(worst <= 1,
                "a flat interior must survive the average within a quantization step: worst \(worst)")
    }

    /// `noTemporalAntialiasing()` after `temporalAntialiasing()` is byte-identical to
    /// never asking: the per-frame reset, the renderer gate, the untouched projection,
    /// and the single-sample path all in one equality.
    @Test(.enabled(if: Snapshot.hasMetal))
    func turningItOffIsTheDefaultAgain() throws {
        let off = try #require(OllinApp.image(of: TAAEdgeProbe.make(taa: false, size: 192), frame: 1))
        let toggled = try #require(OllinApp.image(of: TAAEdgeProbe.make(taa: false, size: 192,
                                                                        toggle: true), frame: 1))
        #expect(pixels(off).data == pixels(toggled).data,
                "an on-then-off frame must be byte-identical to never-on")
    }

    /// Export determinism: the jitter sequence is fixed and ordered, so two renders
    /// of one TAA frame are byte-identical (the promise every snapshot and video
    /// export stands on; the live accumulation never runs headless).
    @Test(.enabled(if: Snapshot.hasMetal))
    func anExportIsAPureFunctionOfTheFrame() throws {
        let first = try #require(OllinApp.image(of: TAAEdgeProbe.make(taa: true, size: 192), frame: 1))
        let second = try #require(OllinApp.image(of: TAAEdgeProbe.make(taa: true, size: 192), frame: 1))
        #expect(pixels(first).data == pixels(second).data,
                "two renders of one TAA frame must be byte-identical")
    }

    /// The no-camera gate: a 2D frame that asks for TAA renders byte-identically to
    /// one that never did (there is nothing to jitter; the primitives carry analytic
    /// AA already), and the ask is answered with a note, not a broken frame.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aTwoDFrameIsUntouched() throws {
        let plain = try #require(OllinApp.image(of: TAAFlat2DProbe.make(taa: false), frame: 1))
        let asked = try #require(OllinApp.image(of: TAAFlat2DProbe.make(taa: true), frame: 1))
        #expect(pixels(plain).data == pixels(asked).data,
                "a 2D frame must ignore the TAA ask byte-identically")
    }

    /// The jitter matrix: an NDC translate premultiplied onto the projection shifts a
    /// projected point by exactly the asked sub-pixel offset, for perspective and
    /// orthographic alike, and leaves depth (z/w) bit-identical, which is what keeps
    /// `depth(at:)` and every depth test exact under TAA. Pure CPU.
    @Test
    func theJitterShiftsExactPixelsAndLeavesDepthAlone() {
        let cameras: [Camera3D] = [
            .orbiting(target: Vector3(0, 0, 0), radius: 5, azimuth: 0.4, elevation: 0.3,
                      fieldOfView: .pi / 3, near: 0.5, far: 50),
            {
                var c = Camera3D.orbiting(target: Vector3(0, 0, 0), radius: 5,
                                          azimuth: 0.4, elevation: 0.3,
                                          fieldOfView: .pi / 3, near: 0.5, far: 50)
                c.projection = .orthographic(height: 4)
                return c
            }(),
        ]
        let width = 192.0
        let ndc = SIMD2<Float>(Float(2.0 / width), 0)   // exactly one pixel in x
        for camera in cameras {
            let plain = camera.projectionMatrix(aspect: 1) * camera.viewMatrix
            let jittered = MetalRenderer.jittered(camera.projectionMatrix(aspect: 1), by: ndc)
                * camera.viewMatrix
            let p = SIMD4<Float>(0.3, -0.2, 0.1, 1)
            let a = plain * p
            let b = jittered * p
            let dxPixels = (b.x / b.w - a.x / a.w) * Float(width) / 2
            #expect(abs(dxPixels - 1) < 1e-3, "expected a one-pixel shift, got \(dxPixels)")
            #expect(b.y == a.y && b.z == a.z && b.w == a.w,
                    "the jitter must touch only clip x")
        }
    }
}

/// The edge probe: thin bright slats at a slight tilt against black, the
/// configuration where MSAA's fixed sample positions band into visible steps and
/// sub-pixel jitter genuinely refines the gradient. Kept free of ray-traced
/// features so the probes run on any Metal GPU.
private final class TAAEdgeProbe: Sketch {
    var taa = true
    var toggle = false
    var size = 192

    static func make(taa: Bool, size: Int, toggle: Bool = false) -> TAAEdgeProbe {
        let probe = TAAEdgeProbe()
        probe.taa = taa
        probe.size = size
        probe.toggle = toggle
        return probe
    }

    override var canvasSize: CanvasSize { .square(size) }

    override func draw() {
        background(.black)
        perspective(eye: Vector3(0, 1.2, 4.2), target: Vector3(0, 0.4, 0),
                    fieldOfView: .pi / 3.2, near: 0.5, far: 30)
        directionalLight(.white, direction: Vector3(-0.4, -1, -0.6))
        if taa { temporalAntialiasing() }
        if toggle { temporalAntialiasing(); noTemporalAntialiasing() }
        fill(.white)
        for i in 0..<5 {
            withState {
                translate(0, 0.25 + Double(i) * 0.28, 0)
                rotate(0.045 + Double(i) * 0.012, axis: .unitZ)
                drawBox(width: 4.6, height: 0.035, depth: 0.05)
            }
        }
    }
}

/// The flat probe: one facing surface filling the frame under `noLights()`, whose
/// interior is constant under any sub-pixel shift, so the N-sample average must
/// reproduce the single render exactly (up to a quantization step).
private final class TAAFlatProbe: Sketch {
    var taa = true

    static func make(taa: Bool) -> TAAFlatProbe {
        let probe = TAAFlatProbe()
        probe.taa = taa
        return probe
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        perspective(eye: Vector3(0, 0, 4), target: Vector3(0, 0, 0),
                    fieldOfView: .pi / 3.2, near: 0.5, far: 30)
        noLights()
        if taa { temporalAntialiasing() }
        fill(Color(red: 0.42, green: 0.55, blue: 0.36))
        drawBox(width: 6, height: 6, depth: 0.4)
    }
}

/// The 2D probe: no camera, so the TAA ask must change nothing at all.
private final class TAAFlat2DProbe: Sketch {
    var taa = true

    static func make(taa: Bool) -> TAAFlat2DProbe {
        let probe = TAAFlat2DProbe()
        probe.taa = taa
        return probe
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(Color(white: 0.12))
        if taa { temporalAntialiasing() }
        fill(.tomato)
        drawCircle(64, 96, 40)
        stroke(.white)
        strokeWeight(3)
        drawLine(20, 150, 172, 40)
    }
}
