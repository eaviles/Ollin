import Foundation
import CoreMedia
import CoreMediaIO

/// Why the virtual camera can't be published to, in user-actionable terms.
public enum VirtualCameraError: Error, CustomStringConvertible {
    /// No camera device with the expected name exists on the system.
    case deviceNotFound(String)
    /// The device exists but has no sink (writable) stream — an old extension build.
    case sinkStreamNotFound(String)
    /// The sink stream wouldn't hand over its transfer queue.
    case queueUnavailable(OSStatus)
    /// The sink stream refused to start.
    case startFailed(OSStatus)

    public var description: String {
        switch self {
        case .deviceNotFound(let name):
            return "\"\(name)\" is not installed — open OllinCamera.app once to install the virtual camera."
        case .sinkStreamNotFound(let name):
            return "\"\(name)\" has no sink stream — update OllinCamera.app to a build that accepts frames."
        case .queueUnavailable(let status):
            return "The virtual camera's sink stream has no transfer queue (error \(status))."
        case .startFailed(let status):
            return "The virtual camera's sink stream wouldn't start (error \(status))."
        }
    }
}

/// A live connection to the virtual camera's **sink stream** — the writable
/// half of the camera device the Ollin Camera extension publishes. Frames
/// enqueued here cross to the extension process (zero-copy, IOSurface-backed)
/// and come out of the camera every webcam app sees.
final class SinkConnection {

    private let deviceID: CMIODeviceID
    private let streamID: CMIOStreamID
    private let queue: CMSimpleQueue

    private init(deviceID: CMIODeviceID, streamID: CMIOStreamID, queue: CMSimpleQueue) {
        self.deviceID = deviceID
        self.streamID = streamID
        self.queue = queue
    }

    deinit {
        CMIODeviceStopStream(deviceID, streamID)
    }

    /// Find the camera device named `name`, locate its sink stream, and start
    /// it. The sink is the device's *output*-direction stream (direction 0,
    /// host-to-device — CoreAudio's perspective); the stream camera apps read
    /// is the input-direction (capture) one. Verified against the live device.
    static func connect(toDeviceNamed name: String) -> Result<SinkConnection, VirtualCameraError> {
        guard let deviceID = systemObjectIDs(selector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices))
            .first(where: { stringProperty(of: $0, selector: CMIOObjectPropertySelector(kCMIOObjectPropertyName)) == name })
        else {
            return .failure(.deviceNotFound(name))
        }

        let streams = objectIDs(of: deviceID, selector: CMIOObjectPropertySelector(kCMIODevicePropertyStreams))
        guard let streamID = streams.first(where: {
            uint32Property(of: $0, selector: CMIOObjectPropertySelector(kCMIOStreamPropertyDirection)) == 0
        }) else {
            return .failure(.sinkStreamNotFound(name))
        }

        var queueOut: Unmanaged<CMSimpleQueue>?
        // The altered proc must be non-nil: with a nil proc the call succeeds
        // but hands back no queue (verified against the live device).
        let copyStatus = CMIOStreamCopyBufferQueue(streamID, { _, _, _ in }, nil, &queueOut)
        guard copyStatus == noErr, let queue = queueOut?.takeRetainedValue() else {
            return .failure(.queueUnavailable(copyStatus))
        }

        let startStatus = CMIODeviceStartStream(deviceID, streamID)
        guard startStatus == noErr else {
            return .failure(.startFailed(startStatus))
        }
        return .success(SinkConnection(deviceID: deviceID, streamID: streamID, queue: queue))
    }

    /// Hand a frame to the extension. Drops the frame (returning `false`) when
    /// the transfer queue is full — the camera runs at its own fixed rate, so a
    /// dropped frame just means the publisher got ahead of it.
    @discardableResult
    func enqueue(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard CMSimpleQueueGetCount(queue) < CMSimpleQueueGetCapacity(queue) else { return false }
        // The queue carries a retain that the receiving end balances.
        let status = CMSimpleQueueEnqueue(queue, element: Unmanaged.passRetained(sampleBuffer).toOpaque())
        if status != noErr {
            Unmanaged.passUnretained(sampleBuffer).release()
            return false
        }
        return true
    }

    // MARK: CMIO property plumbing

    private static func propertyAddress(_ selector: CMIOObjectPropertySelector) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: selector,
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    }

    private static func systemObjectIDs(selector: CMIOObjectPropertySelector) -> [CMIOObjectID] {
        objectIDs(of: CMIOObjectID(kCMIOObjectSystemObject), selector: selector)
    }

    private static func objectIDs(of objectID: CMIOObjectID, selector: CMIOObjectPropertySelector) -> [CMIOObjectID] {
        var address = propertyAddress(selector)
        var dataSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(objectID, &address, 0, nil, &dataSize) == noErr, dataSize > 0 else {
            return []
        }
        let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        var ids = [CMIOObjectID](repeating: 0, count: count)
        var dataUsed: UInt32 = 0
        guard CMIOObjectGetPropertyData(objectID, &address, 0, nil, dataSize, &dataUsed, &ids) == noErr else {
            return []
        }
        return ids
    }

    private static func stringProperty(of objectID: CMIOObjectID, selector: CMIOObjectPropertySelector) -> String? {
        var address = propertyAddress(selector)
        var value: Unmanaged<CFString>?
        var dataUsed: UInt32 = 0
        let size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard CMIOObjectGetPropertyData(objectID, &address, 0, nil, size, &dataUsed, &value) == noErr else {
            return nil
        }
        return value?.takeRetainedValue() as String?
    }

    private static func uint32Property(of objectID: CMIOObjectID, selector: CMIOObjectPropertySelector) -> UInt32? {
        var address = propertyAddress(selector)
        var value: UInt32 = 0
        var dataUsed: UInt32 = 0
        guard CMIOObjectGetPropertyData(objectID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &dataUsed, &value) == noErr else {
            return nil
        }
        return value
    }
}
