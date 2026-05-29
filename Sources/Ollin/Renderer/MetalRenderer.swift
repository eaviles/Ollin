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
///
/// Main-actor isolated: it's created and driven from the main thread (the
/// `MTKViewDelegate` draw callback and the headless export path). The only work
/// that intentionally runs off-actor is the GPU completed-handler, which signals
/// `frameBoundary` (a `Sendable` semaphore) and touches nothing else.
@MainActor
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
        case solid   // tessellated triangles (rects, lines, polygons, arcs)
        case sdf     // instanced SDF quads (circles, ellipses, rects, lines, arcs)
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

    /// Triple-buffered vertex storage, gated by a semaphore so the CPU never
    /// overwrites vertices the GPU is still reading. Writing one shared buffer
    /// every frame with no synchronization tears the on-screen geometry (e.g.
    /// gaps in a stroked ring) because the next frame stomps it mid-draw. Each
    /// slot is grown on demand to keep steady-state frames allocation-free.
    private static let maxFramesInFlight = 3
    private let frameBoundary = DispatchSemaphore(value: MetalRenderer.maxFramesInFlight)
    private var vertexBuffers: [MTLBuffer?] = Array(repeating: nil, count: MetalRenderer.maxFramesInFlight)
    /// Parallel ring for SDF instance data, advanced with `frameIndex` alongside
    /// `vertexBuffers` (one semaphore gates both — they're written and read
    /// together each frame).
    private var sdfBuffers: [MTLBuffer?] = Array(repeating: nil, count: MetalRenderer.maxFramesInFlight)
    private var frameIndex = 0

    /// A separate vertex buffer for off-screen `image(of:)` renders, so headless
    /// export never shares a slot with the on-screen ring. Export is synchronous
    /// (it waits for the GPU before reading back), so one reusable buffer is
    /// enough — no ring needed — but it must not be a ring slot the live loop
    /// could still be reading for an in-flight frame.
    private var exportBuffer: MTLBuffer?
    private var sdfExportBuffer: MTLBuffer?

    init(device: MTLDevice, pixelFormat: MTLPixelFormat, sampleCount: Int) throws {
        self.device = device
        self.pixelFormat = pixelFormat
        self.sampleCount = sampleCount

        guard let queue = device.makeCommandQueue() else {
            throw RendererError.commandQueue
        }
        self.commandQueue = queue

        self.library = try MetalRenderer.loadLibrary(device: device)

        // Build the pipelines we know we need now; `pipeline(_:)` builds any
        // added later on first use. Building here surfaces shader errors at
        // startup rather than mid-frame.
        _ = try pipeline(.solid)
        _ = try pipeline(.sdf)
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

        // Block until a vertex-buffer slot frees up, then advance to the next one
        // in the ring — so this frame's upload can't stomp a buffer the GPU is
        // still reading for an in-flight frame.
        frameBoundary.wait()
        frameIndex = (frameIndex + 1) % MetalRenderer.maxFramesInFlight

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else {
            frameBoundary.signal()   // nothing encoded; hand the slot back
            return
        }
        commandBuffer.addCompletedHandler { [frameBoundary] _ in frameBoundary.signal() }

        encode(drawer, viewport: viewport, into: encoder,
               triangleBuffer: vertexBuffer(at: frameIndex, for: drawer.vertices.count),
               sdfBuffer: sdfBuffer(at: frameIndex, for: drawer.sdfInstances.count))
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

        encode(drawer, viewport: viewport, into: encoder,
               triangleBuffer: exportVertexBuffer(for: drawer.vertices.count),
               sdfBuffer: exportSDFBuffer(for: drawer.sdfInstances.count))
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

    /// Upload `drawer`'s recorded geometry and issue its draws into `encoder`,
    /// one per batch in call order so triangles and SDF shapes composite
    /// front-to-back as the sketch drew them. Shared by the on-screen and
    /// off-screen (export) paths.
    private func encode(_ drawer: Drawer, viewport: SIMD2<Float>,
                        into encoder: MTLRenderCommandEncoder,
                        triangleBuffer: MTLBuffer?, sdfBuffer: MTLBuffer?) {
        let vertices = drawer.vertices
        let instances = drawer.sdfInstances
        let batches = drawer.batches
        guard !batches.isEmpty,
              let solid = pipelines[.solid], let sdf = pipelines[.sdf] else { return }

        if !vertices.isEmpty, let triangleBuffer {
            vertices.withUnsafeBytes { raw in
                triangleBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
        }
        if !instances.isEmpty, let sdfBuffer {
            instances.withUnsafeBytes { raw in
                sdfBuffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }
        }

        var uniforms = Uniforms(viewport: viewport)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)

        let vertexStride = MemoryLayout<OllinVertex>.stride
        let instanceStride = MemoryLayout<SDFInstance>.stride
        for i in batches.indices {
            let batch = batches[i]
            let next = i + 1 < batches.count ? batches[i + 1] : nil
            switch batch.kind {
            case .triangles:
                let end = next?.vertexStart ?? vertices.count
                let count = end - batch.vertexStart
                guard count > 0, let triangleBuffer else { continue }
                encoder.setRenderPipelineState(solid)
                encoder.setVertexBuffer(triangleBuffer, offset: batch.vertexStart * vertexStride, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: count)
            case .sdf:
                let end = next?.instanceStart ?? instances.count
                let count = end - batch.instanceStart
                guard count > 0, let sdfBuffer else { continue }
                encoder.setRenderPipelineState(sdf)
                encoder.setVertexBuffer(sdfBuffer, offset: batch.instanceStart * instanceStride, index: 0)
                encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: count)
            }
        }
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
            // Solid-color triangles: rects, lines, polygons, arcs.
            return try makePipeline(vertex: "ollin_vertex", fragment: "ollin_fragment", using: library)
        case .sdf:
            // Instanced SDF quads: circles, ellipses, rects, lines, arcs. The
            // fragment returns straight-alpha color, so it shares the solid
            // pipeline's blend.
            return try makePipeline(vertex: "ollin_sdf_vertex", fragment: "ollin_sdf_fragment", using: library)
        }
    }

    /// Build a render pipeline from the named vertex/fragment functions with the
    /// shared config: the view's MSAA sample count, the target pixel format, and
    /// standard source-over alpha blending so translucent colors composite.
    private func makePipeline(vertex: String, fragment: String,
                              using library: MTLLibrary) throws -> MTLRenderPipelineState {
        guard let vertexFunction = library.makeFunction(name: vertex),
              let fragmentFunction = library.makeFunction(name: fragment) else {
            throw RendererError.shaderFunctions
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        // Must match the MTKView's MSAA sample count or pipeline creation fails.
        descriptor.rasterSampleCount = sampleCount

        let attachment = descriptor.colorAttachments[0]!
        attachment.pixelFormat = pixelFormat
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

    /// Return the ring's vertex buffer at `index`, large enough for `count`
    /// vertices, growing it (and rounding up) only when a frame needs more room.
    private func vertexBuffer(at index: Int, for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<OllinVertex>.stride
        if let buffer = vertexBuffers[index], buffer.length >= needed {
            return buffer
        }
        // Over-allocate a little so steady-state frames stop reallocating.
        let capacity = needed + needed / 2
        vertexBuffers[index] = device.makeBuffer(length: capacity, options: .storageModeShared)
        return vertexBuffers[index]
    }

    /// The off-screen export buffer, grown on demand. Kept distinct from the
    /// on-screen ring so a headless render can't stomp a buffer an in-flight
    /// frame is still reading.
    private func exportVertexBuffer(for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<OllinVertex>.stride
        if let buffer = exportBuffer, buffer.length >= needed { return buffer }
        exportBuffer = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared)
        return exportBuffer
    }

    /// Return the SDF instance ring buffer at `index`, large enough for `count`
    /// instances, grown on demand. Mirrors `vertexBuffer(at:for:)`.
    private func sdfBuffer(at index: Int, for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<SDFInstance>.stride
        if let buffer = sdfBuffers[index], buffer.length >= needed {
            return buffer
        }
        let capacity = needed + needed / 2
        sdfBuffers[index] = device.makeBuffer(length: capacity, options: .storageModeShared)
        return sdfBuffers[index]
    }

    /// The off-screen export buffer for SDF instances, grown on demand.
    private func exportSDFBuffer(for count: Int) -> MTLBuffer? {
        let needed = max(count, 1) * MemoryLayout<SDFInstance>.stride
        if let buffer = sdfExportBuffer, buffer.length >= needed { return buffer }
        sdfExportBuffer = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared)
        return sdfExportBuffer
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
