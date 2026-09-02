// RoomSession: everything the room does away from the sketch's own thread.
//
// Messages arrive on the transport's queue, so the state they touch lives behind
// one lock and the sketch reads it from `draw()`. The split follows the shipped
// rule for this kind of feature: a background producer, a main-thread reader, and
// a lock between them. The sketch-facing half is `Room`, which runs with the
// sketch on the main actor and owns nothing that a network callback touches.

import Foundation
import Ollin
import os

/// One shared parameter that arrived from another machine, waiting for the frame
/// boundary where it is applied.
struct IncomingParameter: Sendable {
    let name: String
    let stored: ParamStored
    /// When the other machine turned it, by the room's own clock.
    let turnedAt: Double
    let sender: String
}

/// What one machine in the room told us about itself.
struct RoomMember: Sendable, Equatable {
    /// The seat it asked for, or `nil` when it takes the seat its name gives it.
    var seat: Int?
    /// The name of the sketch it is running.
    var sketchName: String
}

final class RoomSession: @unchecked Sendable {

    private struct Binding: Sendable {
        let param: Param<Double>
        let input: ClosedRange<Double>
    }

    private struct State {
        var running = false
        /// Who the transport says is connected. Kept apart from `members` on
        /// purpose: a greeting can arrive before the transport reports the peer
        /// that sent it, and reading membership off the greetings would then make
        /// this machine think it had already greeted that peer, so its own
        /// greeting would never go out.
        var connected: Set<String> = []
        var members: [String: RoomMember] = [:]
        var joined: [String] = []
        var left: [String] = []
        /// How many machines have ever arrived. Read rather than drained, so the
        /// sketch's own `arrivals()` keeps working while the room notices a
        /// newcomer and sends it the shared parameters as they stand.
        var everJoined = 0
        var latest: [String: RoomMessage] = [:]
        var inbox: [RoomMessage] = []
        var bindings: [String: Binding] = [:]
        var incomingParameters: [IncomingParameter] = []
        var clock = RoomClock()
        var pings: [UInt32: Double] = [:]
        var nextPingID: UInt32 = 1
        var lastPingAt: Double = -.greatestFiniteMagnitude
        var owner: String?
        var problem: String?
        var seat: Int?
        var sketchName = ""
    }

    /// Cap on undrained arrivals, so a sketch that never drains does not grow
    /// without bound. The oldest are dropped past it.
    private let inboxLimit = 4096

    /// How often a follower asks the owner what time it is, once the answers have
    /// settled. Before that it asks four times a second, so a machine that just
    /// joined is in step within a couple of seconds rather than a minute.
    private let clockInterval: Double = 2
    private let clockTick: Double = 0.25

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let timerStore = OSAllocatedUnfairLock<DispatchSourceTimer?>(uncheckedState: nil)
    private let queue = DispatchQueue(label: "com.ollin.room.session")
    private let readClock: @Sendable () -> Double
    private let startedAt: Double

    let transport: RoomTransport

    /// `clock` reads this machine's own steady time in seconds. It is the machine's
    /// uptime in a running sketch, and something the tests drive by hand there.
    init(transport: RoomTransport, clock: @escaping @Sendable () -> Double = { ProcessInfo.processInfo.systemUptime }) {
        self.transport = transport
        readClock = clock
        startedAt = clock()
    }

    // MARK: Lifecycle

    var isRunning: Bool { state.withLock { $0.running } }

    func start(seat: Int?, sketchName: String) {
        guard !isRunning else { return }
        state.withLock {
            $0.running = true
            $0.seat = seat
            $0.sketchName = sketchName
            $0.owner = transport.peerName
        }
        // Built here rather than in the sketch's own method: a closure formed in a
        // main-actor context carries that isolation into the network thread that
        // calls it, and the check Swift inserts there stops the process.
        transport.start(RoomTransportHandler(
            received: { [weak self] data, peer in self?.receive(data, from: peer) },
            peersChanged: { [weak self] names in self?.membersChanged(to: names) },
            problem: { [weak self] problem in self?.state.withLock { $0.problem = problem } }
        ))
        startTimer()
    }

