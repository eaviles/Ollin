import Foundation
import Metal
import MetalKit
import simd
import CoreGraphics

/// The Metal back end. Deliberately small: one command queue, an enum-keyed
/// cache of render pipelines (just `.solid` — solid-color 2D triangles — for
/// now), and a reusable vertex buffer.
///
/// You'll be editing this as you add primitives. The shape of the thing:
///
///   1. `Drawer` tessellates every primitive this frame into one flat
///      `[OllinVertex]` array (triangles, in sketch-space points).
///   2. `render(...)` uploads that array into `vertexBuffer`, clears to the
///      background color, and issues a single `drawPrimitives(.triangle)`.
///   3. `Shaders.metal` maps points -> clip space and outputs the vertex color.
///
/// To add a new primitive you usually only touch `Drawer` (more triangles).
/// You only touch this file when you need a *new pipeline* (e.g. instanced or
/// SDF circles, textured quads for images, a new blend mode): add a `Pipeline`
/// case and a branch in `makePipeline(_:)` — don't grow `init`.
final class MetalRenderer {

    enum RendererError: Error {
        case commandQueue
        case shaderLibrary
        case shaderFunctions
    }

    /// Identifies a render pipeline so it's built once and cached in
    /// `pipelines`. Today there's only `.solid`; instanced circles, SDF
    /// circles, textured quads, or a new blend mode each become a new case
    /// here (plus a branch in `makePipeline(_:)`) — not more code in `init`.
    private enum Pipeline: Hashable {
        case solid
    }

    /// Mirrors `Uniforms` in Shaders.metal.
    private struct Uniforms {
        var viewport: SIMD2<Float>
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var library: MTLLibrary
    private let pixelFormat: MTLPixelFormat
    private let sampleCount: Int

    /// Render pipelines, built on first use and reused. Keyed by `Pipeline` so
    /// a new capability is a new case + a branch in `makePipeline(_:)`, never
    /// more inline construction in `init` (see CLAUDE.md).
    private var pipelines: [Pipeline: MTLRenderPipelineState] = [:]

    /// Reused across frames; grown on demand to avoid per-frame allocation.
    private var vertexBuffer: MTLBuffer?

    init(device: MTLDevice, pixelFormat: MTLPixelFormat, sampleCount: Int) throws {
        self.device = device
        self.pixelFormat = pixelFormat
        self.sampleCount = sampleCount

        guard let queue = device.makeCommandQueue() else {
            throw RendererError.commandQueue
        }
        self.commandQueue = queue

        self.library = try MetalRenderer.loadLibrary(device: device)

        // Build the pipeline(s) we know we need now; `pipeline(_:)` builds any
        // added later on first use. Building here surfaces shader errors at
        // startup rather than mid-frame.
        _ = try pipeline(.solid)
    }

    /// Encode and present one frame's worth of recorded geometry.
    func render(_ drawer: Drawer, viewport: SIMD2<Float>, in view: MTKView) {
        // `currentRenderPassDescriptor` already points at the MSAA target with a
        // resolve into the drawable when the view's sampleCount > 1, so we only
        // need to set the load action and clear color.
        guard let renderPass = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable else { return }

        renderPass.colorAttachments[0].loadAction = .clear
        renderPass.colorAttachments[0].clearColor = drawer.backgroundColor.mtlClearColor

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else {
            return
        }

        encode(drawer, viewport: viewport, into: encoder)
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    /// Render `drawer`'s geometry off-screen to a `CGImage` of `width`×`height`
    /// pixels — same pipeline, MSAA, and blending as on-screen — for frame export
    /// (PNG, and later PNG sequences for video). Headless: needs no view or
    /// window. Synchronous: waits for the GPU before reading back.
    func image(of drawer: Drawer, viewport: SIMD2<Float>, width: Int, height: Int) -> CGImage? {
        guard width > 0, height > 0 else { return nil }

        // 4× MSAA color target + a single-sample resolve we can read back.
        let msaaDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
        msaaDesc.textureType = .type2DMultisample
        msaaDesc.sampleCount = sampleCount
        msaaDesc.usage = .renderTarget
        msaaDesc.storageMode = .private

        let resolveDesc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat, width: width, height: height, mipmapped: false)
        resolveDesc.usage = .renderTarget
        resolveDesc.storageMode = .private

        guard let msaaTexture = device.makeTexture(descriptor: msaaDesc),
              let resolveTexture = device.makeTexture(descriptor: resolveDesc) else { return nil }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = msaaTexture
        pass.colorAttachments[0].resolveTexture = resolveTexture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = drawer.backgroundColor.mtlClearColor
        pass.colorAttachments[0].storeAction = .multisampleResolve

        let bytesPerRow = width * 4
        let byteCount = bytesPerRow * height

        guard let readback = device.makeBuffer(length: byteCount, options: .storageModeShared),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }

        encode(drawer, viewport: viewport, into: encoder)
        encoder.endEncoding()

