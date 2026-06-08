import Foundation
import Network

/// Sends OSC messages and bundles to a host over UDP. Create one in `setup()`
/// pointing at the destination, then `send` from `draw()`.
///
/// ```swift
/// let osc = OSCSender(host: "127.0.0.1", port: 9000)
/// override func draw() {
///     osc.send("/cursor", .float(Float(mouseX / width)), .float(Float(mouseY / height)))
/// }
/// ```
///
/// Literals build arguments directly (`send("/light", 0.8, 1, "on")`); a value in
/// a variable is wrapped by its case (`.float(x)`, `.int(n)`, `.string(s)`).
///
/// UDP is fire-and-forget: a `send` returns immediately and delivery isn't
/// confirmed, which is what live performance traffic wants.
public final class OSCSender {

    private let connection: NWConnection

    /// The destination host (an IP or a hostname).
    public let host: String
    /// The destination UDP port.
    public let port: Int

    /// Opens a connection to `host:port` and starts it.
    public init(host: String, port: Int) {
        self.host = host
        self.port = port
        let endpointHost = NWEndpoint.Host(host)
        let endpointPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) ?? 0
        self.connection = NWConnection(host: endpointHost, port: endpointPort, using: .udp)
        self.connection.start(queue: OSCSender.queue)
    }

    /// Sends a single message.
    public func send(_ message: OSCMessage) { transmit(message.encode()) }

    /// Sends a bundle (a group of messages with a time tag).
    public func send(_ bundle: OSCBundle) { transmit(bundle.encode()) }

    /// Builds and sends a message in one call: `send("/x", 0.5, 1, "go")`.
    public func send(_ address: String, _ arguments: OSCArgument...) {
        transmit(OSCMessage(address, arguments: arguments).encode())
    }

    /// Closes the connection. Safe to call more than once; the sender is unusable
    /// afterward.
    public func close() { connection.cancel() }

    private func transmit(_ data: Data) {
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    deinit { connection.cancel() }

    // One shared queue drives every sender's connection callbacks; sends are
    // brief and serialized, so they don't need a queue each.
    private static let queue = DispatchQueue(label: "com.ollin.osc.sender")
}
