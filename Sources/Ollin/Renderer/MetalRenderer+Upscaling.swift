// MetalFX is absent from the simulator, where MetalRenderer+NoMetalFX stands in.
#if !targetEnvironment(simulator)

import Metal
import MetalFX
import simd

/// The live temporal-upscaler state: the platform scaler object (whose
/// accumulation history lives inside it), the sizes it was built for, and the
/// textures it reads and writes each frame. One slot, rebuilt on a size or
/// tier change like the other size-keyed caches.
final class FXScalerSlot {
    let scaler: any MTLFXTemporalScaler
    let inputW: Int, inputH: Int
    let outputW: Int, outputH: Int
    /// The full-screen motion fill the scaler consumes (render resolution;
    /// the linear color format because the effect-fragment pipeline writes
    /// that, with the motion in .xy and .zw unused).
    let motion: MTLTexture
    /// The full-resolution reconstructed frame; also what a same-frame repeat
    /// answers with, since re-encoding the scaler would double-step its
    /// internal history (the `taaHistory` rule).
    let output: MTLTexture
    /// The frame's mover-velocity texture (render resolution), kept so a
    /// same-frame repeat's motion blur reuses it instead of re-encoding a
    /// full-resolution copy into the render-resolution cache.
    var lastMover: MTLTexture?
    /// Discard the scaler's internal history on the next encode (a fresh or
    /// rebuilt scaler has nothing to reproject from).
    var needsReset = true

    init(scaler: any MTLFXTemporalScaler, inputW: Int, inputH: Int,
         outputW: Int, outputH: Int, motion: MTLTexture, output: MTLTexture) {
        self.scaler = scaler
        self.inputW = inputW; self.inputH = inputH
        self.outputW = outputW; self.outputH = outputH
        self.motion = motion; self.output = output
    }
}

extension MetalRenderer {

    /// Whether the temporal upscaler runs this frame: the sketch asked, a 3D
    /// camera is active (the temporal-AA gate), and the GPU supports temporal
    /// scaling. Live path only; the headless/export path renders at full
    /// resolution with the deterministic temporal-AA supersample instead (see
    /// `headlessTemporalAAActive`).
    func temporalUpscalingActive(_ drawer: Drawer) -> Bool {
        guard drawer.temporalUpscalingEnabled else { return false }
        guard drawer.camera3D != nil else {
            drawer.noteOnce("temporalUpscaling() applies to the 3D scene; without an active camera the frame is unchanged.")
            return false
        }
        if !fxSupportChecked {
            fxSupportChecked = true
            fxSupported = MetalRenderer.temporalScalerSupported(on: device)
        }
        guard fxSupported else {
            drawer.noteOnce("temporalUpscaling() needs a GPU with temporal-scaling support; rendering at full resolution.")
            return false
        }
        return true
    }

    /// Whether `device` supports the platform temporal scaler (the live gate).
    static func temporalScalerSupported(on device: MTLDevice) -> Bool {
        MTLFXTemporalScalerDescriptor.supportsDevice(device)
    }

    /// Whether the headless/export path should run its temporal-AA supersample:
    /// the sketch asked for temporal AA *or* for upscaling. An export never
    /// upscales (the scaler's history is stateful and its output device-shaped,
    /// neither of which an export can be), so an upscaling sketch exports as
    /// the full-resolution, supersampled equivalent of what it previews live.
    func headlessTemporalAAActive(_ drawer: Drawer) -> Bool {
        if temporalAAActive(drawer) { return true }
        return drawer.temporalUpscalingEnabled && drawer.camera3D != nil
    }

    /// The upscale factor for a tier: how many output pixels each rendered
    /// pixel becomes per axis. `.performance` renders at half size (factor 2),
    /// `.default` at two-thirds, `.detail` at three-quarters, each clamped to
    /// the scale range the device reports.
    func upscaleFactor(for quality: RenderQuality) -> Double {
        let requested: Double
        switch quality {
        case .performance: requested = 2.0
        case .default:     requested = 1.5
        case .detail:      requested = 4.0 / 3.0
        }
        let lo = Double(MTLFXTemporalScalerDescriptor.supportedInputContentMinScale(device: device))
        let hi = Double(MTLFXTemporalScalerDescriptor.supportedInputContentMaxScale(device: device))
        guard hi > lo, lo > 0 else { return requested }
        return min(max(requested, lo), hi)
    }

