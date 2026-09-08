import CoreMIDI
import Foundation
import os

/// Sends MIDI out — to a hardware destination, or to a *virtual source* other
/// apps (and a same-process `MIDIInput`) can receive from. Create one in
/// `setup()`, open it, then send from `draw()`.
///
/// To a connected device:
///
/// ```swift
/// let out = MIDIOutput()
/// override func setup() { try? out.open(matching: "Grid") }   // first destination matching "Grid"
/// override func draw() { out.controlChange(7, value: Int(level * 127)) }
/// ```
///
/// As a virtual source (the hardware-free loopback an example or test uses — an
/// input connected to it receives what you send):
///
/// ```swift
/// try? out.openVirtual(named: "Ollin Loopback")
/// out.noteOn(60, velocity: 100)
/// ```
public final class MIDIOutput: @unchecked Sendable {

    private let clientName: String

    private struct CoreState: Sendable {
        var client = MIDIClientRef()
        var port = MIDIPortRef()              // for hardware-destination sends
        var destination = MIDIEndpointRef()   // the chosen hardware destination
        var virtualSource = MIDIEndpointRef() // for loopback sends
        var isVirtual = false
        var open = false
    }
    private let core = OSAllocatedUnfairLock(initialState: CoreState())

    /// Creates an output. `name` labels the Core MIDI client this Mac advertises.
    public init(name: String = "Ollin") {
        self.clientName = name
    }

    /// Whether the output has been opened.
    public var isOpen: Bool { core.withLock { $0.open } }

    /// The MIDI destinations currently visible on the system.
    public var destinations: [MIDIEndpoint] {
        (0..<MIDIGetNumberOfDestinations()).compactMap { index in
            let destination = MIDIGetDestination(index)
            return destination != 0 ? MIDIEndpoint(destination) : nil
        }
    }

    /// Opens an output to a hardware destination: the first one whose name
    /// contains `match` (case-insensitive), or the first available when `match` is
    /// `nil`. Throws if Core MIDI can't be opened.
    public func open(matching match: String? = nil) throws {
        guard !isOpen else { return }
        let client = try createClient()
        var port = MIDIPortRef()
        let status = MIDIOutputPortCreate(client, "\(clientName) Out" as CFString, &port)
        guard status == noErr else { MIDIClientDispose(client); throw MIDIError.coreMIDI(status) }
        let destination = MIDIOutput.pickDestination(matching: match)
        let openedClient = client, openedPort = port   // lets: a lock body can't capture a var
        core.withLock { core in
            core.client = openedClient
            core.port = openedPort
            core.destination = destination
            core.isVirtual = false
            core.open = true
        }
    }

    /// Opens the output as a virtual source other apps — and a `MIDIInput` in this
    /// same process — can receive from. The hardware-free path for loopback.
    /// Throws if Core MIDI can't be opened.
    public func openVirtual(named name: String? = nil) throws {
        guard !isOpen else { return }
        let client = try createClient()
        var source = MIDIEndpointRef()
        let status = MIDISourceCreateWithProtocol(client, (name ?? "\(clientName) Out") as CFString, ._1_0, &source)
        guard status == noErr else { MIDIClientDispose(client); throw MIDIError.coreMIDI(status) }
        let openedClient = client, openedSource = source   // lets: a lock body can't capture a var
        core.withLock { core in
            core.client = openedClient
            core.virtualSource = openedSource
            core.isVirtual = true
            core.open = true
        }
    }

    /// Disposes the port/source and client. Safe to call more than once.
    public func close() {
        let (client, port, source) = core.withLock { core -> (MIDIClientRef, MIDIPortRef, MIDIEndpointRef) in
            let snapshot = (core.client, core.port, core.virtualSource)
            core = CoreState()
            return snapshot
        }
        if port != 0 { MIDIPortDispose(port) }
        if source != 0 { MIDIEndpointDispose(source) }
        if client != 0 { MIDIClientDispose(client) }
    }

    // MARK: Sending

    /// Sends a message.
    public func send(_ message: MIDIMessage) { transmit(message) }

    /// Sends a note-on. `velocity` 1…127; `channel` 1…16.
    public func noteOn(_ note: Int, velocity: Int = 100, channel: Int = 1) {
        transmit(MIDIMessage(.noteOn(note: note, velocity: velocity), channel: channel))
    }

