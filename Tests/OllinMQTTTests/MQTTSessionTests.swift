import Foundation
import Testing
import Ollin
@testable import OllinMQTT

/// A whole session against the in-process broker on the loopback: connecting,
/// subscribing, both service levels, retained values, the will, the heartbeat,
/// and what happens when the line drops.
///
/// Each test takes its own broker on an ephemeral port, so they are independent
/// and run in parallel. No GPU, so these run in CI too.
@Suite
struct MQTTSessionTests {

    struct Timeout: Error {}

    /// Polls `probe` until it returns a value or the timeout elapses.
    ///
    /// The probe comes before the clock is read: a starved task can wake past its
    /// own deadline having never looked, and giving up then throws over a message
    /// that already arrived.
    func waitFor<T>(timeout: Double = 5.0, _ probe: () -> T?) async throws -> T {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let value = probe() { return value }
            if Date() >= deadline { throw Timeout() }
            try await Task.sleep(nanoseconds: 5_000_000)   // 5 ms
        }
    }

    /// A broker listening on a loopback port of its own.
    func makeBroker() async throws -> MQTTStubBroker {
        let broker = MQTTStubBroker()
        try broker.start()
        _ = try await waitFor { broker.port }
        return broker
    }

    /// A broker with a client already connected to it.
    func makePair(will: MQTTWill? = nil, keepAlive: Double = 30,
                  reconnects: Bool = true) async throws -> (MQTTStubBroker, MQTTClient) {
        let broker = try await makeBroker()
        let client = MQTTClient(host: "127.0.0.1", port: broker.port ?? 0,
                                clientID: "ollin-test", will: will,
                                keepAlive: keepAlive, reconnects: reconnects)
        try client.connect()
        _ = try await waitFor { client.isConnected ? true : nil }
        return (broker, client)
    }

    // MARK: Connecting

    @Test func connectsAndIsSeenByTheBroker() async throws {
        let (broker, client) = try await makePair()
        defer { client.disconnect(); broker.stop() }

        #expect(client.isConnected)
        #expect(client.lastError == nil)
        #expect(client.connectionCount == 1)
        let connect = try #require(broker.connects.first)
        #expect(connect.clientID == "ollin-test")
        #expect(connect.cleanSession)
        #expect(connect.keepAlive == 30)
        // A client name of its own each run, so two copies of a sketch do not
        // push each other off the broker.
        #expect(MQTTClient.randomClientID() != MQTTClient.randomClientID())
        #expect(MQTTClient.randomClientID().utf8.count <= 23)
    }

    @Test func aRefusedConnectionSaysWhyAndStopsTrying() async throws {
        let broker = try await makeBroker()
        defer { broker.stop() }
        broker.refusalCode = 4                       // bad user name or password
        let client = MQTTClient(host: "127.0.0.1", port: broker.port ?? 0, keepAlive: 2)
        try client.connect()
        defer { client.disconnect() }

        let reason = try await waitFor { client.lastError }
        #expect(reason.contains("password"))
        #expect(!client.isConnected)
        // A refusal is an answer, not a dropped line: nothing reconnects, so the
        // broker sees exactly the one attempt.
        try await Task.sleep(nanoseconds: 600_000_000)
        #expect(broker.connects.count == 1)
    }

    @Test func aPortThatCannotBeAPortThrows() {
        #expect(throws: MQTTError.invalidPort) { try MQTTClient(host: "127.0.0.1", port: 0).connect() }
        #expect(throws: MQTTError.invalidPort) { try MQTTClient(host: "127.0.0.1", port: 70000).connect() }
    }

    // MARK: Publishing and subscribing

    @Test func aPublishComesBackOnASubscription() async throws {
        let (broker, client) = try await makePair()
        defer { client.disconnect(); broker.stop() }

        client.subscribe(to: "home/+/temperature")
        _ = try await waitFor { broker.subscribed.isEmpty ? nil : true }

        client.publish("home/kitchen/temperature", 21.4)
        let warmth = try await waitFor { client.number("home/kitchen/temperature") }
        #expect(warmth == 21.4)
        #expect(client.text("home/kitchen/temperature") == "21.4")
        #expect(client.topics == ["home/kitchen/temperature"])
        #expect(client.topics(matching: "home/#") == ["home/kitchen/temperature"])
        #expect(client.topics(matching: "garden/#").isEmpty)
        #expect(client.number("home/attic/temperature", default: -1) == -1)

        // A switch goes out as the words a device reads, and comes back as a Bool.
        client.publish("home/lamp/temperature", true)
        let lamp = try await waitFor { client.bool("home/lamp/temperature") }
        #expect(lamp == true)
        #expect(client.text("home/lamp/temperature") == "ON")

        // A topic with a wildcard in it is not a topic, so it never goes out.
        let before = broker.publishes.count
        client.publish("home/#", "no")
        client.publish("home/+/x", "no")
        client.publish("", "no")
        try await Task.sleep(nanoseconds: 150_000_000)
        #expect(broker.publishes.count == before)
    }

    @Test func aRetainedValueIsThereBeforeTheSketchAsks() async throws {
        let (broker, client) = try await makePair()
        defer { client.disconnect(); broker.stop() }

        client.publish("home/kitchen/temperature", 19.5, retains: true)
        _ = try await waitFor { broker.retained("home/kitchen/temperature") }

        // A second sketch starting later subscribes and already knows the room.
        let later = MQTTClient(host: "127.0.0.1", port: broker.port ?? 0, clientID: "ollin-later")
        defer { later.disconnect() }
        try later.connect()
        _ = try await waitFor { later.isConnected ? true : nil }
        later.subscribe(to: "home/#")

        let message = try await waitFor { later.message("home/kitchen/temperature") }
        #expect(message.number == 19.5)
        #expect(message.isRetained)
        // What arrives live is not marked retained, which is how a sketch tells a
        // stored value from something that just happened.
        client.publish("home/kitchen/temperature", 20)
        let fresh = try await waitFor { later.number("home/kitchen/temperature") == 20 ? later.message("home/kitchen/temperature") : nil }
        #expect(!fresh.isRetained)
    }

    @Test func atLeastOnceIsAcknowledgedInBothDirections() async throws {
        let (broker, client) = try await makePair()
        defer { client.disconnect(); broker.stop() }

        client.subscribe(to: "home/#", qos: .atLeastOnce)
        _ = try await waitFor { broker.subscribed.isEmpty ? nil : true }

        client.publish("home/lamp/set", "ON", qos: .atLeastOnce)
        // The broker sees it with an identifier, since a packet that is acknowledged
        // needs one.
        let sent = try await waitFor { broker.publishes.first { $0.topic == "home/lamp/set" } }
        #expect(sent.qos == .atLeastOnce)
        #expect(sent.id != nil)
        #expect(!sent.isDuplicate)

        // Coming the other way, the client acknowledges what the broker delivered.
        _ = try await waitFor { client.message("home/lamp/set") }
        let acknowledged = try await waitFor { broker.acknowledgements.isEmpty ? nil : broker.acknowledgements }
        #expect(!acknowledged.isEmpty)
        #expect(client.message("home/lamp/set")?.qos == .atLeastOnce)
    }

    @Test func drainingTakesEverythingOrJustOneFilter() async throws {
        let (broker, client) = try await makePair()
        defer { client.disconnect(); broker.stop() }

        client.subscribe(to: "room/#")
        _ = try await waitFor { broker.subscribed.isEmpty ? nil : true }
        _ = client.messages()

        broker.publish("room/a", "1")
        broker.publish("room/b", "2")
        broker.publish("room/a", "3")
        _ = try await waitFor { client.text("room/a") == "3" ? true : nil }

        // The filtered drain takes its own and leaves the rest where they are.
        let roomA = client.messages(matching: "room/a")
        #expect(roomA.map(\.topic) == ["room/a", "room/a"])
        #expect(roomA.compactMap(\.text) == ["1", "3"])
        let rest = client.messages()
        #expect(rest.map(\.topic) == ["room/b"])
        // And draining clears.
        #expect(client.messages().isEmpty)
        #expect(client.messages(matching: "room/#").isEmpty)
        // The latest value survives a drain: the two ways of reading are separate.
        #expect(client.text("room/a") == "3")
    }

    @Test func unsubscribingStopsDeliveryAndForgetsTheValue() async throws {
        let (broker, client) = try await makePair()
        defer { client.disconnect(); broker.stop() }

        client.subscribe(to: "room/#")
        _ = try await waitFor { broker.subscribed.isEmpty ? nil : true }
        broker.publish("room/a", "1")
        _ = try await waitFor { client.text("room/a") }

        client.unsubscribe(from: "room/#")
        _ = try await waitFor { broker.unsubscribed.isEmpty ? nil : true }
        #expect(client.subscriptions.isEmpty)
        #expect(client.message("room/a") == nil)

        broker.publish("room/a", "2")
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(client.message("room/a") == nil)
    }

    @Test func aTopicDrivesAParameter() async throws {
        let (broker, client) = try await makePair()
        defer { client.disconnect(); broker.stop() }

        client.subscribe(to: "home/#")
        _ = try await waitFor { broker.subscribed.isEmpty ? nil : true }

        let radius = Param(wrappedValue: 0.0, 0...100)
        client.bind("home/dial", to: radius)                    // 0…1 into 0…100
        let warmth = Param(wrappedValue: 0.0, 10...30)
        client.bind("home/kitchen/temperature", to: warmth, from: 0...40)

        broker.publish("home/dial", "0.5")
        broker.publish("home/kitchen/temperature", "20")
        _ = try await waitFor { abs(radius.wrappedValue - 50) < 0.01 ? true : nil }
        _ = try await waitFor { abs(warmth.wrappedValue - 20) < 0.01 ? true : nil }

        // Unbinding stops it; the message still arrives, it just drives nothing.
        client.unbind("home/dial")
        broker.publish("home/dial", "1")
        _ = try await waitFor { client.text("home/dial") == "1" ? true : nil }
        #expect(abs(radius.wrappedValue - 50) < 0.01)
    }

    // MARK: Staying up

    @Test func theHeartbeatKeepsAQuietLineOpen() async throws {
        let (broker, client) = try await makePair(keepAlive: 1)
        defer { client.disconnect(); broker.stop() }

        // Nothing is published, so the only thing that can keep the broker from
        // hanging up is the heartbeat.
        _ = try await waitFor(timeout: 6) { broker.pings >= 2 ? broker.pings : nil }
        #expect(client.isConnected)
        #expect(client.connectionCount == 1)      // never dropped and came back
    }

    /// A will is what the broker publishes when a client vanishes. The whole
    /// point is the difference between vanishing and leaving, so both are here.
    @Test func theWillFiresOnlyWhenTheLineIsCut() async throws {
        let will = MQTTWill(topic: "sketch/status", text: "gone", retains: true)
        let (broker, client) = try await makePair(will: will, reconnects: false)
        defer { broker.stop() }

        let connect = try #require(broker.connects.first)
        #expect(connect.will?.topic == "sketch/status")
        #expect(connect.will?.retains == true)

        // Cut the socket with no goodbye: the broker publishes the will.
        broker.dropClients()
        let fired = try await waitFor { broker.willsFired.first }
        #expect(fired.topic == "sketch/status")
        #expect(fired.text == "gone")

        // Say goodbye properly and the broker discards it instead.
        let polite = MQTTClient(host: "127.0.0.1", port: broker.port ?? 0,
                                clientID: "ollin-polite",
                                will: MQTTWill(topic: "sketch/polite", text: "gone"))
        try polite.connect()
        _ = try await waitFor { polite.isConnected ? true : nil }
        polite.disconnect()
        _ = try await waitFor { broker.goodbyes >= 1 ? true : nil }
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(!broker.willsFired.contains { $0.topic == "sketch/polite" })
        _ = client
    }

    @Test func aDroppedLineComesBackWithItsSubscriptions() async throws {
        let (broker, client) = try await makePair()
        defer { client.disconnect(); broker.stop() }

        client.subscribe(to: "room/#", qos: .atLeastOnce)
        _ = try await waitFor { broker.subscribed.isEmpty ? nil : true }

        broker.dropClients()
        _ = try await waitFor(timeout: 8) { client.connectionCount >= 2 ? true : nil }
        #expect(client.isConnected)
        // The subscription went back up on its own, so a publish still arrives.
        #expect(broker.subscribed.filter { $0.filter == "room/#" }.count >= 2)
        #expect(broker.subscribed.last?.qos == .atLeastOnce)
        broker.publish("room/a", "back")
        let again = try await waitFor(timeout: 8) { client.text("room/a") }
        #expect(again == "back")
    }

    @Test func anUnacknowledgedPublishIsSentAgainAfterAReconnect() async throws {
        let (broker, client) = try await makePair()
        defer { client.disconnect(); broker.stop() }

        broker.holdsAcknowledgements = true
        client.publish("home/lamp/set", "ON", qos: .atLeastOnce)
        let first = try await waitFor { broker.publishes.first { $0.topic == "home/lamp/set" } }
        #expect(!first.isDuplicate)

        broker.holdsAcknowledgements = false
        broker.dropClients()
        _ = try await waitFor(timeout: 8) { client.connectionCount >= 2 ? true : nil }

        // It goes out again, marked as a resend, and this time it is acknowledged.
        let resent = try await waitFor(timeout: 8) {
            broker.publishes.first { $0.topic == "home/lamp/set" && $0.isDuplicate }
        }
        #expect(resent.qos == .atLeastOnce)
        #expect(resent.payload == Data("ON".utf8))
        // Once acknowledged it is not sent a third time.
        try await Task.sleep(nanoseconds: 300_000_000)
        let sends = broker.publishes.filter { $0.topic == "home/lamp/set" }.count
        broker.dropClients()
        _ = try await waitFor(timeout: 8) { client.connectionCount >= 3 ? true : nil }
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(broker.publishes.filter { $0.topic == "home/lamp/set" }.count == sends)
    }

    /// At most once means exactly that: a message published while the line is
    /// down is gone. At least once is held and goes out when it comes back, which
    /// is the whole reason to pay for the level.
    @Test func whatSurvivesAClosedLineIsWhatWasPaidFor() async throws {
        let broker = try await makeBroker()
        defer { broker.stop() }
        let client = MQTTClient(host: "127.0.0.1", port: broker.port ?? 0, clientID: "ollin-early")
        defer { client.disconnect() }

        // Published before the connection is even open.
        client.publish("home/lost", "gone")
        client.publish("home/kept", "held", qos: .atLeastOnce)
        try client.connect()
        _ = try await waitFor { client.isConnected ? true : nil }

        let kept = try await waitFor { broker.publishes.first { $0.topic == "home/kept" } }
        #expect(kept.payload == Data("held".utf8))
        #expect(kept.isDuplicate)             // it is a resend of what was queued
        #expect(!broker.publishes.contains { $0.topic == "home/lost" })
    }
}
