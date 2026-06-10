//
//  Ollin Camera — provider, device, and stream sources.
//
//  Object graph: a provider publishes one device, which owns two streams — a
//  source stream that camera apps read, and a sink stream a publisher (an Ollin
//  sketch) pushes frames into. Sink frames are forwarded straight to the source
//  stream; while nothing has fed the sink recently, a timer renders the
//  "no signal" test card instead, so the camera always has a picture.
//
//  All mutable device state lives on one serial queue (`frameQueue`): the frame
//  timer fires on it, and the stream-lifecycle callbacks and the sink-consume
//  completions hop onto it.
//

import Foundation
import CoreMediaIO
import CoreMedia
import CoreVideo

private let frameWidth = 1280
private let frameHeight = 720
private let frameRate = 30
/// How long after the last sink frame before the test card takes back over.
private let sinkTimeout: CFAbsoluteTime = 1.0

// MARK: - Provider

final class OllinCameraProviderSource: NSObject, CMIOExtensionProviderSource {

    private(set) var provider: CMIOExtensionProvider!
    private var deviceSource: OllinCameraDeviceSource!

    init(clientQueue: DispatchQueue?) {
        super.init()
        provider = CMIOExtensionProvider(source: self, clientQueue: clientQueue)
        deviceSource = OllinCameraDeviceSource(localizedName: "Ollin Camera")
        do {
            try provider.addDevice(deviceSource.device)
        } catch {
            fatalError("Unable to add the Ollin Camera device: \(error)")
        }
    }

    func connect(to client: CMIOExtensionClient) throws {}

    func disconnect(from client: CMIOExtensionClient) {}

    var availableProperties: Set<CMIOExtensionProperty> {
        [.providerManufacturer]
    }

    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let result = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerManufacturer) {
            result.manufacturer = "Ollin"
        }
        return result
    }

    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {}
}

// MARK: - Device

final class OllinCameraDeviceSource: NSObject, CMIOExtensionDeviceSource {

    private(set) var device: CMIOExtensionDevice!
    private var streamSource: OllinCameraStreamSource!
    private var sinkStreamSource: OllinCameraSinkStreamSource!

    private var streamingCounter = 0
    private var timer: DispatchSourceTimer?
    private let frameQueue = DispatchQueue(label: "dev.ollin.OllinCamera.frames", qos: .userInteractive)

    private var bufferPool: CVPixelBufferPool!
    private var frameIndex: UInt64 = 0
    private let testCard = TestCard(width: frameWidth, height: frameHeight)

    /// Sink state, touched only on `frameQueue`.
    private var sinkClient: CMIOExtensionClient?
    private var sinkActive = false
    private var lastSinkFrameAt: CFAbsoluteTime = 0

    private let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    private var hostTimeNanoseconds: UInt64 {
        mach_absolute_time() * UInt64(timebase.numer) / UInt64(timebase.denom)
    }

    init(localizedName: String) {
        super.init()

        device = CMIOExtensionDevice(localizedName: localizedName, deviceID: UUID(), legacyDeviceID: nil, source: self)

        let bufferAttributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: frameWidth,
            kCVPixelBufferHeightKey as String: frameHeight,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
        ]
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, bufferAttributes as CFDictionary, &bufferPool)

        var seedBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, bufferPool, &seedBuffer)
        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: seedBuffer!, formatDescriptionOut: &formatDescription)

        let format = CMIOExtensionStreamFormat(
            formatDescription: formatDescription!,
            maxFrameDuration: CMTime(value: 1, timescale: Int32(frameRate)),
            minFrameDuration: CMTime(value: 1, timescale: Int32(frameRate)),
            validFrameDurations: nil)

        streamSource = OllinCameraStreamSource(localizedName: "Ollin Camera Stream",
                                               streamID: UUID(),
                                               streamFormat: format,
                                               device: device)
        sinkStreamSource = OllinCameraSinkStreamSource(localizedName: "Ollin Camera Sink",
                                                       streamID: UUID(),
                                                       streamFormat: format,
                                                       device: device)
        do {
            try device.addStream(streamSource.stream)
            try device.addStream(sinkStreamSource.stream)
        } catch {
            fatalError("Unable to add the Ollin Camera streams: \(error)")
        }
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.deviceTransportType, .deviceModel]
    }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let result = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceModel) {
            result.model = "Ollin Camera"
        }
        return result
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {}

    // MARK: Source-stream lifecycle

    func startStreaming() {
        frameQueue.async { [weak self] in
            guard let self else { return }
            self.streamingCounter += 1
            guard self.timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(flags: .strict, queue: self.frameQueue)
            timer.schedule(deadline: .now(), repeating: 1.0 / Double(frameRate), leeway: .milliseconds(2))
            timer.setEventHandler { [weak self] in self?.emitTestCardFrame() }
            timer.resume()
            self.timer = timer
        }
    }

    func stopStreaming() {
        frameQueue.async { [weak self] in
            guard let self else { return }
            self.streamingCounter = max(0, self.streamingCounter - 1)
            if self.streamingCounter == 0 {
                self.timer?.cancel()
                self.timer = nil
            }
        }
    }

    /// One timer tick: render and send a test-card frame — unless a publisher
    /// has fed the sink recently, in which case the live feed owns the stream
    /// and the tick is a no-op.
    private func emitTestCardFrame() {
        guard CFAbsoluteTimeGetCurrent() - lastSinkFrameAt > sinkTimeout else { return }

        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, bufferPool, &pixelBuffer) == kCVReturnSuccess,
              let buffer = pixelBuffer else { return }

        testCard.render(into: buffer, frame: frameIndex, frameRate: frameRate)

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: Int32(frameRate)),
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid)

        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: buffer, formatDescriptionOut: &formatDescription)

        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault,
                                                 imageBuffer: buffer,
                                                 formatDescription: formatDescription!,
                                                 sampleTiming: &timing,
                                                 sampleBufferOut: &sampleBuffer)

        if let sampleBuffer {
            streamSource.stream.send(sampleBuffer, discontinuity: [], hostTimeInNanoseconds: hostTimeNanoseconds)
        }
        frameIndex += 1
    }

    // MARK: Sink-stream lifecycle

    func startSinkStreaming(client: CMIOExtensionClient) {
        frameQueue.async { [weak self] in
            guard let self else { return }
            self.sinkClient = client
            self.sinkActive = true
            self.pumpSinkFrames()
        }
    }

    func stopSinkStreaming() {
        frameQueue.async { [weak self] in
            guard let self else { return }
            self.sinkActive = false
            self.sinkClient = nil
            self.lastSinkFrameAt = 0
        }
    }

    /// Pull the next buffer the publisher enqueued; the completion re-arms the
    /// pump, so frames flow for as long as the sink stream is running.
    private func pumpSinkFrames() {
        guard sinkActive, let client = sinkClient else { return }
        sinkStreamSource.stream.consumeSampleBuffer(from: client) { [weak self] sampleBuffer, sequenceNumber, _, _, error in
            guard let self else { return }
            self.frameQueue.async {
                guard self.sinkActive else { return }
                if let sampleBuffer {
                    self.forwardSinkFrame(sampleBuffer, sequenceNumber: sequenceNumber)
                    self.pumpSinkFrames()
                } else if error != nil {
                    // Don't spin on a failing consume; retry shortly.
                    self.frameQueue.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                        self?.pumpSinkFrames()
                    }
                } else {
                    self.pumpSinkFrames()
                }
            }
        }
    }

    private func forwardSinkFrame(_ sampleBuffer: CMSampleBuffer, sequenceNumber: UInt64) {
        lastSinkFrameAt = CFAbsoluteTimeGetCurrent()
        let hostTime = hostTimeNanoseconds
        if streamingCounter > 0 {
            streamSource.stream.send(sampleBuffer, discontinuity: [], hostTimeInNanoseconds: hostTime)
        }
        sinkStreamSource.stream.notifyScheduledOutputChanged(
            CMIOExtensionScheduledOutput(sequenceNumber: sequenceNumber, hostTimeInNanoseconds: hostTime))
    }
}

