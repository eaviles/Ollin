import Foundation
import Network
import os
@testable import OllinMQTT

/// An MQTT broker small enough to live in the test process, speaking the same
/// 3.1.1 wire format the client does over the loopback.
///
/// It exists because `mosquitto` is not installed on the machine these tests run
/// on, and because a real broker cannot be asked to do the things the interesting
/// laws need: cut a socket without warning so a will fires, sit on an
/// acknowledgement so a resend can be seen, refuse a connection with a chosen
/// code. It keeps retained values, fans a publish out to every matching
/// subscription (the publisher included, which is what makes a round trip a round
/// trip), and answers a heartbeat.
final class MQTTStubBroker: @unchecked Sendable {

    /// One connected client, with what the session holds for it. Every field is
    /// touched on the broker's own serial queue and nowhere else, which is what
    /// makes the unchecked conformance true.
    private final class Session: @unchecked Sendable {
        let connection: NWConnection
        var inbound = Data()
        var subscriptions: [String: MQTTQoS] = [:]
        var will: MQTTWill?
        var clientID = ""
        /// Set when the client said goodbye, which is what cancels the will.
        var leftCleanly = false

        init(_ connection: NWConnection) { self.connection = connection }
    }

    private struct Record: Sendable {
        var connects: [MQTTConnect] = []
        var publishes: [MQTTPublish] = []
        var subscribed: [(filter: String, qos: MQTTQoS)] = []
        var unsubscribed: [String] = []
        var acknowledgements: [UInt16] = []
        var pings = 0
        var goodbyes = 0
        var willsFired: [MQTTMessage] = []
    }

    private let queue = DispatchQueue(label: "com.ollin.mqtt.stub")
    private let listenerStore = OSAllocatedUnfairLock<NWListener?>(uncheckedState: nil)
    private let sessionsStore = OSAllocatedUnfairLock<[ObjectIdentifier: Session]>(uncheckedState: [:])
    private let retainedStore = OSAllocatedUnfairLock<[String: MQTTPublish]>(initialState: [:])
    private let record = OSAllocatedUnfairLock(initialState: Record())
    private let portStore = OSAllocatedUnfairLock<UInt16?>(initialState: nil)
    private let settings = OSAllocatedUnfairLock(initialState: Settings())

    private struct Settings: Sendable {
        var refusalCode: UInt8 = 0
        var holdsAcknowledgements = false
        var grantedQoS: UInt8?
    }

    /// The code the broker answers a CONNECT with. `0` accepts.
    var refusalCode: UInt8 {
        get { settings.withLock { $0.refusalCode } }
        set { settings.withLock { $0.refusalCode = newValue } }
    }

    /// When true, a quality-of-service 1 publish is recorded but never
    /// acknowledged, which is how the resend law is set up.
    var holdsAcknowledgements: Bool {
        get { settings.withLock { $0.holdsAcknowledgements } }
        set { settings.withLock { $0.holdsAcknowledgements = newValue } }
    }

    // MARK: Lifecycle

    func start() throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredInterfaceType = .loopback
        let listener = try NWListener(using: parameters, on: .any)
        listener.stateUpdateHandler = { [weak self] state in
            guard let self, case .ready = state else { return }
            self.portStore.withLock { $0 = self.listenerStore.withLock { $0?.port?.rawValue } }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listenerStore.withLock { $0 = listener }
        listener.start(queue: queue)
    }

    func stop() {
        let listener = listenerStore.withLock { stored -> NWListener? in
            let value = stored
            stored = nil
            return value
        }
        listener?.cancel()
        let sessions = sessionsStore.withLock { stored -> [Session] in
            let values = Array(stored.values)
            stored = [:]
            return values
        }
        for session in sessions { session.connection.cancel() }
    }

    /// The port the listener took, once it is ready.
    var port: Int? { portStore.withLock { $0 }.map(Int.init) }

    /// How many clients are connected right now.
    var clientCount: Int { sessionsStore.withLock { $0.count } }

    // MARK: What it saw

    var connects: [MQTTConnect] { record.withLock { $0.connects } }
    var publishes: [MQTTPublish] { record.withLock { $0.publishes } }
    var subscribed: [(filter: String, qos: MQTTQoS)] { record.withLock { $0.subscribed } }
    var unsubscribed: [String] { record.withLock { $0.unsubscribed } }
    var acknowledgements: [UInt16] { record.withLock { $0.acknowledgements } }
    var pings: Int { record.withLock { $0.pings } }
    var goodbyes: Int { record.withLock { $0.goodbyes } }
    var willsFired: [MQTTMessage] { record.withLock { $0.willsFired } }

    /// The retained value a topic holds, if any.
    func retained(_ topic: String) -> MQTTPublish? { retainedStore.withLock { $0[topic] } }

    // MARK: What it can be told to do

    /// Publishes as the broker itself, to every matching subscription.
    func publish(_ topic: String, _ text: String,
                 qos: MQTTQoS = .atMostOnce, retains: Bool = false) {
        let publish = MQTTPublish(topic: topic, payload: Data(text.utf8), qos: qos, retains: retains)
        queue.async { self.deliver(publish) }
    }

    /// Cuts every client's socket with no goodbye, the way a broker restarting
    /// or a network dropping does. Wills fire.
    func dropClients() {
        let sessions = sessionsStore.withLock { Array($0.values) }
        for session in sessions {
            queue.async { self.close(session, cleanly: false) }
        }
    }

    // MARK: The connection

