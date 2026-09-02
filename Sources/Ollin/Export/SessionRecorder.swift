import AVFoundation

/// Records a live run as it happens: the frames as they are rendered, the
/// sound as it is played, written straight into a movie file in real time.
///
/// The offline exporters re-render on a fixed clock, which is exactly wrong
/// for an improvised run: the input, the parameters, and the sound happen once, in
/// real time. This records that once. Start it and stop it from the sketch
/// (`startRecording()` / `stopRecording()`), from a host's record control, or
/// hold the recorder yourself and drive it directly.
///
/// It is a `SketchExtension`: while recording it asks for each rendered frame
/// (paying the off-screen grab only then) and stamps it with the wall clock,
/// so a slow frame simply lasts longer in the file instead of stretching time.
/// Sound is found the way the offline exporters find it, by looking at what
/// the sketch is holding, and each source's output is placed on the same wall
/// clock, so sound and picture stay together even when a device hiccups.
///
/// In the live hosts a recording survives an evaluation: the runner carries
/// the recorder across the swap and it picks up the new sketch's instruments.
/// The one thing it cannot survive is the canvas changing size mid-file; it
/// finishes the file cleanly and says so.
@MainActor
public final class SessionRecorder: SketchExtension {

    /// What the recording listens to.
    public enum Audio: Sendable {
        /// The sound the sketch itself plays. No permission needed.
        case sketch
        /// The room, through the default input device. Asks for microphone
        /// permission the first time.
        case microphone
        /// Both at once, mixed.
        case sketchAndMicrophone
        /// Picture only.
        case none
    }

    /// What the recording listens to. Settable between recordings.
    public var audio: Audio
    /// The codec frames are encoded with. Settable between recordings.
    public var codec: VideoCodec

    /// Whether a recording is running right now.
    public private(set) var isRecording = false
    /// Where the current (or last) recording is being written.
    public private(set) var url: URL?
    /// Seconds since the recording started.
    public var elapsed: Double { isRecording ? hostNow() - startSeconds : 0 }

    public init(audio: Audio = .sketch, codec: VideoCodec = .h264) {
        self.audio = audio
        self.codec = codec
    }

    // MARK: Starting and stopping

    /// Starts recording. With no destination, the file lands in
    /// `~/Movies/Ollin/` named after the sketch and the moment.
    ///
    /// The recorder has to know its sketch first: reach it through
    /// `startRecording()` on the sketch, or `extend(_:)` it and start after
    /// `setup()` has run.
    public func start(to path: String? = nil) {
        start(to: path.map { URL(fileURLWithPath: $0) })
    }

    func start(to destination: URL?) {
        guard !isRecording else { return }
        guard !OllinApp.isRenderingHeadless else {
            print("Ollin: a live recording needs the live window; use --export-video for an offline render")
            return
        }
        guard let sketch else {
            print("Ollin: the recorder has no sketch yet; call startRecording() on the sketch, or extend(_:) it first")
            return
        }
        guard sketch.colorOutput != .extended else {
            print("Ollin: live recording writes standard or wide color for now; use --export-video for HDR")
            return
        }
        let url = destination ?? SessionRecorder.defaultDestination(for: sketch)
        let size = sketch.canvasSize
        let begins = hostNow()
        guard let writer = RecorderWriter(url: url, width: size.width, height: size.height,
                                          codec: codec, output: sketch.colorOutput,
                                          withSound: audio != .none, startSeconds: begins) else { return }
        self.url = url
        self.writer = writer
        self.startSeconds = begins
        self.droppedFrames = 0
        self.rescanCountdown = 0
        isRecording = true
        writerQueue.async { [writerQueue] in writer.begin(on: writerQueue) }
        if audio == .sketch || audio == .sketchAndMicrophone { rescanAudioSources(of: sketch) }
        if audio == .microphone || audio == .sketchAndMicrophone { startMicrophone() }
        catchStops()
        print("Ollin: recording to \(url.path)")
    }

