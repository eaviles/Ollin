import Foundation
import Network
import os
import Ollin

/// Plays a point stream on a network laser DAC.
///
/// A projector has to be fed without a break. The DAC holds a small buffer of
/// points and plays them at a fixed rate; if the buffer empties, the mirrors
/// stop where they stood. So this class does not send a frame and wait for the
/// next one: it keeps the buffer topped up from whatever frame it holds, over
/// and over, and a sketch replaces that frame whenever it likes.
///
/// Every command gets one reply, and the reply says how full the buffer is.
/// That reply is what asks for the next batch, so the stream clocks itself
/// against the hardware rather than against a timer here.
///
/// A sketch usually reaches this through `LaserProjector`, which adds the
/// optimizer and the safety rules. Use it directly to drive a DAC with points
/// you have made some other way.
public final class EtherDreamDAC: @unchecked Sendable {

    // MARK: What it is

    /// The DAC's address on the network.
    public let host: String

    /// The control port (the protocol's own is the default).
    public let port: Int

    /// The point clock to play at. Read when the stream starts.
    public var pointsPerSecond: Int {
        get { settings.withLock { $0.pointsPerSecond } }
        set { settings.withLock { $0.pointsPerSecond = max(1, newValue) } }
    }

    /// How many points the DAC can hold. A DAC that announced itself over the
    /// network says its own capacity; when connecting straight to an address,
    /// this careful default stands in.
    public var bufferCapacity: Int {
        get { settings.withLock { $0.bufferCapacity } }
        set { settings.withLock { $0.bufferCapacity = max(1, newValue) } }
    }

    /// How much of the buffer to leave empty, as a share of the capacity. The
    /// headroom is what absorbs a late reply without the buffer running dry.
    public var headroom: Double {
        get { settings.withLock { $0.headroom } }
        set { settings.withLock { $0.headroom = min(max(newValue, 0), 0.9) } }
    }

    /// The most points to put in one command.
    public var maximumBatch: Int {
        get { settings.withLock { $0.maximumBatch } }
        set { settings.withLock { $0.maximumBatch = max(1, newValue) } }
    }

    /// How long the last frame may keep playing before the beam is blanked.
    /// `LaserProjector` sets this from its `LaserSafety`.
    public var stallTimeout: Double {
        get { settings.withLock { $0.stallTimeout } }
        set { settings.withLock { $0.stallTimeout = max(0, newValue) } }
    }

    // MARK: Stored state

    /// The tunables above. A sketch writes them from `draw()` and the pump
    /// reads them on its own queue, so they live behind a lock rather than as
    /// plain properties, and the pump takes a copy of the whole set at once.
    private struct Settings: Sendable {
        var pointsPerSecond = 20_000
        var bufferCapacity = 1_799
        var headroom = 0.25
        var maximumBatch = 400
        var stallTimeout = 0.5
    }
    private let settings = OSAllocatedUnfairLock(initialState: Settings())

    private let queue = DispatchQueue(label: "com.ollin.laser.etherdream")
    private let connectionStore = OSAllocatedUnfairLock<NWConnection?>(uncheckedState: nil)

    private enum Phase: Sendable {
        case idle, connecting, greeting, preparing, beginning, playing
    }

    private struct Stream: Sendable {
        var phase: Phase = .idle
        var frame: [LaserPoint] = []
        var pending: [LaserPoint]?
        var cursor = 0
        var lastFrameAt: Date?
        var status: EtherDreamStatus?
        var inbox = Data()
        var failure: String?
        var pointsSent = 0
    }
    private let stream = OSAllocatedUnfairLock(initialState: Stream())

    /// A DAC at a known address.
    public init(host: String, port: Int = EtherDreamWire.controlPort) {
        self.host = host
        self.port = port
    }

    /// A DAC that announced itself, taking its capacity and rate ceiling from
    /// what it said about itself.
    public convenience init(device: EtherDreamDevice) {
        self.init(host: device.host)
        bufferCapacity = max(1, device.bufferCapacity)
        if device.maximumPointRate > 0 {
            pointsPerSecond = min(pointsPerSecond, device.maximumPointRate)
        }
    }

    // MARK: What a caller sees

    /// Whether the connection is up and the DAC is taking points.
    public var isPlaying: Bool { stream.withLock { $0.phase == .playing } }

    /// The last thing the DAC said about itself, or `nil` before it has said
    /// anything.
    public var status: EtherDreamStatus? { stream.withLock { $0.status } }

    /// What went wrong, if anything has. Cleared by a fresh `connect()`.
    public var lastError: String? { stream.withLock { $0.failure } }

    /// How many points have gone out since the connection opened.
    public var pointsSent: Int { stream.withLock { $0.pointsSent } }

    // MARK: Lifecycle

