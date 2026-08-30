import COllinShaders
import Foundation
import Metal
import simd
import Testing
@testable import Ollin

/// The mover-velocity buffer behind `withMotion` + temporal AA. The cross-frame
/// registry is pinned CPU-side (identity, deltas, pruning, the call-site key
/// rule); the velocity pass and the TAA resolve's velocity branch are pinned by
/// Metal-gated render probes, which is honest deterministic coverage: both are
/// pure functions of their inputs, so only the live accumulation loop itself
/// stays measurement-verified (the artificial-life rule).
@Suite
@MainActor
struct VelocityBufferTests {

    /// A minimal mover scene: an orthographic camera framing 128 world units on
    /// a 128 px readback (1 world unit = 1 px, world +x = screen right, world
    /// +y = screen up), one mover box driven by `step`, and optional variants.
    final class MoverProbe: Sketch {
        var step = Vector3(0, 0, 0)
        var wall = false
        var wire = false
        var moverInTarget = false
        var skipMover = false
        var useAltSite = false
        var wipeAfter = false

        private func mover() {
            translate(step.x, step.y, step.z)
            if wire { wireframe(true) }
            drawBox(width: 30, height: 30, depth: 2)
            if wire { wireframe(false) }
        }

        override func draw() {
            background(.black)
            ortho(eye: Vector3(0, 0, 100), target: .zero, height: 128, near: 1, far: 200)
            temporalAntialiasing()
            if wall {
                // Between the camera and the mover, covering the canvas center.
                withState {
                    translate(0, 0, 40)
                    drawBox(width: 40, height: 40, depth: 2)
                }
            }
            guard !skipMover else { return }
            if moverInTarget {
                let layer = makeRenderTarget()
                withTarget(layer) { self.withMotion("boxed") { self.mover() } }
                drawImage(layer.image, 0, 0)
            } else if useAltSite {
                withMotion("crate") { self.mover() }   // a different line, same name
            } else {
                withMotion("crate") { self.mover() }
            }
            if wipeAfter { background(.black) }
        }
    }

    /// Two same-line `withMotion` blocks (a loop): occurrence order keys them.
    final class LoopProbe: Sketch {
        var offsets: [Double] = [0, 50]
        override func draw() {
            ortho(eye: Vector3(0, 0, 100), target: .zero, height: 128, near: 1, far: 200)
            temporalAntialiasing()
            for o in offsets {
                withMotion {
                    withState {
                        translate(o, 0, 0)
                        drawBox(width: 10, height: 10, depth: 2)
                    }
                }
            }
        }
    }

    private func matches(_ m: simd_float4x4, taking p: SIMD3<Float>, to q: SIMD3<Float>,
                         within tolerance: Float = 1e-3) -> Bool {
        let r = m * SIMD4<Float>(p, 1)
        return simd_distance(SIMD3(r.x, r.y, r.z) / r.w, q) < tolerance
    }

    // MARK: The registry (CPU)