    /// The render (input) size for an upscaled frame of `width` by `height`.
    func upscaleInputSize(width: Int, height: Int, quality: RenderQuality) -> (Int, Int) {
        let f = upscaleFactor(for: quality)
        return (max(1, Int((Double(width) / f).rounded())),
                max(1, Int((Double(height) / f).rounded())))
    }

    /// How many jitter phases the upscaler cycles: a scaler reconstructing s×
    /// the pixels per axis needs about 8·s² distinct sub-pixel positions to
    /// visit every output sample, capped at the table's 32.
    func fxJitterPhaseCount(inputWidth: Int, outputWidth: Int) -> Int {
        let s = Double(outputWidth) / Double(max(1, inputWidth))
        return min(MetalRenderer.taaJitterOffsets.count, max(8, Int((8 * s * s).rounded(.up))))
    }

    /// Encode this frame's temporal upscale: the full-screen velocity fill
    /// (the mover texture composited over depth-reprojected camera motion, raw
    /// previous-minus-current pixels), then the platform scaler consuming the
    /// render-resolution color + depth + motion and writing the full-resolution
    /// output. Returns the output plus the frame's mover-velocity texture (for
    /// the motion-blur chain to reuse at its scale), or nil when the upscaler
    /// isn't running and the caller should resolve normally. On a same-frame
    /// repeat the slot's existing output answers without re-encoding, since the
    /// scaler's internal history must advance exactly once per frame.
    func applyTemporalUpscaling(_ drawer: Drawer, resolved: MTLTexture, depth: MTLTexture?,
                                meshBuffer: MTLBuffer?, into cb: MTLCommandBuffer,
                                inputWidth: Int, inputHeight: Int,
                                outputWidth: Int, outputHeight: Int,
                                jitterIndex: Int) -> (output: MTLTexture, mover: MTLTexture?)? {
        guard temporalUpscalingActive(drawer), let camera = drawer.camera3D, let depth else { return nil }
        if statefulEncodeIsRepeat, let slot = fxSlot,
           slot.inputW == inputWidth, slot.inputH == inputHeight,
           slot.outputW == outputWidth, slot.outputH == outputHeight {
            return (slot.output, slot.lastMover)
        }
        let slot: FXScalerSlot
        if let existing = fxSlot, existing.inputW == inputWidth, existing.inputH == inputHeight,
           existing.outputW == outputWidth, existing.outputH == outputHeight {
            slot = existing
        } else {
            guard let fresh = makeFXSlot(inputWidth: inputWidth, inputHeight: inputHeight,
                                         outputWidth: outputWidth, outputHeight: outputHeight) else {
                // Creation failing (an exotic format/size refusal) would retry
                // every frame; treat it as unsupported so the note prints once
                // and the frame keeps rendering.
                fxSupported = false
                drawer.noteOnce("temporalUpscaling() could not create the temporal scaler; rendering at full resolution.")
                return nil
            }
            fxSlot = fresh
            slot = fresh
        }
        // TAA's own resolve is bypassed while the scaler runs (the scaler *is*
        // the accumulation); drop its history so a later TAA-only frame starts
        // fresh instead of reprojecting through a stale matrix.
        taaHistory = nil

        let aspect = outputHeight > 0 ? Double(outputWidth) / Double(outputHeight) : 1
        let mover = encodeFXVelocityFill(drawer, camera: camera, into: cb, depth: depth,
                                         fallbackColor: resolved, meshBuffer: meshBuffer,
                                         motion: slot.motion,
                                         width: inputWidth, height: inputHeight, aspect: aspect)
        slot.lastMover = mover

        // The jitter offset handed to the scaler is the pixel shift the
        // jittered projection applied to the frame's content (x right, y down,
        // the table's own units): exactly "the offset to sample to return to
        // the reference frame". The motion texture is already
        // previous-minus-current in pixels, y-down, so its scale is 1.
        let px = MetalRenderer.taaJitterOffsets[jitterIndex % MetalRenderer.taaJitterOffsets.count]
        let s = slot.scaler
        s.colorTexture = resolved
        s.depthTexture = depth
        s.motionTexture = slot.motion
        s.outputTexture = slot.output
        s.inputContentWidth = inputWidth
        s.inputContentHeight = inputHeight
        s.jitterOffsetX = px.x
        s.jitterOffsetY = px.y
        s.motionVectorScaleX = 1
        s.motionVectorScaleY = 1
        s.reset = slot.needsReset
        slot.needsReset = false
        s.encode(commandBuffer: cb)
        return (slot.output, mover)
    }

