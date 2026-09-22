import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// A minimal client for macOS's `usbmuxd` — the daemon that multiplexes TCP
/// connections to USB-attached iOS devices (the same plumbing `libimobiledevice`
/// and Xcode use). It opens the local Unix socket, lists devices, and tunnels a
/// connection to a TCP port the device is listening on.
///
/// This is the standard, publicly-documented usbmuxd plist protocol — wholly
/// independent of any RGBD or sensor library; only the *port* it connects to (and
/// the frame format read from it) belongs to the streaming app. Shared (via the
/// `package`-level surface) by `OllinRecord3D` (Record3D's RGBD stream on 1337)
/// and `OllinPhone` (the Ollin capture app's sensor stream on 1338).
///
/// The protocol: each message is a 16-byte little-endian header
/// (`length`, `version` = 1, `type` = 8 for plist, `tag`) followed by an XML
/// property-list body. `ListDevices` returns the attached devices; `Connect`
/// (with the target port in **network byte order**) turns the socket into a
/// transparent pipe to that port on success.
package enum USBMux {

    /// The macOS usbmuxd Unix-domain socket.
    static let socketPath = "/var/run/usbmuxd"

    /// One attached device, as reported by `ListDevices`.
    package struct DeviceInfo: Sendable {
        package let deviceID: Int
        package let serialNumber: String
        package let connectionType: String
    }

    package enum USBMuxError: Error, CustomStringConvertible {
        case socketUnavailable
        case noDevice
        case handshakeFailed
        /// usbmuxd's `Connect` returned a non-zero result. `3` is "connection
        /// refused" — the device is reachable but nothing is listening on the port.
        case connectFailed(Int)

        package var description: String {
            switch self {
            case .socketUnavailable: return "Could not reach usbmuxd at \(USBMux.socketPath)"
            case .noDevice: return "No USB device attached"
            case .handshakeFailed: return "usbmuxd handshake failed"
            case .connectFailed(let n):
                return n == 3 ? "Device refused the connection (nothing listening on that port)"
                              : "usbmuxd Connect failed (result \(n))"
            }
        }
    }

    // The fields every usbmuxd request carries.
    private static var baseRequest: [String: Any] {
        ["ClientVersionString": "Ollin", "ProgName": "Ollin", "kLibUSBMuxVersion": 3]
    }

    /// List the devices usbmuxd currently sees.
    package static func listDevices() throws -> [DeviceInfo] {
        let fd = try openSocket()
        defer { close(fd) }
        var request = baseRequest
        request["MessageType"] = "ListDevices"
        try send(fd, request)
        guard let reply = recv(fd), reply["DeviceList"] != nil else {
            throw USBMuxError.handshakeFailed
        }
        return devices(in: reply)
    }

    /// The devices a `ListDevices` reply names. An entry with no numeric
    /// `DeviceID` is skipped; a missing property reads as an empty string.
    package static func devices(in reply: [String: Any]) -> [DeviceInfo] {
        guard let list = reply["DeviceList"] as? [[String: Any]] else { return [] }
        return list.compactMap { entry in
            guard let id = entry["DeviceID"] as? Int else { return nil }
            let props = entry["Properties"] as? [String: Any] ?? [:]
            return DeviceInfo(deviceID: id,
                              serialNumber: props["SerialNumber"] as? String ?? "",
                              connectionType: props["ConnectionType"] as? String ?? "")
        }
    }

    /// Open a transparent connection to `port` on the first USB-attached device.
    ///
    /// On success the returned file descriptor is a raw pipe to the device's TCP
    /// port — read and write it directly. The caller owns it and must `close` it.
    /// Throws `.noDevice` when nothing is attached and `.connectFailed(3)` when the
    /// device is reachable but no server is listening on `port`.
    package static func connect(toPort port: UInt16) throws -> Int32 {
        let devices = try listDevices()
        // Prefer a USB device; fall back to whatever is attached.
        guard let device = devices.first(where: { $0.connectionType == "USB" }) ?? devices.first else {
            throw USBMuxError.noDevice
        }
        let fd = try openSocket()
        var request = baseRequest
        request["MessageType"] = "Connect"
        request["DeviceID"] = device.deviceID
        // usbmuxd wants the port in network byte order.
        request["PortNumber"] = Int((port << 8) | (port >> 8))
        try send(fd, request)
        guard let reply = recv(fd), let number = reply["Number"] as? Int else {
            close(fd)
            throw USBMuxError.handshakeFailed
        }
        guard number == 0 else {
            close(fd)
            throw USBMuxError.connectFailed(number)
        }
        return fd
    }

    // MARK: - Socket + framing

    private static func openSocket() throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw USBMuxError.socketUnavailable }
        // A write to a phone that has just gone (the cable pulled, the app
        // closed) must fail the write rather than raise SIGPIPE, whose default
        // is to end the whole process: the sketch, not only the connection.
        var noSignal: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        withUnsafeMutablePointer(to: &addr.sun_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: capacity) { dst in
                _ = socketPath.withCString { strcpy(dst, $0) }
            }
        }
        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, length)
            }
        }
        guard result == 0 else {
            close(fd)
            throw USBMuxError.socketUnavailable
        }
        return fd
    }

    private static func send(_ fd: Int32, _ dict: [String: Any]) throws {
        let payload = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        var header = Data()
        func appendU32(_ value: UInt32) {
            var le = value.littleEndian
            withUnsafeBytes(of: &le) { header.append(contentsOf: $0) }
        }
        appendU32(UInt32(16 + payload.count))   // total length
        appendU32(1)                             // protocol version (plist)
        appendU32(8)                             // message type (plist)
        appendU32(1)                             // tag (echoed back; one round trip)
        writeFully(fd, header + payload)
    }

    private static func recv(_ fd: Int32) -> [String: Any]? {
        guard let length = replyBodyLength(header: readFully(fd, 16)) else { return nil }
        return reply(body: readFully(fd, length))
    }

    /// The most a reply body is allowed to claim. A device list is a few
    /// hundred bytes; a header announcing more than this is a desynchronized
    /// stream, and refusing it is what keeps a bad length from steering a
    /// huge read.
    package static let maxReplyBytes = 16 << 20

    /// The body length a 16-byte reply header announces, or `nil` when the
    /// header is short, claims less than its own size, or claims more than
    /// `maxReplyBytes`.
    package static func replyBodyLength(header: Data) -> Int? {
        guard header.count == 16 else { return nil }
        let total = header.withUnsafeBytes { raw -> UInt32 in
            var value: UInt32 = 0
            for i in 0..<4 { value |= UInt32(raw[i]) << (8 * i) }
            return value
        }
        guard total >= 16, Int(total) - 16 <= maxReplyBytes else { return nil }
        return Int(total) - 16
    }

    /// A reply body read as the dictionary usbmuxd sends, or `nil` when the
    /// bytes are not a property list holding one.
    package static func reply(body: Data) -> [String: Any]? {
        (try? PropertyListSerialization.propertyList(from: body, format: nil)) as? [String: Any]
    }

    // MARK: - Low-level read/write

    /// Read exactly `count` bytes (or fewer if the connection ends or times out).
    package static func readFully(_ fd: Int32, _ count: Int) -> Data {
        var out = Data()
        out.reserveCapacity(count)
        var buffer = [UInt8](repeating: 0, count: min(count, 65536))
        while out.count < count {
            let want = min(buffer.count, count - out.count)
            let got = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress, want) }
            if got <= 0 { break }
            out.append(contentsOf: buffer[0..<got])
        }
        return out
    }

    /// Write every byte of `data`, reporting whether all of them went. A short
    /// write means the connection is gone or the send timed out, which is what
    /// tells a caller to drop it rather than keep writing into a dead socket.
    @discardableResult
    package static func writeFully(_ fd: Int32, _ data: Data) -> Bool {
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Bool in
            guard let base = raw.baseAddress else { return data.isEmpty }
            var offset = 0
            while offset < data.count {
                let written = write(fd, base.advanced(by: offset), data.count - offset)
                if written <= 0 { return false }
                offset += written
            }
            return true
        }
    }
}