    /// Sends a note-off. `channel` 1…16.
    public func noteOff(_ note: Int, velocity: Int = 0, channel: Int = 1) {
        transmit(MIDIMessage(.noteOff(note: note, velocity: velocity), channel: channel))
    }

    /// Sends a control change (a knob/fader value). `value` 0…127; `channel` 1…16.
    public func controlChange(_ controller: Int, value: Int, channel: Int = 1) {
        transmit(MIDIMessage(.controlChange(controller: controller, value: value), channel: channel))
    }

    /// Sends a system exclusive message. `body` is the bytes between the
    /// exclusive's start and end (the 0xF0 and 0xF7 go on the wire around
    /// it); every byte must be under 0x80.
    public func send(sysEx body: [UInt8]) {
        // Six bytes to a packet: one complete packet for a short message, or
        // a start, any continues, and an end for a longer one.
        var words: [UInt32] = []
        let chunks = stride(from: 0, to: max(1, body.count), by: 6).map { Array(body.dropFirst($0).prefix(6)) }
        for (index, chunk) in chunks.enumerated() {
            let status: UInt32 = chunks.count == 1 ? 0x0 : index == 0 ? 0x1 : index == chunks.count - 1 ? 0x3 : 0x2
            var padded = chunk.map { UInt32($0 & 0x7F) }
            while padded.count < 6 { padded.append(0) }
            words.append((0x3 << 28) | (status << 20) | (UInt32(chunk.count) << 16) | (padded[0] << 8) | padded[1])
            words.append((padded[2] << 24) | (padded[3] << 16) | (padded[4] << 8) | padded[5])
        }
        transmit(words: words)
    }

    /// Sends a timecode whole, as the full-frame message a deck sends when it
    /// locates or stops; a `TimecodeClock` on the other end jumps to it.
    public func send(timecode: Timecode) {
        send(sysEx: timecode.fullFrameSysEx)
    }

    // MARK: Internals

    private func createClient() throws -> MIDIClientRef {
        var client = MIDIClientRef()
        let status = MIDIClientCreateWithBlock(clientName as CFString, &client, nil)
        guard status == noErr else { throw MIDIError.coreMIDI(status) }
        return client
    }

    private static func pickDestination(matching match: String?) -> MIDIEndpointRef {
        let count = MIDIGetNumberOfDestinations()
        guard count > 0 else { return 0 }
        if let match {
            for index in 0..<count {
                let destination = MIDIGetDestination(index)
                let name = MIDIEndpoint.stringProperty(destination, kMIDIPropertyDisplayName)
                    ?? MIDIEndpoint.stringProperty(destination, kMIDIPropertyName) ?? ""
                if name.localizedCaseInsensitiveContains(match) { return destination }
            }
        }
        return MIDIGetDestination(0)
    }

    /// Packs the message into a one-word MIDI 1.0 event list and emits it, either
    /// through the virtual source (loopback) or the output port (hardware).
    private func transmit(_ message: MIDIMessage) {
        transmit(words: [message.umpWord])
    }

    /// Emits Universal MIDI Packet words as one event list.
    private func transmit(words: [UInt32]) {
        // Read the endpoints out of the lock first (they're plain UInt32 refs),
        // then build and emit outside it: a lock body can't capture the `var`
        // event list the Core MIDI calls need by reference.
        let (isVirtual, source, port, destination) = core.withLock {
            ($0.isVirtual, $0.virtualSource, $0.port, $0.destination)
        }
        var words = words
        var list = MIDIEventList()
        let packet = MIDIEventListInit(&list, ._1_0)
        // Stamped with the actual host time rather than 0: both mean "send now",
        // but the real stamp gives an in-process receiver (the loopback path) a
        // precise emission time to derive tempo from.
        _ = MIDIEventListAdd(&list, MemoryLayout<MIDIEventList>.size, packet, mach_absolute_time(),
                             words.count, &words)
        if isVirtual {
            if source != 0 { MIDIReceivedEventList(source, &list) }
        } else if port != 0, destination != 0 {
            MIDISendEventList(port, destination, &list)
        }
    }

    deinit { close() }
}