    /// Stops recording and finishes the file. The completion runs on the main
    /// thread with the file's location, or `nil` when writing failed.
    public func stop(completion: (@MainActor (URL?) -> Void)? = nil) {
        guard isRecording, let writer else { return }
        isRecording = false
        endAudioCapture()
        let finishedAt = hostNow()
        let dropped = droppedFrames
        let began = startSeconds
        writerQueue.async { [weak self] in
            writer.finish(at: finishedAt) { finished, frames, failure in
                Task { @MainActor in
                    guard let self else { return }
                    let url = self.url
                    self.writer = nil
                    if finished, let url {
                        var line = String(format: "Ollin: recorded %.1fs to %@ (%d frames",
                                          finishedAt - began, url.path, frames)
                        line += dropped > 0 ? ", \(dropped) dropped)" : ")"
                        print(line)
                        completion?(url)
                    } else {
                        print("Ollin: the recording could not be finished"
                              + (failure.map { ": \($0)" } ?? ""))
                        completion?(nil)
                    }
                }
            }
        }
    }

    /// Stops and blocks until the file is finished, bounded. For the ways a
    /// process ends that cannot wait for a callback: quitting the app,
    /// Control-C in the terminal.
    public func stopAndWait() {
        guard isRecording, let writer else { return }
        isRecording = false
        endAudioCapture()
        let finishedAt = hostNow()
        let done = DispatchSemaphore(value: 0)
        writerQueue.async {
            writer.finish(at: finishedAt) { _, _, _ in done.signal() }
        }
        _ = done.wait(timeout: .now() + 10)
        self.writer = nil
        if let url { print("Ollin: recording saved to \(url.path)") }
    }

    // MARK: The extension hooks

    public func setup(_ sketch: Sketch) {
        self.sketch = sketch
        // Claim the sketch's recorder slot, so `isRecording` and the runner's
        // reload carry see this recorder however it was attached.
        if sketch.sessionRecorder == nil { sketch.sessionRecorder = self }
        guard isRecording, let writer else { return }
        // A swapped-in sketch with a different canvas cannot continue this
        // file: a movie's frames are all one size. Finish cleanly, say so.
        if sketch.canvasSize.width != writer.width || sketch.canvasSize.height != writer.height {
            print("Ollin: the canvas changed size, so the recording was finished")
            stop()
            return
        }
        if audio == .sketch || audio == .sketchAndMicrophone { rescanAudioSources(of: sketch) }
    }

    public var wantsRenderedFrame: Bool { isRecording }

    public func frameRendered(_ sketch: Sketch, image: CGImage) {
        guard isRecording, let writer else { return }
        guard image.width == writer.width, image.height == writer.height else {
            print("Ollin: the canvas changed size, so the recording was finished")
            stop()
            return
        }
        // Instruments can be made mid-run, so look again now and then.
        rescanCountdown -= 1
        if rescanCountdown <= 0 {
            rescanCountdown = 60
            if audio == .sketch || audio == .sketchAndMicrophone { rescanAudioSources(of: sketch) }
        }
        let seconds = hostNow() - startSeconds
        guard writer.videoInput.isReadyForMoreMediaData else {
            // Real time cannot wait for the encoder; a frame it cannot take
            // now is a frame the file goes without.
            droppedFrames += 1
            return
        }
        let grab = FrameGrab(image: image, seconds: seconds)
        writerQueue.async { writer.append(grab) }
    }

    // MARK: Finding the sketch's sound

