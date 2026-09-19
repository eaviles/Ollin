import Foundation
import Network
import Ollin
import os

/// What can go wrong before a connection is even attempted. A bad topic or
/// filter is not here: those are passed in from `draw()`, where throwing is
/// hostile, so a publish to a topic holding a wildcard and a subscription to a
/// filter a broker would refuse both do nothing instead.
public enum MQTTError: Error, Sendable, Equatable {
    /// The port number was outside `1...65535`.
    case invalidPort
}

/// A client on an MQTT broker: the message bus a building speaks.
///
/// Sensors publish to topics, switches subscribe to them, and a broker in the
/// middle carries one to the other. That is the whole protocol, and it is why a
/// sketch joins it: you subscribe to `home/+/temperature` and the room's readings
/// arrive, you publish to `home/lamp/set` and the lamp turns on.
///
/// ```swift
/// let bus = MQTTClient(host: "localhost")
///
/// override func setup() {
///     try? bus.connect()
///     bus.subscribe(to: "home/+/temperature")
/// }
///
/// override func draw() {
///     let warmth = bus.number("home/kitchen/temperature", default: 20)
///     background(Color.blue.mixed(with: .red, (warmth - 15) / 15))
///     if mouseIsPressed { bus.publish("home/lamp/set", "ON") }
/// }
/// ```
///
/// Reading works the two ways every input in Ollin does. A value that is
/// published over and over is read at its latest, with `number(_:default:)` and
/// its siblings; something that happens once is drained from `messages()`, in
/// arrival order, every frame.
///
/// The connection looks after itself. A broker that goes away is reconnected to
/// with a backing-off delay, and the subscriptions and any unacknowledged
/// messages go back up with it, so a sketch left running for a week does not need
/// to know that the network blinked.
///
/// Packets arrive on a background queue and the sketch reads on the main thread;
/// everything shared is held behind locks, which is what makes that safe.
public final class MQTTClient: @unchecked Sendable {

    // MARK: Configuration

    /// The broker's host name or address.
    public let host: String
    /// The broker's port. 1883 is the standard unencrypted one.
    public let port: Int
    /// The name this client is known by on the broker. Two clients sharing one
    /// name push each other off, so it defaults to a name of its own.
    public let clientID: String
    /// How long the line may stay quiet before the client sends a heartbeat, in
    /// seconds. The broker drops a client it has not heard from in one and a half
    /// of these.
    public let keepAlive: Double
    /// Whether a lost connection is reopened on its own.
    public let reconnects: Bool

    private let username: String?
    private let password: String?
    private let will: MQTTWill?

    private let queue = DispatchQueue(label: "com.ollin.mqtt.client")

    // MARK: Stored state

    private struct ParamBinding: Sendable {
        let input: ClosedRange<Double>
        let output: ClosedRange<Double>
        let write: @Sendable (Double) -> Void
    }

    private struct State: Sendable {
        var wantsConnection = false
        var isConnected = false
        var latest: [String: MQTTMessage] = [:]
        var inbox: [MQTTMessage] = []
        var subscriptions: [String: MQTTQoS] = [:]
        var bindings: [String: ParamBinding] = [:]
        /// Quality-of-service 1 publishes still waiting for their acknowledgement,
        /// in the order they were sent, so a reconnection resends them in order.
        var unacknowledged: [(id: UInt16, publish: MQTTPublish)] = []
        var nextID: UInt16 = 1
        var inbound = Data()
        var attempt = 0
        var lastSentAt = Date.distantPast
        var lastHeardAt = Date.distantPast
        var failure: String?
        var connections = 0
        /// Set when the broker answered a CONNECT with a refusal. A refusal is an
        /// answer, so nothing after it may overwrite the reason or reconnect.
        var wasRefused = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let connectionStore = OSAllocatedUnfairLock<NWConnection?>(uncheckedState: nil)
    private let timerStore = OSAllocatedUnfairLock<DispatchSourceTimer?>(uncheckedState: nil)

