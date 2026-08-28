import Metal
import MetalFX
import MetalKit
import simd

/// The live frame-interpolator state: the platform object (whose history lives
/// inside it), the sizes it was built for, and the textures it reads and writes.
/// One slot, rebuilt on a size change like the other size-keyed caches.
final class FXInterpolatorSlot {
    let interpolator: any MTLFXFrameInterpolator
    /// The depth and motion size (the render resolution, which is smaller than
    /// the output while the upscaler runs).
    let inputW: Int, inputH: Int
    /// The color and output size (the full canvas).
    let outputW: Int, outputH: Int
    /// The motion fill this slot owns, used when the upscaler did not already
    /// fill one this frame.
    let motion: MTLTexture
    /// The two drawn frames the interpolator works between: `colors[newest]` is
    /// the frame just drawn, the other one the frame before it. A pair rather
    /// than one texture because the older frame is still being read while the
    /// newer one is written, and because the newer one is shown a refresh later.
    let colors: [MTLTexture]
    /// The made frame.
    let output: MTLTexture
    /// Which of `colors` holds the newest drawn frame.
    var newest = 0
    /// Whether `colors[1 - newest]` holds a frame to interpolate from.
    var hasPrevious = false
    /// Discard the interpolator's history on the next encode (a fresh slot, or a
    /// run that stopped and started again, has nothing to carry).
    var needsReset = true

    init(interpolator: any MTLFXFrameInterpolator, inputW: Int, inputH: Int,
         outputW: Int, outputH: Int, motion: MTLTexture, colors: [MTLTexture], output: MTLTexture) {
        self.interpolator = interpolator
        self.inputW = inputW; self.inputH = inputH
        self.outputW = outputW; self.outputH = outputH
        self.motion = motion; self.colors = colors; self.output = output
    }
}

extension MetalRenderer {

    /// Whether the frame interpolator runs this frame: the sketch asked, a 3D
    /// camera with a field of view is active, and the GPU supports interpolation.
    /// Live path only, and only while the runner is free to give up a refresh:
    /// `hostAllowsInterpolation` carries the conditions the renderer cannot see
    /// (a take, a still sketch, a wall of displays).
    func frameInterpolationActive(_ drawer: Drawer) -> Bool {
        guard drawer.frameInterpolationEnabled else { return false }
        guard hostAllowsInterpolation else { return false }
        guard let camera = drawer.camera3D else {
            drawer.noteOnce("frameInterpolation() applies to the 3D scene; without an active camera the frame is unchanged.")
            return false
        }
        guard MetalRenderer.verticalFieldOfView(camera, aspect: 1) != nil else {
            drawer.noteOnce("frameInterpolation() needs a camera with a field of view; an orthographic scene renders every frame instead.")
            return false
        }
        if !interpolationSupportChecked {
            interpolationSupportChecked = true
            interpolationSupported = MetalRenderer.frameInterpolationSupported(on: device)
        }
        guard interpolationSupported else {
            drawer.noteOnce("frameInterpolation() needs a GPU with frame-interpolation support; every frame is drawn instead.")
            return false
        }
        return true
    }

    /// Whether `device` supports the platform frame interpolator.
    static func frameInterpolationSupported(on device: MTLDevice) -> Bool {
        MTLFXFrameInterpolatorDescriptor.supportsDevice(device)
    }

    /// The vertical field of view a camera frames the scene with, in degrees, or
    /// `nil` for a projection that has none. A pinhole calibration carries one in
    /// its focal length, so a depth feed's own lens answers too.
    static func verticalFieldOfView(_ camera: Camera3D, aspect: Double) -> Double? {
        switch camera.projection {
        case .perspective(let fieldOfView):
            return fieldOfView * 180 / .pi
        case .intrinsic(let intrinsics):
            guard intrinsics.fy > 0, intrinsics.height > 0 else { return nil }
            return 2 * atan(Double(intrinsics.height) / (2 * intrinsics.fy)) * 180 / .pi
        case .orthographic:
            return nil
        }
    }

    /// Whether a drawn frame is waiting to be shown. The runner asks this at the
    /// top of a refresh: while it is true the sketch draws nothing and the frame
    /// held from the last refresh goes to the screen instead.
    var hasHeldFrame: Bool { heldFrame != nil }

    /// Show the frame held from the last refresh. No geometry is uploaded, so
    /// this takes no slot in the frame ring and signals none: it is the present
    /// pass alone, over a texture that is already finished.
    func presentHeldFrame(_ drawer: Drawer, in view: MTKView) {
        guard let held = heldFrame else { return }
        heldFrame = nil
        guard let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer() else { return }
        if let presentEncoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: presentPass(into: drawable.texture)) {
            encodePresent(from: held, drawer: drawer, into: presentEncoder, projected: true)
            presentEncoder.endEncoding()
        }
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// Forget any frame held for the next refresh (a reload, a resize, or a
    /// sketch that stopped asking for interpolation), so the runner draws again
    /// rather than showing something that no longer belongs to this run.
    func dropHeldFrame() {
        heldFrame = nil
        interpolationSlot?.hasPrevious = false
        interpolationSlot?.needsReset = true
    }

