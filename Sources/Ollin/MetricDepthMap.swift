import Metal

/// A metric depth map (meters) carried to the depth-scene path and uploaded as a
/// single-channel float (`r32Float`) texture, so the depth-scene fragment can write
/// *true metric* depth into the depth buffer rather than a coarse 8-bit gray value.
///
/// Reference-typed so the GPU texture is built once and reused across draws of the
/// same map (mirroring `Image`'s lazy texture cache) — a live feed builds a fresh
/// one per frame, but a held frame orbited in place uploads nothing after the first
/// draw. The texture stores raw meters; the fragment converts to clip-space depth
/// against the active camera's near/far. A hole (depth ≤ 0) reads back as 0 and the
/// fragment treats it as "infinitely far", so it never falsely occludes.
final class MetricDepthMap {

    /// Metric depth in meters, row-major from the top-left, `width × height`.
    let depth: [Float]
    let width: Int
    let height: Int

    private var cachedTexture: MTLTexture?

    init(depth: [Float], width: Int, height: Int) {
        self.depth = depth
        self.width = width
        self.height = height
    }

    /// The depth map as an `r32Float` texture, built and cached on first use.
    func texture(for device: MTLDevice) -> MTLTexture? {
        if let cachedTexture { return cachedTexture }
        guard width > 0, height > 0, depth.count >= width * height else { return nil }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r32Float, width: width, height: height, mipmapped: false)
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared   // CPU-written, GPU-read
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }
        depth.withUnsafeBytes { raw in
            texture.replace(region: MTLRegionMake2D(0, 0, width, height),
                            mipmapLevel: 0,
                            withBytes: raw.baseAddress!,
                            bytesPerRow: width * MemoryLayout<Float>.stride)
        }
        cachedTexture = texture
        return texture
    }
}
