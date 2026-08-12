import Foundation
import Network
import Ollin
import os

/// Errors thrown while starting DMX networking.
public enum DMXError: Error, Sendable {
    /// The port number was outside `0...65535`.
    case invalidPort
}

/// Listens for incoming DMX (sACN or Art-Net) and surfaces the latest levels
/// as values a sketch reads in `draw()`, so a lighting console can drive a
/// sketch the way it drives a fixture. Create one in `setup()`, `start()` it,
/// then poll it.
///
/// ```swift
/// let dmx = DMXReceiver()                      // sACN on port 5568
/// override func setup() { try? dmx.start() }
/// override func draw() {
///     let brightness = dmx.level(1)            // channel 1, universe 1, 0…1
///     let wash = dmx.color(at: 10)             // channels 10-12 as a color
/// }
/// ```
///
/// Or bind a channel straight onto a `@Param` knob, so a console fader drives
/// the same parameter a live-inspector slider does:
///
/// ```swift
/// @Param(20...400) var radius = 120.0
/// override func setup() {
///     try? dmx.start()
///     dmx.bind(channel: 1, to: $radius)        // incoming 0…255 mapped into 20…400
/// }
/// ```
///
/// DMX is continuous levels rather than events, so the read surface is the
/// latest-value kind only; there is no message drain to empty.
///
/// `start()` hears unicast sent to this machine. An sACN rig usually
/// multicasts instead, so `start(universes: [1])` also joins those universes'
/// standard multicast groups. Datagrams arrive on a background queue and the
/// sketch reads on the main thread; all shared state is held behind locks.
public final class DMXReceiver: @unchecked Sendable {

    // MARK: Stored state

    /// Which wire protocol this receiver decodes.
    public let dmxProtocol: DMXProtocol

    private let desiredPort: UInt16
    private let queue = DispatchQueue(label: "com.ollin.dmx.receiver")

    // The listener and multicast group are non-Sendable, so they live behind
    // unchecked locks; the resolved port is plain and Sendable.
    private let listenerStore = OSAllocatedUnfairLock<NWListener?>(uncheckedState: nil)
    private let groupStore = OSAllocatedUnfairLock<NWConnectionGroup?>(uncheckedState: nil)
    private let resolvedPort = OSAllocatedUnfairLock<UInt16?>(initialState: nil)

    /// How long a source stays authoritative for a universe with nothing
    /// heard from it (the E1.31 network data loss timeout).
    private static let sourceTimeout = 2.5

    private struct Slot: Sendable {
        var channels: [UInt8]
        var priority: UInt8
        var cid: UUID?
        var sequence: UInt8
        var sequenced: Bool
        var arrival: Double
    }

    private struct BindingKey: Hashable, Sendable {
        let universe: Int
        let channel: Int
    }

    private struct ParamBinding: Sendable {
        let param: Param<Double>
    }

    private struct State: Sendable {
        var slots: [Int: Slot] = [:]
        var bindings: [BindingKey: ParamBinding] = [:]
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    // MARK: Lifecycle

    /// Creates a receiver for a protocol, on its standard port by default.
    /// Pass `port: 0` to let the system assign a free one (read it back from
    /// `boundPort` after `start()`).
    public init(_ dmxProtocol: DMXProtocol = .sACN, port: Int? = nil) {
        self.dmxProtocol = dmxProtocol
        self.desiredPort = UInt16(clamping: port ?? dmxProtocol.defaultPort)
    }

    /// Whether the listener is currently running.
    public var isRunning: Bool { listenerStore.withLock { $0 != nil } }

    /// The port actually in use once the listener is ready, or `nil` before
    /// then. Equals the requested port, or the system-assigned one when `0`
    /// was passed.
    public var boundPort: Int? { resolvedPort.withLock { $0 }.map(Int.init) }

