import Foundation
import Metal

/// A tiny GPU pass that reads a handful of canvas pixels back to the CPU each
/// frame: the seam behind anything that turns *rendered pixels* into a few
/// hundred output values (an LED map driving fixtures, a sensor tap). It is the
/// counterpart to the whole-frame `CGImage` grab: where that pays a full
/// GPU→CPU readback, this dispatches one small compute kernel that samples N
/// points from the rendered texture into an N-entry buffer, so the readback is
/// hundreds of bytes rather than megabytes.
///
/// Feed it the texture the rendered-texture extension hook hands over
/// (`frameRendered(_:texture:)`): that texture is the frame the window shows,
/// at the canvas size, in display form (sRGB-encoded bytes), and the samples
/// come back in the same encoding, so a byte sampled here is the byte a
/// screenshot of that pixel would hold.
///
/// Each point carries its own box radius: the kernel averages the
/// `(2r+1)×(2r+1)` texel patch around the point, **in linear light** (the
/// texture reads decode sRGB, the average happens on linear values, and the
/// result re-encodes), so a patch half black and half white reads as the gray
/// that actually looks halfway, the same rule the renderer's own compositing
/// follows. Radius 0 reads the one texel under the point. Points off the
/// canvas clamp to the nearest edge texel.
@MainActor
package final class CanvasSampler {

    /// One sample point: a position in canvas pixels (top-left origin, the
    /// drawing coordinate space) and the box radius, in pixels, to average
    /// around it. Radius 0 samples a single texel; larger radii are clamped to
    /// a sane ceiling (256) so a wild value can't stall the GPU.
    package struct Point: Equatable, Sendable {
        package var position: Vector2
        package var radius: Double

        package init(position: Vector2, radius: Double = 0) {
            self.position = position
            self.radius = radius
        }
    }

    /// The points to sample, in order. Assigning re-uploads on the next
    /// `sample(_:)`, so a static map costs one upload total and a moving one
    /// costs one small copy per change.
    package var points: [Point] {
        didSet { pointsDirty = true }
    }

    private var pointsDirty = true
    private var pipeline: MTLComputePipelineState?
    private var queue: MTLCommandQueue?
    private var pointBuffer: MTLBuffer?
    private var colorBuffer: MTLBuffer?
    private var device: MTLDevice?
    private var failed = false

    package init(points: [Point] = []) {
        self.points = points
    }

    /// Sample the current `points` from `texture` and return one RGBA value per
    /// point: sRGB-encoded bytes, matching the display texture's own encoding.
    /// Synchronous. The GPU work is a few hundred threads, and waiting here is
    /// what lets the caller hand the texture back to the render loop safely
    /// (the loop re-renders into it next frame on its own queue, and hazard
    /// tracking doesn't span queues). Returns `nil` (once, with a note) if the
    /// kernel can't be built, and `[]` for an empty point list.
    package func sample(_ texture: MTLTexture) -> [SIMD4<UInt8>]? {
        guard !points.isEmpty else { return [] }
        guard ensurePipeline(on: texture.device),
              let pipeline, let queue,
              let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }

        let count = points.count
        if pointsDirty || pointBuffer == nil {
            uploadPoints()
            pointsDirty = false
        }
        guard let pointBuffer, let colorBuffer else { return nil }

        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(texture, index: 0)
        encoder.setBuffer(pointBuffer, offset: 0, index: 0)
        encoder.setBuffer(colorBuffer, offset: 0, index: 1)
        var n = UInt32(count)
        encoder.setBytes(&n, length: MemoryLayout<UInt32>.size, index: 2)
        let perGroup = min(count, 64)
        let groups = (count + perGroup - 1) / perGroup
        encoder.dispatchThreadgroups(MTLSize(width: groups, height: 1, depth: 1),
                                     threadsPerThreadgroup: MTLSize(width: perGroup, height: 1, depth: 1))
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        let raw = colorBuffer.contents().bindMemory(to: SIMD4<UInt8>.self, capacity: count)
        return Array(UnsafeBufferPointer(start: raw, count: count))
    }

    // MARK: Plumbing

    /// Build (once) the pipeline, queue, and buffers on the texture's device.
    private func ensurePipeline(on textureDevice: MTLDevice) -> Bool {
        if failed { return false }
        if pipeline != nil, device === textureDevice { return true }
        device = textureDevice
        do {
            let library = try textureDevice.makeLibrary(source: Self.kernelSource, options: nil)
            guard let function = library.makeFunction(name: "ollin_canvas_sample") else {
                throw NSError(domain: "Ollin", code: 1)
            }
            pipeline = try textureDevice.makeComputePipelineState(function: function)
            queue = textureDevice.makeCommandQueue()
            pointsDirty = true
            return pipeline != nil && queue != nil
        } catch {
            failed = true
            FileHandle.standardError.write(Data("Ollin: canvas sampling unavailable (\(error.localizedDescription))\n".utf8))
            return false
        }
    }

    /// (Re)upload the point list as float4 (x, y, radius, 0) and size the
    /// output buffer to match.
    private func uploadPoints() {
        guard let device else { return }
        let packed = points.map { p -> SIMD4<Float> in
            SIMD4(Float(p.position.x), Float(p.position.y),
                  Float(min(max(p.radius, 0), 256)), 0)
        }
        let pointLength = max(1, packed.count) * MemoryLayout<SIMD4<Float>>.stride
        if pointBuffer == nil || pointBuffer!.length < pointLength {
            pointBuffer = device.makeBuffer(length: pointLength, options: .storageModeShared)
        }
        packed.withUnsafeBytes { bytes in
            if let base = bytes.baseAddress, let buffer = pointBuffer {
                buffer.contents().copyMemory(from: base, byteCount: bytes.count)
            }
        }
        let colorLength = max(1, packed.count) * MemoryLayout<SIMD4<UInt8>>.stride
        if colorBuffer == nil || colorBuffer!.length < colorLength {
            colorBuffer = device.makeBuffer(length: colorLength, options: .storageModeShared)
        }
    }

    /// The sample kernel. Self-contained (compiled on its own, not part of the
    /// shader segment concatenation): it shares no types or helpers with the
    /// drawing shaders, and a buffer of plain `float4`/`uchar4` on both sides
    /// leaves no struct layout to drift. Reads on the sRGB texture decode to
    /// linear, the box average runs on those linear values, and the result
    /// re-encodes to sRGB bytes; alpha averages and quantizes straight, since
    /// it carries no gamma.
    private static let kernelSource = """
    #include <metal_stdlib>
    using namespace metal;

    static inline float ollin_encode_srgb(float c) {
        c = saturate(c);
        return (c <= 0.0031308f) ? c * 12.92f : 1.055f * pow(c, 1.0f / 2.4f) - 0.055f;
    }

    kernel void ollin_canvas_sample(
        texture2d<float, access::read> canvas [[texture(0)]],
        device const float4 *points [[buffer(0)]],
        device uchar4 *colors [[buffer(1)]],
        constant uint &count [[buffer(2)]],
        uint id [[thread_position_in_grid]])
    {
        if (id >= count) return;
        int w = int(canvas.get_width());
        int h = int(canvas.get_height());
        float4 p = points[id];
        int cx = clamp(int(floor(p.x)), 0, w - 1);
        int cy = clamp(int(floor(p.y)), 0, h - 1);
        int r = clamp(int(rint(p.z)), 0, 256);
        float4 sum = 0;
        for (int dy = -r; dy <= r; dy++) {
            for (int dx = -r; dx <= r; dx++) {
                int x = clamp(cx + dx, 0, w - 1);
                int y = clamp(cy + dy, 0, h - 1);
                sum += canvas.read(uint2(x, y));
            }
        }
        float side = float(2 * r + 1);
        float4 mean = sum / (side * side);
        colors[id] = uchar4(uchar(rint(ollin_encode_srgb(mean.r) * 255.0f)),
                            uchar(rint(ollin_encode_srgb(mean.g) * 255.0f)),
                            uchar(rint(ollin_encode_srgb(mean.b) * 255.0f)),
                            uchar(rint(saturate(mean.a) * 255.0f)));
    }
    """
}