    /// Open the connection and start playing. Safe to call when already open.
    public func connect() {
        guard connectionStore.withLock({ $0 == nil }) else { return }
        stream.withLock {
            $0 = Stream()
            $0.phase = .connecting
        }
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: port)) else {
            fail("port \(port) is not a port number")
            return
        }
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                // The DAC greets a new connection with a status of its own, so
                // the first thing to do is listen rather than talk.
                self.stream.withLock { $0.phase = .greeting }
                self.receive()
            case .failed(let error):
                self.fail("connection failed: \(error.localizedDescription)")
            case .cancelled:
                self.stream.withLock { $0.phase = .idle }
            default:
                break
            }
        }
        connectionStore.withLock { $0 = connection }
        connection.start(queue: queue)
    }

    /// Stop playing and close the connection. Sends the stop command first, so
    /// the DAC is left idle rather than starved.
    public func disconnect() {
        let connection = connectionStore.withLock { stored -> NWConnection? in
            let value = stored
            stored = nil
            return value
        }
        guard let connection else { return }
        connection.send(content: EtherDreamWire.stop(), completion: .contentProcessed { _ in
            connection.cancel()
        })
        stream.withLock { $0.phase = .idle }
    }

    // MARK: Feeding it

    /// Replace the frame being played. The swap happens at the end of the
    /// frame already going out, so a picture is never cut in half.
    public func play(_ points: [LaserPoint]) {
        stream.withLock {
            $0.lastFrameAt = Date()
            if $0.frame.isEmpty {
                $0.frame = points
                $0.cursor = 0
            } else {
                $0.pending = points
            }
        }
    }

    /// Ask the DAC to play at a new point rate. Before it is playing this only
    /// records the rate, which the start command then carries; while it plays,
    /// the change is queued for the next point.
    public func setPointRate(_ rate: Int) {
        let rate = max(1, rate)
        let changed = settings.withLock { state -> Bool in
            guard state.pointsPerSecond != rate else { return false }
            state.pointsPerSecond = rate
            return true
        }
        guard changed, isPlaying else { return }
        send(EtherDreamWire.queueRateChange(pointsPerSecond: rate))
    }

    // MARK: The pump

    private func receive() {
        guard let connection = connectionStore.withLock({ $0 }) else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                self.fail("read failed: \(error.localizedDescription)")
                return
            }
            if let data, !data.isEmpty { self.ingest(data) }
            if isComplete {
                self.fail("the DAC closed the connection")
                return
            }
            self.receive()
        }
    }

    /// Pull whole replies out of the incoming bytes and act on each.
    private func ingest(_ data: Data) {
        let replies = stream.withLock { state -> [EtherDreamResponse] in
            var out: [EtherDreamResponse] = []
            state.inbox.append(data)
            while state.inbox.count >= EtherDreamWire.responseSize {
                let head = state.inbox.prefix(EtherDreamWire.responseSize)
                state.inbox.removeFirst(EtherDreamWire.responseSize)
                guard let reply = EtherDreamResponse.decode(Data(head)) else { continue }
                state.status = reply.status
                out.append(reply)
            }
            return out
        }
        for reply in replies { handle(reply) }
    }

    private func handle(_ reply: EtherDreamResponse) {
        switch reply.code {
        case .ack:
            advance()
        case .full:
            // No room right now. Wait for some of it to drain, then ask again.
            askAgain(after: 0.003)
        case .invalid:
            // The DAC would not take that in the state it is in. Start the
            // handshake again rather than guessing.
            stream.withLock { $0.phase = .preparing }
            send(EtherDreamWire.prepare())
        case .stopped:
            fail("the DAC is in a stop condition")
            send(EtherDreamWire.clearEmergencyStop())
            stream.withLock { $0.phase = .preparing }
        }
    }

    /// Take the next step of the handshake, or keep the buffer fed once it is
    /// done.
    private func advance() {
        let phase = stream.withLock { $0.phase }
        switch phase {
        case .greeting:
            stream.withLock { $0.phase = .preparing }
            send(EtherDreamWire.prepare())
        case .preparing:
            stream.withLock { $0.phase = .beginning }
            send(EtherDreamWire.begin(pointsPerSecond: pointsPerSecond))
        case .beginning:
            stream.withLock { $0.phase = .playing }
            pump()
        case .playing:
            pump()
        case .idle, .connecting:
            break
        }
    }

    /// Send as many points as the buffer has room for.
    private func pump() {
        guard stream.withLock({ $0.phase == .playing }) else { return }
        let settings = settings.withLock { $0 }
        let fullness = stream.withLock { $0.status?.bufferFullness ?? 0 }
        let ceiling = Int(Double(settings.bufferCapacity) * (1 - settings.headroom))
        let room = max(0, ceiling - fullness)
        guard room > 0 else {
            askAgain(after: 0.002)
            return
        }
        let points = take(min(room, settings.maximumBatch), stallTimeout: settings.stallTimeout)
        guard !points.isEmpty else {
            askAgain(after: 0.02)
            return
        }
        stream.withLock { $0.pointsSent += points.count }
        send(EtherDreamWire.write(points))
    }

    /// Wait, then ask the DAC how it is doing.
    ///
    /// This is load-bearing rather than tidy. The buffer figure the host works
    /// from arrives on a reply, so a host that has nothing to send must still
    /// ask something: re-reading the last figure it was given is reading a
    /// number that cannot change, and the stream stops for good. A ping is the
    /// question with no side effect, and its reply starts the loop again.
    private func askAgain(after delay: Double) {
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.isPlaying else { return }
            self.send(EtherDreamWire.ping())
        }
    }

    /// The next `count` points to play: from the frame in hand, wrapping round
    /// and swapping in a newer frame at the seam.
    ///
    /// Two cases never reach the beam. A frame that has gone stale is not
    /// played, and neither is a frame with nothing in it: both hold the beam
    /// blanked instead. Sending nothing at all would be worse than either,
    /// because the DAC would drain its buffer and stop the mirrors wherever
    /// the last lit point left them.
    private func take(_ count: Int, stallTimeout: Double) -> [LaserPoint] {
        stream.withLock { state in
            if let last = state.lastFrameAt, Date().timeIntervalSince(last) > stallTimeout {
                return LaserSafety.blankHold(count: count)
            }
            if state.cursor >= state.frame.count, let next = state.pending {
                state.frame = next
                state.pending = nil
                state.cursor = 0
            }
            guard !state.frame.isEmpty else { return LaserSafety.blankHold(count: count) }
            var out: [LaserPoint] = []
            out.reserveCapacity(count)
            while out.count < count {
                if state.cursor >= state.frame.count {
                    if let next = state.pending {
                        state.frame = next
                        state.pending = nil
                    }
                    state.cursor = 0
                    if state.frame.isEmpty { break }
                }
                let take = min(count - out.count, state.frame.count - state.cursor)
                out.append(contentsOf: state.frame[state.cursor ..< state.cursor + take])
                state.cursor += take
            }
            return out.isEmpty ? LaserSafety.blankHold(count: count) : out
        }
    }

    private func send(_ data: Data) {
        guard let connection = connectionStore.withLock({ $0 }) else { return }
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error { self?.fail("write failed: \(error.localizedDescription)") }
        })
    }

    private func fail(_ message: String) {
        stream.withLock {
            $0.failure = message
            $0.phase = .idle
        }
        let connection = connectionStore.withLock { stored -> NWConnection? in
            let value = stored
            stored = nil
            return value
        }
        connection?.cancel()
    }
}

