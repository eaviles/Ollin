import Foundation
import Network

/// A tiny TCP server the Mac connects to over the usbmuxd USB tunnel. It accepts
/// connections on `PhoneWire.streamPort` and broadcasts each encoded sensor frame
/// to every connected client (normally one, the sketch on the Mac).
///
/// All connection state lives on the server's serial `queue`, so accepts, removals,
/// sends, and the bytes arriving the other way never race.
///
/// The stream runs both ways. Sensor frames go out; requests come back, framed the
/// same length-prefixed way against their own magic, so a sketch can ask for a mode
/// and send the pictures it wants found. A connection's incoming bytes are
/// accumulated per connection until a whole frame is there, since TCP promises an
/// ordered stream and nothing about where one read ends.
final class SensorServer: @unchecked Sendable {

    /// Called (on the server queue) whenever a client connects or drops. Set at
    /// init, before the listener starts, so a server-queue accept can't race a
    /// later assignment. (`connections` and everything below stays on `queue`,
    /// which is what `@unchecked Sendable` is asserting.)
    private let onClientCountChange: (@Sendable (Int) -> Void)?

    /// Called (on the server queue) with each request the Mac sends. Set at init
    /// for the same reason the count handler is.
    private let onRequest: (@Sendable (PhoneRequest) -> Void)?

    private let listener: NWListener
    private let queue = DispatchQueue(label: "dev.ollin.capture.server")
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    /// What has arrived from each client and not yet made a whole frame.
    private var inbox: [ObjectIdentifier: Data] = [:]

    init(port: UInt16, onClientCountChange: (@Sendable (Int) -> Void)? = nil,
         onRequest: (@Sendable (PhoneRequest) -> Void)? = nil) throws {
        self.onClientCountChange = onClientCountChange
        self.onRequest = onRequest
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
        inbox[ObjectIdentifier(conn)] = Data()
        onClientCountChange?(connections.count)
        receive(conn)
    }

    private func remove(_ conn: NWConnection) {         // on queue
        inbox.removeValue(forKey: ObjectIdentifier(conn))
        if connections.removeValue(forKey: ObjectIdentifier(conn)) != nil {
            onClientCountChange?(connections.count)
        }
    }

    /// Keep reading whatever the Mac sends. Each chunk joins that connection's
    /// buffer and every whole frame in it is decoded; a frame whose header does
    /// not parse means the stream is out of step, so the connection goes rather
    /// than guessing where the next one starts.
    private func receive(_ conn: NWConnection) {        // on queue
        conn.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty { self.take(data, from: conn) }
            if isComplete || error != nil {
                conn.cancel()
                return
            }
            self.receive(conn)
        }
    }

    /// Add bytes to a connection's buffer and pull out every whole frame. The
    /// framing arithmetic is `PhoneWire.takeRequests`, in the file both ends share,
    /// so the Mac's tests pin what runs here.
    private func take(_ data: Data, from conn: NWConnection) {   // on queue
        let key = ObjectIdentifier(conn)
        guard var buffer = inbox[key] else { return }
        buffer.append(data)
        guard let requests = PhoneWire.takeRequests(from: &buffer) else {
            // Not our framing at all: drop the connection instead of hunting for a
            // magic word further along.
            inbox[key] = Data()
            conn.cancel()
            return
        }
        inbox[key] = buffer
        for request in requests { onRequest?(request) }
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
