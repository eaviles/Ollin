import Foundation
import Network
import Ollin
import os

/// Errors thrown while starting OSC networking.
public enum OSCError: Error, Sendable {
    /// The port number was outside `0...65535`.
    case invalidPort
}

/// Listens for incoming OSC over UDP and surfaces what arrives as values a sketch
/// reads in `draw()`. Create one in `setup()`, `start()` it, then poll it.
///
/// Three ways to read, depending on what the address carries:
///
/// ```swift
/// let osc = OSCReceiver(port: 9000)
/// override func setup() { try? osc.start() }
/// override func draw() {
///     // 1. Continuous control — read the latest value each frame:
///     let level = osc.number("/level", default: 0)
///
///     // 2. Discrete events — drain everything since the last frame:
///     for note in osc.messages() where note.address == "/note" { trigger(note.int ?? 0) }
/// }
/// ```
///
/// Or bind an address straight onto a `@Param` parameter (the third way), so an
/// external fader drives the same parameter a live-inspector slider does:
///
/// ```swift
/// @Param(20...400) var radius = 120.0
/// override func setup() {
///     try? osc.start()
///     osc.bind("/radius", to: $radius)   // incoming 0…1 mapped into 20…400
/// }
/// ```
///
/// Datagrams arrive on a background queue and the sketch reads on the main
/// thread; all shared state is held behind locks, which is what makes this safe.
public final class OSCReceiver: @unchecked Sendable {

    // MARK: Stored state

    private let desiredPort: UInt16
    private let queue = DispatchQueue(label: "com.ollin.osc.receiver")

    // The listener is non-Sendable, so it lives behind an unchecked lock; the
    // resolved port (set once ready, e.g. when an ephemeral port-0 is assigned)
    // is plain and Sendable.
    private let listenerStore = OSAllocatedUnfairLock<NWListener?>(uncheckedState: nil)
    private let resolvedPort = OSAllocatedUnfairLock<UInt16?>(initialState: nil)

    private struct ParamBinding: Sendable {
        let input: ClosedRange<Double>
        let output: ClosedRange<Double>
        let write: @Sendable (Double) -> Void
    }

    private struct State: Sendable {
        var latest: [String: OSCMessage] = [:]
        var inbox: [OSCMessage] = []
        var bindings: [String: ParamBinding] = [:]
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Cap on undrained messages, so a sketch that never calls `messages()`
    /// doesn't grow the inbox without bound; the oldest are dropped past it.
    private let inboxLimit = 4096

    /// Handlers called for every message as it arrives. The seam a decoder over
    /// this receiver rides (the TUIO surface is the one in the tree), kept
    /// internal because a sketch reads through the polling surface above, and
    /// separate from `state` so a handler never runs under that lock.
    private let observers = OSAllocatedUnfairLock<[@Sendable (OSCMessage) -> Void]>(initialState: [])

    // MARK: Lifecycle

    /// Creates a receiver bound to `port`. Pass `0` to let the system assign a
    /// free port (read it back from `boundPort` after `start()`).
    public init(port: Int) {
        self.desiredPort = UInt16(clamping: port)
    }

    /// Whether the listener is currently running.
    public var isRunning: Bool { listenerStore.withLock { $0 != nil } }

    /// The port actually in use once the listener is ready, or `nil` before then.
    /// Equals the requested port, or the system-assigned one when `0` was passed.
    public var boundPort: Int? { resolvedPort.withLock { $0 }.map(Int.init) }

    /// Begins listening. Throws if the port is invalid or the socket can't open.
    public func start() throws {
        guard !isRunning else { return }

        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true

        let listener: NWListener
        if desiredPort == 0 {
            listener = try NWListener(using: parameters)
        } else {
            guard let port = NWEndpoint.Port(rawValue: desiredPort) else { throw OSCError.invalidPort }
            listener = try NWListener(using: parameters, on: port)
        }

        // Read the port back from the stored listener (set just below) rather than
        // capturing the non-Sendable listener into this @Sendable handler.
        listener.stateUpdateHandler = { [weak self] newState in
            guard let self, case .ready = newState else { return }
            let port = self.listenerStore.withLock { $0?.port?.rawValue }
            self.resolvedPort.withLock { $0 = port }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(ConnectionBox(connection))
        }

        listenerStore.withLock { $0 = listener }
        listener.start(queue: queue)
    }

    /// Stops listening. Safe to call when not running.
    public func stop() {
        let listener = listenerStore.withLock { stored -> NWListener? in
            let value = stored
            stored = nil
            return value
        }
        listener?.cancel()
        resolvedPort.withLock { $0 = nil }
    }

    // MARK: Reading — polling cache

    /// The most recent message received at `address`, or `nil` if none yet.
    public func message(_ address: String) -> OSCMessage? {
        state.withLock { $0.latest[address] }
    }

    /// The arguments of the most recent message at `address`.
    public func arguments(_ address: String) -> [OSCArgument]? { message(address)?.arguments }