    /// Cap on undrained messages, so a sketch that never calls `messages()` does
    /// not grow the inbox without bound; the oldest are dropped past it.
    private let inboxLimit = 4096
    /// Cap on unacknowledged publishes, so a broker that never answers cannot
    /// grow the resend list without bound.
    private let unacknowledgedLimit = 1024

    // MARK: Lifecycle

    /// Creates a client for a broker. Nothing happens on the network until
    /// `connect()` is called.
    ///
    /// - Parameters:
    ///   - host: the broker's host name or address.
    ///   - port: the broker's port, 1883 by default.
    ///   - clientID: the name this client takes on the broker. A fresh one each
    ///     run by default, so two copies of a sketch do not fight over it.
    ///   - username: a user name, when the broker asks for one.
    ///   - password: the password beside it.
    ///   - will: what the broker publishes if this client vanishes without
    ///     saying goodbye.
    ///   - keepAlive: how long the line may stay quiet, in seconds.
    ///   - reconnects: whether a lost connection is reopened on its own.
    public init(host: String,
                port: Int = 1883,
                clientID: String = MQTTClient.randomClientID(),
                username: String? = nil,
                password: String? = nil,
                will: MQTTWill? = nil,
                keepAlive: Double = 30,
                reconnects: Bool = true) {
        self.host = host
        self.port = port
        self.clientID = clientID
        self.username = username
        self.password = password
        self.will = will
        self.keepAlive = max(1, keepAlive)
        self.reconnects = reconnects
    }

    /// A client name no other run will pick: a fixed prefix and a random tail,
    /// inside the 23 characters every broker must accept. It is the default
    /// `clientID`, since two clients sharing one name push each other off.
    public static func randomClientID() -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
        let tail = String((0..<8).map { _ in alphabet.randomElement() ?? "0" })
        return "ollin-" + tail
    }

    /// Whether the broker has accepted this client and the session is live.
    /// False between a dropped connection and the reconnection that follows.
    public var isConnected: Bool { state.withLock { $0.isConnected } }

    /// What went wrong the last time something did, in words worth printing.
    /// `nil` when nothing has.
    public var lastError: String? { state.withLock { $0.failure } }

    /// Opens the connection and asks the broker for a session. Returns as soon as
    /// the attempt starts: `isConnected` turns true when the broker answers, which
    /// is usually within a frame or two on a local network.
    public func connect() throws {
        guard port > 0, let exact = UInt16(exactly: port),
              let nwPort = NWEndpoint.Port(rawValue: exact) else {
            throw MQTTError.invalidPort
        }
        let alreadyWanted = state.withLock { state -> Bool in
            let wanted = state.wantsConnection
            state.wantsConnection = true
            state.wasRefused = false
            return wanted
        }
        guard !alreadyWanted else { return }
        openConnection(to: nwPort)
        startHeartbeat()
    }

    /// Says goodbye and closes the connection. The broker discards the will,
    /// which is the difference between leaving and being cut off, and nothing
    /// reconnects afterwards until `connect()` is called again.
    public func disconnect() {
        state.withLock {
            $0.wantsConnection = false
            $0.isConnected = false
        }
        stopHeartbeat()
        let connection = connectionStore.withLock { stored -> NWConnection? in
            let value = stored
            stored = nil
            return value
        }
        guard let connection else { return }
        connection.send(content: MQTTPacket.disconnect.encode(),
                        completion: .contentProcessed { _ in connection.cancel() })
    }

    deinit {
        stopHeartbeat()
        connectionStore.withLock { $0 }?.cancel()
    }

    // MARK: Publishing

    /// Publishes text on a topic.
    ///
    /// At `MQTTQoS.atMostOnce`, a message published while the connection is down
    /// is gone: that is what at most once means, and a value published again in a
    /// moment is better served that way. At `MQTTQoS.atLeastOnce` it is held and
    /// sent when the connection comes back.
    ///
    /// - Parameters:
    ///   - topic: where to publish. No wildcards: a published topic is exact.
    ///   - text: the payload.
    ///   - qos: how hard to work at delivering it.
    ///   - retains: whether the broker should keep it as the topic's stored
    ///     value, handed to anyone who subscribes later.
    public func publish(_ topic: String, _ text: String,
                        qos: MQTTQoS = .atMostOnce, retains: Bool = false) {
        publish(topic, payload: Data(text.utf8), qos: qos, retains: retains)
    }