    /// Matches the recorder's lanes to the sound sources the sketch is holding
    /// right now: new sources get a lane, departed ones lose theirs.
    private func rescanAudioSources(of sketch: Sketch) {
        guard let writer else { return }
        let found = sketch.captureAudioSources()
        let foundIDs = Set(found.map { ObjectIdentifier($0) })
        for (id, source, _) in lanes where !foundIDs.contains(id) {
            source.endAudioCapture()
        }
        lanes.removeAll { !foundIDs.contains($0.id) }
        let known = Set(lanes.map(\.id))
        for source in found where !known.contains(ObjectIdentifier(source)) {
            let sink = AudioCaptureSink(sampleRate: RecorderWriter.audioSampleRate,
                                        startHostSeconds: startSeconds)
            source.beginAudioCapture(into: sink)
            lanes.append((ObjectIdentifier(source), source, sink))
        }
        let sinks = lanes.map(\.sink) + (microphoneSink.map { [$0] } ?? [])
        writerQueue.async { writer.sinks = sinks }
    }

    private func endAudioCapture() {
        for (_, source, _) in lanes { source.endAudioCapture() }
        lanes.removeAll()
        stopMicrophone()
    }

    // MARK: The microphone

    private func startMicrophone() {
        // Touching the input device before permission is granted is what trips
        // the system, so it waits for the grant; until then the recording
        // simply carries no room sound.
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            startMicrophoneEngine()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                guard granted else { return }
                Task { @MainActor in
                    guard self.isRecording else { return }
                    self.startMicrophoneEngine()
                }
            }
        default:
            print("Ollin: microphone permission is denied, so the recording carries no room sound")
        }
    }

    private func startMicrophoneEngine() {
        guard microphoneEngine == nil, let writer else { return }
        let engine = AVAudioEngine()
        let sink = AudioCaptureSink(sampleRate: RecorderWriter.audioSampleRate,
                                    startHostSeconds: startSeconds)
        installCaptureTap(on: engine.inputNode, sink: sink)
        engine.prepare()
        do {
            try engine.start()
        } catch {
            print("Ollin: the microphone could not be started: \(error.localizedDescription)")
            return
        }
        microphoneEngine = engine
        microphoneSink = sink
        let sinks = lanes.map(\.sink) + [sink]
        writerQueue.async { writer.sinks = sinks }
    }

    private func stopMicrophone() {
        guard let engine = microphoneEngine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        microphoneEngine = nil
        microphoneSink = nil
    }

    // MARK: Ending with the process

    /// A recording stopped by Control-C or a kill must still be a playable
    /// file: an unfinished movie is an unreadable one. The default action dies
    /// before anything can be written down, so it is replaced once, kept for
    /// the life of the process, and finishes whatever is recording on the way
    /// out.
    private func catchStops() {
        guard SessionRecorder.signalSources.isEmpty else { return }
        for number in [SIGTERM, SIGINT] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated {
                    self?.stopAndWait()
                    exit(number == SIGINT ? 130 : 143)
                }
            }
            source.resume()
            SessionRecorder.signalSources.append(source)
        }
    }

    // MARK: Plumbing

    private weak var sketch: Sketch?
    private var writer: RecorderWriter?
    private var startSeconds: Double = 0
    private var droppedFrames = 0
    private var rescanCountdown = 0
    private var lanes: [(id: ObjectIdentifier, source: CaptureAudioSource, sink: AudioCaptureSink)] = []
    private var microphoneEngine: AVAudioEngine?
    private var microphoneSink: AudioCaptureSink?
    private let writerQueue = DispatchQueue(label: "ollin.session-recorder")
    private static var signalSources: [DispatchSourceSignal] = []

    static func defaultDestination(for sketch: Sketch) -> URL {
        // The home directory is read by name on a sandboxed platform, where the
        // property is not offered and the path is the container's own.
        let home = URL(fileURLWithPath: NSHomeDirectory())
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? home.appendingPathComponent("Movies")
        let folder = movies.appendingPathComponent("Ollin", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let name = "\(String(describing: type(of: sketch))) \(stamp.string(from: Date())).mov"
        return folder.appendingPathComponent(name)
    }
}

/// The host clock in seconds, the one timeline sound and picture share.
private func hostNow() -> Double {
    AVAudioTime.seconds(forHostTime: mach_absolute_time())
}