    @Test func aMoversFirstFrameRecordsNoRange() {
        let s = MoverProbe()
        s.setup()
        s.performDraw()
        #expect(s.drawer.moverRanges.isEmpty,
                "with no previous placement there is no motion to state")
    }

    @Test func theSecondFrameRecordsTheWayBackToLastFramesPlacement() {
        let s = MoverProbe()
        s.setup()
        s.performDraw()
        s.step = Vector3(10, 0, 0)
        s.performDraw()
        let ranges = s.drawer.moverRanges
        #expect(ranges.count == 1)
        guard let r = ranges.first else { return }
        #expect(r.count > 0)
        #expect(matches(r.previousOfCurrent, taking: SIMD3(10, 0, 0), to: SIMD3(0, 0, 0)),
                "previousOfCurrent must take this frame's world placement to last frame's")
    }

    @Test func aStationaryMoverRecordsTheIdentity() {
        let s = MoverProbe()
        s.setup()
        s.performDraw()
        s.performDraw()
        guard let r = s.drawer.moverRanges.first else {
            Issue.record("expected a recorded range")
            return
        }
        #expect(matches(r.previousOfCurrent, taking: SIMD3(7, -3, 2), to: SIMD3(7, -3, 2)),
                "a mover that held still moves nothing")
    }

    @Test func aSkippedFrameStartsTheHistoryOver() {
        let s = MoverProbe()
        s.setup()
        s.performDraw()
        s.skipMover = true
        s.performDraw()
        s.skipMover = false
        s.step = Vector3(10, 0, 0)
        s.performDraw()
        #expect(s.drawer.moverRanges.isEmpty,
                "a two-frame-old placement must not be read as one frame of motion")
    }

    @Test func sameLineBlocksKeepSeparateHistoriesByOccurrence() {
        let s = LoopProbe()
        s.setup()
        s.performDraw()
        s.offsets = [4, 50]   // the first block moves; the second holds still
        s.performDraw()
        let ranges = s.drawer.moverRanges
        #expect(ranges.count == 2)
        guard ranges.count == 2 else { return }
        #expect(matches(ranges[0].previousOfCurrent, taking: SIMD3(4, 0, 0), to: SIMD3(0, 0, 0)),
                "the first occurrence's delta belongs to the first block")
        #expect(matches(ranges[1].previousOfCurrent, taking: SIMD3(50, 0, 0), to: SIMD3(50, 0, 0)),
                "the second occurrence held still")
    }

    @Test func theNamedFormPinsIdentityAcrossCallSites() {
        let s = MoverProbe()
        s.setup()
        s.performDraw()
        s.useAltSite = true   // the same named block drawn from a different line
        s.step = Vector3(10, 0, 0)
        s.performDraw()
        let ranges = s.drawer.moverRanges
        #expect(ranges.count == 1)
        guard let r = ranges.first else { return }
        #expect(matches(r.previousOfCurrent, taking: SIMD3(10, 0, 0), to: SIMD3(0, 0, 0)),
                "a named mover keeps its history when the code path that draws it moves")
    }

    @Test func aMidFrameWipeDropsTheRecordedRanges() {
        let s = MoverProbe()
        s.setup()
        s.performDraw()
        s.wipeAfter = true   // background() after the mover empties the mesh list
        s.step = Vector3(10, 0, 0)
        s.performDraw()
        #expect(s.drawer.moverRanges.isEmpty,
                "a range surviving the wipe would index geometry that no longer exists")
    }

    @Test func aWireframeMoverIsNotRecorded() {
        let s = MoverProbe()
        s.wire = true
        s.setup()
        s.performDraw()
        s.step = Vector3(10, 0, 0)
        s.performDraw()
        #expect(s.drawer.moverRanges.isEmpty,
                "the velocity pass rasterizes solid triangles; a wireframe's interior is see-through")
    }

    @Test func aRenderTargetMoverIsNotRecorded() {
        let s = MoverProbe()
        s.moverInTarget = true
        s.setup()
        s.performDraw()
        s.step = Vector3(10, 0, 0)
        s.performDraw()
        #expect(s.drawer.moverRanges.isEmpty,
                "temporal AA never runs on a render target, so its movers record nothing")
    }

    // MARK: The velocity pass (Metal render probes)

    private func makeRenderer() throws -> (MetalRenderer, MTLDevice)? {
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let renderer = try MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device))
        return (renderer, device)
    }

    /// Drive the probe two frames and read the velocity texture back. The 1:1
    /// ortho makes world deltas pixel deltas, so expectations are exact numbers.
    private func velocityField(_ s: MoverProbe, from: Vector3, to: Vector3,
                               renderer: MetalRenderer,
                               previousEye: Vector3? = nil) throws -> [SIMD2<Float>] {
        s.setup()
        s.step = from
        s.performDraw()
        var prevCamera = try #require(s.drawer.camera3D)
        if let previousEye {
            prevCamera = Camera3D(eye: previousEye,
                                  target: Vector3(previousEye.x, previousEye.y, 0),
                                  up: .unitY, near: prevCamera.near, far: prevCamera.far,
                                  projection: prevCamera.projection)
        }
        let prevVP = prevCamera.projectionMatrix(aspect: 1) * prevCamera.viewMatrix
        s.step = to
        s.performDraw()
        return try #require(renderer.debugVelocityReadback(
            s.drawer, width: 128, height: 128, previousViewProjection: prevVP))
    }

    private func at(_ field: [SIMD2<Float>], _ x: Int, _ y: Int) -> SIMD2<Float> {
        field[y * 128 + x]
    }

    /// A written texel holds a screen delta; an unwritten one the sentinel.
    private func isWritten(_ v: SIMD2<Float>) -> Bool { v.x > 0.5 * OLLIN_VELOCITY_NONE }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aMoverWritesWhereItsPixelsCameFrom() throws {
        guard let (renderer, _) = try makeRenderer() else { return }
        let s = MoverProbe()
        // Right 10 and up 8 in world units = right 10, up 8 pixels: previous
        // minus current is (-10, +8) in y-down pixels.
        let field = try velocityField(s, from: .zero, to: Vector3(10, 8, 0), renderer: renderer)
        let center = at(field, 64 + 10, 64 - 8)   // the mover's new center pixel
        #expect(isWritten(center))
        #expect(abs(center.x - -10) < 0.15, "expected -10 px in x, got \(center.x)")
        #expect(abs(center.y - 8) < 0.15, "expected +8 px in y (y-down), got \(center.y)")
        let background = at(field, 8, 8)
        #expect(!isWritten(background), "an unwritten texel must keep the sentinel")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aStationaryMoverWritesZeroNotTheSentinel() throws {
        guard let (renderer, _) = try makeRenderer() else { return }
        let s = MoverProbe()
        let field = try velocityField(s, from: .zero, to: .zero, renderer: renderer)
        let center = at(field, 64, 64)
        #expect(isWritten(center), "a still mover is still a written mover")
        #expect(simd_length(center) < 0.05, "a still mover under a still camera moves nothing")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func cameraMotionRidesAMoversVelocityToo() throws {
        guard let (renderer, _) = try makeRenderer() else { return }
        let s = MoverProbe()
        // The camera trucked right 5 units between frames while the mover held
        // still: under the previous camera the mover sat 5 px right of where it
        // sits now, so its velocity is the camera's own motion (+5, 0). This is
        // the total-motion contract: written velocity includes the camera term,
        // which is what a full-screen consumer (MetalFX) requires.
        let field = try velocityField(s, from: .zero, to: .zero, renderer: renderer,
                                      previousEye: Vector3(-5, 0, 100))
        let center = at(field, 64, 64)
        #expect(isWritten(center))
        #expect(abs(center.x - 5) < 0.15, "expected +5 px of camera motion, got \(center.x)")
        #expect(abs(center.y) < 0.15)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func anOccluderInFrontHoldsAMoversVelocityBack() throws {
        guard let (renderer, _) = try makeRenderer() else { return }
        let s = MoverProbe()
        s.wall = true
        let field = try velocityField(s, from: .zero, to: Vector3(10, 0, 0), renderer: renderer)
        // The 40×40 wall spans pixels 44…84: the mover's center sits behind it.
        let hidden = at(field, 64 + 10, 64)
        #expect(!isWritten(hidden),
                "a mover must not write velocity through the static wall in front of it")
        // The mover's right edge (world x 25 → pixel 89) clears the wall.
        let visible = at(field, 64 + 23, 64)
        #expect(isWritten(visible))
        #expect(abs(visible.x - -10) < 0.15)
    }

    // MARK: The resolve's velocity branch (a pure function, probed directly)

    /// Craft the resolve's four inputs so the velocity branch is the only
    /// variable: identity reprojection matrices (the fallback is a no-op), a
    /// far-plane depth, a history whose left half is black and right half white,
    /// and a checkerboard current (so the rectification box is wide open). A
    /// written velocity then steers which half of the history the probe pixel
    /// reads; the sentinel keeps the identity fallback.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theResolveFollowsAWrittenVelocityToItsHistory() throws {
        guard let (renderer, device) = try makeRenderer() else { return }
        let w = 32, h = 32
        func floatTexture(_ format: MTLPixelFormat, channels: Int,
                          fill: (Int, Int) -> [Float]) throws -> MTLTexture {
            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: format, width: w, height: h, mipmapped: false)
            desc.usage = [.shaderRead]
            desc.storageMode = .shared
            let tex = try #require(device.makeTexture(descriptor: desc))
            var data = [Float]()
            data.reserveCapacity(w * h * channels)
            for y in 0..<h { for x in 0..<w { data.append(contentsOf: fill(x, y)) } }
            data.withUnsafeBytes { raw in
                tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0,
                            withBytes: raw.baseAddress!, bytesPerRow: w * channels * 4)
            }
            return tex
        }
        // Current: a 0.15 / 0.85 checkerboard (wide moments box). History: black
        // left half, white right half. Velocity: one value everywhere per run.
        let current = try floatTexture(.rgba32Float, channels: 4) { x, y in
            let v: Float = (x + y) % 2 == 0 ? 0.15 : 0.85
            return [v, v, v, 1]
        }
        let history = try floatTexture(.rgba32Float, channels: 4) { x, _ in
            let v: Float = x < w / 2 ? 0 : 1
            return [v, v, v, 1]
        }
        let depthDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float, width: w, height: h, mipmapped: false)
        depthDesc.usage = [.renderTarget, .shaderRead]
        depthDesc.storageMode = .private
        let depth = try #require(device.makeTexture(descriptor: depthDesc))
        let outDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float, width: w, height: h, mipmapped: false)
        outDesc.usage = [.renderTarget, .shaderRead]
        outDesc.storageMode = .shared
        func resolve(velocityX: Float) throws -> Float {
            let velocity = try floatTexture(.rg32Float, channels: 2) { _, _ in
                [velocityX, 0]
            }
            let out = try #require(device.makeTexture(descriptor: outDesc))
            let cb = try #require(renderer.commandQueue.makeCommandBuffer())
            // Clear the depth to the far plane (the fallback then reprojects by
            // the identity, so the velocity branch is the only moving part).
            let clearPass = MTLRenderPassDescriptor()
            clearPass.depthAttachment.texture = depth
            clearPass.depthAttachment.loadAction = .clear
            clearPass.depthAttachment.clearDepth = 1
            clearPass.depthAttachment.storeAction = .store
            try #require(cb.makeRenderCommandEncoder(descriptor: clearPass)).endEncoding()
            var params = [SIMD4<Float>](repeating: .zero, count: 12)
            params[0] = SIMD4(1 / Float(w), 1 / Float(h), 1, 0)   // texel, hasHistory
            params[1] = SIMD4(0, 0, 1, 0)                          // no jitter, hasVelocity
            let identity = matrix_identity_float4x4
            params[4] = identity.columns.0; params[5] = identity.columns.1
            params[6] = identity.columns.2; params[7] = identity.columns.3
            params[8] = identity.columns.0; params[9] = identity.columns.1
            params[10] = identity.columns.2; params[11] = identity.columns.3
            renderer.encodeEffectFragment("ollin_fx_taa_resolve",
                                          inputs: [current, depth, history, velocity],
                                          output: out, params: params, into: cb)
            cb.commit()
            cb.waitUntilCompleted()
            // Read the probe pixel at the vertical seam's left side (15, 16):
            // its own history is black; velocity +8 px reaches the white half.
            var half = [UInt16](repeating: 0, count: 4)
            out.getBytes(&half, bytesPerRow: w * 8, from: MTLRegionMake2D(15, 16, 1, 1),
                         mipmapLevel: 0)
            let bits = half[0]
            let sign: Float = (bits & 0x8000) != 0 ? -1 : 1
            let e = Int((bits >> 10) & 0x1F), m = Int(bits & 0x3FF)
            if e == 0 { return sign * Float(m) * exp2(Float(-24)) }
            if e == 0x1F { return .nan }
            return sign * (1 + Float(m) / 1024) * exp2(Float(e - 15))
        }
        let toWhite = try resolve(velocityX: 8)                       // reads the white half
        let toBlack = try resolve(velocityX: -8)                      // stays in the black half
        let fallback = try resolve(velocityX: Float(OLLIN_VELOCITY_NONE))   // sentinel: identity
        #expect(toWhite - toBlack > 0.3,
                "a +8 px velocity must pull history from 8 px right: \(toWhite) vs \(toBlack)")
        #expect(fallback < toWhite && fallback >= toBlack - 0.05,
                "the sentinel must keep the identity fallback between the two: \(fallback)")
    }
}
