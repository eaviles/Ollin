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
/// compressor writes HEVC in real time with no reordering, so a picture goes out
/// the moment it is made rather than waiting on a later one.
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

    // The compressor and its size are made, used, and replaced on the thread that
    // calls `encode` (the main thread, live), which is what `@unchecked Sendable`
    // asserts. Only the count of pictures in flight is also written by the
    // compressor's thread, so only it sits behind the lock.
    private var session: VTCompressionSession?
    private var pool: CVPixelBufferPool?
    private var width = 0
    private var height = 0
    private var failedSize: (width: Int, height: Int)?
    private var frameIndex: Int64 = 0
    private let pending = OSAllocatedUnfairLock(initialState: 0)

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

    deinit {
        if let session { VTCompressionSessionInvalidate(session) }
    }

    /// How many pictures have been handed to the compressor and not come back.
    var inFlight: Int { pending.withLock { $0 } }

    /// The size a canvas of `width` by `height` pixels is sent at: fitted under
    /// `maxSide` with its proportion kept, and rounded down to even numbers,
    /// since the codec samples its color at half size.
    static func pictureSize(width: Int, height: Int, maxSide: Int) -> (width: Int, height: Int) {
        guard width > 0, height > 0 else { return (0, 0) }
        let scale = min(1, Double(maxSide) / Double(max(width, height)))
        func even(_ value: Double) -> Int { max(2, Int(value) & ~1) }
        return (even(Double(width) * scale), even(Double(height) * scale))
    }

    /// The bit rate a picture size runs at: about an eighth of a bit for every
    /// pixel of every frame, which keeps a hairline and a grain of noise intact
    /// on a screen held a hand away, and inside what the cable carries.
    static func bitRate(width: Int, height: Int, framesPerSecond: Double) -> Int {
        let rate = Double(width * height) * framesPerSecond * 0.125
        return Int(min(max(rate, 4_000_000), 40_000_000))
    }

    /// Copy `texture` into a pixel buffer and hand it to the compressor.
    ///
    /// Returns `false` when nothing was submitted: no compressor could be made,
    /// or the copy failed. `forceKeyframe` asks for a picture that stands alone,
    /// which the phone needs after it connects or comes back to Sketch mode.
    @discardableResult
    func encode(_ texture: MTLTexture, forceKeyframe: Bool) -> Bool {
        let size = Self.pictureSize(width: texture.width, height: texture.height, maxSide: maxSide)
        guard size.width > 0, let (session, pool) = sessionFitting(size) else { return false }
        guard let pixelBuffer = copy(texture, into: pool, width: size.width, height: size.height)
        else { return false }

        let index = frameIndex
        frameIndex += 1
        pending.withLock { $0 += 1 }
        let scale = Int32(max(1, (framesPerSecond * 1000).rounded()))
        let time = CMTime(value: index * 1000, timescale: scale)
        let duration = CMTime(value: 1000, timescale: scale)
        let properties: CFDictionary? = forceKeyframe
            ? [kVTEncodeFrameOptionKey_ForceKeyFrame: kCFBooleanTrue] as CFDictionary : nil

        let deliver = onPicture
        let pending = pending
        let status = VTCompressionSessionEncodeFrame(
            session, imageBuffer: pixelBuffer, presentationTimeStamp: time, duration: duration,
            frameProperties: properties, infoFlagsOut: nil
        ) { status, _, sampleBuffer in
            // Read the picture before the count drops, so a caller that waits for
            // nothing in flight has the picture in hand by then.
            let picture = status == noErr ? sampleBuffer.flatMap(PhonePicture.init(sampleBuffer:)) : nil
            if let picture { deliver(picture) }
            pending.withLock { $0 = max(0, $0 - 1) }
        }
        if status != noErr {
            pending.withLock { $0 = max(0, $0 - 1) }
            return false
        }
        return true
    }

    /// Wait for every submitted picture to come back. The tests use it; the live
    /// path never waits on the compressor.
    func finish() {
        if let session {
            VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        }
    }

    // MARK: The compressor

    /// The session for this picture size, made on first use and made again when
    /// the canvas changes size. A new session starts on a keyframe by itself.
    private func sessionFitting(_ size: (width: Int, height: Int))
        -> (VTCompressionSession, CVPixelBufferPool)? {
        if let session, let pool, width == size.width, height == size.height {
            return (session, pool)
        }
        // A size the machine could not compress once is not asked for every frame.
        if let failedSize, failedSize == size { return nil }

        if let old = session {
            VTCompressionSessionCompleteFrames(old, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(old)
        }
        session = nil
        pool = nil

        guard let made = makeSession(width: size.width, height: size.height),
              let madePool = VTCompressionSessionGetPixelBufferPool(made) else {
            failedSize = size
            return nil
        }
        session = made
        pool = madePool
        width = size.width
        height = size.height
        failedSize = nil
        return (made, madePool)
    }

    private func makeSession(width: Int, height: Int) -> VTCompressionSession? {
        let sourceAttributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [CFString: Any](),
            kCVPixelBufferMetalCompatibilityKey: true,
        ]
        // Low-latency rate control where the machine has it, the plain real-time
        // compressor where it does not.
        let specifications: [[CFString: Any]] = [
            [kVTVideoEncoderSpecification_EnableLowLatencyRateControl: true],
            [:],
        ]
        for specification in specifications {
            var made: VTCompressionSession?
            let status = VTCompressionSessionCreate(
                allocator: kCFAllocatorDefault, width: Int32(width), height: Int32(height),
                codecType: kCMVideoCodecType_HEVC,
                encoderSpecification: specification.isEmpty ? nil : specification as CFDictionary,
                imageBufferAttributes: sourceAttributes as CFDictionary,
                compressedDataAllocator: nil, outputCallback: nil, refcon: nil,
                compressionSessionOut: &made)
            guard status == noErr, let session = made else { continue }
            configure(session, width: width, height: height)
            VTCompressionSessionPrepareToEncodeFrames(session)
            return session
        }
        return nil
    }

    private func configure(_ session: VTCompressionSession, width: Int, height: Int) {
        func set(_ key: CFString, _ value: Any) {
            VTSessionSetProperty(session, key: key, value: value as CFTypeRef)
        }
        set(kVTCompressionPropertyKey_RealTime, kCFBooleanTrue!)
        set(kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse!)
        set(kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_HEVC_Main_AutoLevel)
        set(kVTCompressionPropertyKey_ExpectedFrameRate, framesPerSecond as NSNumber)
        set(kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, 1.0 as NSNumber)
        set(kVTCompressionPropertyKey_MaxKeyFrameInterval,
            Int(framesPerSecond.rounded()) as NSNumber)
        set(kVTCompressionPropertyKey_AverageBitRate,
            Self.bitRate(width: width, height: height, framesPerSecond: framesPerSecond) as NSNumber)
        // The canvas is sRGB, and saying so is what lets the phone show it as drawn.
        set(kVTCompressionPropertyKey_ColorPrimaries, kCVImageBufferColorPrimaries_ITU_R_709_2)
        set(kVTCompressionPropertyKey_TransferFunction, kCVImageBufferTransferFunction_sRGB)
        set(kVTCompressionPropertyKey_YCbCrMatrix, kCVImageBufferYCbCrMatrix_ITU_R_709_2)
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
