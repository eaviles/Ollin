import Foundation
import Testing
import OllinTestSupport
@testable import OllinMQTT

/// A client told not to reconnect on its own still connects again when asked.
///
/// After a drop, the client kept its wish for a connection, and `connect()`
/// read that wish as a connection already under way and returned, so a sketch
/// doing the reconnecting itself could never get the line back.
@Suite
struct MQTTReconnectTests {

    func waitFor<T>(timeout: Double = 5.0, _ probe: () -> T?) async throws -> T {
        try await OllinTestSupport.waitFor(timeout: timeout, probe)
    }

    @Test func aClientThatDoesNotReconnectOnItsOwnConnectsAgainWhenAsked() async throws {
        let broker = MQTTStubBroker()
        try broker.start()
        defer { broker.stop() }
        _ = try await waitFor { broker.port }
        let client = MQTTClient(host: "127.0.0.1", port: broker.port ?? 0,
                                clientID: "ollin-by-hand", reconnects: false)
        defer { client.disconnect() }
        try client.connect()
        _ = try await waitFor { client.isConnected ? true : nil }
        #expect(client.connectionCount == 1)

        broker.dropClients()
        _ = try await waitFor { client.isConnected ? nil : true }
        // Nothing redials on its own.
        try await Task.sleep(nanoseconds: 400_000_000)
        #expect(!client.isConnected)
        #expect(client.connectionCount == 1)

        // The sketch does.
        try client.connect()
        _ = try await waitFor { client.isConnected ? true : nil }
        #expect(client.connectionCount == 2)
    }
}
