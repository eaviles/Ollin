import CoreMedia
import CoreVideo
import Foundation
import Metal
import VideoToolbox
import os
import Ollin

/// Compresses a sketch's rendered frames into pictures for the phone's screen.
///
/// Two steps, both on the GPU and the media engine, so a picture never passes
/// through the CPU as pixels. The frame texture is drawn into a pixel buffer
/// backed by an IOSurface, which the compressor reads where it lies; the
/// compressor (`PhonePictureCompressor`, the one the phone compresses its
/// camera with) writes HEVC in real time with no reordering, so a picture goes
/// out the moment it is made rather than waiting on a later one.
///
/// The copy runs synchronously inside the frame hook, because the renderer takes
/// the texture back the moment the hook returns and may write the next frame into
/// it on its own queue. The compression runs asynchronously, and its output
/// arrives on a thread of the compressor's own; `onPicture` is called there.
///
/// Not main-actor bound: the compressor's output handler is formed inside these
/// nonisolated methods, so it carries no executor assertion into the thread that
/// calls it.
final class PhonePictureEncoder: @unchecked Sendable {

    /// The longest side a picture is sent at. A phone's screen is under 2,800
    /// pixels on its long side and a canvas usually shows inside it, so a bigger
    /// canvas is scaled down on the Mac rather than sent whole.
    static let defaultMaxSide = 1920

    /// Called with each finished picture, on the compressor's thread.
    let onPicture: @Sendable (PhonePicture) -> Void

    let maxSide: Int
    let framesPerSecond: Double

    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState

    // The compressor is made, used, and replaced on the thread that calls
    // `encode` (the main thread, live), which is what `@unchecked Sendable`
    // asserts. Its own count of pictures in flight is the one thing the
    // compressor's thread also writes, and it keeps that behind a lock.
    private var compressor: PhonePictureCompressor?
    private var pool: CVPixelBufferPool?
    private var failedSize: (width: Int, height: Int)?
    private var frameIndex: Int64 = 0

