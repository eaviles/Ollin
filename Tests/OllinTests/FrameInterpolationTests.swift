import CoreGraphics
import Foundation
import Metal
import MetalKit
import simd
import Testing
@testable import Ollin

/// Probes for the made frames `frameInterpolation()` shows between the drawn
/// ones. The interpolator is a stateful platform object whose output is
/// device-shaped, so it carries no pixel snapshot (the same honesty rule the
/// upscaler follows). What is deterministic is pinned here: where a made frame
/// puts a moving mark, what the first one does before there is any history, the
/// field of view each projection implies, the gating, the alternation of drawn
/// and held frames, and the headless contract (an export writes only the frames
/// the sketch drew).
@Suite
@MainActor
struct FrameInterpolationTests {

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

    // MARK: The field of view each projection implies (pure)

    @Test func theFieldOfViewComesFromTheProjection() {
        var camera = Camera3D(eye: Vector3(0, 0, 5), target: .zero,
                              projection: .perspective(fieldOfView: .pi / 3))
        let perspective = MetalRenderer.verticalFieldOfView(camera, aspect: 1)
        #expect(abs((perspective ?? 0) - 60) < 1e-9, "a third of pi is 60 degrees")

        // A pinhole calibration carries its own angle: 2·atan(h / 2fy).
        camera.projection = .intrinsic(CameraIntrinsics(fx: 500, fy: 500, cx: 320, cy: 240,
                                                        width: 640, height: 480))
        let expected = 2 * atan(480.0 / 1000.0) * 180 / .pi
        let intrinsic = try? #require(MetalRenderer.verticalFieldOfView(camera, aspect: 4.0 / 3))
        #expect(abs((intrinsic ?? 0) - expected) < 1e-9)

        // An orthographic camera has none, which is what turns the feature off.
        camera.projection = .orthographic(height: 10)
        #expect(MetalRenderer.verticalFieldOfView(camera, aspect: 1) == nil)
    }

    // MARK: What the interpolator makes (crafted-frame device probe)

    /// A gray field with a bright vertical bar 24 px wide, left edge at `x`.
    private func barField(_ x: Int, width: Int, height: Int) -> [Float] {
        var field = [Float](repeating: 0.04, count: width * height)
        for r in (height / 4)..<(height * 3 / 4) {
            for c in max(0, x)..<min(width, x + 24) { field[r * width + c] = 1 }
        }
        return field
    }

    /// The bar's motion, written the way Ollin's fill writes it: each pixel
    /// points at where it was in the previous frame, so a bar that moved right
    /// by `dx` carries (-dx, 0) where it is now.
    private func barMotion(_ x: Int, dx: Float, width: Int, height: Int) -> [SIMD2<Float>] {
        var field = [SIMD2<Float>](repeating: .zero, count: width * height)
        for r in (height / 4)..<(height * 3 / 4) {
            for c in max(0, x)..<min(width, x + 24) { field[r * width + c] = SIMD2(-dx, 0) }
        }
        return field
    }

    /// Where the bright mark sits across x, as a center of mass over the bar's
    /// rows. Immune to how the interpolator softens the edges, which is what a
    /// column count would not be.
    private func markCenter(_ field: [Float], width: Int, height: Int) -> Double {
        var num = 0.0, den = 0.0
        for c in 0..<width {
            var column = 0.0
            for r in (height / 4)..<(height * 3 / 4) { column += Double(field[r * width + c]) }
            let v = max(0, column / Double(height / 2) - 0.04)
            num += v * Double(c); den += v
        }
        return den > 0 ? num / den : -1
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aMadeFrameLandsBetweenTheDrawnOnes() throws {
        guard let (renderer, device) = try makeRenderer() else { return }
        guard MetalRenderer.frameInterpolationSupported(on: device) else { return }
        let w = 256, h = 256, step = 8
        // A bar walking right one step per drawn frame. Every made frame should
        // show it halfway along that step.
        var xs: [Int] = []
        var x = 16
        for _ in 0..<8 { xs.append(x); x += step }
        let frames = xs.map { barField($0, width: w, height: h) }
        let motion = xs.dropFirst().map { barMotion($0, dx: Float(step), width: w, height: h) }
        let made = try #require(renderer.debugFrameInterpolationReadback(
            width: w, height: h, frames: frames, motion: Array(motion)))
        #expect(made.count == frames.count - 1)

