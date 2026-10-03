import Metal

extension MetalRenderer {

    /// The frame as the renderer composited it, one step before the present pass
    /// tone-maps, dithers, and quantizes it: linear light, Rec. 709 primaries,
    /// half-float components that are free to run above 1, premultiplied by the
    /// frame's own coverage, and, for a frame drawn through a 3D camera, the
    /// distance from the eye at every pixel beside it.
    ///
    /// What `--export-exr` writes. Kept by a render only while
    /// `capturesLinearFrame` is set.
    struct LinearFrame {
        let width: Int
        let height: Int
        /// `rgba16Float`, `width * 8` bytes per row, the first row at the top.
        let color: MTLBuffer
        /// Distance from the eye in the sketch's own world units, canvas-sized,
        /// the first row at the top. Nil for a frame with no 3D camera: a flat
        /// sketch's depth buffer holds a sort key, not a distance, and writing it
        /// as one would be a lie.
        let depth: [Float]?
    }

    /// The two GPU copies a linear capture needs, taken while the frame's command
    /// buffer is still open. Read into a `LinearFrame` by `finishLinearCapture`
    /// once the GPU has finished.
    struct LinearCapture {
        let color: MTLBuffer
        /// Whether `color` holds single-precision components (a `.float32`
        /// accumulation surface), which `finishLinearCapture` narrows to the
        /// half floats a `LinearFrame` carries.
        var colorIsSingle = false
        /// The resolved scene depth, still at the render's own size, which a
        /// supersampled export makes larger than the canvas.
        let depth: MTLBuffer?
        let depthWidth: Int
        let depthHeight: Int
    }

    /// Copy the canvas the present pass is about to read, and the scene depth if
    /// the frame resolved one, into CPU-readable buffers inside the frame's own
    /// command buffer. The blit is how every read-back here reaches a `.private`
    /// texture.
    func beginLinearCapture(_ color: MTLTexture, depth: MTLTexture?,
                            into commandBuffer: MTLCommandBuffer,
                            width: Int, height: Int) -> LinearCapture? {
        let single = color.pixelFormat == .rgba32Float
        let colorBytesPerRow = width * (single ? 16 : 8)    // rgba32Float or rgba16Float
        let colorBytes = colorBytesPerRow * height
        guard width > 0, height > 0,
              let colorBuffer = device.makeBuffer(length: colorBytes, options: .storageModeShared),
              let blit = commandBuffer.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: color, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1),
                  to: colorBuffer, destinationOffset: 0,
                  destinationBytesPerRow: colorBytesPerRow, destinationBytesPerImage: colorBytes)

        var depthBuffer: MTLBuffer?
        var depthWidth = 0, depthHeight = 0
        if let depth {
            depthWidth = depth.width
            depthHeight = depth.height
            let rowBytes = depthWidth * 4                   // depth32Float
            let bytes = rowBytes * depthHeight
            if let buffer = device.makeBuffer(length: bytes, options: .storageModeShared) {
                blit.copy(from: depth, sourceSlice: 0, sourceLevel: 0,
                          sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                          sourceSize: MTLSize(width: depthWidth, height: depthHeight, depth: 1),
                          to: buffer, destinationOffset: 0,
                          destinationBytesPerRow: rowBytes, destinationBytesPerImage: bytes)
                depthBuffer = buffer
            }
        }
        blit.endEncoding()
        return LinearCapture(color: colorBuffer, colorIsSingle: single, depth: depthBuffer,
                             depthWidth: depthWidth, depthHeight: depthHeight)
    }

    /// Turn a finished capture into a `LinearFrame`: the color buffer travels as
    /// it is (the renderer's own half-float bytes, so nothing is converted), and
    /// the depth buffer becomes distance from the eye. A single-precision pile is
    /// narrowed to half floats here, the one form a `LinearFrame` holds (nil
    /// only if the buffer for that cannot be made). Call only after the command
    /// buffer has completed.
    func finishLinearCapture(_ capture: LinearCapture, drawer: Drawer,
                             width: Int, height: Int) -> LinearFrame? {
        let color: MTLBuffer
        if capture.colorIsSingle {
            guard let narrowed = halfFloats(of: capture.color, count: width * height * 4) else { return nil }
            color = narrowed
        } else {
            color = capture.color
        }
        return LinearFrame(width: width, height: height, color: color,
                           depth: eyeDistances(capture, camera: drawer.camera3D,
                                               width: width, height: height))
    }

    /// `count` single-precision components narrowed to half floats in a new
    /// shared buffer, in the same order.
    private func halfFloats(of buffer: MTLBuffer, count: Int) -> MTLBuffer? {
        guard let out = device.makeBuffer(length: count * 2, options: .storageModeShared) else { return nil }
        let source = buffer.contents().bindMemory(to: Float.self, capacity: count)
        let target = out.contents().bindMemory(to: Float16.self, capacity: count)
        for i in 0..<count { target[i] = Float16(source[i]) }
        return out
    }

    /// The depth buffer read as distance from the eye, canvas-sized.
    ///
    /// Two steps. A supersampled render resolved its depth at the larger size, so
    /// each canvas pixel takes the **nearest** of the samples that cover it: the
    /// front-most surface, which is the rule the multisample depth resolve itself
    /// follows, and the one a compositor wants out of a Z channel. Then the clip
    /// depth is inverted over the camera's near and far, the same curve
    /// `ollin_fx_depth_normalize` walks on the GPU, where a perspective (or
    /// pinhole) frustum spreads depth hyperbolically and an orthographic one
    /// linearly.
    ///
    /// A pixel nothing drew to keeps the cleared depth, which inverts to exactly
    /// the camera's far distance.
    private func eyeDistances(_ capture: LinearCapture, camera: Camera3D?,
                              width: Int, height: Int) -> [Float]? {
        guard let buffer = capture.depth, let camera,
              capture.depthWidth >= width, capture.depthHeight >= height else { return nil }
        // Double, not Float: the inverse subtracts two nearly equal numbers, and
        // in single precision a far plane of 1000 came back as 1000.244.
        let near = camera.near, far = camera.far
        guard far > near else { return nil }
        var perspective = true
        if case .orthographic = camera.projection { perspective = false }

        let scaleX = capture.depthWidth / width, scaleY = capture.depthHeight / height
        let source = buffer.contents().bindMemory(to: Float.self,
                                                  capacity: capture.depthWidth * capture.depthHeight)
        var out = [Float](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                var clip = Float.greatestFiniteMagnitude
                for sy in 0..<scaleY {
                    let row = (y * scaleY + sy) * capture.depthWidth
                    for sx in 0..<scaleX {
                        clip = min(clip, source[row + x * scaleX + sx])
                    }
                }
                let d = Double(min(max(clip, 0), 1))
                out[y * width + x] = Float(perspective
                    ? (near * far) / max(1e-9, far - d * (far - near))
                    : near + d * (far - near))
            }
        }
        return out
    }
}