    /// Fill a render-resolution motion field for the platform's temporal
    /// effects: this frame's declared movers over the camera term the depth
    /// buffer implies, as raw previous-minus-current pixels, y-down. Shared by
    /// the temporal upscaler and the frame interpolator, which read the same
    /// field under the same convention (a vector points at where its pixel was
    /// in the previous frame). Both matrices are unjittered, the
    /// remove-the-jitter rule; the platform object is told the jitter separately.
    /// Returns the mover-velocity texture, or nil when the frame declared none.
    @discardableResult
    func encodeFXVelocityFill(_ drawer: Drawer, camera: Camera3D, into cb: MTLCommandBuffer,
                              depth: MTLTexture, fallbackColor: MTLTexture,
                              meshBuffer: MTLBuffer?, motion: MTLTexture,
                              width: Int, height: Int, aspect: Double) -> MTLTexture? {
        let curVP = camera.projectionMatrix(aspect: aspect) * camera.viewMatrix
        let prevVP = drawer.previousCamera3D.map {
            $0.projectionMatrix(aspect: aspect) * $0.viewMatrix
        } ?? curVP
        let mover = encodeMoverVelocity(drawer, into: cb, meshBuffer: meshBuffer,
                                        width: width, height: height,
                                        previousViewProjection: prevVP)
        let invVP = simd_inverse(curVP)
        var params = [SIMD4<Float>](repeating: .zero, count: 10)
        params[0] = SIMD4(1 / Float(width), 1 / Float(height), 0, 0)
        params[1] = SIMD4(mover != nil ? 1 : 0, 0, 0, 0)
        params[2] = invVP.columns.0; params[3] = invVP.columns.1
        params[4] = invVP.columns.2; params[5] = invVP.columns.3
        params[6] = prevVP.columns.0; params[7] = prevVP.columns.1
        params[8] = prevVP.columns.2; params[9] = prevVP.columns.3
        encodeEffectFragment("ollin_fx_velocity_fill", inputs: [depth, mover ?? fallbackColor],
                             output: motion, params: params, into: cb)
        return mover
    }

