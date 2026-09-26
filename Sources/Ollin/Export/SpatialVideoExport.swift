import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import QuartzCore
import VideoToolbox

public extension OllinApp {

    /// Render `sketch` headlessly as **spatial video**: a stereo pair per frame,
    /// muxed into the multi-layer HEVC file Apple's platforms play with depth.
    ///
    /// It is the moving counterpart of writing a scene out as a model. That sends
    /// the geometry and lets a viewer walk around it; this sends the motion, seen
    /// from two eyes at once, which is the only way an animation reads as
    /// three-dimensional in a headset.
    ///
    /// ```sh
    /// swift run Example-3D-Geometry-Solids --export-spatial piece.mov --seconds 6
    /// ```
    ///
    /// The frame is drawn **once** and rendered twice, from two cameras a little
    /// way apart, so a sketch whose randomness or simulations would run
    /// differently on a second pass still gives the two eyes the same world. How
    /// far apart and how far away they agree come from `stereo`, and both default
    /// to being read off the sketch's own camera (see `StereoGeometry`).
    ///
    /// `metersPerUnit` says how big one world unit is, the same declaration the
    /// model exporter takes. A player reads it as the distance between the eyes
    /// that made the shot, and scales the depth it shows accordingly, so a scene
    /// drawn in meters wants the default of 1 and a scene drawn in canvas-sized
    /// numbers wants something much smaller.
    ///
    /// The container should be `.mov`, which is what every spatial video on Apple
    /// platforms is; `.mp4` also carries it. Sound the sketch makes rides along,
    /// exactly as it does in an ordinary video export.
    ///
    /// Throws `ExportError` when the clip cannot be made, as `exportVideo`
    /// does, and when this Mac's encoder cannot write stereo video at all. A
    /// file stopped partway is removed.
    static func exportSpatialVideo(_ sketch: Sketch, to path: String,
                                   frames: Int, fps: FrameRate = 30,
                                   stereo: StereoGeometry? = nil,
                                   metersPerUnit: Double = 1,
                                   bitsPerSecond: Int? = nil,
                                   quality: Double? = nil,
                                   renderQuality: RenderQuality = .detail,
                                   skipSeconds: Double = 0) throws {
        guard frames > 0 else {
            throw ExportError(.unsupported, path: path,
                              problem: "asks for \(frames) frames, and a clip needs at least one")
        }
        let rate = fps
        let fps = rate.framesPerSecond
        guard VTIsStereoMVHEVCEncodeSupported() else {
            throw ExportError(.unsupported, path: path,
                              problem: "this Mac's video encoder cannot write spatial video (stereo MV-HEVC)")
        }

        let fileType: AVFileType
        switch (path as NSString).pathExtension.lowercased() {
        case "mov": fileType = .mov
        case "mp4", "m4v": fileType = .mp4
        case let ext:
            throw ExportError(.unsupported, path: path,
                              problem: "'.\(ext)' is not a spatial-video extension; use .mov")
        }
        #if !arch(arm64)
        if quality != nil {
            throw ExportError(.unsupported, path: path,
                              problem: "constant-quality encoding needs the Apple-silicon video encoder; set a bitrate instead on this Mac")
        }
        #endif

        let url = URL(fileURLWithPath: path)
        try? FileManager.default.removeItem(at: url)
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: fileType)
        } catch {
            throw ExportError(.unwritable, path: path,
                              problem: "the spatial-video writer could not be made: \(error.localizedDescription)")
        }

        let size = sketch.canvasSizeForRun()
        // Either number given here overrides the sketch's own declaration on its
        // own, so naming just a convergence distance leaves a declared eye spacing
        // alone rather than quietly dropping it back to the derived one.
        var geometry = sketch.stereoGeometry
        if let stereo {
            if let interocular = stereo.interocular { geometry.interocular = interocular }
            if let convergence = stereo.convergence { geometry.convergence = convergence }
        }
        var receiver: AVAssetWriterInput.TaggedPixelBufferGroupReceiver?
        var input: AVAssetWriterInput?
        // An exact integer clock at any rate: frame k presents at k·tick/timescale,
        // on the fraction the rate is (k·1001/30000 for NTSC, k·1000/30000 for 30).
        let (timescale, tick) = rate.mediaClock

        print("Ollin: exporting \(frames) spatial frames at \(Int(fps)) fps → \(path) "
              + "(\(size.width)×\(size.height), stereo hevc)")

        var isComplete = false
        defer { if !isComplete { abandon(writer, at: url) } }
        let elapsed = try renderStereoFrames(sketch, frames: frames, fps: fps, skipSeconds: skipSeconds,
                                             geometry: geometry, quality: renderQuality,
                                             for: path) { pair, index in
            if index == 0 {
                // Everything about the shot is known only once the sketch has drawn
                // its first frame, because the camera is set in `draw()`: how wide
                // the lens is, how far apart the eyes ended up. The writer takes its
                // settings before it starts, so it is built here rather than above.
                let baseline = pair.interocular * metersPerUnit
                let settings = spatialVideoSettings(width: size.width, height: size.height,
                                                    fieldOfView: pair.fieldOfView,
                                                    baselineMeters: baseline,
                                                    fps: fps, bitsPerSecond: bitsPerSecond,
                                                    quality: quality)
                let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
                // The track keeps the rate's own clock, so a fractional rate's
                // frames land on its fraction rather than the writer's default.
                videoInput.mediaTimeScale = timescale
                // Realtime, deliberately, and not because the data is. A
                // file-paced input is interleaved in chunks of about a second,
                // and a multi-layer one stops accepting frames at the end of the
                // first chunk and never becomes ready again: measured at exactly
                // frame 36 of a 30 fps export, with the writer still reporting
                // itself as writing and no error to read. A realtime input is
                // exempt from that pacing, and the only thing it costs is a less
                // tidily interleaved file, which for one video track is nothing.
                // The soundtrack input is realtime for its own version of the
                // same reason.
                videoInput.expectsMediaDataInRealTime = true
                var attributes = CVPixelBufferCreationAttributes(
                    pixelFormatType: CVPixelFormatType(rawValue: kCVPixelFormatType_32BGRA),
                    size: CVImageSize(width: size.width, height: size.height))
                // The encoder reads the two eyes straight out of shared memory, so
                // the buffers have to be surface-backed rather than plain malloc.
                attributes.backing = .ioSurface
                writer.add(videoInput)
                receiver = writer.inputTaggedPixelBufferGroupReceiver(for: videoInput,
                                                                     pixelBufferAttributes: attributes)
                input = videoInput

                let recipe = ExportMetadata.capture(from: sketch, fps: fps).recipe
                let description = AVMutableMetadataItem()
                description.identifier = .commonIdentifierDescription
                description.value = recipe as NSString
                let software = AVMutableMetadataItem()
                software.identifier = .commonIdentifierSoftware
                software.value = "Ollin" as NSString
                writer.metadata = [description, software]
                prepareSoundtrack(for: sketch, writer: writer)
                guard writer.startWriting() else {
                    throw ExportError(.unwritable, path: path, frame: 0,
                                      problem: "the spatial-video writer would not start: "
                                          + (writer.error?.localizedDescription ?? "no reason given"))
                }
                writer.startSession(atSourceTime: .zero)
            }
            guard let receiver, let input else { return }

            // The sound for this frame goes first, so the audio track never lags the
            // picture; see the note on the ordinary video export for why that matters.
            pumpSoundtrack(for: sketch, upTo: Double(index + 1) / fps)
            // Bounded, because a wedged writer never says so: it simply never
            // becomes ready again, and an export that hangs is worse than one
            // that explains itself.
            var waited = 0
            while !input.isReadyForMoreMediaData {
                usleep(1000)
                waited += 1
                guard waited < 30_000 else {
                    throw ExportError(.unwritable, path: path, frame: index,
                                      problem: "the spatial-video writer stopped taking frames at frame \(index): "
                                          + (writer.error?.localizedDescription ?? "no reason given"))
                }
            }

            guard let pool = receiver.pixelBufferPool else {
                throw ExportError(.unwritable, path: path, frame: index,
                                  problem: "the spatial-video encoder refused the settings: "
                                      + (writer.error?.localizedDescription ?? "no reason given"))
            }
            // Layer 0 is the left eye and layer 1 the right, in that order,
            // because that is what the settings above declared; the encoder
            // checks the two against each other and refuses a mismatch.
            let eyes = [(image: pair.left, tag: CMTag.stereoView(.leftEye)),
                        (image: pair.right, tag: CMTag.stereoView(.rightEye))]
            let buffers = try eyes.enumerated().map { layer, eye in
                CMTaggedDynamicBuffer(tags: [.videoLayerID(Int64(layer)), eye.tag],
                                      content: try readOnlyBuffer(of: eye.image, from: pool, size: size, path: path))
            }
            let time = CMTime(value: Int64(index) * tick, timescale: timescale)
            do {
                guard try receiver.appendImmediately(buffers, with: time) else {
                    throw ExportError(.unwritable, path: path, frame: index,
                                      problem: "the encoder refused spatial frame \(index): "
                                          + (writer.error?.localizedDescription ?? "no reason given"))
                }
            } catch let error as ExportError {
                throw error
            } catch {
                throw ExportError(.unwritable, path: path, frame: index,
                                  problem: "the encoder refused spatial frame \(index): \(error.localizedDescription)")
            }
        }

        receiver?.finish()
        input?.markAsFinished()
        finishSoundtrack(for: sketch, seconds: Double(frames) / fps)
        let finished = DispatchSemaphore(value: 0)
        writer.finishWriting { finished.signal() }
        finished.wait()
        guard writer.status == .completed else {
            throw ExportError(.unwritable, path: path, problem: "the file could not be finished: "
                              + (writer.error?.localizedDescription ?? "no reason given"))
        }
        isComplete = true
        let megabytes = Double((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? Int ?? 0) / 1_000_000
        print(String(format: "Ollin: exported %d spatial frames in %.1fs → %@ (%.1f MB)",
                     frames, elapsed, path, megabytes))
    }

    /// One rendered eye copied into a surface-backed buffer the encoder can read.
    private static func readOnlyBuffer(of image: CGImage, from pool: CVMutablePixelBuffer.Pool,
                                       size: CanvasSize, path: String) throws -> CVReadOnlyPixelBuffer {
        guard let buffer = try? pool.makeMutablePixelBuffer() else {
            throw ExportError(.unwritable, path: path, problem: "no buffer could be made for a spatial frame")
        }
        buffer.withUnsafeBuffer { raw in
            CVPixelBufferLockBaseAddress(raw, [])
            if let context = CGContext(data: CVPixelBufferGetBaseAddress(raw),
                                       width: size.width, height: size.height,
                                       bitsPerComponent: 8,
                                       bytesPerRow: CVPixelBufferGetBytesPerRow(raw),
                                       space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                       bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                           | CGBitmapInfo.byteOrder32Little.rawValue) {
                context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
            }
            CVPixelBufferUnlockBaseAddress(raw, [])
        }
        return CVReadOnlyPixelBuffer(buffer)
    }

    /// The encoder settings for a stereo pair, and the five numbers that make the
    /// result read as *spatial* rather than merely as a video with two layers.
    ///
    /// Layer 0 is the left eye and layer 1 the right, which is what the tags on
    /// each frame have to agree with. The view IDs are spelled out three times
    /// over because the encoder wants the list, the mapping, and which two of them
    /// are the eyes, and naming the middle one without the last is the one
    /// combination that hangs the encoder rather than refusing.
    ///
    /// The spatial half is the field of view (in thousandths of a degree), the
    /// distance between the eyes (in millionths of a meter), the disparity
    /// adjustment, and the two flags saying both eyes are here. A file missing any
    /// of those five still plays, and still plays in stereo, but the system will
    /// not call it spatial. The disparity adjustment is zero because the
    /// convergence is already in the pictures: the eyes were aimed when the frame
    /// was drawn, rather than left parallel for a player to slide together later.
    private static func spatialVideoSettings(width: Int, height: Int,
                                             fieldOfView: Double, baselineMeters: Double,
                                             fps: Double, bitsPerSecond: Int?,
                                             quality: Double?) -> [String: Any] {
        let degrees = fieldOfView * 180 / .pi
        if degrees > 90 {
            print("Ollin: a field of view over 90 degrees is wider than spatial video is meant to "
                  + "carry, so the depth may read oddly; narrow the camera for the export")
        }
        var compression: [String: Any] = [
            kVTCompressionPropertyKey_MVHEVCVideoLayerIDs as String: [0, 1],
            kVTCompressionPropertyKey_MVHEVCViewIDs as String: [0, 1],
            kVTCompressionPropertyKey_MVHEVCLeftAndRightViewIDs as String: [0, 1],
            kVTCompressionPropertyKey_HasLeftStereoEyeView as String: true,
            kVTCompressionPropertyKey_HasRightStereoEyeView as String: true,
            kVTCompressionPropertyKey_HorizontalFieldOfView as String:
                UInt32(max(0, min(180_000, (degrees * 1000).rounded()))),
            kVTCompressionPropertyKey_StereoCameraBaseline as String:
                UInt32(max(0, min(Double(UInt32.max), (baselineMeters * 1_000_000).rounded()))),
            kVTCompressionPropertyKey_HorizontalDisparityAdjustment as String: Int32(0),
            kVTCompressionPropertyKey_HeroEye as String: kCMFormatDescriptionHeroEye_Left as String,
            AVVideoExpectedSourceFrameRateKey: fps,
        ]
        if let quality {
            compression[AVVideoQualityKey] = quality
        } else if let bitsPerSecond {
            compression[AVVideoAverageBitRateKey] = bitsPerSecond
        }
        return [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            // The canvas is sRGB-encoded; tag the track Rec. 709, the video
            // convention for those bytes, so players show it as rendered.
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: compression,
        ]
    }
}