    /// Publishes a number on a topic, written the way a sensor writes one: plain
    /// decimal text, with no exponent and no trailing zeros.
    public func publish(_ topic: String, _ number: Double,
                        qos: MQTTQoS = .atMostOnce, retains: Bool = false) {
        publish(topic, MQTTClient.format(number), qos: qos, retains: retains)
    }

    /// Publishes a switch as the words a device expects: `ON` or `OFF`.
    public func publish(_ topic: String, _ on: Bool,
                        qos: MQTTQoS = .atMostOnce, retains: Bool = false) {
        publish(topic, on ? "ON" : "OFF", qos: qos, retains: retains)
    }

    /// Publishes raw bytes on a topic.
    public func publish(_ topic: String, payload: Data,
                        qos: MQTTQoS = .atMostOnce, retains: Bool = false) {
        guard !topic.isEmpty, !topic.contains("#"), !topic.contains("+") else { return }
        let base = MQTTPublish(topic: topic, payload: payload, qos: qos, retains: retains)
        if qos == .atMostOnce {
            send(.publish(base))
            return
        }
        let bytes: Data = state.withLock { state in
            var packet = base
            packet.id = MQTTClient.take(&state.nextID)
            state.unacknowledged.append((packet.id ?? 1, packet))
            if state.unacknowledged.count > unacknowledgedLimit {
                state.unacknowledged.removeFirst(state.unacknowledged.count - unacknowledgedLimit)
            }
            return MQTTPacket.publish(packet).encode()
        }
        send(bytes)
    }

