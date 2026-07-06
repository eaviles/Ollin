import CoreMIDI
import Foundation
import Ollin
import os

/// Receives MIDI from the devices connected to this Mac and surfaces what arrives
/// as values a sketch reads in `draw()`. Create one in `setup()`, `start()` it,
/// then poll it — the same shape as `OSCReceiver`.
///
/// Three ways to read, depending on what you're after:
///
/// ```swift
/// let midi = MIDIInput()
/// override func setup() { try? midi.start() }
/// override func draw() {
///     // 1. Continuous control — the latest value of a knob/fader (CC 7):
///     let level = midi.controlValue(7, default: 0)
///
///     // 2. State — is a key/pad held right now?
///     if midi.isNoteOn(60) { … }
///
///     // 3. Discrete events — drain everything since the last frame, in order:
///     for message in midi.messages() where message.isNoteOn { trigger(message.note!) }
/// }
/// ```
///
/// Or bind a control straight onto a `@Param` knob, so a hardware fader drives the
/// same parameter the inspector slider does (give the param `smoothing:` and the
/// hardware moves glide instead of jumping):
///
/// ```swift
/// @Param(20...400, smoothing: .eased(0.3)) var radius = 120
/// override func setup() {
///     try? midi.start()
///     midi.bind(controlChange: 7, to: $radius)   // CC 0…127 mapped into 20…400
/// }
/// ```
///
/// MIDI arrives on a Core MIDI thread and the sketch reads on the main thread; all
/// shared state is held behind locks, which is what makes this safe.
public final class MIDIInput: @unchecked Sendable {

    // MARK: Stored state

    private let clientName: String

    // Core MIDI handles (UInt32 refs) plus the running flag, behind one lock.
    private struct CoreState: Sendable {
        var client = MIDIClientRef()
        var port = MIDIPortRef()
        var connected: Set<MIDIEndpointRef> = []
        var running = false
    }
    private let core = OSAllocatedUnfairLock(initialState: CoreState())

    private struct ControlKey: Hashable, Sendable { let channel: Int; let controller: Int }
    private struct NoteKey: Hashable, Sendable { let channel: Int; let note: Int }
    private struct ParamBinding: Sendable {
        let param: Param<Double>
        let input: ClosedRange<Double>
    }

    private struct State: Sendable {
        var latestControl: [ControlKey: Int] = [:]
        var heldNotes: Set<NoteKey> = []
        var inbox: [MIDIMessage] = []
        var bindings: [ControlKey: ParamBinding] = [:]
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Cap on undrained messages, so a sketch that never calls `messages()`
    /// doesn't grow the inbox without bound; the oldest are dropped past it.
    private let inboxLimit = 4096

    // MARK: Lifecycle

    /// Creates an input. `name` labels the Core MIDI client this Mac advertises.
    public init(name: String = "Ollin") {
        self.clientName = name
    }

    /// Whether the input is currently connected and listening.
    public var isRunning: Bool { core.withLock { $0.running } }

    /// The MIDI sources currently visible on the system (every connected device).
    public var sources: [MIDIEndpoint] {
        (0..<MIDIGetNumberOfSources()).compactMap { index in
            let source = MIDIGetSource(index)
            return source != 0 ? MIDIEndpoint(source) : nil
        }
    }

    /// Opens the Core MIDI client and input port and connects every current
    /// source. New devices plugged in afterward connect automatically. Throws if
    /// Core MIDI can't be opened.
    public func start() throws {
        guard !isRunning else { return }

        // Reconnect on setup changes so hot-plugged devices are picked up. Formed
        // in this non-isolated method (not @MainActor) so the Core MIDI thread can
        // call it without tripping an executor assertion.
        let notify: MIDINotifyBlock = { [weak self] notification in
            if notification.pointee.messageID == .msgSetupChanged { self?.connectAllSources() }
        }
        var client = MIDIClientRef()
        var status = MIDIClientCreateWithBlock(clientName as CFString, &client, notify)
        guard status == noErr else { throw MIDIError.coreMIDI(status) }

        let receive: MIDIReceiveBlock = { [weak self] eventList, _ in self?.handle(eventList) }
        var port = MIDIPortRef()
        status = MIDIInputPortCreateWithProtocol(client, "\(clientName) In" as CFString, ._1_0, &port, receive)
        guard status == noErr else {
            MIDIClientDispose(client)
            throw MIDIError.coreMIDI(status)
        }

        // Copy into immutable lets: the C calls above needed `inout` vars, but a
        // lock body can't capture a mutable var under strict concurrency.
        let openedClient = client
        let openedPort = port
        core.withLock { core in
            core.client = openedClient
            core.port = openedPort
            core.running = true
        }
        connectAllSources()
    }

    /// Disconnects, disposes the port and client, and clears the running state.
    /// Safe to call when not running.
    public func stop() {
        let (port, client, connected) = core.withLock { core -> (MIDIPortRef, MIDIClientRef, Set<MIDIEndpointRef>) in
            let snapshot = (core.port, core.client, core.connected)
            core = CoreState()
            return snapshot
        }
        if port != 0 {
            for source in connected { MIDIPortDisconnectSource(port, source) }
            MIDIPortDispose(port)
        }
        if client != 0 { MIDIClientDispose(client) }
    }

    /// Connects any source not already connected. Run at `start()` and again on
    /// every setup change (a device plugged or unplugged).
    private func connectAllSources() {
        let port = core.withLock { $0.port }
        guard port != 0 else { return }
        for index in 0..<MIDIGetNumberOfSources() {
            let source = MIDIGetSource(index)
            guard source != 0 else { continue }
            let isNew = core.withLock { core -> Bool in
                guard core.running, !core.connected.contains(source) else { return false }
                core.connected.insert(source)
                return true
            }
            guard isNew else { continue }
            if MIDIPortConnectSource(port, source, nil) != noErr {
                core.withLock { _ = $0.connected.remove(source) }
            }
        }
    }