        // The interpolator needs two encodes of history before it has anything to
        // work between, so the first pair repeat the drawn frame (see the
        // warm-up probe below). Every one after lands within a pixel of halfway.
        for (i, field) in made.enumerated() where i >= 2 {
            let center = markCenter(field, width: w, height: h)
            let previous = Double(xs[i]) + 11.5
            let current = Double(xs[i + 1]) + 11.5
            let halfway = (previous + current) / 2
            #expect(abs(center - halfway) < 1.5,
                    "made frame \(i) put the mark at \(center); halfway is \(halfway)")
            #expect(abs(center - current) > 2,
                    "made frame \(i) repeated the drawn frame rather than interpolating")
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theFirstMadeFrameRepeatsTheDrawnOne() throws {
        guard let (renderer, device) = try makeRenderer() else { return }
        guard MetalRenderer.frameInterpolationSupported(on: device) else { return }
        // Before there is history, the interpolator hands back the frame it was
        // given. That is why starting up shows no artifact: the worst a viewer
        // sees is a frame held twice, never a wrong picture.
        let w = 128, h = 128
        let frames = [barField(16, width: w, height: h), barField(24, width: w, height: h)]
        let motion = [barMotion(24, dx: 8, width: w, height: h)]
        let made = try #require(renderer.debugFrameInterpolationReadback(
            width: w, height: h, frames: frames, motion: motion))
        let center = markCenter(made[0], width: w, height: h)
        #expect(abs(center - (24 + 11.5)) < 1.0,
                "the first made frame should repeat the drawn one, got \(center)")
    }

    // MARK: Gating

    @Test(.enabled(if: Snapshot.hasMetal))
    func theGateNeedsACameraAndAHostThatCanSpareARefresh() throws {
        guard let (renderer, _) = try makeRenderer() else { return }
        let sketch = InterpolationProbe()
        sketch.setCanvasSize(width: 256, height: 256)
        sketch.advance(time: 0, deltaTime: 1.0 / 30, frameRate: 30)
        sketch.performDraw()

        renderer.hostAllowsInterpolation = true
        #expect(renderer.frameInterpolationActive(sketch.drawer))

        // A refresh the host cannot give up (a take, a still sketch, a wall).
        renderer.hostAllowsInterpolation = false
        #expect(!renderer.frameInterpolationActive(sketch.drawer))
        renderer.hostAllowsInterpolation = true

        // A sketch that never asked.
        let plain = InterpolationProbe()
        plain.interpolating = false
        plain.setCanvasSize(width: 256, height: 256)
        plain.advance(time: 0, deltaTime: 1.0 / 30, frameRate: 30)
        plain.performDraw()
        #expect(!renderer.frameInterpolationActive(plain.drawer))

        // A flat sketch: no camera, nothing to interpolate through.
        let flat = InterpolationProbe()
        flat.flat2D = true
        flat.setCanvasSize(width: 256, height: 256)
        flat.advance(time: 0, deltaTime: 1.0 / 30, frameRate: 30)
        flat.performDraw()
        #expect(!renderer.frameInterpolationActive(flat.drawer))

        // An orthographic camera has no field of view to hand over.
        let ortho = InterpolationProbe()
        ortho.orthographic = true
        ortho.setCanvasSize(width: 256, height: 256)
        ortho.advance(time: 0, deltaTime: 1.0 / 30, frameRate: 30)
        ortho.performDraw()
        #expect(!renderer.frameInterpolationActive(ortho.drawer))
    }

    // MARK: Holding a drawn frame back one refresh

    @Test(.enabled(if: Snapshot.hasMetal))
    func aDrawnFrameIsHeldForTheRefreshAfterItsMadeOne() throws {
        guard let (renderer, device) = try makeRenderer() else { return }
        guard MetalRenderer.frameInterpolationSupported(on: device) else { return }
        let size = 256
        let sketch = InterpolationProbe()
        sketch.setCanvasSize(width: Double(size), height: Double(size))
        renderer.hostAllowsInterpolation = true

        let depthDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: renderer.depthPixelFormat, width: size, height: size, mipmapped: false)
        depthDesc.usage = [.shaderRead, .renderTarget]
        depthDesc.storageMode = .private
        let depth = try #require(device.makeTexture(descriptor: depthDesc))

        func drawOneFrame(_ frame: Int) -> MTLTexture? {
            sketch.advance(time: Double(frame) / 30, deltaTime: 1.0 / 30, frameRate: 30)
            sketch.performDraw()
            guard let drawn = renderer.makeFilterTexture(width: size, height: size),
                  let cb = renderer.commandQueue.makeCommandBuffer() else { return nil }
            let made = renderer.applyFrameInterpolation(
                sketch.drawer, drawn: drawn, depth: depth, upscalerMotion: nil,
                meshBuffer: nil, into: cb,
                inputWidth: size, inputHeight: size, outputWidth: size, outputHeight: size)
            cb.commit(); cb.waitUntilCompleted()
            return made
        }

        // The first drawn frame has nothing to interpolate from: it goes to the
        // screen itself, and no frame is held, so the next refresh draws.
        #expect(drawOneFrame(0) == nil)
        #expect(!renderer.hasHeldFrame)

        // From the second on, the drawable carries the made frame and the drawn
        // one waits for the refresh after it.
        let made = drawOneFrame(1)
        #expect(made != nil, "with a previous frame in hand the interpolator should make one")
        #expect(renderer.hasHeldFrame)

        // The made frame and the held frame are different textures: showing one
        // then the other is the whole point.
        #expect(made !== renderer.heldFrame)

        // A reload or a resize drops the held frame rather than showing
        // something that belongs to a run that has ended.
        renderer.dropHeldFrame()
        #expect(!renderer.hasHeldFrame)

        // And with the gate closed, nothing is made or held.
        renderer.hostAllowsInterpolation = false
        #expect(drawOneFrame(2) == nil)
        #expect(!renderer.hasHeldFrame)
    }

    // MARK: The live loop

    @Test(.enabled(if: Snapshot.hasMetal))
    func theLiveLoopAlternatesDrawnAndMadeFrames() throws {
        guard let (renderer, device) = try makeRenderer() else { return }
        guard MetalRenderer.frameInterpolationSupported(on: device) else { return }
        let size = 256
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: size, height: size), device: device)
        view.colorPixelFormat = ollinColorPixelFormat
        view.framebufferOnly = false
        view.drawableSize = CGSize(width: size, height: size)
        view.isPaused = true
        view.enableSetNeedsDisplay = true

        /// The refreshes a runner would take, labelled by what each one showed.
        func walk(_ sketch: InterpolationProbe, refreshes: Int) -> [String] {
            var pattern: [String] = []
            for frame in 0..<refreshes {
                if renderer.hasHeldFrame {
                    renderer.presentHeldFrame(sketch.drawer, in: view)
                    pattern.append("held")
                    continue
                }
                sketch.advance(time: Double(frame) / 30, deltaTime: 1.0 / 30, frameRate: 30)
                sketch.performDraw()
                renderer.render(sketch.drawer,
                                viewport: SIMD2<Float>(Float(size), Float(size)), in: view)
                pattern.append(renderer.hasHeldFrame ? "made" : "drawn")
            }
            return pattern
        }

        let sketch = InterpolationProbe()
        sketch.setCanvasSize(width: Double(size), height: Double(size))
        renderer.hostAllowsInterpolation = true
        // The first refresh has nothing to interpolate from, so it shows the
        // frame it drew. After that every drawn frame puts a made frame on the
        // screen and waits its own turn on the refresh after.
        #expect(walk(sketch, refreshes: 6) == ["drawn", "made", "held", "made", "held", "made"])

        // The counterfactual: a sketch that never asks draws on every refresh.
        // (This is the probe that caught the depth resolve being allocated for
        // temporal AA, the upscaler, and the flare, but not for this.)
        renderer.dropHeldFrame()
        let plain = InterpolationProbe()
        plain.interpolating = false
        plain.setCanvasSize(width: Double(size), height: Double(size))
        #expect(walk(plain, refreshes: 4) == ["drawn", "drawn", "drawn", "drawn"])
    }

    // MARK: The headless contract

    @Test(.enabled(if: Snapshot.hasMetal))
    func anExportWritesOnlyTheFramesTheSketchDrew() throws {
        // Every export path renders the sketch's own frames; the interpolator
        // belongs to the live window alone. So asking for it must change an
        // exported frame not at all.
        let asked = try #require(OllinApp.image(of: InterpolationProbe.make(interpolating: true), frame: 3))
        let plain = try #require(OllinApp.image(of: InterpolationProbe.make(interpolating: false), frame: 3))
        #expect(bytes(asked) == bytes(plain),
                "frameInterpolation() must leave an export untouched")
    }
}