    /// TEST SEAM: run the upscaler's velocity fill over crafted inputs (a full
    /// per-pixel depth array and an optional mover field, sentinel gaps included)
    /// and read the filled field back as row-major pixel deltas. Exercises the
    /// fill fragment alone: the mover passthrough must be raw (no shutter scale,
    /// no clamp), the fallback the camera reprojection, and the depth-1 backdrop
    /// zero. Tests only.
    func debugUpscaleFillReadback(width: Int, height: Int,
                                  depth: [Float], mover: [SIMD2<Float>]?,
                                  viewProjection: simd_float4x4,
                                  previousViewProjection: simd_float4x4) -> [SIMD2<Float>]? {
        guard depth.count == width * height else { return nil }
        let dDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .depth32Float, width: width, height: height, mipmapped: false)
        dDesc.usage = [.shaderRead]
        dDesc.storageMode = .private
        guard let dTex = device.makeTexture(descriptor: dDesc),
              let dBuf = depth.withUnsafeBytes({ raw in
                  device.makeBuffer(bytes: raw.baseAddress!, length: raw.count,
                                    options: .storageModeShared)
              }),
              let out = makeFilterTexture(width: width, height: height),
              let cb = commandQueue.makeCommandBuffer(),
              let blit = cb.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: dBuf, sourceOffset: 0, sourceBytesPerRow: width * 4,
                  sourceBytesPerImage: width * 4 * height,
                  sourceSize: MTLSize(width: width, height: height, depth: 1),
                  to: dTex, destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        // The mover texture is always bound (type-valid for the fragment's
        // texture2d slot); a 1×1 stand-in rides along when the probe has none,
        // with the bound-flag param telling the shader not to sample it.
        let mw = mover != nil ? width : 1
        let mh = mover != nil ? height : 1
        let mDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rg32Float, width: mw, height: mh, mipmapped: false)
        mDesc.usage = [.shaderRead]
        mDesc.storageMode = .shared
        guard let mTex = device.makeTexture(descriptor: mDesc) else { return nil }
        if let mover {
            guard mover.count == width * height else { return nil }
            mover.withUnsafeBytes { raw in
                mTex.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                             withBytes: raw.baseAddress!, bytesPerRow: width * 8)
            }
        }
        let invVP = simd_inverse(viewProjection)
        var params = [SIMD4<Float>](repeating: .zero, count: 10)
        params[0] = SIMD4(1 / Float(width), 1 / Float(height), 0, 0)
        params[1] = SIMD4(mover != nil ? 1 : 0, 0, 0, 0)
        params[2] = invVP.columns.0; params[3] = invVP.columns.1
        params[4] = invVP.columns.2; params[5] = invVP.columns.3
        params[6] = previousViewProjection.columns.0; params[7] = previousViewProjection.columns.1
        params[8] = previousViewProjection.columns.2; params[9] = previousViewProjection.columns.3
        encodeEffectFragment("ollin_fx_velocity_fill", inputs: [dTex, mTex],
                             output: out, params: params, into: cb)
        let bytesPerRow = width * 8
        guard let readback = device.makeBuffer(length: bytesPerRow * height,
                                               options: .storageModeShared),
              let outBlit = cb.makeBlitCommandEncoder() else { return nil }
        outBlit.copy(from: out, sourceSlice: 0, sourceLevel: 0,
                     sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                     sourceSize: MTLSize(width: width, height: height, depth: 1),
                     to: readback, destinationOffset: 0,
                     destinationBytesPerRow: bytesPerRow,
                     destinationBytesPerImage: bytesPerRow * height)
        outBlit.endEncoding()
        cb.commit()
        cb.waitUntilCompleted()
        func half(_ h: UInt16) -> Float {
            let sign = Float((h & 0x8000) != 0 ? -1 : 1)
            let exponent = Int((h >> 10) & 0x1F)
            let mantissa = Int(h & 0x3FF)
            if exponent == 0 { return sign * Float(mantissa) * exp2(Float(-24)) }
            if exponent == 0x1F { return mantissa == 0 ? sign * .infinity : .nan }
            return sign * (1 + Float(mantissa) / 1024) * exp2(Float(exponent - 15))
        }
        let words = readback.contents().bindMemory(to: UInt16.self, capacity: width * height * 4)
        return (0..<(width * height)).map {
            SIMD2(half(words[$0 * 4]), half(words[$0 * 4 + 1]))
        }
    }

    /// Build the scaler and its textures for one input/output size pair.
    private func makeFXSlot(inputWidth: Int, inputHeight: Int,
                            outputWidth: Int, outputHeight: Int) -> FXScalerSlot? {
        let desc = MTLFXTemporalScalerDescriptor()
        desc.colorTextureFormat = linearFormat
        desc.depthTextureFormat = depthPixelFormat
        desc.motionTextureFormat = linearFormat
        desc.outputTextureFormat = linearFormat
        desc.inputWidth = inputWidth
        desc.inputHeight = inputHeight
        desc.outputWidth = outputWidth
        desc.outputHeight = outputHeight
        // The canvas is linear pre-tonemap and can carry HDR values; let the
        // scaler meter its own exposure rather than plumbing one through.
        desc.isAutoExposureEnabled = true
        guard let scaler = desc.makeTemporalScaler(device: device) else { return nil }
        scaler.isDepthReversed = false   // Ollin's depth runs 0 near, 1 far

        let motionDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: linearFormat, width: inputWidth, height: inputHeight, mipmapped: false)
        motionDesc.usage = MTLTextureUsage([.renderTarget, .shaderRead]).union(scaler.motionTextureUsage)
        motionDesc.storageMode = .private
        let outputDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: linearFormat, width: outputWidth, height: outputHeight, mipmapped: false)
        // The scaler's required output bits plus `.shaderRead` for the frame
        // filters and the present pass that sample it afterward.
        outputDesc.usage = MTLTextureUsage([.shaderRead]).union(scaler.outputTextureUsage)
        outputDesc.storageMode = .private
        guard let motion = device.makeTexture(descriptor: motionDesc),
              let output = device.makeTexture(descriptor: outputDesc) else { return nil }
        return FXScalerSlot(scaler: scaler, inputW: inputWidth, inputH: inputHeight,
                            outputW: outputWidth, outputH: outputHeight,
                            motion: motion, output: output)
    }
}

#endif