/// A rendered frame on its way to the encoder. The image is immutable, so
/// carrying it across to the writer queue is safe; the annotation says so.
private struct FrameGrab: @unchecked Sendable {
    let image: CGImage
    let seconds: Double
}

/// The microphone tap. A free function on purpose: the closure runs on the
/// audio thread, and one formed inside a main-actor method would carry an
/// executor assertion that traps the moment that thread invokes it.
private func installCaptureTap(on node: AVAudioNode, sink: AudioCaptureSink) {
    node.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, time in
        sink.take(buffer, at: time)
    }
}

// MARK: - The writer

/// Everything that touches the file. Confined to the recorder's writer queue
/// after `init`; the annotation states the discipline rather than a free-for-all.
private final class RecorderWriter: @unchecked Sendable {
    static let audioSampleRate = 48_000.0
    /// How far the sound mix stays behind the clock, so a buffer still in
    /// flight on some audio thread makes it into its slot before the slot is
    /// written down.
    static let mixDelay = 0.15

    let width: Int
    let height: Int
    let startSeconds: Double
    let videoInput: AVAssetWriterInput
    var sinks: [AudioCaptureSink] = []
    var failureReason: String?

    private let writer: AVAssetWriter
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let audioInput: AVAssetWriterInput?
    private let output: ColorOutput
    private var audioFormat: CMAudioFormatDescription?
    private var audioCursor: Int64 = 0
    private var mixScratch: [Float] = []
    private var drainTimer: DispatchSourceTimer?
    private var framesWritten = 0
    private var started = false

