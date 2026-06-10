//
//  Ollin Camera — provider, device, and stream sources.
//
//  Object graph: a provider publishes one device, which owns one source-
//  direction stream. While a client is reading, a timer renders frames into an
//  IOSurface-backed pixel buffer and hands them to the stream.
//

import Foundation
import CoreMediaIO
import CoreMedia
import CoreVideo

private let frameWidth = 1280
private let frameHeight = 720
private let frameRate = 30

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

    private var streamingCounter = 0
    private var timer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "dev.ollin.OllinCamera.frames", qos: .userInteractive)

    private var bufferPool: CVPixelBufferPool!
    private var frameIndex: UInt64 = 0

    private let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

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
        do {
            try device.addStream(streamSource.stream)
        } catch {
            fatalError("Unable to add the Ollin Camera stream: \(error)")
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

    // MARK: Streaming lifecycle

    func startStreaming() {
        streamingCounter += 1
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: timerQueue)
        timer.schedule(deadline: .now(), repeating: 1.0 / Double(frameRate), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in self?.emitFrame() }
        timer.resume()
        self.timer = timer
    }

    func stopStreaming() {
        streamingCounter = max(0, streamingCounter - 1)
        if streamingCounter == 0 {
            timer?.cancel()
            timer = nil
        }
    }

    private func emitFrame() {
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, bufferPool, &pixelBuffer) == kCVReturnSuccess,
              let buffer = pixelBuffer else { return }

        render(into: buffer, frame: frameIndex)

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
            let hostTimeNs = mach_absolute_time() * UInt64(timebase.numer) / UInt64(timebase.denom)
            streamSource.stream.send(sampleBuffer, discontinuity: [], hostTimeInNanoseconds: hostTimeNs)
        }
        frameIndex += 1
    }

    /// A cheap, obviously-animated pattern: the background hue cycles while a
    /// white band sweeps top to bottom. Enough to prove our frames are live.
    private func render(into pixelBuffer: CVPixelBuffer, frame: UInt64) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        let t = Double(frame) / Double(frameRate)
        let r = UInt32((sin(t * 0.7) * 0.5 + 0.5) * 255)
        let g = UInt32((sin(t * 0.9 + 2) * 0.5 + 0.5) * 255)
        let b = UInt32((sin(t * 1.3 + 4) * 0.5 + 0.5) * 255)
        // 32BGRA in memory is B,G,R,A; little-endian that packs as A<<24|R<<16|G<<8|B.
        let background: UInt32 = (0xFF << 24) | (r << 16) | (g << 8) | b
        let white: UInt32 = 0xFFFFFFFF

        let bandHeight = height / 8
        let period = UInt64(frameRate * 3)
        let bandY = Int(Double(height) * Double(frame % period) / Double(period))

        for y in 0..<height {
            let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt32.self)
            let value = (y >= bandY && y < bandY + bandHeight) ? white : background
            for x in 0..<width {
                row[x] = value
            }
        }
    }
}

// MARK: - Stream

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