    /// Begins listening for unicast, and, when `universes` names any and the
    /// protocol is sACN, joins those universes' multicast groups too (the way
    /// consoles usually send). Art-Net has no multicast to join, so there the
    /// universes are ignored. Throws if the port is invalid or the socket
    /// can't open.
    public func start(universes: [Int] = []) throws {
        guard !isRunning else { return }

        let parameters = NWParameters.udp
        parameters.allowLocalEndpointReuse = true

        let listener: NWListener
        if desiredPort == 0 {
            listener = try NWListener(using: parameters)
        } else {
            guard let port = NWEndpoint.Port(rawValue: desiredPort) else { throw DMXError.invalidPort }
            listener = try NWListener(using: parameters, on: port)
        }

        // Read the port back from the stored listener (set just below) rather
        // than capturing the non-Sendable listener into this handler.
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

        if dmxProtocol == .sACN, !universes.isEmpty {
            try joinMulticast(universes: universes)
        }
    }

    /// Stops listening. Safe to call when not running.
    public func stop() {
        let listener = listenerStore.withLock { stored -> NWListener? in
            let value = stored
            stored = nil
            return value
        }
        listener?.cancel()
        let group = groupStore.withLock { stored -> NWConnectionGroup? in
            let value = stored
            stored = nil
            return value
        }
        group?.cancel()
        resolvedPort.withLock { $0 = nil }
    }

    private func joinMulticast(universes: [Int]) throws {
        guard let port = NWEndpoint.Port(rawValue: desiredPort) else { throw DMXError.invalidPort }
        let endpoints = universes.map { universe in
            NWEndpoint.hostPort(
                host: NWEndpoint.Host(SACNDataPacket.multicastGroup(universe: universe)),
                port: port
            )
        }
        let group = NWConnectionGroup(with: try NWMulticastGroup(for: endpoints), using: .udp)
        group.setReceiveHandler(maximumMessageSize: 65535, rejectOversizedMessages: true) {
            [weak self] _, content, _ in
            if let content, !content.isEmpty { self?.handle(content) }
        }
        groupStore.withLock { $0 = group }
        group.start(queue: queue)
    }

    // MARK: Reading

    /// The latest full universe received, or `nil` if none has arrived yet.
    public func universe(_ number: Int = 1) -> DMXUniverse? {
        state.withLock { $0.slots[number] }.map { DMXUniverse(channels: $0.channels) }
    }

    /// The universe numbers heard so far, in order.
    public func universes() -> [Int] {
        state.withLock { $0.slots.keys.sorted() }
    }

    /// The latest raw value of a channel, or 0 if nothing has arrived.
    public func channel(_ channel: Int, universe: Int = 1) -> UInt8 {
        guard (1...DMXUniverse.channelCount).contains(channel) else { return 0 }
        return state.withLock { state in
            guard let slot = state.slots[universe], channel <= slot.channels.count else { return 0 }
            return slot.channels[channel - 1]
        }
    }

    /// The latest value of a channel as a 0…1 level.
    public func level(_ channel: Int, universe: Int = 1) -> Double {
        Double(self.channel(channel, universe: universe)) / 255
    }

    /// Three consecutive channels read as a color (red at `channel`).
    public func color(at channel: Int, universe: Int = 1) -> Color {
        Color(
            red: level(channel, universe: universe),
            green: level(channel + 1, universe: universe),
            blue: level(channel + 2, universe: universe)
        )
    }

    // MARK: Parameter binding

    /// Drives a `@Param` from a channel: each arriving value is mapped from
    /// 0…255 into the parameter's own range and assigned.
    public func bind(channel: Int, universe: Int = 1, to param: Param<Double>) {
        state.withLock {
            $0.bindings[BindingKey(universe: universe, channel: channel)] = ParamBinding(param: param)
        }
    }