    init?(url: URL, width: Int, height: Int, codec: VideoCodec, output: ColorOutput,
          withSound: Bool, startSeconds: Double) {
        let kind: AVFileType
        switch url.pathExtension.lowercased() {
        case "mp4", "m4v":
            guard !codec.requiresQuickTime else {
                print("Ollin: \(codec.rawValue) needs a QuickTime container; use a .mov path")
                return nil
            }
            kind = .mp4
        default:
            kind = .mov
        }
        try? FileManager.default.removeItem(at: url)
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: kind)
        } catch {
            print("Ollin: could not create the recording at \(url.path): \(error.localizedDescription)")
            return nil
        }
        self.width = width
        self.height = height
        self.output = output
        self.startSeconds = startSeconds

        // The same track tagging the offline exporter writes: sRGB frames are
        // tagged as the video convention for those bytes, wide ones as P3-D65.
        let colorProperties: [String: Any] = output == .wide
            ? [AVVideoColorPrimariesKey: AVVideoColorPrimaries_P3_D65,
               AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
               AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]
            : [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
               AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
               AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]
        var settings: [String: Any] = [
            AVVideoCodecKey: codec.avCodec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoColorPropertiesKey: colorProperties,
        ]
        if !codec.requiresQuickTime {
            settings[AVVideoCompressionPropertiesKey] = [AVVideoExpectedSourceFrameRateKey: 60]
        }
        videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        videoInput.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ])
        writer.add(videoInput)

        if withSound {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: RecorderWriter.audioSampleRate,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000,
            ]
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            input.expectsMediaDataInRealTime = true
            writer.add(input)
            audioInput = input
        } else {
            audioInput = nil
        }

        let software = AVMutableMetadataItem()
        software.identifier = .commonIdentifierSoftware
        software.value = "Ollin" as NSString
        writer.metadata = [software]
    }

    /// Opens the session. First thing on the writer queue, which is also the
    /// queue everything after it runs on: the sound beat has to share the
    /// video appends' queue, or the two would race the writer.
    func begin(on queue: DispatchQueue) {
        guard writer.startWriting() else {
            failureReason = writer.error?.localizedDescription ?? "the writer refused to start"
            print("Ollin: the recording could not start: \(failureReason!)")
            return
        }
        writer.startSession(atSourceTime: .zero)
        started = true
        guard audioInput != nil else { return }
        var description = AudioStreamBasicDescription(
            mSampleRate: RecorderWriter.audioSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8,
            mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0
        )
        CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault, asbd: &description, layoutSize: 0, layout: nil,
            magicCookieSize: 0, magicCookie: nil, extensions: nil,
            formatDescriptionOut: &audioFormat)
        // Sound is written on a slow beat rather than per buffer: the lanes
        // absorb the audio threads' arrivals, and every so often the region
        // every lane has had time to fill is mixed and written down.
        let timer = DispatchSource.makeTimerSource(queue: queue)
        drainTimer = timer
        timer.setEventHandler { [weak self] in self?.drainAudio() }
        timer.schedule(deadline: .now() + 0.1, repeating: 0.1)
        timer.resume()
    }

    /// Encodes one grabbed frame. On the writer queue.
    func append(_ grab: FrameGrab) {
        guard started, writer.status == .writing, videoInput.isReadyForMoreMediaData,
              let pool = adaptor.pixelBufferPool else { return }
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard let buffer = pixelBuffer else { return }
        // A wide-gamut frame is drawn into a Display P3 buffer, so the colors
        // it named outside sRGB survive the trip.
        let space = output == .wide
            ? CGColorSpace(name: CGColorSpace.displayP3)! : CGColorSpace(name: CGColorSpace.sRGB)!
        CVPixelBufferLockBaseAddress(buffer, [])
        if let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer),
                                   width: width, height: height,
                                   bitsPerComponent: 8,
                                   bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                   space: space,
                                   bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                                       | CGBitmapInfo.byteOrder32Little.rawValue) {
            context.draw(grab.image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        let time = CMTime(value: Int64(grab.seconds * 1_000_000), timescale: 1_000_000)
        if adaptor.append(buffer, withPresentationTime: time) {
            framesWritten += 1
        } else {
            failureReason = writer.error?.localizedDescription
        }
    }

    /// Mixes and writes the sound every lane has had time to deliver.
    /// Returns whether it advanced, so the final drain can loop to the end.
    @discardableResult
    private func drainAudio(upTo limitSeconds: Double? = nil) -> Bool {
        guard started, writer.status == .writing, let input = audioInput,
              let format = audioFormat else { return false }
        let now = limitSeconds ?? (AVAudioTime.seconds(forHostTime: mach_absolute_time())
                                   - startSeconds - RecorderWriter.mixDelay)
        let target = Int64(now * RecorderWriter.audioSampleRate)
        var frames = Int(target - audioCursor)
        guard frames > 0 else { return false }
        // A stalled queue must not build an unbounded block; catch up in slices.
        frames = min(frames, Int(RecorderWriter.audioSampleRate) * 2)
        if mixScratch.count < frames * 2 { mixScratch = [Float](repeating: 0, count: frames * 2) }
        for i in 0..<(frames * 2) { mixScratch[i] = 0 }
        for sink in sinks { sink.mix(into: &mixScratch, from: audioCursor, frames: frames) }
        // Several instruments at once must not clip where one would not; over
        // the knee the sum is bent rather than cut, meeting the straight part
        // at the same slope. The same rule the offline mix uses.
        for i in 0..<(frames * 2) where abs(mixScratch[i]) > 0.7 {
            let sign: Float = mixScratch[i] < 0 ? -1 : 1
            let over = (abs(mixScratch[i]) - 0.7) / 0.3
            mixScratch[i] = sign * (0.7 + 0.3 * Float(tanh(Double(over))))
        }
        guard input.isReadyForMoreMediaData else { return false }

        let bytes = frames * 8
        guard let block = malloc(bytes) else { return false }
        mixScratch.withUnsafeBufferPointer { source in
            block.copyMemory(from: source.baseAddress!, byteCount: bytes)
        }
        var blockBuffer: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault, memoryBlock: block, blockLength: bytes,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil,
            offsetToData: 0, dataLength: bytes, flags: 0, blockBufferOut: &blockBuffer
        ) == noErr, let blockBuffer else {
            free(block)
            return false
        }
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: CMTimeScale(RecorderWriter.audioSampleRate)),
            presentationTimeStamp: CMTime(value: audioCursor,
                                          timescale: CMTimeScale(RecorderWriter.audioSampleRate)),
            decodeTimeStamp: .invalid)
        var sampleSize = 8
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreate(
            allocator: kCFAllocatorDefault, dataBuffer: blockBuffer, dataReady: true,
            makeDataReadyCallback: nil, refcon: nil, formatDescription: format,
            sampleCount: frames, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        ) == noErr, let sampleBuffer else { return false }
        guard input.append(sampleBuffer) else { return false }
        audioCursor += Int64(frames)
        return true
    }

    /// Final drain, close both tracks, finish the file. On the writer queue.
    func finish(at endHostSeconds: Double,
                completion: @escaping @Sendable (Bool, Int, String?) -> Void) {
        drainTimer?.cancel()
        drainTimer = nil
        guard started, writer.status == .writing else {
            completion(false, framesWritten, failureReason)
            return
        }
        // Written in slices, so the last one is looped to the actual end.
        while drainAudio(upTo: endHostSeconds - startSeconds) {}
        videoInput.markAsFinished()
        audioInput?.markAsFinished()
        let frames = framesWritten
        let handoff = WriterHandoff(writer)
        writer.finishWriting {
            let writer = handoff.value
            completion(writer.status == .completed, frames,
                       writer.error?.localizedDescription)
        }
    }
}