    func stop() {
        guard isRunning else { return }
        stopTimer()
        transport.stop()
        state.withLock {
            $0.running = false
            $0.connected = []
            $0.members = [:]
            $0.pings = [:]
            $0.owner = nil
            $0.clock.reset()
        }
    }

    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + clockTick, repeating: clockTick)
        timer.setEventHandler { [weak self] in self?.pumpClock() }
        timerStore.withLock { $0 = timer }
        timer.resume()
    }

    private func stopTimer() {
        let timer = timerStore.withLock { stored -> DispatchSourceTimer? in
            let previous = stored
            stored = nil
            return previous
        }
        timer?.cancel()
    }

    deinit {
        stopTimer()
        // A live reload builds a fresh sketch, so the old room has to leave
        // rather than sit there as a member nobody is drawing.
        transport.stop()
    }

    // MARK: Membership

    var peerName: String { transport.peerName }

    /// What each connected machine said about itself.
    var members: [String: RoomMember] {
        state.withLock { state in
            state.members.filter { state.connected.contains($0.key) }
        }
    }

    var peers: [String] { state.withLock { $0.connected.sorted() } }

    var problem: String? { state.withLock { $0.problem } }

    /// Every machine in the room, this one included, in the order every machine
    /// agrees on.
    var everyone: [String] {
        let names = state.withLock { $0.connected }
        return (Array(names) + [transport.peerName]).sorted()
    }

    /// This machine's seat: the one it asked for, or its place in the sorted list
    /// of names when it asked for none.
    var seat: Int {
        let (declared, names) = state.withLock { state -> (Int?, Set<String>) in
            (state.seat, state.connected)
        }
        if let declared { return declared }
        let sorted = (Array(names) + [transport.peerName]).sorted()
        return sorted.firstIndex(of: transport.peerName) ?? 0
    }

    /// How many seats the room has: one per machine, or one past the highest seat
    /// anybody asked for, whichever is larger.
    var seatCount: Int {
        let (declared, connected, members) = state.withLock { state -> (Int?, Set<String>, [String: RoomMember]) in
            (state.seat, state.connected, state.members)
        }
        var highest = declared ?? 0
        for (name, member) in members where connected.contains(name) {
            if let seat = member.seat { highest = max(highest, seat) }
        }
        return max(connected.count + 1, highest + 1)
    }

    /// How many machines have ever joined, counted rather than drained.
    var everJoined: Int { state.withLock { $0.everJoined } }

    func drainJoined() -> [String] {
        state.withLock { state in
            let drained = state.joined
            state.joined.removeAll(keepingCapacity: true)
            return drained
        }
    }

    func drainLeft() -> [String] {
        state.withLock { state in
            let drained = state.left
            state.left.removeAll(keepingCapacity: true)
            return drained
        }
    }

    private func membersChanged(to names: [String]) {
        let (hello, arrivals) = state.withLock { state -> (Data?, [String]) in
            let now = Set(names)
            for gone in state.connected.subtracting(now) {
                state.members[gone] = nil
                state.left.append(gone)
            }
            let arrivals = Array(now.subtracting(state.connected))
            state.joined.append(contentsOf: arrivals)
            state.everJoined += arrivals.count
            state.connected = now
            guard !arrivals.isEmpty else { return (nil, []) }
            return (RoomWire.encodeHello(seat: state.seat, sketchName: state.sketchName), arrivals)
        }
        // Said to the machines that just arrived, so a room that grows one
        // machine at a time does not tell the whole room again each time.
        if let hello { transport.send(hello, reliable: true, to: arrivals) }
        electClockOwner()
    }

    /// Works out who owns the clock, and forgets the old answers when it changes.
    private func electClockOwner() {
        let names = everyone
        let elected = RoomClock.owner(among: names)
        state.withLock { state in
            guard state.owner != elected else { return }
            state.owner = elected
            state.pings.removeAll(keepingCapacity: true)
            // The offset survives this: see RoomClock.offset.
            state.clock.reset()
        }
    }

    // MARK: Time

    /// Seconds since this machine started its room.
    var elapsed: Double { readClock() - startedAt }

    /// The time the whole room agrees on.
    var time: Double { elapsed + state.withLock { $0.clock.offset } }

    /// Whether this machine owns the clock the room runs on.
    var ownsClock: Bool {
        state.withLock { $0.owner } == transport.peerName
    }

    /// How far room time can be from the owner's, or `nil` before the first
    /// answer. Zero on the machine that owns the clock.
    var clockError: Double? {
        if ownsClock { return 0 }
        return state.withLock { $0.clock.error }
    }

    /// Sends one clock question when it is time for one. Runs on the timer, and
    /// the tests call it directly.
    func pumpClock() {
        let now = elapsed
        let question = state.withLock { state -> (Data, String)? in
            guard state.running, let owner = state.owner, owner != transport.peerName else { return nil }
            let settled = state.clock.samples.count >= RoomClock.sampleLimit
            let due = now - state.lastPingAt >= (settled ? clockInterval : clockTick)
            guard due else { return nil }
            let id = state.nextPingID
            state.nextPingID &+= 1
            state.pings[id] = now
            state.lastPingAt = now
            // A question nobody answered is not worth keeping.
            if state.pings.count > 32 {
                let stale = state.pings.filter { now - $0.value > 10 }.map(\.key)
                for key in stale { state.pings[key] = nil }
            }
            return (RoomWire.encodeClockPing(id: id), owner)
        }
        guard let question else { return }
        transport.send(question.0, reliable: false, to: [question.1])
    }

    // MARK: Sending

    func send(_ key: String, _ value: RoomValue, reliable: Bool, to peers: [String]) {
        guard isRunning else { return }
        transport.send(RoomWire.encodeValue(key: key, value: value), reliable: reliable, to: peers)
    }

    func send(parameter name: String, _ stored: ParamStored, turnedAt: Double) {
        guard isRunning,
              let frame = RoomWire.encodeParameter(name: name, stored: stored, turnedAt: turnedAt) else { return }
        transport.send(frame, reliable: true, to: [])
    }

    // MARK: Reading

    func message(_ key: String) -> RoomMessage? { state.withLock { $0.latest[key] } }

    func messages() -> [RoomMessage] {
        state.withLock { state in
            let drained = state.inbox
            state.inbox.removeAll(keepingCapacity: true)
            return drained
        }
    }

    func bind(_ key: String, to param: Param<Double>, from input: ClosedRange<Double>) {
        state.withLock { $0.bindings[key] = Binding(param: param, input: input) }
    }

    func unbind(_ key: String) {
        state.withLock { $0.bindings[key] = nil }
    }

    func drainIncomingParameters() -> [IncomingParameter] {
        state.withLock { state in
            let drained = state.incomingParameters
            state.incomingParameters.removeAll(keepingCapacity: true)
            return drained
        }
    }

    // MARK: Receiving

    /// Reads one message. The transport's queue is the only caller in a running
    /// sketch; the tests call it directly.
    func receive(_ data: Data, from peer: String) {
        guard let (kind, payload) = RoomWire.unframe(data) else { return }
        switch kind {
        case .hello:
            guard let hello = RoomWire.decodeHello(payload) else { return }
            state.withLock { $0.members[peer] = RoomMember(seat: hello.seat, sketchName: hello.sketchName) }
        case .value:
            guard let decoded = RoomWire.decodeValue(payload) else { return }
            ingest(RoomMessage(key: decoded.key, value: decoded.value, sender: peer))
        case .parameter:
            guard let parameter = RoomWire.decodeParameter(payload) else { return }
            state.withLock {
                $0.incomingParameters.append(IncomingParameter(
                    name: parameter.name, stored: parameter.stored, turnedAt: parameter.turnedAt, sender: peer
                ))
            }
        case .clockPing:
            guard let id = RoomWire.decodeClockPing(payload) else { return }
            // Answered from here rather than from a queue, so the time reported is
            // as close as possible to the time it is sent.
            guard ownsClock else { return }
            transport.send(RoomWire.encodeClockPong(id: id, roomTime: time), reliable: false, to: [peer])
        case .clockPong:
            guard let pong = RoomWire.decodeClockPong(payload) else { return }
            let arrived = elapsed
            state.withLock { state in
                guard state.owner == peer, let sentAt = state.pings.removeValue(forKey: pong.id) else { return }
                guard let sample = RoomClock.sample(sentAt: sentAt, receivedAt: arrived, ownerTime: pong.roomTime) else { return }
                state.clock.add(sample)
            }
        }
    }

    private func ingest(_ message: RoomMessage) {
        // The binding is read under the lock and applied outside it, so the
        // parameter's own lock is never taken inside this one.
        let binding: Binding? = state.withLock { state in
            state.latest[message.key] = message
            state.inbox.append(message)
            if state.inbox.count > inboxLimit {
                state.inbox.removeFirst(state.inbox.count - inboxLimit)
            }
            return state.bindings[message.key]
        }
        if let binding, let raw = message.number {
            binding.param.wrappedValue = RoomSession.map(raw, from: binding.input, to: binding.param.range)
        }
    }

    static func map(_ value: Double, from input: ClosedRange<Double>, to output: ClosedRange<Double>) -> Double {
        let span = input.upperBound - input.lowerBound
        guard span != 0 else { return output.lowerBound }
        let t = (value - input.lowerBound) / span
        return output.lowerBound + t * (output.upperBound - output.lowerBound)
    }
}