    /// Removes a binding previously set with `bind(channel:universe:to:)`.
    public func unbind(channel: Int, universe: Int = 1) {
        state.withLock {
            $0.bindings[BindingKey(universe: universe, channel: channel)] = nil
        }
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

    // Internal so the tests can feed crafted datagrams straight through the
    // ingest rules with no sockets involved.
    func handle(_ datagram: Data) {
        let now = ProcessInfo.processInfo.systemUptime
        switch dmxProtocol {
        case .sACN:
            guard let packet = SACNDataPacket(data: datagram) else { return }
            ingest(packet, now: now)
        case .artNet:
            guard let packet = ArtDmxPacket(data: datagram) else { return }
            ingest(packet, now: now)
        }
    }

    private func ingest(_ packet: SACNDataPacket, now: Double) {
        // Only ordinary dimmer data drives output: alternate START codes are
        // other dialects, and preview data is for visualizers by definition.
        guard packet.startCode == 0, !packet.isPreview else { return }
        let bindings: [(binding: ParamBinding, value: UInt8)] = state.withLock { state in
            if packet.isTerminated {
                // The source's goodbye: forget the universe if it was ours.
                if (state.slots[packet.universe]?.cid ?? packet.cid) == packet.cid {
                    state.slots[packet.universe] = nil
                }
                return []
            }
            if let slot = state.slots[packet.universe], now - slot.arrival < Self.sourceTimeout {
                if slot.cid == packet.cid {
                    // The standard's out-of-order window: a step back of up to
                    // 19 is a straggler to drop, a bigger jump is a reset.
                    let diff = Int8(bitPattern: packet.sequence &- slot.sequence)
                    if diff <= 0 && diff > -20 { return [] }
                } else if packet.priority < slot.priority {
                    // Another live source outranks this one.
                    return []
                }
            }
            state.slots[packet.universe] = Slot(
                channels: packet.channels,
                priority: packet.priority,
                cid: packet.cid,
                sequence: packet.sequence,
                sequenced: true,
                arrival: now
            )
            return matchedBindings(in: state, universe: packet.universe, channels: packet.channels)
        }
        apply(bindings)
    }

    private func ingest(_ packet: ArtDmxPacket, now: Double) {
        let bindings: [(binding: ParamBinding, value: UInt8)] = state.withLock { state in
            if let slot = state.slots[packet.universe],
                slot.sequenced, packet.sequence != 0,
                now - slot.arrival < Self.sourceTimeout {
                let diff = Int8(bitPattern: packet.sequence &- slot.sequence)
                if diff <= 0 && diff > -20 { return [] }
            }
            state.slots[packet.universe] = Slot(
                channels: packet.channels,
                priority: 100,
                cid: nil,
                sequence: packet.sequence,
                sequenced: packet.sequence != 0,
                arrival: now
            )
            return matchedBindings(in: state, universe: packet.universe, channels: packet.channels)
        }
        apply(bindings)
    }

    private func matchedBindings(
        in state: State, universe: Int, channels: [UInt8]
    ) -> [(binding: ParamBinding, value: UInt8)] {
        state.bindings.compactMap { key, binding in
            guard key.universe == universe else { return nil }
            guard key.channel >= 1, key.channel <= channels.count else { return nil }
            return (binding, channels[key.channel - 1])
        }
    }

    // Bindings are applied outside the state lock so the param's own lock is
    // never nested under this one.
    private func apply(_ bindings: [(binding: ParamBinding, value: UInt8)]) {
        for (binding, value) in bindings {
            let range = binding.param.range
            let t = Double(value) / 255
            binding.param.wrappedValue =
                range.lowerBound + t * (range.upperBound - range.lowerBound)
        }
    }

    deinit { stop() }
}

/// Carries a non-`Sendable` `NWConnection` across the receiver's `@Sendable`
/// network callbacks. The connection is internally thread-safe, so wrapping it
/// is the standard way to satisfy strict concurrency without copying anything.
private final class ConnectionBox: @unchecked Sendable {
    let connection: NWConnection
    init(_ connection: NWConnection) { self.connection = connection }
}
