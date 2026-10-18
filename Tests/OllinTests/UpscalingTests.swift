import COllinShaders
import CoreGraphics
import Foundation
import Metal
import simd
import Testing
@testable import Ollin

/// Deterministic probes for the temporal upscaler. The live scaler is a
/// stateful platform object whose output is device-shaped, so it carries no
/// pixel snapshot (the artificial-life honesty rule; the live verification is
/// the frame-diff and FPS record in ARCHITECTURE.md). What *is* deterministic
/// is pinned here: the gating, the tier-to-fraction mapping, the jitter table's
/// shipped prefix, the velocity fill's three behaviors over crafted inputs, and
/// the headless contract (an upscaling sketch exports as the full-resolution
/// temporal-AA supersample, byte-identical to asking for temporal AA).
@Suite
@MainActor
struct UpscalingTests {

    private func makeRenderer() throws -> (MetalRenderer, MTLDevice)? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let renderer = try MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device))
        return (renderer, device)
    }

    private func bytes(_ image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    // MARK: The jitter table and phase count (pure)

    @Test func theJitterTableKeepsItsShippedPrefix() {
        // TAA's live path cycles the first 8 and the export supersample takes up
        // to the first 16; extending the table for the upscaler must leave every
        // one of those entries exactly as shipped.
        #expect(MetalRenderer.taaJitterOffsets.count == 32)
        for i in 0..<16 {
            let expected = SIMD2(Float(halton(i + 1, base: 2)) - 0.5,
                                 Float(halton(i + 1, base: 3)) - 0.5)
            #expect(MetalRenderer.taaJitterOffsets[i] == expected)
        }
    }

    @Test func thePhaseCountFollowsTheScaleSquared() throws {
        guard let (renderer, _) = try makeRenderer() else { return }
        // 8·s² phases, floored at TAA's 8 and capped at the table: a 2× scale
        // wants 32, three-quarters rendering about 15, no scaling the plain 8.
        #expect(renderer.fxJitterPhaseCount(inputWidth: 540, outputWidth: 1080) == 32)
        #expect(renderer.fxJitterPhaseCount(inputWidth: 810, outputWidth: 1080) == 15)
        #expect(renderer.fxJitterPhaseCount(inputWidth: 1080, outputWidth: 1080) == 8)
    }

    // MARK: Tier mapping (device-clamped)

    @Test(.enabled(if: Snapshot.hasMetal))
    func theTiersMapToTheirRenderFractions() throws {
        guard let (renderer, device) = try makeRenderer() else { return }
        guard MTLFXSupport.isSupported(device) else { return }
        // The requested factors, clamped to the device range; on every GPU the
        // ordering must hold and `.performance` must render the fewest pixels.
        let p = renderer.upscaleFactor(for: .performance)
        let d = renderer.upscaleFactor(for: .default)
        let q = renderer.upscaleFactor(for: .detail)
        #expect(p >= d && d >= q && q >= 1)
        let (pw, ph) = renderer.upscaleInputSize(width: 1080, height: 1080, quality: .performance)
        let (dw, dh) = renderer.upscaleInputSize(width: 1080, height: 1080, quality: .default)
        #expect(pw <= dw && ph <= dh)
        // On hardware whose range admits the requested factors, the exact sizes.
        if p == 2.0 { #expect((pw, ph) == (540, 540)) }
        if d == 1.5 { #expect((dw, dh) == (720, 720)) }
    }

    // MARK: The velocity fill (crafted-texture render probes)

    /// A view-projection that translates NDC by (dx, dy): with the identity as
    /// the current camera, world coordinates *are* NDC and the previous frame
    /// saw everything shifted, so the expected pixel delta is exact.
    private func ndcTranslation(_ dx: Float, _ dy: Float) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3.x = dx
        m.columns.3.y = dy
        return m
    }

    /// Over a plain clear color the far plane holds 2D drawing and the clear,
    /// which the camera does not move: depth 1 writes zero motion.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theBackdropHoldsStill() throws {
        guard let (renderer, _) = try makeRenderer() else { return }
        let field = try #require(renderer.debugUpscaleFillReadback(
            width: 16, height: 16, depth: [Float](repeating: 1, count: 256), mover: nil,
            viewProjection: matrix_identity_float4x4,
            previousViewProjection: ndcTranslation(0.5, 0.5)))
        for v in field { #expect(v == .zero, "depth 1 over a plain background must write zero motion") }
    }

    /// A perspective camera at `eye` looking along `yaw` radians from -z, and its
    /// view-projection at a square aspect.
    private func camera(eye: Vector3, yaw: Double) -> (Camera3D, simd_float4x4) {
        let target = eye + Vector3(sin(yaw), 0, -cos(yaw))
        let cam = Camera3D(eye: eye, target: target, up: .unitY, near: 0.5, far: 100,
                           projection: .perspective(fieldOfView: .pi / 3))
        return (cam, cam.projectionMatrix(aspect: 1) * cam.viewMatrix)
    }

    /// Under an environment the far plane is the sky, which turns with the
    /// camera: a camera that yawed between frames moves every sky pixel by its
    /// turn, and by exactly what a surface at the same pixel moves under that
    /// turn (a pure turn moves every direction alike, whatever its distance),
    /// which is the floor meeting the sky at the horizon with no seam.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theSkyTurnsWithTheCameraLikeAFloorAtTheHorizon() throws {
        guard let (renderer, _) = try makeRenderer() else { return }
        let w = 32, h = 32
        let (cam, now) = camera(eye: Vector3(0, 1, 0), yaw: 0.05)
        let (_, before) = camera(eye: Vector3(0, 1, 0), yaw: 0)
        let eye = cam.eye.simd3
        let sky = try #require(renderer.debugUpscaleFillReadback(
            width: w, height: h, depth: [Float](repeating: 1, count: w * h), mover: nil,
            viewProjection: now, previousViewProjection: before,
            backdropTurns: true, eye: eye, previousEye: eye))
        let surface = try #require(renderer.debugUpscaleFillReadback(
            width: w, height: h, depth: [Float](repeating: 0.9, count: w * h), mover: nil,
            viewProjection: now, previousViewProjection: before))
        var worst: Float = 0
        for i in 0..<(w * h) { worst = max(worst, simd_length(sky[i] - surface[i])) }
        #expect(worst < 0.05, "the sky and a far surface parted by \(worst) px under one turn")
        // And the turn is real: a 0.05 radian yaw at this lens is about 1.4 px.
        let center = sky[16 * w + 16]
        #expect(center.x > 1, "the sky moved \(center.x) px under a turn of 0.05 radians")
        #expect(abs(center.y) < 0.05)
    }

    /// The sky sits at infinity, so a camera that travels without turning
    /// leaves it where it was, while a surface in front of it slides.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aTravelingCameraLeavesTheSkyStill() throws {
        guard let (renderer, _) = try makeRenderer() else { return }
        let w = 32, h = 32
        let (cam, now) = camera(eye: Vector3(1, 1, 0), yaw: 0)
        let (was, before) = camera(eye: Vector3(0, 1, 0), yaw: 0)
        let sky = try #require(renderer.debugUpscaleFillReadback(
            width: w, height: h, depth: [Float](repeating: 1, count: w * h), mover: nil,
            viewProjection: now, previousViewProjection: before,
            backdropTurns: true, eye: cam.eye.simd3, previousEye: was.eye.simd3))
        for v in sky { #expect(simd_length(v) < 0.01, "the sky moved \(v) under a camera that only traveled") }
        let near = try #require(renderer.debugUpscaleFillReadback(
            width: w, height: h, depth: [Float](repeating: 0.5, count: w * h), mover: nil,
            viewProjection: now, previousViewProjection: before))
        #expect(simd_length(near[16 * w + 16]) > 1, "a surface in front slid \(near[16 * w + 16]) px")
    }

    /// Without an environment the same turn moves the far plane by nothing: the
    /// flag, not the matrices, decides.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aPlainBackdropHoldsStillUnderATurn() throws {
        guard let (renderer, _) = try makeRenderer() else { return }
        let w = 16, h = 16
        let (cam, now) = camera(eye: Vector3(0, 1, 0), yaw: 0.05)
        let (_, before) = camera(eye: Vector3(0, 1, 0), yaw: 0)
        let field = try #require(renderer.debugUpscaleFillReadback(
            width: w, height: h, depth: [Float](repeating: 1, count: w * h), mover: nil,
            viewProjection: now, previousViewProjection: before,
            backdropTurns: false, eye: cam.eye.simd3, previousEye: cam.eye.simd3))
        for v in field { #expect(v == .zero, "a plain backdrop moved \(v) under a turn") }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theCameraFallbackReprojectsExactly() throws {
        guard let (renderer, _) = try makeRenderer() else { return }
        // A previous camera shifted by (4/W, -6/H) in NDC puts every pixel's
        // previous position 2 px right and 3 px down of its current one
        // (NDC y runs up, pixels run down): previous minus current = (+2, +3).
        let w = 32, h = 32
        let field = try #require(renderer.debugUpscaleFillReadback(
            width: w, height: h, depth: [Float](repeating: 0.5, count: w * h), mover: nil,
            viewProjection: matrix_identity_float4x4,
            previousViewProjection: ndcTranslation(4 / Float(w), -6 / Float(h))))
        let center = field[16 * w + 16]
        #expect(abs(center.x - 2) < 0.02, "expected +2 px, got \(center.x)")
        #expect(abs(center.y - 3) < 0.02, "expected +3 px (y-down), got \(center.y)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aMoverTexelPassesThroughRaw() throws {
        guard let (renderer, _) = try makeRenderer() else { return }
        // The fill must hand the scaler the mover's raw pixel delta: no shutter
        // scale, no half-spread, no magnitude clamp (the motion-blur fill's
        // transforms are exactly what this variant must not apply). Sentinel
        // texels fall back to the camera term.
        let w = 16, h = 16
        var mover = [SIMD2<Float>](repeating: SIMD2(OLLIN_VELOCITY_NONE, 0), count: w * h)
        mover[8 * w + 8] = SIMD2(-7.25, 4.5)
        let field = try #require(renderer.debugUpscaleFillReadback(
            width: w, height: h, depth: [Float](repeating: 0.5, count: w * h), mover: mover,
            viewProjection: matrix_identity_float4x4,
            previousViewProjection: ndcTranslation(4 / Float(w), 0)))
        let written = field[8 * w + 8]
        #expect(written == SIMD2(-7.25, 4.5), "a mover texel must pass through untouched, got \(written)")
        let fallback = field[2 * w + 2]
        #expect(abs(fallback.x - 2) < 0.02, "a sentinel texel takes the camera term, got \(fallback.x)")
        #expect(abs(fallback.y) < 0.02)
    }

    // MARK: Gating and the headless contract

    @Test(.enabled(if: Snapshot.hasMetal))
    func aTwoDFrameIsUntouched() throws {
        let plain = try OllinApp.image(of: UpscaleProbe.make(mode: .off, flat2D: true), frame: 1)
        let asked = try OllinApp.image(of: UpscaleProbe.make(mode: .upscaling, flat2D: true), frame: 1)
        #expect(bytes(plain) == bytes(asked),
                "without a 3D camera the upscaler must change nothing")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aHeadlessUpscalingFrameIsTheTemporalAASupersample() throws {
        // The headless path never touches the scaler: a sketch asking for
        // upscaling renders as the full-resolution supersampled equivalent,
        // byte-identical to asking for temporal AA. The two are independent renders
        // through that one supersample, so the equality also says an upscaling frame
        // renders twice identically.
        let upscaled = try OllinApp.image(of: UpscaleProbe.make(mode: .upscaling), frame: 1)
        let taa = try OllinApp.image(of: UpscaleProbe.make(mode: .taa), frame: 1)
        #expect(bytes(upscaled) == bytes(taa))
        // And it genuinely engages: the supersample differs from the plain render.
        let off = try OllinApp.image(of: UpscaleProbe.make(mode: .off), frame: 1)
        #expect(bytes(upscaled) != bytes(off))
    }
}