    /// The decimal text a published number takes. `Double`'s own description
    /// would write `21.0` as `21.0` and `1e-05` in exponent form, and a device
    /// reading the topic wants neither.
    static func format(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        if value == value.rounded() && abs(value) < 1e15 {
            return String(Int64(value))
        }
        var text = String(format: "%.6f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    // MARK: Subscribing

    /// Subscribes to a filter, so everything published under it arrives.
    ///
    /// A filter is a topic with `+` standing for any one level and `#` for every
    /// level from there down: `home/+/temperature` takes every room's reading,
    /// `home/#` takes the lot. The subscription is remembered, so a reconnection
    /// puts it back without the sketch doing anything.
    public func subscribe(to filter: String, qos: MQTTQoS = .atMostOnce) {
        guard MQTTTopic.isValidFilter(filter) else { return }
        let bytes: Data? = state.withLock { state in
            state.subscriptions[filter] = qos
            guard state.isConnected else { return nil }
            let id = MQTTClient.take(&state.nextID)
            return MQTTPacket.subscribe(id: id, filters: [(filter, qos)]).encode()
        }
        if let bytes { send(bytes) }
    }

    /// Drops a subscription. Messages already drained stay where they are; the
    /// latest value the topic held is forgotten.
    public func unsubscribe(from filter: String) {
        let bytes: Data? = state.withLock { state in
            state.subscriptions[filter] = nil
            state.latest = state.latest.filter { !MQTTTopic.matches($0.key, filter: filter) }
            guard state.isConnected else { return nil }
            let id = MQTTClient.take(&state.nextID)
            return MQTTPacket.unsubscribe(id: id, filters: [filter]).encode()
        }
        if let bytes { send(bytes) }
    }

    /// The filters currently subscribed to, in no particular order.
    public var subscriptions: [String] { state.withLock { Array($0.subscriptions.keys) } }

    // MARK: Reading, the latest value

    /// The most recent message on an exact topic, or `nil` if none has arrived.
    public func message(_ topic: String) -> MQTTMessage? {
        state.withLock { $0.latest[topic] }
    }

    /// The most recent payload on a topic, read as text.
    public func text(_ topic: String) -> String? { message(topic)?.text }
    /// The most recent payload on a topic, read as a number.
    public func number(_ topic: String) -> Double? { message(topic)?.number }
    /// The most recent payload on a topic, read as a whole number.
    public func int(_ topic: String) -> Int? { message(topic)?.int }
    /// The most recent payload on a topic, read as a switch.
    public func bool(_ topic: String) -> Bool? { message(topic)?.bool }

    /// The most recent number on a topic, or `fallback` if nothing has arrived.
    public func number(_ topic: String, default fallback: Double) -> Double {
        number(topic) ?? fallback
    }
    /// The most recent whole number on a topic, or `fallback` if nothing has arrived.
    public func int(_ topic: String, default fallback: Int) -> Int { int(topic) ?? fallback }
    /// The most recent switch on a topic, or `fallback` if nothing has arrived.
    public func bool(_ topic: String, default fallback: Bool) -> Bool { bool(topic) ?? fallback }
    /// The most recent text on a topic, or `fallback` if nothing has arrived.
    public func text(_ topic: String, default fallback: String) -> String {
        text(topic) ?? fallback
    }

    /// Every topic a message has arrived on since the client connected.
    public var topics: [String] { state.withLock { Array($0.latest.keys) }.sorted() }

    /// The topics matching a filter, sorted. Reads what has already arrived, so
    /// it answers the question a sensor network asks: which rooms are reporting.
    public func topics(matching filter: String) -> [String] {
        topics.filter { MQTTTopic.matches($0, filter: filter) }
    }

    // MARK: Reading, the event drain

    /// Returns every message received since the last call and clears the queue.
    /// Call it once a frame in `draw()` to handle things that happen once, in
    /// arrival order.
    public func messages() -> [MQTTMessage] {
        state.withLock { state in
            let drained = state.inbox
            state.inbox.removeAll(keepingCapacity: true)
            return drained
        }
    }

    /// Returns the messages matching a filter and clears just those, leaving the
    /// rest for another reader. Two parts of a sketch can each drain their own
    /// topics without taking each other's.
    public func messages(matching filter: String) -> [MQTTMessage] {
        state.withLock { state in
            var taken: [MQTTMessage] = []
            var kept: [MQTTMessage] = []
            for message in state.inbox {
                if MQTTTopic.matches(message.topic, filter: filter) {
                    taken.append(message)
                } else {
                    kept.append(message)
                }
            }
            state.inbox = kept
            return taken
        }
    }

    // MARK: Parameter binding

    /// Drives a `@Param` from a topic: each message's number is mapped from
    /// `input` into the parameter's own range and assigned, clamped.
    ///
    /// ```swift
    /// bus.bind("home/dial/level", to: $radius)                  // 0…1 into the range
    /// bus.bind("home/kitchen/temperature", to: $warmth, from: 0...40)
    /// ```
    public func bind(_ topic: String, to param: Param<Double>,
                     from input: ClosedRange<Double> = 0...1) {
        let binding = ParamBinding(input: input, output: param.range) { param.wrappedValue = $0 }
        state.withLock { $0.bindings[topic] = binding }
    }

    /// Removes a binding previously set with `bind(_:to:from:)`.
    public func unbind(_ topic: String) {
        state.withLock { $0.bindings[topic] = nil }
    }

    /// How many times the client has been accepted by the broker, first
    /// connection included. A sketch that wants to know the line dropped can
    /// watch this rather than poll `isConnected` between frames.
    public var connectionCount: Int { state.withLock { $0.connections } }

    // MARK: The connection

    private func openConnection(to nwPort: NWEndpoint.Port) {
        let connection = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        connection.stateUpdateHandler = { [weak self] newState in
            guard let self else { return }
            switch newState {
            case .ready:
                self.state.withLock { $0.inbound.removeAll(keepingCapacity: true) }
                self.sendConnect()
                self.receive()
            case .failed(let error):
                self.drop("connection failed: \(error.localizedDescription)")
            case .cancelled:
                self.drop(nil)
            default:
                break
            }
        }
        connectionStore.withLock { $0 = connection }
        connection.start(queue: queue)
    }

    private func sendConnect() {
        let connect = MQTTConnect(clientID: clientID,
                                  cleanSession: true,
                                  keepAlive: UInt16(clamping: Int(keepAlive.rounded())),
                                  will: will,
                                  username: username,
                                  password: password)
        send(MQTTPacket.connect(connect))
    }

    /// The connection is gone. Report why if there is a why, forget the session,
    /// and line up another attempt if the sketch still wants one.
    private func drop(_ reason: String?) {
        let shouldRetry: Bool = state.withLock { state in
            if let reason, !state.wasRefused { state.failure = reason }
            state.isConnected = false
            state.inbound.removeAll(keepingCapacity: true)
            return state.wantsConnection && reconnects
        }
        connectionStore.withLock { stored in
            stored?.cancel()
            stored = nil
        }
        guard shouldRetry else { return }
        let delay: Double = state.withLock { state in
            state.attempt = min(state.attempt + 1, 6)
            // A quarter second doubling to eight, so a broker rebooting is waited
            // out without hammering it.
            return min(8, 0.25 * pow(2, Double(state.attempt - 1)))
        }
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            let stillWanted = self.state.withLock { $0.wantsConnection && !$0.isConnected }
            guard stillWanted, self.connectionStore.withLock({ $0 }) == nil else { return }
            guard let nwPort = NWEndpoint.Port(rawValue: UInt16(clamping: self.port)) else { return }
            self.openConnection(to: nwPort)
        }
    }

    private func send(_ packet: MQTTPacket) { send(packet.encode()) }

    private func send(_ bytes: Data) {
        guard let connection = connectionStore.withLock({ $0 }) else { return }
        state.withLock { $0.lastSentAt = Date() }
        connection.send(content: bytes, completion: .contentProcessed { _ in })
    }

    private func receive() {
        guard let connection = connectionStore.withLock({ $0 }) else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let error {
                self.drop("read failed: \(error.localizedDescription)")
                return
            }
            if let data, !data.isEmpty { self.ingest(data) }
            if isComplete {
                self.drop("the broker closed the connection")
                return
            }
            self.receive()
        }
    }

