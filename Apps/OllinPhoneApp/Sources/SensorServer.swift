import Foundation
import Network

/// A tiny TCP server the Mac connects to over the usbmuxd USB tunnel. It accepts
/// connections on `PhoneWire.streamPort` and broadcasts each encoded sensor frame
/// to every connected client (normally one — the sketch on the Mac).
///
/// All connection state lives on the server's serial `queue`, so accepts, removals,
/// and sends never race. The Mac side never writes back; this is a one-way push.
final class SensorServer: @unchecked Sendable {

    /// Called (on the server queue) whenever a client connects or drops. Set at
    /// init, before the listener starts, so a server-queue accept can't race a
    /// later assignment. (`connections` and everything below stays on `queue`,
    /// which is what `@unchecked Sendable` is asserting.)
    private let onClientCountChange: (@Sendable (Int) -> Void)?

    private let listener: NWListener
    private let queue = DispatchQueue(label: "dev.ollin.capture.server")
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    init(port: UInt16, onClientCountChange: (@Sendable (Int) -> Void)? = nil) throws {
        self.onClientCountChange = onClientCountChange
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: port)!)
        listener.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        listener.stateUpdateHandler = { state in NSLog("Ollin capture listener: \(state)") }
        listener.start(queue: queue)
    }

    private func accept(_ conn: NWConnection) {
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready: self?.add(conn)
            case .failed, .cancelled: self?.remove(conn)
            default: break
            }
        }
        conn.start(queue: queue)
    }

    private func add(_ conn: NWConnection) {           // on queue
        connections[ObjectIdentifier(conn)] = conn
        onClientCountChange?(connections.count)
    }

    private func remove(_ conn: NWConnection) {         // on queue
        if connections.removeValue(forKey: ObjectIdentifier(conn)) != nil {
            onClientCountChange?(connections.count)
        }
    }

    /// Broadcast one already-framed message to every connected client.
    func send(_ data: Data) {
        queue.async { [weak self] in
            guard let self else { return }
            for conn in self.connections.values {
                conn.send(content: data, completion: .contentProcessed { _ in })
            }
        }
    }
}