        // Copy the resolved texture into a CPU-readable buffer (works on every
        // Mac GPU, unlike texture.getBytes on discrete cards).
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { return nil }
        blit.copy(from: resolveTexture, sourceSlice: 0, sourceLevel: 0,
                  sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                  sourceSize: MTLSize(width: width, height: height, depth: 1),
                  to: readback, destinationOffset: 0,
                  destinationBytesPerRow: bytesPerRow, destinationBytesPerImage: byteCount)
        blit.endEncoding()

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        // BGRA8 bytes -> CGImage. Frames are opaque, so skip the alpha channel.
        let data = Data(bytes: readback.contents(), count: byteCount)
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue
                                      | CGBitmapInfo.byteOrder32Little.rawValue)
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: bitmapInfo, provider: provider, decode: nil,
                       shouldInterpolate: false, intent: .defaultIntent)
    }

    /// Upload `drawer`'s vertices and issue the solid-triangle draw into
    /// `encoder`. Shared by the on-screen and off-screen (export) paths.
    private func encode(_ drawer: Drawer, viewport: SIMD2<Float>, into encoder: MTLRenderCommandEncoder) {
        let vertices = drawer.vertices
        guard !vertices.isEmpty,
              let buffer = vertexBuffer(for: vertices.count),
              let solid = pipelines[.solid] else { return }
        vertices.withUnsafeBytes { raw in
            buffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
        }
        var uniforms = Uniforms(viewport: viewport)
        encoder.setRenderPipelineState(solid)
        encoder.setVertexBuffer(buffer, offset: 0, index: 0)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
    }

    // MARK: Pipelines

    /// Return the cached pipeline for `kind`, building and caching it on first
    /// use.
    private func pipeline(_ kind: Pipeline) throws -> MTLRenderPipelineState {
        if let existing = pipelines[kind] { return existing }
        let built = try makePipeline(kind)
        pipelines[kind] = built
        return built
    }

    /// Recompile the shader library from `source` and rebuild the cached
    /// pipelines against it — the renderer side of live shader reload. Builds the
    /// replacements *before* committing, so a compile/link error leaves the
    /// current library and pipelines untouched (it throws, and the caller reports
    /// it); a bad shader edit never blanks or crashes the running sketch.
    func reloadLibrary(source: String) throws {
        let newLibrary = try device.makeLibrary(source: source, options: nil)
        let kinds = pipelines.isEmpty ? [Pipeline.solid] : Array(pipelines.keys)
        var rebuilt: [Pipeline: MTLRenderPipelineState] = [:]
        for kind in kinds {
            rebuilt[kind] = try makePipeline(kind, using: newLibrary)
        }
        library = newLibrary           // commit atomically once all rebuilt
        pipelines = rebuilt
    }

    /// The single place pipeline descriptors are constructed. Add a `case` here
    /// when you add a `Pipeline` — e.g. instanced/SDF circles get their own
    /// vertex/fragment functions and (for instancing) a per-instance buffer.
    private func makePipeline(_ kind: Pipeline) throws -> MTLRenderPipelineState {
        try makePipeline(kind, using: library)
    }

    private func makePipeline(_ kind: Pipeline, using library: MTLLibrary) throws -> MTLRenderPipelineState {
        switch kind {
        case .solid:
            return try makeSolidPipeline(using: library)
        }
    }

    /// Solid-color 2D triangles with standard source-over alpha blending. Fills
    /// (triangle fans) and strokes (triangle-strip annuli) both go through this.
    private func makeSolidPipeline(using library: MTLLibrary) throws -> MTLRenderPipelineState {
        guard let vertexFunction = library.makeFunction(name: "ollin_vertex"),
              let fragmentFunction = library.makeFunction(name: "ollin_fragment") else {
            throw RendererError.shaderFunctions
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        // Must match the MTKView's MSAA sample count or pipeline creation fails.
        descriptor.rasterSampleCount = sampleCount

        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = pixelFormat
        // Standard source-over alpha blending so translucent colors composite.
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add
        attachment.sourceRGBBlendFactor = .sourceAlpha
        attachment.sourceAlphaBlendFactor = .one
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        return try device.makeRenderPipelineState(descriptor: descriptor)
    }

    // MARK: Helpers

    /// Return a shared vertex buffer large enough for `count` vertices, growing
    /// it (and rounding up) only when the frame needs more room.
    private func vertexBuffer(for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<OllinVertex>.stride
        if let buffer = vertexBuffer, buffer.length >= needed {
            return buffer
        }
        // Over-allocate a little so steady-state frames stop reallocating.
        let capacity = needed + needed / 2
        vertexBuffer = device.makeBuffer(length: capacity, options: .storageModeShared)
        return vertexBuffer
    }

    /// Load the shader library for `Shaders.metal`.
    ///
    /// SwiftPM's resource rule copies `Shaders.metal` into `Bundle.module` as
    /// *source* — it does not produce a precompiled `default.metallib`. So the
    /// reliable path is to read that source and compile it at runtime. We still
    /// try a precompiled `default.metallib` first in case a future build step
    /// (e.g. a build-tool plugin) produces one.
    private static func loadLibrary(device: MTLDevice) throws -> MTLLibrary {
        if let library = try? device.makeDefaultLibrary(bundle: Bundle.module) {
            return library
        }
        if let url = Bundle.module.url(forResource: "Shaders", withExtension: "metal"),
           let source = try? String(contentsOf: url, encoding: .utf8) {
            // Let compile errors propagate: a bad shader should fail loudly here.
            return try device.makeLibrary(source: source, options: nil)
        }
        if let library = device.makeDefaultLibrary() {
            return library
        }
        throw RendererError.shaderLibrary
    }
}

extension Color {
    /// Background/clear-color representation for a render pass.
    var mtlClearColor: MTLClearColor {
        MTLClearColorMake(red, green, blue, alpha)
    }
}