// MARK: - The stereo drive

extension OllinApp {

    /// One frame of a stereo pair, and the shot it was taken with.
    struct StereoFrame {
        var left: CGImage
        var right: CGImage
        /// The distance between the eyes and the angle the shot frames, both in the
        /// sketch's own units, for the file's spatial metadata.
        var interocular: Double
        var fieldOfView: Double
    }

    /// Drive `sketch` headlessly at a fixed timestep and hand each frame's stereo
    /// pair to `write`, the twin of `renderFrames` for two eyes.
    ///
    /// The one difference that matters is the reason this exists: each frame is
    /// **drawn once and rendered twice**. Drawing twice would advance the sketch
    /// twice, and the simulations that are honest about not reproducing frame for
    /// frame would hand the eyes two different worlds. Rendering twice is free of
    /// that: the renderer already knows a second pass over one drawn frame must
    /// not step anything again, because the live frame grab does exactly that.
    static func renderStereoFrames(_ sketch: Sketch, frames: Int, fps: Double,
                                   skipSeconds: Double, geometry: StereoGeometry,
                                   quality: RenderQuality = .detail,
                                   for path: String = "",
                                   write: (StereoFrame, Int) throws -> Void) throws -> Double {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ExportError(.unrendered, path: path, problem: "no Metal device to draw with")
        }
        let renderer: MetalRenderer
        do {
            renderer = try MetalRenderer(device: device, pixelFormat: ollinColorPixelFormat,
                                         sampleCount: ollinPreferredSampleCount(device))
        } catch {
            throw ExportError(.unrendered, path: path, problem: "the renderer would not start: \(error)")
        }
        renderer.automaticQuality = quality
        renderer.renderScale = OllinApp.exportRenderScale
        isRenderingHeadless = true
        defer { isRenderingHeadless = false }

