import Foundation
import os
@testable import OllinRoom

// A room that lives in one process: no socket, no permission prompt, no timing
// slop. Messages are handed over as they are sent, so a test can put two whole
// rooms together and read the result on the next line.

final class MemoryRoomBus: @unchecked Sendable {

    private let members = OSAllocatedUnfairLock(initialState: [String: MemoryRoomTransport]())

    /// Runs before each delivery. A clock test uses it to make time pass between
    /// a question and its answer.
    let beforeDelivery = OSAllocatedUnfairLock<(@Sendable () -> Void)?>(uncheckedState: nil)

    func join(_ transport: MemoryRoomTransport) {
        members.withLock { $0[transport.peerName] = transport }
        announce()
    }

    func leave(_ name: String) {
        members.withLock { $0[name] = nil }
        announce()
    }

    /// Tells every member who else is present. The lock is dropped first, because
    /// a member answers by sending, which comes straight back through this bus.
    private func announce() {
        let all = members.withLock { Array($0.values) }
        for member in all {
            member.report(all.map(\.peerName).filter { $0 != member.peerName })
        }
    }

    /// While this is on, messages wait instead of arriving, which is how a test
    /// makes two machines act before either has heard the other.
    private let held = OSAllocatedUnfairLock<(on: Bool, queue: [(Data, String, [String])])>(
        uncheckedState: (false, [])
    )

    func hold() { held.withLock { $0.on = true } }

    /// Delivers everything that waited, oldest first.
    func flush() {
        let waiting = held.withLock { current -> [(Data, String, [String])] in
            current.on = false
            let queued = current.queue
            current.queue = []
            return queued
        }
        for (data, sender, peers) in waiting { deliver(data, from: sender, to: peers) }
    }

    func send(_ data: Data, from sender: String, to peers: [String]) {
        let waiting = held.withLock { current -> Bool in
            guard current.on else { return false }
            current.queue.append((data, sender, peers))
            return true
        }
        guard !waiting else { return }
        deliver(data, from: sender, to: peers)
    }

    private func deliver(_ data: Data, from sender: String, to peers: [String]) {
        let all = members.withLock { $0 }
        let targets = peers.isEmpty ? all.keys.filter { $0 != sender } : peers
        for name in targets {
            guard let target = all[name] else { continue }
            beforeDelivery.withLock { $0 }?()
            target.deliver(data, from: sender)
        }
    }
}

final class MemoryRoomTransport: RoomTransport, @unchecked Sendable {

    let peerName: String
    private let bus: MemoryRoomBus
    private let state = OSAllocatedUnfairLock<(handler: RoomTransportHandler?, peers: [String])>(
        uncheckedState: (nil, [])
    )

    init(name: String, bus: MemoryRoomBus) {
        peerName = name
        self.bus = bus
    }

    var connectedPeers: [String] { state.withLock { $0.peers } }

    func start(_ handler: RoomTransportHandler) {
        state.withLock { $0.handler = handler }
        bus.join(self)
    }

    func stop() {
        bus.leave(peerName)
        state.withLock { $0 = (nil, []) }
    }

    func send(_ data: Data, reliable: Bool, to peers: [String]) {
        bus.send(data, from: peerName, to: peers)
    }

    func deliver(_ data: Data, from sender: String) {
        state.withLock { $0.handler }?.received(data, sender)
    }

    func report(_ peers: [String]) {
        let handler = state.withLock { current -> RoomTransportHandler? in
            current.peers = peers
            return current.handler
        }
        handler?.peersChanged(peers)
    }
}

/// A clock a test winds by hand.
final class TestClock: @unchecked Sendable {
    private let value = OSAllocatedUnfairLock(initialState: 0.0)

    init(_ start: Double = 0) { value.withLock { $0 = start } }

    var now: Double { value.withLock { $0 } }

    func advance(_ seconds: Double) { value.withLock { $0 += seconds } }

    /// The reader a session takes.
    var reader: @Sendable () -> Double { { [value] in value.withLock { $0 } } }
}