/// A small moving 3D scene: a camera with a field of view, a still floor, and a
/// bar that crosses it, which is exactly what a made frame has to carry.
private final class InterpolationProbe: Sketch {
    var interpolating = true
    var flat2D = false
    var orthographic = false

    override var canvasSize: CanvasSize { .square(256) }

    static func make(interpolating: Bool) -> InterpolationProbe {
        let sketch = InterpolationProbe()
        sketch.interpolating = interpolating
        return sketch
    }

    override func draw() {
        background(Color(white: 0.05))
        if flat2D {
            fill(.white)
            drawCircle(width / 2 + cos(time) * 60, height / 2, 40)
            if interpolating { frameInterpolation() }
            return
        }
        if orthographic {
            camera(Camera3D(eye: Vector3(0, 2.5, 7), target: Vector3(0, 0.6, 0),
                            projection: .orthographic(height: 6)))
        } else {
            camera(Camera3D(eye: Vector3(0, 2.5, 7), target: Vector3(0, 0.6, 0),
                            projection: .perspective(fieldOfView: .pi / 3)))
        }
        directionalLight(.white, direction: Vector3(-0.4, -0.8, -0.4), intensity: 0.9)
        if interpolating { frameInterpolation() }

        withState {
            fill(Color(white: 0.7))
            translate(0, -0.1, 0)
            drawBox(width: 12, height: 0.2, depth: 12)
        }
        withMotion("bar") {
            withState {
                fill(Color(hex: 0xE0B341))
                translate(cos(time * 1.7) * 2.6, 0.9, 0)
                drawBox(width: 0.5, height: 1.6, depth: 0.5)
            }
        }
    }
}