    /// Encode this frame's interpolation and return the picture the drawable
    /// should carry *now*, which is the made frame that belongs between the last
    /// drawn frame and this one. The frame just drawn is held for the next
    /// refresh (`hasHeldFrame`). Returns `nil` when interpolation is not running
    /// or has nothing to work from yet, and then the caller presents the drawn
    /// frame as usual.
    ///
    /// - Parameters:
    ///   - drawn: this frame's finished picture, after every filter.
    ///   - upscalerMotion: the motion field the upscaler already filled this
    ///     frame at the render resolution, reused rather than filled twice.
    func applyFrameInterpolation(_ drawer: Drawer, drawn: MTLTexture, depth: MTLTexture?,
                                 upscalerMotion: MTLTexture?, meshBuffer: MTLBuffer?,
                                 into cb: MTLCommandBuffer,
                                 inputWidth: Int, inputHeight: Int,
                                 outputWidth: Int, outputHeight: Int) -> MTLTexture? {
        guard frameInterpolationActive(drawer), let camera = drawer.camera3D, let depth else {
            if interpolationSlot != nil { dropHeldFrame() }
            return nil
        }
        // A repeat encode of the same frame (the off-screen re-render a frame
        // grab asks for) must not step the interpolator's history, and has no
        // refresh of its own to show a made frame on.
        guard !statefulEncodeIsRepeat else { return nil }

        let slot: FXInterpolatorSlot
        if let existing = interpolationSlot, existing.inputW == inputWidth, existing.inputH == inputHeight,
           existing.outputW == outputWidth, existing.outputH == outputHeight {
            slot = existing
        } else {
            guard let fresh = makeInterpolatorSlot(inputWidth: inputWidth, inputHeight: inputHeight,
                                                   outputWidth: outputWidth, outputHeight: outputHeight) else {
                // Creation failing would retry every frame; treat it as
                // unsupported so the note prints once and the sketch keeps
                // drawing every refresh.
                interpolationSupported = false
                drawer.noteOnce("frameInterpolation() could not create the interpolator; every frame is drawn instead.")
                heldFrame = nil
                return nil
            }
            interpolationSlot = fresh
            slot = fresh
        }

        // Keep this frame: the pair alternates, so writing the newer frame never
        // touches the older one the interpolator is about to read.
        let next = 1 - slot.newest
        guard let blit = cb.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: drawn, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: outputWidth, height: outputHeight, depth: 1),
                  to: slot.colors[next], destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()

        // The first frame after starting has nothing to interpolate from: show it
        // as drawn, and hold nothing, so the next refresh draws normally.
        guard slot.hasPrevious else {
            slot.hasPrevious = true
            slot.newest = next
            heldFrame = nil
            return nil
        }

        let aspect = outputHeight > 0 ? Double(outputWidth) / Double(outputHeight) : 1
        let motion = upscalerMotion ?? encodeFXVelocityFill(
            drawer, camera: camera, into: cb, depth: depth, fallbackColor: drawn,
            meshBuffer: meshBuffer, motion: slot.motion,
            width: inputWidth, height: inputHeight, aspect: aspect)

        let fx = slot.interpolator
        fx.colorTexture = slot.colors[next]
        fx.prevColorTexture = slot.colors[slot.newest]
        fx.depthTexture = depth
        fx.motionTexture = motion
        fx.outputTexture = slot.output
        // The motion field is previous-minus-current in pixels, y-down, which is
        // exactly what a scale of 1 means here: each vector points at where its
        // pixel was in the previous frame.
        fx.motionVectorScaleX = 1
        fx.motionVectorScaleY = 1
        // The color handed over is always a resolved frame (the temporal-AA
        // resolve, or the upscaler's output), so it already sits on the
        // reference grid and asks for no jitter offset back.
        fx.jitterOffsetX = 0
        fx.jitterOffsetY = 0
        fx.deltaTime = Float(frameDelta)
        fx.nearPlane = Float(camera.near)
        fx.farPlane = Float(camera.far)
        fx.fieldOfView = Float(MetalRenderer.verticalFieldOfView(camera, aspect: aspect) ?? 60)
        fx.aspectRatio = Float(aspect)
        fx.isDepthReversed = false   // Ollin's depth runs 0 near, 1 far
        fx.shouldResetHistory = slot.needsReset
        slot.needsReset = false
        fx.encode(commandBuffer: cb)