    private func accept(_ connection: NWConnection) {
        let session = Session(connection)
        sessionsStore.withLock { $0[ObjectIdentifier(session)] = session }
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.close(session, cleanly: false)
            default: break
            }
        }
        connection.start(queue: queue)
        receive(session)
    }

    private func receive(_ session: Session) {
        session.connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty { self.ingest(data, into: session) }
            if isComplete || error != nil {
                self.close(session, cleanly: session.leftCleanly)
                return
            }
            self.receive(session)
        }
    }

    private func ingest(_ data: Data, into session: Session) {
        session.inbound.append(data)
        while !session.inbound.isEmpty {
            guard let taken = try? MQTTPacket.decode(from: session.inbound) else { break }
            session.inbound.removeFirst(taken.consumed)
            handle(taken.packet, from: session)
        }
    }

    private func handle(_ packet: MQTTPacket, from session: Session) {
        switch packet {
        case .connect(let connect):
            record.withLock { $0.connects.append(connect) }
            session.clientID = connect.clientID
            session.will = connect.will
            let code = settings.withLock { $0.refusalCode }
            if code == 0 {
                write(.connectAcknowledgement(sessionPresent: false, code: code), to: session)
            } else {
                // Close only once the refusal is actually on the wire: cancelling a
                // connection with a send still queued loses it, and the client then
                // sees a closed socket with no reason in it.
                session.connection.send(
                    content: MQTTPacket.connectAcknowledgement(sessionPresent: false, code: code).encode(),
                    completion: .contentProcessed { _ in
                        self.queue.asyncAfter(deadline: .now() + 0.05) {
                            self.close(session, cleanly: true)
                        }
                    })
            }

        case .publish(let publish):
            record.withLock { $0.publishes.append(publish) }
            if publish.qos == .atLeastOnce, let id = publish.id {
                if !settings.withLock({ $0.holdsAcknowledgements }) {
                    write(.publishAcknowledgement(id: id), to: session)
                }
            }
            deliver(publish)

        case .subscribe(let id, let filters):
            var codes: [UInt8] = []
            for entry in filters {
                session.subscriptions[entry.filter] = entry.qos
                record.withLock { $0.subscribed.append(entry) }
                codes.append(settings.withLock { $0.grantedQoS } ?? UInt8(entry.qos.rawValue))
            }
            write(.subscribeAcknowledgement(id: id, codes: codes), to: session)
            // A fresh subscription is handed the value every matching topic holds,
            // which is the one piece of broker behavior a sketch leans on at start.
            let retained = retainedStore.withLock { $0 }
            for entry in filters {
                for (topic, stored) in retained where MQTTTopic.matches(topic, filter: entry.filter) {
                    var copy = stored
                    copy.qos = .atMostOnce
                    copy.id = nil
                    copy.retains = true
                    write(.publish(copy), to: session)
                }
            }

        case .unsubscribe(let id, let filters):
            for filter in filters {
                session.subscriptions[filter] = nil
                record.withLock { $0.unsubscribed.append(filter) }
            }
            write(.unsubscribeAcknowledgement(id: id), to: session)

        case .publishAcknowledgement(let id):
            record.withLock { $0.acknowledgements.append(id) }

        case .ping:
            record.withLock { $0.pings += 1 }
            write(.pingResponse, to: session)

        case .disconnect:
            record.withLock { $0.goodbyes += 1 }
            session.leftCleanly = true
            session.will = nil
            close(session, cleanly: true)

        default:
            break
        }
    }

    /// Fans a publish out to every session subscribed to a matching filter, and
    /// stores it when it is retained.
    private func deliver(_ publish: MQTTPublish) {
        if publish.retains {
            retainedStore.withLock { stored in
                if publish.payload.isEmpty {
                    stored[publish.topic] = nil       // an empty retained payload clears it
                } else {
                    stored[publish.topic] = publish
                }
            }
        }
        let sessions = sessionsStore.withLock { Array($0.values) }
        for session in sessions {
            let level = session.subscriptions
                .filter { MQTTTopic.matches(publish.topic, filter: $0.key) }
                .map(\.value)
                .max(by: { $0.rawValue < $1.rawValue })
            guard let level else { continue }
            var out = publish
            // The broker delivers at the lower of what was published and what was
            // asked for, and a delivered message is never marked retained unless
            // it is a stored value being handed to a new subscriber.
            out.qos = MQTTQoS(rawValue: min(publish.qos.rawValue, level.rawValue)) ?? .atMostOnce
            out.retains = false
            out.isDuplicate = false
            out.id = out.qos == .atMostOnce ? nil : UInt16.random(in: 1...30000)
            write(.publish(out), to: session)
        }
    }

    private func write(_ packet: MQTTPacket, to session: Session) {
        session.connection.send(content: packet.encode(), completion: .contentProcessed { _ in })
    }

    private func close(_ session: Session, cleanly: Bool) {
        let known = sessionsStore.withLock { stored -> Bool in
            stored.removeValue(forKey: ObjectIdentifier(session)) != nil
        }
        guard known else { return }
        if !cleanly, let will = session.will {
            record.withLock {
                $0.willsFired.append(MQTTMessage(topic: will.topic, payload: will.payload,
                                                 qos: will.qos, isRetained: will.retains))
            }
            deliver(MQTTPublish(topic: will.topic, payload: will.payload,
                                qos: will.qos, retains: will.retains))
        }
        session.connection.cancel()
    }
}