    /// Pull whole packets out of the incoming bytes and act on each. A packet
    /// arrives split across reads as often as not, which is why the buffer is
    /// kept rather than each read decoded on its own.
    private func ingest(_ data: Data) {
        let taken: (packets: [MQTTPacket], failure: String?) = state.withLock { state in
            var packets: [MQTTPacket] = []
            var failure: String?
            state.inbound.append(data)
            state.lastHeardAt = Date()
            while !state.inbound.isEmpty {
                do {
                    guard let one = try MQTTPacket.decode(from: state.inbound) else { break }
                    state.inbound.removeFirst(one.consumed)
                    packets.append(one.packet)
                } catch {
                    failure = "the broker sent something this client cannot read (\(error))"
                    state.inbound.removeAll(keepingCapacity: true)
                    break
                }
            }
            return (packets, failure)
        }
        for packet in taken.packets { handle(packet) }
        if let failure = taken.failure { drop(failure) }
    }

    private func handle(_ packet: MQTTPacket) {
        switch packet {
        case .connectAcknowledgement(_, let code):
            guard code == 0 else {
                state.withLock {
                    $0.failure = MQTTClient.refusal(code)
                    $0.wantsConnection = false
                    $0.wasRefused = true
                }
                connectionStore.withLock { stored in
                    stored?.cancel()
                    stored = nil
                }
                return
            }
            resumeSession()

        case .publish(let publish):
            if publish.qos == .atLeastOnce, let id = publish.id {
                send(.publishAcknowledgement(id: id))
            }
            deliver(MQTTMessage(topic: publish.topic, payload: publish.payload,
                                qos: publish.qos, isRetained: publish.retains,
                                isDuplicate: publish.isDuplicate))

        case .publishAcknowledgement(let id):
            state.withLock { $0.unacknowledged.removeAll { $0.id == id } }

        case .ping:
            // A broker has no business sending one, but answering costs nothing.
            send(.pingResponse)

        case .pingResponse, .subscribeAcknowledgement, .unsubscribeAcknowledgement:
            break

        case .disconnect:
            drop("the broker sent a disconnect")

        case .connect, .subscribe, .unsubscribe:
            // Packets only a client sends. A broker sending one is broken.
            drop("the broker sent a client packet")
        }
    }