/// Whether this GPU can create the platform temporal scaler (the live gate;
/// the deterministic probes above don't need it except where noted).
enum MTLFXSupport {
    @MainActor static func isSupported(_ device: MTLDevice) -> Bool {
        MetalRenderer.temporalScalerSupported(on: device)
    }
}

/// The thin-rod scene from the TAA probes, with the temporal mode switchable:
/// off, temporal AA, or temporal upscaling. Free of ray-traced features so it
/// runs on any Metal GPU.
private final class UpscaleProbe: Sketch {
    enum Mode { case off, taa, upscaling }
    var mode: Mode = .off
    var flat2D = false

    static func make(mode: Mode, flat2D: Bool = false) -> UpscaleProbe {
        let probe = UpscaleProbe()
        probe.mode = mode
        probe.flat2D = flat2D
        return probe
    }

    override var canvasSize: CanvasSize { .square(192) }

    override func draw() {
        background(.black)
        if flat2D {
            if mode == .upscaling { temporalUpscaling() }
            fill(.white)
            drawCircle(96, 96, 60)
            return
        }
        perspective(eye: Vector3(0, 1.2, 4.2), target: Vector3(0, 0.4, 0),
                    fieldOfView: .pi / 3.2, near: 0.5, far: 30)
        directionalLight(.white, direction: Vector3(-0.4, -1, -0.6))
        switch mode {
        case .off: break
        case .taa: temporalAntialiasing()
        case .upscaling: temporalUpscaling()
        }
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