        slot.newest = next
        heldFrame = slot.colors[next]
        return slot.output
    }

    /// TEST SEAM: run the interpolator over crafted frames and read the made one
    /// back. `frames` is a walk of full-canvas gray fields (row-major, values in
    /// linear light); each step hands the interpolator the pair (previous,
    /// current) with `motion` as the previous-minus-current pixel field of the
    /// current frame, and collects what it made. The returned array holds one
    /// made frame per step after the first. Tests only.
    func debugFrameInterpolationReadback(width: Int, height: Int,
                                         frames: [[Float]], motion: [[SIMD2<Float>]],
                                         depth: Float = 0.5,
                                         deltaTime: Double = 1.0 / 30) -> [[Float]]? {
        guard frames.count >= 2, motion.count == frames.count - 1,
              frames.allSatisfy({ $0.count == width * height }),
              MetalRenderer.frameInterpolationSupported(on: device) else { return nil }
        let desc = MTLFXFrameInterpolatorDescriptor()
        desc.colorTextureFormat = linearFormat
        desc.outputTextureFormat = linearFormat
        desc.depthTextureFormat = depthPixelFormat
        desc.motionTextureFormat = linearFormat
        desc.inputWidth = width; desc.inputHeight = height
        desc.outputWidth = width; desc.outputHeight = height
        guard let fx = desc.makeFrameInterpolator(device: device) else { return nil }

        func colorTexture() -> MTLTexture? {
            let d = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: linearFormat, width: width, height: height, mipmapped: false)
            d.usage = MTLTextureUsage([.renderTarget, .shaderRead]).union(fx.colorTextureUsage)
            d.storageMode = .private
            return device.makeTexture(descriptor: d)
        }
        let outDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: linearFormat, width: width, height: height, mipmapped: false)
        outDesc.usage = MTLTextureUsage([.shaderRead]).union(fx.outputTextureUsage)
        outDesc.storageMode = .private
        let depthDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: depthPixelFormat, width: width, height: height, mipmapped: false)
        depthDesc.usage = MTLTextureUsage([.shaderRead]).union(fx.depthTextureUsage)
        depthDesc.storageMode = .private
        let motionDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: linearFormat, width: width, height: height, mipmapped: false)
        motionDesc.usage = MTLTextureUsage([.renderTarget, .shaderRead]).union(fx.motionTextureUsage)
        motionDesc.storageMode = .private
        guard let prevTex = colorTexture(), let curTex = colorTexture(),
              let outTex = device.makeTexture(descriptor: outDesc),
              let depthTex = device.makeTexture(descriptor: depthDesc),
              let motionTex = device.makeTexture(descriptor: motionDesc) else { return nil }

        // One depth fill for the whole walk: a flat wall at `depth`.
        do {
            let plane = [Float](repeating: depth, count: width * height)
            guard let buf = plane.withUnsafeBytes({ raw in
                device.makeBuffer(bytes: raw.baseAddress!, length: raw.count, options: .storageModeShared)
            }), let cb = commandQueue.makeCommandBuffer(),
                  let blit = cb.makeBlitCommandEncoder() else { return nil }
            blit.copy(from: buf, sourceOffset: 0, sourceBytesPerRow: width * 4,
                      sourceBytesPerImage: width * 4 * height,
                      sourceSize: MTLSize(width: width, height: height, depth: 1),
                      to: depthTex, destinationSlice: 0, destinationLevel: 0,
                      destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
            blit.endEncoding()
            cb.commit(); cb.waitUntilCompleted()
        }

        fx.depthTexture = depthTex
        fx.motionTexture = motionTex
        fx.outputTexture = outTex
        fx.colorTexture = curTex
        fx.prevColorTexture = prevTex
        fx.motionVectorScaleX = 1; fx.motionVectorScaleY = 1
        fx.jitterOffsetX = 0; fx.jitterOffsetY = 0
        fx.deltaTime = Float(deltaTime)
        fx.nearPlane = 0.1; fx.farPlane = 1000
        fx.fieldOfView = 60; fx.aspectRatio = Float(width) / Float(max(1, height))
        fx.isDepthReversed = false

        var made: [[Float]] = []
        for step in 0..<(frames.count - 1) {
            guard uploadGrayField(frames[step], to: prevTex, width: width, height: height),
                  uploadGrayField(frames[step + 1], to: curTex, width: width, height: height),
                  uploadMotionField(motion[step], to: motionTex, width: width, height: height),
                  let cb = commandQueue.makeCommandBuffer() else { return nil }
            fx.shouldResetHistory = (step == 0)
            fx.encode(commandBuffer: cb)
            cb.commit(); cb.waitUntilCompleted()
            guard let read = readGrayField(outTex, width: width, height: height) else { return nil }
            made.append(read)
        }
        return made
    }

    /// Build the interpolator and its textures for one input/output size pair.
    private func makeInterpolatorSlot(inputWidth: Int, inputHeight: Int,
                                      outputWidth: Int, outputHeight: Int) -> FXInterpolatorSlot? {
        let desc = MTLFXFrameInterpolatorDescriptor()
        desc.colorTextureFormat = linearFormat
        desc.outputTextureFormat = linearFormat
        desc.depthTextureFormat = depthPixelFormat
        desc.motionTextureFormat = linearFormat
        // The depth and motion come from the geometry pass, which is smaller than
        // the canvas while the upscaler runs; the color and the made frame are
        // always the full canvas.
        desc.inputWidth = inputWidth
        desc.inputHeight = inputHeight
        desc.outputWidth = outputWidth
        desc.outputHeight = outputHeight
        guard let interpolator = desc.makeFrameInterpolator(device: device) else { return nil }

        let colorDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: linearFormat, width: outputWidth, height: outputHeight, mipmapped: false)
        // The pair is written by a blit and read by the interpolator, and the
        // newer one is also read by the present pass a refresh later.
        colorDesc.usage = MTLTextureUsage([.renderTarget, .shaderRead]).union(interpolator.colorTextureUsage)
        colorDesc.storageMode = .private
        let outputDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: linearFormat, width: outputWidth, height: outputHeight, mipmapped: false)
        outputDesc.usage = MTLTextureUsage([.shaderRead]).union(interpolator.outputTextureUsage)
        outputDesc.storageMode = .private
        let motionDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: linearFormat, width: inputWidth, height: inputHeight, mipmapped: false)
        motionDesc.usage = MTLTextureUsage([.renderTarget, .shaderRead]).union(interpolator.motionTextureUsage)
        motionDesc.storageMode = .private
        guard let first = device.makeTexture(descriptor: colorDesc),
              let second = device.makeTexture(descriptor: colorDesc),
              let output = device.makeTexture(descriptor: outputDesc),
              let motion = device.makeTexture(descriptor: motionDesc) else { return nil }
        return FXInterpolatorSlot(interpolator: interpolator,
                                  inputW: inputWidth, inputH: inputHeight,
                                  outputW: outputWidth, outputH: outputHeight,
                                  motion: motion, colors: [first, second], output: output)
    }

    // MARK: Test-seam texture helpers

    private func uploadGrayField(_ values: [Float], to texture: MTLTexture,
                                 width: Int, height: Int) -> Bool {
        var pixels = [Float16](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            let v = Float16(values[i])
            pixels[i * 4] = v; pixels[i * 4 + 1] = v; pixels[i * 4 + 2] = v; pixels[i * 4 + 3] = 1
        }
        return replace(texture, with: pixels, width: width, height: height)
    }

    private func uploadMotionField(_ values: [SIMD2<Float>], to texture: MTLTexture,
                                   width: Int, height: Int) -> Bool {
        guard values.count == width * height else { return false }
        var pixels = [Float16](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            pixels[i * 4] = Float16(values[i].x); pixels[i * 4 + 1] = Float16(values[i].y)
        }
        return replace(texture, with: pixels, width: width, height: height)
    }

    /// Blit a half-float RGBA field into a private texture through a shared one.
    private func replace(_ texture: MTLTexture, with pixels: [Float16],
                         width: Int, height: Int) -> Bool {
        let stagingDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: texture.pixelFormat, width: width, height: height, mipmapped: false)
        stagingDesc.storageMode = .shared
        stagingDesc.usage = [.shaderRead]
        guard let staging = device.makeTexture(descriptor: stagingDesc),
              let cb = commandQueue.makeCommandBuffer(),
              let blit = cb.makeBlitCommandEncoder() else { return false }
        pixels.withUnsafeBytes { raw in
            staging.replace(region: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0,
                            withBytes: raw.baseAddress!, bytesPerRow: width * 8)
        }
        blit.copy(from: staging, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1),
                  to: texture, destinationSlice: 0, destinationLevel: 0,
                  destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
        blit.endEncoding()
        cb.commit(); cb.waitUntilCompleted()
        return true
    }

    /// Read a texture's red channel back as a row-major field.
    private func readGrayField(_ texture: MTLTexture, width: Int, height: Int) -> [Float]? {
        let bytesPerRow = width * 8
        guard let readback = device.makeBuffer(length: bytesPerRow * height,
                                               options: .storageModeShared),
              let cb = commandQueue.makeCommandBuffer(),
              let blit = cb.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: texture, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1),
                  to: readback, destinationOffset: 0,
                  destinationBytesPerRow: bytesPerRow,
                  destinationBytesPerImage: bytesPerRow * height)
        blit.endEncoding()
        cb.commit(); cb.waitUntilCompleted()
        let words = readback.contents().bindMemory(to: Float16.self, capacity: width * height * 4)
        return (0..<(width * height)).map { Float(words[$0 * 4]) }
    }
}