    /// The session is live: put the subscriptions back and resend anything that
    /// was still unacknowledged when the line went down.
    private func resumeSession() {
        let bytes: [Data] = state.withLock { state in
            state.isConnected = true
            state.attempt = 0
            state.connections += 1
            state.lastHeardAt = Date()
            // The line is up, so whatever went wrong last time is over. Left
            // standing, it would say a live client was broken forever.
            state.failure = nil
            var out: [Data] = []
            if !state.subscriptions.isEmpty {
                let id = MQTTClient.take(&state.nextID)
                let filters = state.subscriptions.map { (filter: $0.key, qos: $0.value) }
                    .sorted { $0.filter < $1.filter }
                out.append(MQTTPacket.subscribe(id: id, filters: filters).encode())
            }
            for entry in state.unacknowledged {
                var again = entry.publish
                again.isDuplicate = true
                out.append(MQTTPacket.publish(again).encode())
            }
            return out
        }
        for packet in bytes { send(packet) }
    }

    private func deliver(_ message: MQTTMessage) {
        let binding: ParamBinding? = state.withLock { state in
            state.latest[message.topic] = message
            state.inbox.append(message)
            if state.inbox.count > inboxLimit {
                state.inbox.removeFirst(state.inbox.count - inboxLimit)
            }
            return state.bindings[message.topic]
        }
        if let binding, let raw = message.number {
            binding.write(MQTTClient.map(raw, from: binding.input, to: binding.output))
        }
    }

    // MARK: The heartbeat

    /// A timer at half the keep-alive: it sends a heartbeat when the line has
    /// gone quiet, and drops a connection that has stopped answering. Without it
    /// a broker hangs up on a sketch that only ever reads.
    private func startHeartbeat() {
        stopHeartbeat()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + keepAlive / 2, repeating: keepAlive / 2)
        timer.setEventHandler { [weak self] in self?.beat() }
        timerStore.withLock { $0 = timer }
        timer.resume()
    }

    private func stopHeartbeat() {
        let timer = timerStore.withLock { stored -> DispatchSourceTimer? in
            let value = stored
            stored = nil
            return value
        }
        timer?.cancel()
    }

    private func beat() {
        let now = Date()
        enum Action { case none, ping, dead }
        let action: Action = state.withLock { state in
            guard state.isConnected else { return .none }
            // One and a half keep-alives with nothing heard is a line that is
            // gone: the broker answers a heartbeat at once, so silence that long
            // has already outlasted one.
            if now.timeIntervalSince(state.lastHeardAt) > keepAlive * 1.5 { return .dead }
            if now.timeIntervalSince(state.lastSentAt) >= keepAlive * 0.75 { return .ping }
            return .none
        }
        switch action {
        case .none: break
        case .ping: send(.ping)
        case .dead: drop("the broker stopped answering")
        }
    }

    // MARK: Small shared pieces

    private static func take(_ next: inout UInt16) -> UInt16 {
        let id = next
        next = next == UInt16.max ? 1 : next + 1
        return id
    }

    private static func map(_ value: Double, from input: ClosedRange<Double>,
                            to output: ClosedRange<Double>) -> Double {
        let span = input.upperBound - input.lowerBound
        guard span != 0 else { return output.lowerBound }
        let t = (value - input.lowerBound) / span
        return output.lowerBound + t * (output.upperBound - output.lowerBound)
    }

    /// The words behind a refusal code, so `lastError` says what to fix.
    static func refusal(_ code: UInt8) -> String {
        switch code {
        case 1: return "the broker does not speak this version of the protocol"
        case 2: return "the broker rejected the client name"
        case 3: return "the broker is unavailable"
        case 4: return "the user name or password was wrong"
        case 5: return "this client is not authorized"
        default: return "the broker refused the connection (code \(code))"
        }
    }
}