        let size = sketch.canvasSizeForRun()
        let width = size.width, height = size.height
        let aspect = height > 0 ? Double(width) / Double(height) : 1
        let viewport = SIMD2<Float>(Float(width), Float(height))
        sketch.setCanvasSize(width: Double(width), height: Double(height))
        sketch.runSetup()

        // Each eye measures its own motion against where that same eye was last
        // frame. Measured against the other one, the gap between the eyes would
        // read as the whole world lurching sideways every frame.
        var previous: (left: Camera3D, right: Camera3D)?
        let skipFrames = max(0, Int((skipSeconds * fps).rounded()))
        let wallStart = CACurrentMediaTime()

        for k in 0 ..< (skipFrames + frames) {
            // Both eyes' readbacks, and everything the frame drew, are done with at
            // the end of the iteration; this drive never reaches a run loop that
            // would drain them, so a long clip would otherwise hold every frame.
            try autoreleasepool {
                sketch.advance(time: Double(k) / fps, deltaTime: 1 / fps, frameRate: fps)
                sketch.performDraw()
                let unrendered = ExportError(.unrendered, path: path, frame: max(0, k - skipFrames),
                                             problem: "frame \(max(0, k - skipFrames)) did not come back from the GPU")

                let accumulates = sketch.drawer.accumulates
                let center = sketch.drawer.camera3D
                let pair = center?.stereoPair(geometry, aspect: aspect)
                let resolved = center.map { geometry.resolved(for: $0, aspect: aspect) }

                // A persistent picture renders through the warmup, as in the
                // flat export's loop (`renderFrames`).
                var frame: StereoFrame?
                if accumulates || sketch.drawer.usesFeedback || k >= skipFrames {
                    if accumulates {
                        // The pile lives in one persistent surface, and there is only one
                        // of it, so both eyes are handed the same picture and the piece
                        // reads flat. Rendering it twice would deposit the frame twice.
                        sketch.drawer.noteOnce(
                            "Ollin: this sketch accumulates onto one surface, so its spatial video "
                            + "shows the same picture to both eyes and will read flat")
                        guard let image = renderer.accumulatedImage(of: sketch.drawer, viewport: viewport,
                                                                    width: width, height: height) else {
                            throw unrendered
                        }
                        let convergence = resolved?.convergence ?? 1
                        frame = StereoFrame(left: image, right: image, interocular: 0,
                                            fieldOfView: center?.horizontalFieldOfView(
                                                aspect: aspect, convergence: convergence) ?? .pi / 3)
                    } else if let pair, let resolved {
                        sketch.drawer.aimStereoEye(pair.left, previous: previous?.left)
                        guard let left = renderer.image(of: sketch.drawer, viewport: viewport,
                                                        width: width, height: height) else {
                            throw unrendered
                        }
                        sketch.drawer.aimStereoEye(pair.right, previous: previous?.right)
                        guard let right = renderer.image(of: sketch.drawer, viewport: viewport,
                                                         width: width, height: height) else {
                            throw unrendered
                        }
                        frame = StereoFrame(left: left, right: right,
                                            interocular: resolved.interocular,
                                            fieldOfView: pair.left.horizontalFieldOfView(
                                                aspect: aspect, convergence: resolved.convergence))
                    } else {
                        sketch.drawer.noteOnce(
                            "Ollin: this sketch sets no 3D camera, so its spatial video shows the same "
                            + "picture to both eyes and will read flat")
                        guard let image = renderer.image(of: sketch.drawer, viewport: viewport,
                                                         width: width, height: height) else {
                            throw unrendered
                        }
                        frame = StereoFrame(left: image, right: image, interocular: 0, fieldOfView: .pi / 3)
                    }
                } else {
                    // A warmup frame nobody keeps: still stepped, so a stateful sim
                    // evolves into the first frame that is.
                    renderer.stepCompute(sketch.drawer)
                }
                previous = pair

                if k < skipFrames {
                    FileHandle.standardError.write(Data(
                        String(format: "\r  warming up %d/%d    ", k + 1, skipFrames).utf8))
                    return                            // the pool is the iteration, so leaving it is `continue`
                }
                guard let frame else { throw unrendered }
                let done = k - skipFrames + 1
                try write(frame, done - 1)

                let elapsed = CACurrentMediaTime() - wallStart
                let renderFPS = elapsed > 0 ? Double(done) / elapsed : 0
                let line = String(format: "\r  rendering %d/%d (%d%%) · %.0f fps    ",
                                  done, frames, done * 100 / frames, renderFPS)
                FileHandle.standardError.write(Data(line.utf8))
            }
        }
        FileHandle.standardError.write(Data("\n".utf8))
        return CACurrentMediaTime() - wallStart
    }
}