    init?(device: MTLDevice, framesPerSecond: Double, maxSide: Int = PhonePictureEncoder.defaultMaxSide,
          onPicture: @escaping @Sendable (PhonePicture) -> Void) {
        guard let library = try? device.makeLibrary(source: Self.shaderSource,
                                                     options: ollinShaderCompileOptions()),
              let vertex = library.makeFunction(name: "ollin_phone_picture_vertex"),
              let fragment = library.makeFunction(name: "ollin_phone_picture_fragment"),
              let queue = device.makeCommandQueue() else { return nil }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor) else { return nil }
        self.device = device
        self.queue = queue
        self.pipeline = pipeline
        self.maxSide = max(16, maxSide)
        self.framesPerSecond = max(1, framesPerSecond)
        self.onPicture = onPicture
    }

    /// How many pictures have been handed to the compressor and not come back.
    var inFlight: Int { compressor?.inFlight ?? 0 }

    /// The size a canvas of `width` by `height` pixels is sent at: fitted under
    /// `maxSide` with its proportion kept, and rounded down to even numbers,
    /// since the codec samples its color at half size.
    static func pictureSize(width: Int, height: Int, maxSide: Int) -> (width: Int, height: Int) {
        guard width > 0, height > 0 else { return (0, 0) }
        let scale = min(1, Double(maxSide) / Double(max(width, height)))
        func even(_ value: Double) -> Int { max(2, Int(value) & ~1) }
        return (even(Double(width) * scale), even(Double(height) * scale))
    }

    /// The bit rate a picture size runs at, which is the shared compressor's rule.
    static func bitRate(width: Int, height: Int, framesPerSecond: Double) -> Int {
        PhonePictureCompressor.bitRate(width: width, height: height, framesPerSecond: framesPerSecond)
    }

    /// Copy `texture` into a pixel buffer and hand it to the compressor.
    ///
    /// Returns `false` when nothing was submitted: no compressor could be made,
    /// or the copy failed. `forceKeyframe` asks for a picture that stands alone,
    /// which the phone needs after it connects or comes back to Sketch mode.
    @discardableResult
    func encode(_ texture: MTLTexture, forceKeyframe: Bool) -> Bool {
        let size = Self.pictureSize(width: texture.width, height: texture.height, maxSide: maxSide)
        guard size.width > 0, let (compressor, pool) = compressorFitting(size) else { return false }
        guard let pixelBuffer = copy(texture, into: pool, width: size.width, height: size.height)
        else { return false }

        let index = frameIndex
        frameIndex += 1
        let deliver = onPicture
        return compressor.encode(pixelBuffer, at: Double(index) / framesPerSecond,
                                 forceKeyframe: forceKeyframe) { picture in
            if let picture { deliver(picture) }
        }
    }

    /// Wait for every submitted picture to come back. The tests use it; the live
    /// path never waits on the compressor.
    func finish() { compressor?.finish() }

    // MARK: The compressor

    /// The compressor for this picture size, made on first use and made again
    /// when the canvas changes size. A new one starts on a keyframe by itself.
    private func compressorFitting(_ size: (width: Int, height: Int))
        -> (PhonePictureCompressor, CVPixelBufferPool)? {
        if let compressor, let pool, compressor.width == size.width, compressor.height == size.height {
            return (compressor, pool)
        }
        // A size the machine could not compress once is not asked for every frame.
        if let failedSize, failedSize == size { return nil }

        // What the old one still holds comes back before it is let go.
        compressor?.finish()
        compressor = nil
        pool = nil

        // The copy draws into buffers from the compressor's own pool, which it
        // reads where they lie.
        let sourceAttributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: size.width,
            kCVPixelBufferHeightKey: size.height,
            kCVPixelBufferIOSurfacePropertiesKey: [CFString: Any](),
            kCVPixelBufferMetalCompatibilityKey: true,
        ]
        guard let made = PhonePictureCompressor(
                width: size.width, height: size.height, framesPerSecond: framesPerSecond,
                colors: .sRGBCanvas, sourceAttributes: sourceAttributes),
              let madePool = made.pixelBufferPool else {
            failedSize = size
            return nil
        }
        compressor = made
        pool = madePool
        failedSize = nil
        return (made, madePool)
    }

    // MARK: The copy

    /// Draw the frame into a pixel buffer from the compressor's own pool. The
    /// canvas bytes are display-ready sRGB, so an eight-bit frame is read through
    /// a plain view and written as it is; a floating-point frame (a wide or a
    /// bright sketch) is clamped and encoded on the way.
    private func copy(_ texture: MTLTexture, into pool: CVPixelBufferPool,
                      width: Int, height: Int) -> CVPixelBuffer? {
        var made: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &made)
        guard let pixelBuffer = made,
              let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
        else { return nil }
        CVBufferSetAttachment(pixelBuffer, kCVImageBufferColorPrimariesKey,
                              kCVImageBufferColorPrimaries_ITU_R_709_2, .shouldPropagate)
        CVBufferSetAttachment(pixelBuffer, kCVImageBufferTransferFunctionKey,
                              kCVImageBufferTransferFunction_sRGB, .shouldPropagate)
        CVBufferSetAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey,
                              kCVImageBufferYCbCrMatrix_ITU_R_709_2, .shouldPropagate)

        let targetDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        targetDescriptor.usage = [.renderTarget]
        guard let target = device.makeTexture(descriptor: targetDescriptor, iosurface: surface, plane: 0)
        else { return nil }

        let isFloat = texture.pixelFormat == .rgba16Float || texture.pixelFormat == .rgba32Float
        let source: MTLTexture
        switch texture.pixelFormat {
        case .bgra8Unorm_srgb: source = texture.makeTextureView(pixelFormat: .bgra8Unorm) ?? texture
        case .rgba8Unorm_srgb: source = texture.makeTextureView(pixelFormat: .rgba8Unorm) ?? texture
        default: source = texture
        }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store
        guard let commandBuffer = queue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        var encodes: UInt32 = isFloat ? 1 : 0
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentBytes(&encodes, length: MemoryLayout<UInt32>.size, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.commit()
        // The renderer takes the texture back when the hook returns, and its
        // hazard tracking does not reach across to this queue.
        commandBuffer.waitUntilCompleted()
        guard commandBuffer.status == .completed else { return nil }
        return pixelBuffer
    }

    /// One triangle over the whole target, sampling the frame. `v = 0` is the top
    /// edge of both a canvas and a video picture, so nothing is flipped.
    private static let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;

        struct PhonePictureVertex {
            float4 position [[position]];
            float2 uv;
        };

        vertex PhonePictureVertex ollin_phone_picture_vertex(uint vid [[vertex_id]]) {
            float2 uv = float2((vid << 1) & 2, vid & 2);
            PhonePictureVertex out;
            out.position = float4(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, 0.0, 1.0);
            out.uv = uv;
            return out;
        }

        fragment float4 ollin_phone_picture_fragment(PhonePictureVertex in [[stage_in]],
                                                     texture2d<float> source [[texture(0)]],
                                                     constant uint &encodes [[buffer(0)]]) {
            constexpr sampler bilinear(address::clamp_to_edge, filter::linear);
            float3 color = source.sample(bilinear, in.uv).rgb;
            if (encodes != 0) {
                color = saturate(color);
                color = select(1.055 * pow(color, float3(1.0 / 2.4)) - 0.055,
                               color * 12.92, color <= 0.0031308);
            }
            return float4(color, 1.0);
        }
        """
}