// MARK: - Finding one

/// Listens for the announcements a network DAC broadcasts once a second, so a
/// sketch can find one without being told its address.
///
/// ```swift
/// let finder = EtherDreamFinder()
/// try finder.start()
/// // a second later
/// if let dac = finder.devices.first { laser.connect(to: dac) }
/// ```
///
/// Listening on the local network makes macOS ask for its Local Network
/// permission once, attributed to whatever launched the sketch.
public final class EtherDreamFinder: @unchecked Sendable {

    private let queue = DispatchQueue(label: "com.ollin.laser.finder")
    private let listenerStore = OSAllocatedUnfairLock<NWListener?>(uncheckedState: nil)
    private let found = OSAllocatedUnfairLock<[String: EtherDreamDevice]>(initialState: [:])

    public init() {}

    /// Every DAC heard from, in address order.
    public var devices: [EtherDreamDevice] {
        found.withLock { Array($0.values) }.sorted { $0.host < $1.host }
    }

    /// Whether the listener is running.
    public var isRunning: Bool { listenerStore.withLock { $0 != nil } }

    /// Start listening for announcements.
    public func start() throws {
        guard !isRunning else { return }
        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true
        guard let port = NWEndpoint.Port(rawValue: UInt16(EtherDreamWire.broadcastPort)) else { return }
        let listener = try NWListener(using: parameters, on: port)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listenerStore.withLock { $0 = listener }
        listener.start(queue: queue)
    }

    /// Stop listening. What was already found stays readable.
    public func stop() {
        let listener = listenerStore.withLock { stored -> NWListener? in
            let value = stored
            stored = nil
            return value
        }
        listener?.cancel()
    }

    /// Take one announcement apart, whatever brought it in. Tests feed
    /// datagrams here with no socket in the way.
    func handle(_ data: Data, from host: String) {
        guard let device = EtherDreamDevice.decode(data, host: host) else { return }
        found.withLock { $0[device.macAddress] = device }
    }

    private func accept(_ connection: NWConnection) {
        let host = Self.address(of: connection.endpoint)
        connection.stateUpdateHandler = { [weak self] state in
            guard let self, case .ready = state else { return }
            connection.receiveMessage { [weak self] data, _, _, _ in
                if let data { self?.handle(data, from: host) }
                connection.cancel()
            }
        }
        connection.start(queue: queue)
    }

    static func address(of endpoint: NWEndpoint) -> String {
        switch endpoint {
        case .hostPort(let host, _):
            switch host {
            case .ipv4(let address): return "\(address)".components(separatedBy: "%").first ?? "\(address)"
            case .ipv6(let address): return "\(address)".components(separatedBy: "%").first ?? "\(address)"
            case .name(let name, _): return name
            @unknown default: return "\(host)"
            }
        default:
            return "\(endpoint)"
        }
    }
}
