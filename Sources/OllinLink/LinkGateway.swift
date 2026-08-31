import Darwin
import Foundation

/// The per-interface socket bundle. Each interface gets three UDP sockets:
/// the multicast listener bound to the shared well-known port (with address
/// and port reuse, so every participant on the machine can hold it at once),
/// a unicast discovery socket that sends the multicasts and receives the
/// unicast replies, and the measurement socket whose address is what travels
/// in the `mep4` entry. Receive callbacks arrive on the queue handed to
/// `start`, one dispatch read source per socket.
///
/// `@unchecked Sendable` because the mutable pieces (`sources`, `isClosed`)
/// are guarded by ownership, not a lock: a gateway is started once before it
/// is published, and closed exactly once, by whoever removed it from the
/// clock's table under the clock's lock (or by `deinit`, after the last
/// reference). The sockets themselves are safe to send on from any thread.
final class LinkGateway: @unchecked Sendable {

    static let multicastGroup: UInt32 = 0xE04C_4E4B   // 224.76.78.75
    static let port: UInt16 = 20808

    let address: UInt32
    let measurementEndpoint: LinkEndpoint

    private let multicastSocket: Int32
    private let discoverySocket: Int32
    private let measurementSocket: Int32
    private var sources: [DispatchSourceRead] = []
    private var isClosed = false

    struct SocketError: Error {
        let stage: String
        let code: Int32
    }

    var info: LinkGatewayInfo {
        LinkGatewayInfo(address: address, measurementEndpoint: measurementEndpoint)
    }

    // MARK: Setup

    init(address: UInt32) throws {
        self.address = address

        multicastSocket = try Self.openSocket(stage: "multicast")
        do {
            try Self.enableReuse(multicastSocket)
            try Self.bind(multicastSocket, address: 0, port: Self.port, stage: "multicast bind")
            try Self.joinGroup(multicastSocket, interface: address)

            discoverySocket = try Self.openSocket(stage: "discovery")
            do {
                try Self.bind(discoverySocket, address: address, port: 0, stage: "discovery bind")
                try Self.setMulticastInterface(discoverySocket, interface: address)
                // Loopback of our own multicasts is explicit rather than a
                // platform default: it is how several participants on this
                // one machine hear each other.
                try Self.setMulticastLoop(discoverySocket, enabled: true)

                measurementSocket = try Self.openSocket(stage: "measurement")
                do {
                    try Self.bind(measurementSocket, address: address, port: 0, stage: "measurement bind")
                    let port = try Self.localPort(of: measurementSocket)
                    measurementEndpoint = LinkEndpoint(address: address, port: port)
                } catch {
                    Darwin.close(measurementSocket)
                    throw error
                }
            } catch {
                Darwin.close(discoverySocket)
                throw error
            }
        } catch {
            Darwin.close(multicastSocket)
            throw error
        }
    }

    /// Arms the three read sources. `onDiscovery` receives traffic from the
    /// multicast listener and the discovery socket; `onMeasurement` from the
    /// measurement socket.
    func start(
        queue: DispatchQueue,
        onDiscovery: @escaping (Data, LinkEndpoint) -> Void,
        onMeasurement: @escaping (Data, LinkEndpoint) -> Void
    ) {
        sources = [
            Self.readSource(socket: multicastSocket, queue: queue, handler: onDiscovery),
            Self.readSource(socket: discoverySocket, queue: queue, handler: onDiscovery),
            Self.readSource(socket: measurementSocket, queue: queue, handler: onMeasurement),
        ]
        sources.forEach { $0.activate() }
    }

    /// Cancels the read sources and closes the sockets. Safe to call twice.
    func close() {
        guard !isClosed else { return }
        isClosed = true
        let fds = [multicastSocket, discoverySocket, measurementSocket]
        if sources.isEmpty {
            fds.forEach { Darwin.close($0) }
            return
        }
        // Each socket closes in its source's cancel handler, so a read that
        // is mid-flight on the queue never touches a dead descriptor.
        for (source, fd) in zip(sources, fds) {
            source.setCancelHandler { Darwin.close(fd) }
            source.cancel()
        }
        sources.removeAll()
    }

    deinit { close() }

    // MARK: Sending

    func sendMulticast(_ data: Data) {
        send(data, over: discoverySocket, to: LinkEndpoint(address: Self.multicastGroup, port: Self.port))
    }

    func sendDiscovery(_ data: Data, to endpoint: LinkEndpoint) {
        send(data, over: discoverySocket, to: endpoint)
    }

    func sendMeasurement(_ data: Data, to endpoint: LinkEndpoint) {
        send(data, over: measurementSocket, to: endpoint)
    }