    // MARK: Reading — polling cache

    /// The most recent value of a continuous controller (knob, fader, pedal), or
    /// `nil` if none has arrived. Pass `channel` (1…16) to read one channel; omit
    /// it for the latest value on any channel.
    public func controlValue(_ controller: Int, channel: Int? = nil) -> Int? {
        state.withLock { $0.latestControl[ControlKey(channel: channel ?? 0, controller: controller)] }
    }

    /// The latest controller value, or `fallback` if none has arrived.
    public func controlValue(_ controller: Int, default fallback: Int, channel: Int? = nil) -> Int {
        controlValue(controller, channel: channel) ?? fallback
    }

    /// Whether a note (key or pad) is held down right now. Pass `channel` (1…16)
    /// to check one channel; omit it for any channel.
    public func isNoteOn(_ note: Int, channel: Int? = nil) -> Bool {
        state.withLock { state in
            if let channel { return state.heldNotes.contains(NoteKey(channel: channel, note: note)) }
            return state.heldNotes.contains { $0.note == note }
        }
    }

    // MARK: Reading — event drain

    /// Returns every message received since the last call and clears the queue.
    /// Call it once per frame in `draw()` to handle discrete events (notes,
    /// transport, clock) in arrival order.
    public func messages() -> [MIDIMessage] {
        state.withLock { state in
            let drained = state.inbox
            state.inbox.removeAll(keepingCapacity: true)
            return drained
        }
    }

    // MARK: Parameter binding

    /// Drives a `@Param` from a control-change knob: each incoming value is mapped
    /// from `input` (a controller's `0…127` by default) into the parameter's own
    /// range and assigned. Give the param `smoothing:` and the hardware moves glide
    /// rather than jump. Pass `channel` (1…16) to bind one channel only.
    ///
    /// ```swift
    /// midi.bind(controlChange: 7, to: $radius)                    // 0…127 → the param's range
    /// midi.bind(controlChange: 1, to: $mix, from: 0...127)        // explicit input range
    /// ```
    public func bind(controlChange controller: Int, to param: Param<Double>,
                     channel: Int? = nil, from input: ClosedRange<Double> = 0...127) {
        let key = ControlKey(channel: channel ?? 0, controller: controller)
        state.withLock { $0.bindings[key] = ParamBinding(param: param, input: input) }
    }

    /// Removes a binding previously set with `bind(controlChange:to:channel:from:)`.
    public func unbind(controlChange controller: Int, channel: Int? = nil) {
        let key = ControlKey(channel: channel ?? 0, controller: controller)
        state.withLock { $0.bindings[key] = nil }
    }

    // MARK: Receiving (Core MIDI thread)

    private func handle(_ eventList: UnsafePointer<MIDIEventList>) {
        let packetCount = Int(eventList.pointee.numPackets)
        guard packetCount > 0 else { return }

        var parsed: [MIDIMessage] = []
        // The packets follow the list header; walk them with MIDIEventPacketNext,
        // reading each packet's Universal MIDI Packet words.
        var packet = UnsafeRawPointer(eventList)
            .advanced(by: MemoryLayout<MIDIEventList>.offset(of: \.packet)!)
            .assumingMemoryBound(to: MIDIEventPacket.self)
        for _ in 0..<packetCount {
            let wordCount = Int(packet.pointee.wordCount)
            withUnsafeBytes(of: packet.pointee.words) { raw in
                let words = raw.bindMemory(to: UInt32.self)
                for i in 0..<min(wordCount, words.count) {
                    if let message = MIDIMessage(umpWord: words[i]) { parsed.append(message) }
                }
            }
            packet = UnsafePointer(MIDIEventPacketNext(packet))
        }
        if !parsed.isEmpty { ingest(parsed) }
    }

    private func ingest(_ messages: [MIDIMessage]) {
        // Update the caches and queue under the lock; collect any bindings to
        // apply, then write the params *outside* the lock so the param's own lock
        // is never nested under this one.
        let toApply: [(ParamBinding, Double)] = state.withLock { state in
            var collected: [(ParamBinding, Double)] = []
            for message in messages {
                switch message.kind {
                case .controlChange(let controller, let value):
                    state.latestControl[ControlKey(channel: message.channel, controller: controller)] = value
                    state.latestControl[ControlKey(channel: 0, controller: controller)] = value   // "any channel"
                    let exact = ControlKey(channel: message.channel, controller: controller)
                    let wildcard = ControlKey(channel: 0, controller: controller)
                    if let binding = state.bindings[exact] ?? state.bindings[wildcard] {
                        collected.append((binding, Double(value)))
                    }
                case .noteOn(let note, _):
                    state.heldNotes.insert(NoteKey(channel: message.channel, note: note))
                case .noteOff(let note, _):
                    state.heldNotes.remove(NoteKey(channel: message.channel, note: note))
                default:
                    break
                }
                state.inbox.append(message)
            }
            if state.inbox.count > inboxLimit {
                state.inbox.removeFirst(state.inbox.count - inboxLimit)
            }
            return collected
        }
        for (binding, raw) in toApply {
            binding.param.wrappedValue = MIDIInput.map(raw, from: binding.input, to: binding.param.range)
        }
    }

    private static func map(_ value: Double, from input: ClosedRange<Double>, to output: ClosedRange<Double>) -> Double {
        let span = input.upperBound - input.lowerBound
        guard span != 0 else { return output.lowerBound }
        let t = (value - input.lowerBound) / span
        return output.lowerBound + t * (output.upperBound - output.lowerBound)
    }

    deinit { stop() }
}