/// Carries the writer into its own completion handler, where reading its final
/// status is the documented thing to do; the checker just cannot see that.
private struct WriterHandoff: @unchecked Sendable {
    let value: AVAssetWriter
    init(_ value: AVAssetWriter) { self.value = value }
}

// MARK: - The sketch's side

public extension Sketch {
    /// Starts recording this run: the frames as rendered, the sound as played,
    /// written in real time. With no destination the file lands in
    /// `~/Movies/Ollin/`, named after the sketch and the moment.
    ///
    /// The offline exporters (`--export-video`) are the way to a reproducible,
    /// fixed-clock render; this is the way to keep an improvised one.
    func startRecording(to path: String? = nil, audio: SessionRecorder.Audio = .sketch) {
        if sessionRecorder == nil {
            let recorder = SessionRecorder(audio: audio)
            extend(recorder)
            // The lazy extension pass may not have run yet, and starting needs
            // the recorder to know its sketch now.
            recorder.setup(self)
        }
        guard let recorder = sessionRecorder, !recorder.isRecording else { return }
        recorder.audio = audio
        recorder.start(to: path)
    }

    /// Stops the recording and finishes the file. Safe to call when nothing
    /// is recording. The completion runs on the main thread with the file's
    /// location, or `nil` when writing failed.
    func stopRecording(completion: (@MainActor (URL?) -> Void)? = nil) {
        sessionRecorder?.stop(completion: completion)
    }

    /// Whether a live recording is running right now.
    var isRecording: Bool { sessionRecorder?.isRecording ?? false }

    /// Seconds since the live recording started, for a host's elapsed readout.
    var recordingElapsed: Double { sessionRecorder?.elapsed ?? 0 }

    /// The sound sources this sketch is holding, for the live recorder. Found
    /// by looking at the sketch's own stored properties, the same way the
    /// offline exporters find theirs.
    internal func captureAudioSources() -> [CaptureAudioSource] {
        var found: [CaptureAudioSource] = []
        var mirror: Mirror? = Mirror(reflecting: self)
        while let current = mirror {
            for child in current.children {
                if let source = child.value as? CaptureAudioSource { found.append(source) }
            }
            mirror = current.superclassMirror
        }
        return found
    }
}
