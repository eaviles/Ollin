import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The codec a video export encodes with.
///
/// `h264` is the share-anywhere default: every player, browser, and chat app
/// decodes it. `hevc` is noticeably better quality per byte (a good first
/// switch when a file needs to be smaller) at a small compatibility cost on
/// old players. The two ProRes profiles are mastering codecs — visually
/// lossless and an order of magnitude larger, meant for an edit timeline or a
/// later re-encode, not for posting — and they require a `.mov` container.
public enum VideoCodec: String, CaseIterable, Sendable {
    case h264
    case hevc
    case prores422
    case prores4444

    var avCodec: AVVideoCodecType {
        switch self {
        case .h264: .h264
        case .hevc: .hevc
        case .prores422: .proRes422
        case .prores4444: .proRes4444
        }
    }

    /// ProRes only fits the QuickTime container; H.264/HEVC fit `.mp4` too.
    var requiresQuickTime: Bool {
        switch self {
        case .prores422, .prores4444: true
        case .h264, .hevc: false
        }
    }
}

public extension OllinApp {

    /// Render `sketch` headlessly and encode it straight to a video file — one
    /// command from an animated sketch to something you can post. Same
    /// deterministic fixed-timestep drive as `exportSequence` (a slow render
    /// still plays back smooth at `fps`), with the encoding folded in so no
    /// external tool is needed.
    ///
    /// The container comes from the path's extension (`.mp4`/`.m4v` or `.mov`).
    /// `bitsPerSecond` sets the average bitrate — the file-size dial: a 1080²
    /// clip looks clean around 10–15 Mbps in `h264` and ~60% of that in `hevc`;
    /// omit it for the encoder's own (generous) default. `quality` (0…1) is
    /// constant-quality rate control instead of a bitrate — supported by the
    /// Apple-silicon hardware encoder only, so on an Intel Mac use
    /// `bitsPerSecond`. ProRes takes neither (it's effectively a fixed,
    /// very high rate).
    ///
    /// `skipSeconds` runs the sketch that long before capture starts, so a
    /// stateful sketch settles into motion first. For a *reproducible* clip,
    /// seed the sketch (`seed(…)` in `setup()`).
    static func exportVideo(_ sketch: Sketch, to path: String,
                            frames: Int, fps: Double = 60,
                            codec: VideoCodec = .h264,
                            bitsPerSecond: Int? = nil,
                            quality: Double? = nil,
                            renderQuality: RenderQuality = .detail,
                            skipSeconds: Double = 0) {
        guard frames > 0 else { return }

        let fileType: AVFileType
        switch (path as NSString).pathExtension.lowercased() {
        case "mov": fileType = .mov
        case "mp4", "m4v":
            guard !codec.requiresQuickTime else {
                fatalError("Ollin: \(codec.rawValue) needs a QuickTime container — use a .mov path")
            }
            fileType = .mp4
        case let ext:
            fatalError("Ollin: unsupported video extension '.\(ext)' — use .mp4, .m4v, or .mov")
        }

        var quality = quality
        if quality != nil {
            #if arch(arm64)
            if bitsPerSecond != nil {
                print("Ollin: quality and bitrate are alternative rate controls; using quality")
            }
            #else
            fatalError("Ollin: constant-quality encoding needs the Apple-silicon video encoder — set a bitrate instead on this Mac")
            #endif
        }
        if codec.requiresQuickTime, bitsPerSecond != nil || quality != nil {
            print("Ollin: ProRes sets its own rate; ignoring bitrate/quality")
            quality = nil
        }

        let url = URL(fileURLWithPath: path)
        try? FileManager.default.removeItem(at: url)
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: fileType)
        } catch {
            fatalError("Ollin: failed to create the video writer for \(path): \(error)")
        }

        let size = sketch.canvasSize
        var settings: [String: Any] = [
            AVVideoCodecKey: codec.avCodec,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
            // The canvas is sRGB-encoded; tag the track Rec. 709 (the video
            // convention for those bytes) so players show it as rendered.
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
        ]
        if !codec.requiresQuickTime {
            var compression: [String: Any] = [AVVideoExpectedSourceFrameRateKey: fps]
            if let quality {
                compression[AVVideoQualityKey] = quality
            } else if let bitsPerSecond {
                compression[AVVideoAverageBitRateKey] = bitsPerSecond
            }
            settings[AVVideoCompressionPropertiesKey] = compression
        }

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size.width,
            kCVPixelBufferHeightKey as String: size.height,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        // An exact integer clock at any fps: frame k presents at k·1000/(fps·1000).
        let timescale = Int32((fps * 1000).rounded())

        print("Ollin: exporting \(frames) frames at \(Int(fps)) fps → \(path) (\(size.width)×\(size.height), \(codec.rawValue))")
        let elapsed = renderFrames(sketch, frames: frames, fps: fps, skipSeconds: skipSeconds,
                                   quality: renderQuality) { cgImage, index in
            while !input.isReadyForMoreMediaData { usleep(1000) }
            guard let pool = adaptor.pixelBufferPool else {
                fatalError("Ollin: video encoder rejected the settings: \(writer.error?.localizedDescription ?? "unknown error")")
            }
            var pixelBuffer: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            guard let buffer = pixelBuffer else {
                fatalError("Ollin: failed to allocate a frame buffer")
            }
            CVPixelBufferLockBaseAddress(buffer, [])
            if let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                                       width: size.width, height: size.height,
                                       bitsPerComponent: 8,
                                       bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                       bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                           | CGBitmapInfo.byteOrder32Little.rawValue) {
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
            }
            CVPixelBufferUnlockBaseAddress(buffer, [])
            let time = CMTime(value: Int64(index) * 1000, timescale: timescale)
            if !adaptor.append(buffer, withPresentationTime: time) {
                fatalError("Ollin: failed to encode frame \(index): \(writer.error?.localizedDescription ?? "unknown error")")
            }
        }

        input.markAsFinished()
        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting { finished.signal() }
        finished.wait()
        guard writer.status == .completed else {
            fatalError("Ollin: failed to finish \(path): \(writer.error?.localizedDescription ?? "unknown error")")
        }
        print(String(format: "Ollin: exported %d frames in %.1fs → %@ (%.1f MB)",
                     frames, elapsed, path, fileSizeMB(of: path)))
    }

    /// Render `sketch` headlessly and write an animated GIF that loops forever.
    /// The right framing is short loops at modest sizes: GIF is palette-limited
    /// (256 colors) and heavy per second next to video, so for anything long or
    /// subtle, `exportVideo` is the better tool. `width` downscales the output
    /// (height follows the canvas aspect); the canvas size is used as-is when
    /// omitted.
    ///
    /// GIF stores each frame's delay in whole centiseconds, so the achievable
    /// rates are 50, 33.3, 25, 20, … fps. The requested `fps` is quantized to
    /// the closest achievable rate and the sketch's fixed timestep runs at
    /// *that* rate, so motion plays back at true speed and the clip keeps its
    /// requested duration (the frame count is rescaled to match).
    static func exportGIF(_ sketch: Sketch, to path: String,
                          frames: Int, fps: Double = 25,
                          width targetWidth: Int? = nil,
                          skipSeconds: Double = 0,
                          renderQuality: RenderQuality = .detail) {
        guard frames > 0 else { return }

        let delay = Double(max(2, Int((100 / fps).rounded()))) / 100   // decoders clamp delays under 2cs
        let effectiveFPS = 1 / delay
        let effectiveFrames = max(1, Int((Double(frames) / fps * effectiveFPS).rounded()))
        if abs(effectiveFPS - fps) > 0.01 {
            print(String(format: "Ollin: GIF delays are whole centiseconds — rendering at %.3g fps (closest to %g)",
                         effectiveFPS, fps))
        }

        let size = sketch.canvasSize
        let outWidth = targetWidth ?? size.width
        let outHeight = max(1, Int((Double(size.height) * Double(outWidth) / Double(size.width)).rounded()))

        let url = URL(fileURLWithPath: path)
        try? FileManager.default.removeItem(at: url)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.gif.identifier as CFString,
                                                                effectiveFrames, nil) else {
            fatalError("Ollin: failed to create the GIF writer for \(path)")
        }
        CGImageDestinationSetProperties(destination, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],   // 0 = loop forever
        ] as CFDictionary)
        let frameProperties = [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFDelayTime: delay,
                kCGImagePropertyGIFUnclampedDelayTime: delay,
            ],
        ] as CFDictionary

        print("Ollin: exporting \(effectiveFrames) frames at \(Int(effectiveFPS.rounded())) fps → \(path) (\(outWidth)×\(outHeight), gif)")
        let elapsed = renderFrames(sketch, frames: effectiveFrames, fps: effectiveFPS,
                                   skipSeconds: skipSeconds, quality: renderQuality) { cgImage, index in
            var frame = cgImage
            if outWidth != size.width {
                guard let context = CGContext(data: nil, width: outWidth, height: outHeight,
                                              bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                              bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                                  | CGBitmapInfo.byteOrder32Little.rawValue) else {
                    fatalError("Ollin: failed to downscale frame \(index)")
                }
                context.interpolationQuality = .high
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: outWidth, height: outHeight))
                guard let scaled = context.makeImage() else {
                    fatalError("Ollin: failed to downscale frame \(index)")
                }
                frame = scaled
            }
            CGImageDestinationAddImage(destination, frame, frameProperties)
        }

        guard CGImageDestinationFinalize(destination) else {
            fatalError("Ollin: failed to finish \(path)")
        }
        print(String(format: "Ollin: exported %d frames in %.1fs → %@ (%.1f MB)",
                     effectiveFrames, elapsed, path, fileSizeMB(of: path)))
    }

    private static func fileSizeMB(of path: String) -> Double {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return Double(attributes?[.size] as? Int ?? 0) / 1_000_000
    }
}