// MARK: - Source stream

final class OllinCameraStreamSource: NSObject, CMIOExtensionStreamSource {

    private(set) var stream: CMIOExtensionStream!
    private let _streamFormat: CMIOExtensionStreamFormat
    private weak var device: CMIOExtensionDevice?

    init(localizedName: String, streamID: UUID, streamFormat: CMIOExtensionStreamFormat, device: CMIOExtensionDevice) {
        self._streamFormat = streamFormat
        self.device = device
        super.init()
        stream = CMIOExtensionStream(localizedName: localizedName,
                                     streamID: streamID,
                                     direction: .source,
                                     clockType: .hostTime,
                                     source: self)
    }

    var formats: [CMIOExtensionStreamFormat] {
        [_streamFormat]
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.streamActiveFormatIndex, .streamFrameDuration]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let result = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) {
            result.activeFormatIndex = 0
        }
        if properties.contains(.streamFrameDuration) {
            result.frameDuration = CMTime(value: 1, timescale: Int32(frameRate))
        }
        return result
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {}

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        true
    }

    func startStream() throws {
        (device?.source as? OllinCameraDeviceSource)?.startStreaming()
    }

    func stopStream() throws {
        (device?.source as? OllinCameraDeviceSource)?.stopStreaming()
    }
}

// MARK: - Sink stream

final class OllinCameraSinkStreamSource: NSObject, CMIOExtensionStreamSource {

    private(set) var stream: CMIOExtensionStream!
    private let _streamFormat: CMIOExtensionStreamFormat
    private weak var device: CMIOExtensionDevice?

    /// The publisher whose buffers the device consumes, recorded when it asks
    /// to start the stream.
    private var client: CMIOExtensionClient?

    init(localizedName: String, streamID: UUID, streamFormat: CMIOExtensionStreamFormat, device: CMIOExtensionDevice) {
        self._streamFormat = streamFormat
        self.device = device
        super.init()
        stream = CMIOExtensionStream(localizedName: localizedName,
                                     streamID: streamID,
                                     direction: .sink,
                                     clockType: .hostTime,
                                     source: self)
    }

    var formats: [CMIOExtensionStreamFormat] {
        [_streamFormat]
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.streamActiveFormatIndex, .streamFrameDuration,
         .streamSinkBufferQueueSize, .streamSinkBuffersRequiredForStartup]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let result = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) {
            result.activeFormatIndex = 0
        }
        if properties.contains(.streamFrameDuration) {
            result.frameDuration = CMTime(value: 1, timescale: Int32(frameRate))
        }
        if properties.contains(.streamSinkBufferQueueSize) {
            result.sinkBufferQueueSize = 8
        }
        if properties.contains(.streamSinkBuffersRequiredForStartup) {
            result.sinkBuffersRequiredForStartup = 1
        }
        return result
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {}

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        self.client = client
        return true
    }

    func startStream() throws {
        guard let client else { return }
        (device?.source as? OllinCameraDeviceSource)?.startSinkStreaming(client: client)
    }

    func stopStream() throws {
        client = nil
        (device?.source as? OllinCameraDeviceSource)?.stopSinkStreaming()
    }
}
