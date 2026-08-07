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

        // An exact integer clock at any fps: frame k presents at k·1000/(fps·1000).
        let timescale = Int32((fps * 1000).rounded())

        print("Ollin: exporting \(frames) frames at \(Int(fps)) fps → \(path) (\(size.width)×\(size.height), \(codec.rawValue))")
        let elapsed = renderFrames(sketch, frames: frames, fps: fps, skipSeconds: skipSeconds,
                                   quality: renderQuality) { cgImage, index in
            if index == 0 {
                // Writing starts on the first frame, after the sketch has run
                // `setup()`, so the reproduction recipe can carry the seed it
                // applied there (writer metadata must be set before writing).
                let recipe = ExportMetadata.capture(from: sketch, fps: fps).recipe
                let description = AVMutableMetadataItem()
                description.identifier = .commonIdentifierDescription
                description.value = recipe as NSString
                let software = AVMutableMetadataItem()
                software.identifier = .commonIdentifierSoftware
                software.value = "Ollin" as NSString
                writer.metadata = [description, software]
                // Declared before writing starts, and after `setup()` has run,
                // so an instrument made there is found.
                prepareSoundtrack(for: sketch, writer: writer)
                guard writer.startWriting() else {
                    fatalError("Ollin: the video writer refused to start: "
                               + (writer.error?.localizedDescription ?? "unknown error"))
                }
                writer.startSession(atSourceTime: .zero)
            }
            // Bounded, because a wedged writer never says so: it simply never
            // becomes ready again, and an export that hangs is worse than one
            // that says what went wrong.
            var videoWait = 0
            // The sound that goes with this frame, written before the picture
            // so the audio track never lags the video track. It cannot go any
            // further ahead than this: the notes for the next frame have not
            // been asked for yet.
            pumpSoundtrack(for: sketch, upTo: Double(index + 1) / fps)
            while !input.isReadyForMoreMediaData {
                usleep(1000)
                videoWait += 1
                guard videoWait < 30_000 else {
                    fatalError("Ollin: the video writer stopped taking frames at \(index): "
                               + (writer.error?.localizedDescription ?? "no error reported"))
                }
            }
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
        // The sound the sketch made while those frames were being drawn. A
        // sketch that holds no instrument declared no track, so it writes
        // exactly the file it wrote before.
        finishSoundtrack(for: sketch, seconds: Double(frames) / fps)
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

// MARK: - Sound

extension OllinApp {
    /// Makes room in the file for the sketch's own sound.
    ///
    /// Called once the sketch has run `setup()` and before the writer starts,
    /// because a track has to be declared before anything is written and an
    /// instrument may have been made in `setup()`. Whether there is anything to
    /// play is not known yet: that is decided while the frames are drawn.
    static func prepareSoundtrack(for sketch: Sketch, writer: AVAssetWriter) {
        pendingSoundtrack = nil
        soundtrackSources = sketch.exportAudioSources()
        soundtrackWritten = 0
        guard !soundtrackSources.isEmpty else { return }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: soundtrackSampleRate,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 192_000,
        ]
        guard writer.canApply(outputSettings: settings, forMediaType: .audio) else {
            print("Ollin: this container cannot carry the sketch's sound; writing it silent")
            return
        }
        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: settings)
        // Realtime, deliberately, and not because the data is. A file-paced
        // input is interleaved in chunks of about a second, and the writer
        // holds every other track until the lagging one has delivered its
        // chunk. The sound cannot run a second ahead of the picture, because
        // the notes for those frames have not been asked for yet, so the
        // writer would hold the picture forever, about a second in. A realtime
        // input is exempt from that gating: the writer takes what arrives when
        // it arrives, at the cost of a less tidily interleaved file.
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        pendingSoundtrack = input
    }

    /// Writes the sound the sketch has made so far, up to `seconds`.
    ///
    /// Called after each frame rather than at the end, because a writer will
    /// not let one track run far ahead of another: it stops taking pictures
    /// until the sound catches up, and an export that looks like a hang is what
    /// that turns into. Everything the sketch asked for up to this moment has
    /// already been asked for, so there is always something to render.
    static func pumpSoundtrack(for sketch: Sketch, upTo seconds: Double) {
        guard let input = pendingSoundtrack else { return }
        let samples = sketch.renderSoundtrack(upTo: seconds, sampleRate: soundtrackSampleRate,
                                              sources: soundtrackSources)
        guard !samples.isEmpty else { return }
        append(samples, to: input)
    }

    /// Finishes the track once the last frame is in.
    static func finishSoundtrack(for sketch: Sketch, seconds: Double) {
        guard let input = pendingSoundtrack else { return }
        pumpSoundtrack(for: sketch, upTo: seconds)
        input.markAsFinished()
        pendingSoundtrack = nil
        soundtrackSources = []
    }

    private static func append(_ samples: [Float], to input: AVAssetWriterInput) {
        let sampleRate = soundtrackSampleRate
        // Float pairs, one per frame, exactly as the mixer left them. The
        // encoder is handed uncompressed samples and does the compressing.
        var description = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8,
            mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0
        )
        var format: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, asbd: &description, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format
        ) == noErr, let format else {
            print("Ollin: could not describe the sketch's sound; writing it silent")
            return
        }

        let framesPerBlock = 4096
        let totalFrames = samples.count / 2
        var written = 0
        while written < totalFrames {
            // Bounded, because a writer that has stopped accepting data never
            // says so: it simply never becomes ready again, and an export that
            // hangs is worse than one that says what went wrong.
            var waited = 0
            while !input.isReadyForMoreMediaData, waited < 5000 {
                usleep(1000)
                waited += 1
            }
            guard input.isReadyForMoreMediaData else {
                print("Ollin: the writer stopped taking sound; the picture is unaffected")
                return
            }

            let count = min(framesPerBlock, totalFrames - written)
            let bytes = count * 8
            guard let block = malloc(bytes) else { return }
            samples.withUnsafeBufferPointer { source in
                block.copyMemory(from: source.baseAddress! + written * 2, byteCount: bytes)
            }

            var blockBuffer: CMBlockBuffer?
            guard CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault, memoryBlock: block, blockLength: bytes,
                blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
                offsetToData: 0, dataLength: bytes, flags: 0, blockBufferOut: &blockBuffer
            ) == noErr, let blockBuffer else {
                free(block)
                return
            }

            var timing = CMSampleTimingInfo(
                duration: CMTime(value: 1, timescale: CMTimeScale(sampleRate)),
                presentationTimeStamp: CMTime(value: Int64(soundtrackWritten + written),
                                              timescale: CMTimeScale(sampleRate)),
                decodeTimeStamp: .invalid
            )
            var sampleSize = 8
            var sampleBuffer: CMSampleBuffer?
            guard CMSampleBufferCreate(
                allocator: kCFAllocatorDefault, dataBuffer: blockBuffer, dataReady: true,
                makeDataReadyCallback: nil, refcon: nil, formatDescription: format,
                sampleCount: count, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize,
                sampleBufferOut: &sampleBuffer
            ) == noErr, let sampleBuffer else { return }

            guard input.append(sampleBuffer) else {
                print("Ollin: the encoder refused the sketch's sound; the picture is unaffected")
                return
            }
            written += count
        }
        soundtrackWritten += totalFrames
    }

    static let soundtrackSampleRate = 44100.0

    /// The audio track being filled as the frames go in, what is filling it,
    /// and how far it has got.
    nonisolated(unsafe) private static var pendingSoundtrack: AVAssetWriterInput?
    nonisolated(unsafe) private static var soundtrackSources: [ExportAudioSource] = []
    nonisolated(unsafe) private static var soundtrackWritten = 0
}