    private func send(_ data: Data, over socket: Int32, to endpoint: LinkEndpoint) {
        var target = Self.socketAddress(address: endpoint.address, port: endpoint.port)
        data.withUnsafeBytes { raw in
            withUnsafePointer(to: &target) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                    _ = sendto(socket, raw.baseAddress, raw.count, 0, generic, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    // MARK: Interfaces

    /// Every usable IPv4 interface address, loopback included (it is how two
    /// participants on one machine with no network still find each other).
    static func usableInterfaceAddresses() -> [UInt32] {
        var addresses: Set<UInt32> = []
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return [] }
        defer { freeifaddrs(list) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let flags = Int32(entry.pointee.ifa_flags)
            guard flags & IFF_UP != 0,
                  let sa = entry.pointee.ifa_addr,
                  sa.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            let value = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
            }
            if value != 0 {
                addresses.insert(value)
            }
        }
        return addresses.sorted()
    }

    static let loopbackAddress: UInt32 = 0x7F00_0001   // 127.0.0.1

    // MARK: Socket plumbing

    private static func openSocket(stage: String) throws -> Int32 {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { throw SocketError(stage: stage, code: errno) }
        // Read sources need non-blocking reads: a spurious wakeup must not
        // park the queue in `recvfrom`.
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        return fd
    }

    private static func enableReuse(_ fd: Int32) throws {
        var yes: Int32 = 1
        guard setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size)) == 0,
              setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &yes, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
            throw SocketError(stage: "reuse", code: errno)
        }
    }

    private static func socketAddress(address: UInt32, port: UInt16) -> sockaddr_in {
        var sa = sockaddr_in()
        sa.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        sa.sin_family = sa_family_t(AF_INET)
        sa.sin_port = port.bigEndian
        sa.sin_addr = in_addr(s_addr: address.bigEndian)
        return sa
    }

    private static func bind(_ fd: Int32, address: UInt32, port: UInt16, stage: String) throws {
        var sa = socketAddress(address: address, port: port)
        let result = withUnsafePointer(to: &sa) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                Darwin.bind(fd, generic, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else { throw SocketError(stage: stage, code: errno) }
    }

    private static func joinGroup(_ fd: Int32, interface: UInt32) throws {
        var request = ip_mreq(
            imr_multiaddr: in_addr(s_addr: multicastGroup.bigEndian),
            imr_interface: in_addr(s_addr: interface.bigEndian)
        )
        guard setsockopt(fd, IPPROTO_IP, IP_ADD_MEMBERSHIP, &request, socklen_t(MemoryLayout<ip_mreq>.size)) == 0 else {
            throw SocketError(stage: "membership", code: errno)
        }
    }

    private static func setMulticastInterface(_ fd: Int32, interface: UInt32) throws {
        var addr = in_addr(s_addr: interface.bigEndian)
        guard setsockopt(fd, IPPROTO_IP, IP_MULTICAST_IF, &addr, socklen_t(MemoryLayout<in_addr>.size)) == 0 else {
            throw SocketError(stage: "multicast interface", code: errno)
        }
    }

    private static func setMulticastLoop(_ fd: Int32, enabled: Bool) throws {
        var flag: UInt8 = enabled ? 1 : 0
        guard setsockopt(fd, IPPROTO_IP, IP_MULTICAST_LOOP, &flag, socklen_t(MemoryLayout<UInt8>.size)) == 0 else {
            throw SocketError(stage: "multicast loop", code: errno)
        }
    }

    private static func localPort(of fd: Int32) throws -> UInt16 {
        var sa = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &sa) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                getsockname(fd, generic, &length)
            }
        }
        guard result == 0 else { throw SocketError(stage: "local port", code: errno) }
        return UInt16(bigEndian: sa.sin_port)
    }

    private static func readSource(
        socket fd: Int32,
        queue: DispatchQueue,
        handler: @escaping (Data, LinkEndpoint) -> Void
    ) -> DispatchSourceRead {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler {
            var buffer = [UInt8](repeating: 0, count: 2048)
            // Drain everything ready; the source fires by level, but reading
            // to empty here keeps latency down when packets arrive in bursts.
            while true {
                var sender = sockaddr_in()
                var length = socklen_t(MemoryLayout<sockaddr_in>.size)
                let count = withUnsafeMutablePointer(to: &sender) { pointer in
                    pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                        recvfrom(fd, &buffer, buffer.count, 0, generic, &length)
                    }
                }
                guard count > 0 else { break }
                let source = LinkEndpoint(
                    address: UInt32(bigEndian: sender.sin_addr.s_addr),
                    port: UInt16(bigEndian: sender.sin_port)
                )
                handler(Data(buffer[0..<count]), source)
            }
        }
        return source
    }
}