    /// The first argument at `address` as a `Double` (coerced across numeric tags).
    public func number(_ address: String) -> Double? { message(address)?.number }
    /// The first argument at `address` as an `Int`.
    public func int(_ address: String) -> Int? { message(address)?.int }
    /// The first argument at `address` as a `String`.
    public func text(_ address: String) -> String? { message(address)?.text }
    /// The first argument at `address` as a `Bool`.
    public func bool(_ address: String) -> Bool? { message(address)?.bool }

    /// The latest `Double` at `address`, or `fallback` if nothing has arrived.
    public func number(_ address: String, default fallback: Double) -> Double { number(address) ?? fallback }
    /// The latest `Int` at `address`, or `fallback` if nothing has arrived.
    public func int(_ address: String, default fallback: Int) -> Int { int(address) ?? fallback }
    /// The latest `Bool` at `address`, or `fallback` if nothing has arrived.
    public func bool(_ address: String, default fallback: Bool) -> Bool { bool(address) ?? fallback }

    // MARK: Reading — event drain

    /// Returns every message received since the last call and clears the queue.
    /// Call it once per frame in `draw()` to handle discrete events (notes,
    /// triggers) in arrival order.
    public func messages() -> [OSCMessage] {
        state.withLock { state in
            let drained = state.inbox
            state.inbox.removeAll(keepingCapacity: true)
            return drained
        }
    }

    // MARK: Parameter binding

    /// Drives a `@Param` from an incoming address: each message's first value is
    /// mapped from `input` into the parameter's own range and assigned (clamped).
    ///
    /// ```swift
    /// osc.bind("/radius", to: $radius)            // 0…1 → the param's range
    /// osc.bind("/freq", to: $freq, from: 0...127) // a MIDI-style 0…127 fader
    /// ```
    public func bind(_ address: String, to param: Param<Double>, from input: ClosedRange<Double> = 0...1) {
        let binding = ParamBinding(input: input, output: param.range) { param.wrappedValue = $0 }
        state.withLock { $0.bindings[address] = binding }
    }

    /// Drives a `Tempo` parameter from an incoming address, mapped into its
    /// range in beats per minute. The beats per bar stay what the declaration
    /// gave them.
    public func bind(_ address: String, to param: Param<Tempo>, from input: ClosedRange<Double> = 0...1) {
        let binding = ParamBinding(input: input, output: param.range) {
            param.wrappedValue = Tempo($0, beatsPerBar: param.wrappedValue.beatsPerBar)
        }
        state.withLock { $0.bindings[address] = binding }
    }

    /// Removes a binding previously set with `bind(_:to:from:)`.
    public func unbind(_ address: String) {
        state.withLock { $0.bindings[address] = nil }
    }

    // MARK: Observing (internal)

    /// Calls `handler` on the network queue for every message that arrives, once
    /// the caches above have taken it.
    func observe(_ handler: @escaping @Sendable (OSCMessage) -> Void) {
        observers.withLock { $0.append(handler) }
    }

    // MARK: Receiving (background queue)

    private func accept(_ box: ConnectionBox) {
        box.connection.start(queue: queue)
        receive(box)
    }

    private func receive(_ box: ConnectionBox) {
        box.connection.receiveMessage { [weak self] data, _, _, error in
            if let data, !data.isEmpty { self?.handle(data) }
            if error == nil { self?.receive(box) } else { box.connection.cancel() }
        }
    }

    private func handle(_ datagram: Data) {
        guard let packet = OSCPacket(data: datagram) else { return }
        process(packet)
    }

    private func process(_ packet: OSCPacket) {
        switch packet {
        case .message(let message): ingest(message)
        case .bundle(let bundle): bundle.elements.forEach(process)
        }
    }

    private func ingest(_ message: OSCMessage) {
        // Stash under the lock and read out any binding, then apply the binding
        // outside the lock so the param's own lock is never nested under this one.
        let binding: ParamBinding? = state.withLock { state in
            state.latest[message.address] = message
            state.inbox.append(message)
            if state.inbox.count > inboxLimit {
                state.inbox.removeFirst(state.inbox.count - inboxLimit)
            }
            return state.bindings[message.address]
        }
        if let binding, let raw = message.number {
            binding.write(OSCReceiver.map(raw, from: binding.input, to: binding.output))
        }
        for handler in observers.withLock({ $0 }) { handler(message) }
    }

    private static func map(_ value: Double, from input: ClosedRange<Double>, to output: ClosedRange<Double>) -> Double {
        let span = input.upperBound - input.lowerBound
        guard span != 0 else { return output.lowerBound }
        let t = (value - input.lowerBound) / span
        return output.lowerBound + t * (output.upperBound - output.lowerBound)
    }

    deinit { stop() }
}

/// Carries a non-`Sendable` `NWConnection` across the receiver's `@Sendable`
/// network callbacks. The connection is internally thread-safe, so wrapping it is
/// the standard way to satisfy strict concurrency without copying anything.
private final class ConnectionBox: @unchecked Sendable {
    let connection: NWConnection
    init(_ connection: NWConnection) { self.connection = connection }
}
