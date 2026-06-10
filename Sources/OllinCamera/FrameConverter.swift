import CoreMedia
import CoreVideo
import Metal

/// Turns the sketch's rendered canvas texture into camera frames: letterboxes
/// it into a fixed-size BGRA pixel buffer (IOSurface-backed, so it crosses to
/// the extension process without a copy) and wraps it in a `CMSampleBuffer`.
///
/// The GPU does the scale on the sketch's own device — one textured-quad pass
/// over a black clear. The canvas bytes pass through *unconverted*: Ollin
/// renders into an sRGB target, so its bytes are already display-ready sRGB,
/// which is exactly what a camera frame carries — the pass samples and writes
/// through non-sRGB texture views so nothing re-encodes them.
final class FrameConverter {

    /// The camera's fixed stream format — must match the extension's.
    static let width = 1280
    static let height = 720
    static let frameRate = 30

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let pool: CVPixelBufferPool
    private var formatDescription: CMVideoFormatDescription?

    init?(device: MTLDevice) {
        self.device = device
        guard let library = try? device.makeLibrary(source: Self.shaderSource, options: nil),
              let vertexFunction = library.makeFunction(name: "ollin_camera_vertex"),
              let fragmentFunction = library.makeFunction(name: "ollin_camera_fragment"),
              let commandQueue = device.makeCommandQueue()
        else { return nil }
        self.commandQueue = commandQueue

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        self.pipeline = pipeline

        let attributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: Self.width,
            kCVPixelBufferHeightKey as String: Self.height,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            kCVPixelBufferMetalCompatibilityKey as String: true,
        ]
        var poolOut: CVPixelBufferPool?
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &poolOut)
        guard let pool = poolOut else { return nil }
        self.pool = pool
    }

    /// Letterbox `texture` into a fresh pixel buffer and wrap it as a frame.
    /// Synchronous: the GPU pass completes before the buffer is handed out, so
    /// the extension can never read a half-written surface.
    func makeSampleBuffer(from texture: MTLTexture) -> CMSampleBuffer? {
        var pixelBufferOut: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &pixelBufferOut)
        guard let pixelBuffer = pixelBufferOut,
              let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
        else { return nil }

        let targetDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: Self.width, height: Self.height, mipmapped: false)
        targetDescriptor.usage = [.renderTarget]
        guard let target = device.makeTexture(descriptor: targetDescriptor, iosurface: surface, plane: 0)
        else { return nil }

        // The fitted quad in clip space: scale to fit, centered, bars black.
        let scale = min(Double(Self.width) / Double(texture.width),
                        Double(Self.height) / Double(texture.height))
        let fractionX = Float(Double(texture.width) * scale / Double(Self.width))
        let fractionY = Float(Double(texture.height) * scale / Double(Self.height))
        var rect = SIMD4<Float>(-fractionX, fractionY, fractionX, -fractionY)

        let source = texture.makeTextureView(pixelFormat: .bgra8Unorm) ?? texture

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        pass.colorAttachments[0].storeAction = .store

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass)
        else { return nil }
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&rect, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
        encoder.setFragmentTexture(source, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        if formatDescription == nil {
            CMVideoFormatDescriptionCreateForImageBuffer(
                allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
                formatDescriptionOut: &formatDescription)
        }
        guard let formatDescription else { return nil }

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: Int32(Self.frameRate)),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid)
        var sampleBufferOut: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer,
            formatDescription: formatDescription, sampleTiming: &timing,
            sampleBufferOut: &sampleBufferOut)
        return sampleBufferOut
    }

    /// The letterbox pass: a unit quad placed by a clip-space rect, sampling
    /// the source linearly. `v = 0` is the top edge on both sides (the canvas
    /// and a video frame are both top-down), so no flip.
    private static let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct CameraVertexOut {
            float4 position [[position]];
            float2 uv;
        };

        vertex CameraVertexOut ollin_camera_vertex(uint vid [[vertex_id]],
                                                   constant float4 &rect [[buffer(0)]]) {
            float2 positions[4] = {
                float2(rect.x, rect.y), float2(rect.z, rect.y),
                float2(rect.x, rect.w), float2(rect.z, rect.w),
            };
            float2 uvs[4] = { float2(0, 0), float2(1, 0), float2(0, 1), float2(1, 1) };
            CameraVertexOut out;
            out.position = float4(positions[vid], 0, 1);
            out.uv = uvs[vid];
            return out;
        }

        fragment float4 ollin_camera_fragment(CameraVertexOut in [[stage_in]],
                                              texture2d<float> source [[texture(0)]]) {
            constexpr sampler linearSampler(address::clamp_to_edge, filter::linear);
            return float4(source.sample(linearSampler, in.uv).rgb, 1.0);
        }
        """
}
