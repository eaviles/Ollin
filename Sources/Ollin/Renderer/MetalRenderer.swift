import Foundation
import Metal
import MetalKit
import simd

/// The Metal back end. Deliberately small: one command queue, one render
/// pipeline (solid-color 2D triangles), and a reusable vertex buffer.
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
/// You only touch this file when you need a *new pipeline* (e.g. textured
/// quads for images, or a different blend mode).
final class MetalRenderer {

    enum RendererError: Error {
        case commandQueue
        case shaderLibrary
        case shaderFunctions
    }

    /// Mirrors `Uniforms` in Shaders.metal.
    private struct Uniforms {
        var viewport: SIMD2<Float>
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipelineState: MTLRenderPipelineState

    /// Reused across frames; grown on demand to avoid per-frame allocation.
    private var vertexBuffer: MTLBuffer?

    init(device: MTLDevice, pixelFormat: MTLPixelFormat, sampleCount: Int) throws {
        self.device = device

        guard let queue = device.makeCommandQueue() else {
            throw RendererError.commandQueue
        }
        self.commandQueue = queue

        let library = try MetalRenderer.loadLibrary(device: device)
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

        self.pipelineState = try device.makeRenderPipelineState(descriptor: descriptor)
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

        let vertices = drawer.vertices
        if !vertices.isEmpty, let buffer = vertexBuffer(for: vertices.count) {
            vertices.withUnsafeBytes { raw in
                buffer.contents().copyMemory(from: raw.baseAddress!, byteCount: raw.count)
            }

            var uniforms = Uniforms(viewport: viewport)

            encoder.setRenderPipelineState(pipelineState)
            encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            encoder.setVertexBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: vertices.count)
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
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

    /// Load the shader library that SwiftPM compiled from `Shaders.metal`.
    ///
    /// SwiftPM compiles `.metal` sources into `default.metallib` inside the
    /// target's resource bundle (`Bundle.module`). We fall back to the default
    /// library if the layout ever differs (e.g. when embedded differently).
    private static func loadLibrary(device: MTLDevice) throws -> MTLLibrary {
        if let library = try? device.makeDefaultLibrary(bundle: Bundle.module) {
            return library
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
