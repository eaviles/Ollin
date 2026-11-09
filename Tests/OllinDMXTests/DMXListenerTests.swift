import Foundation
import Testing
@testable import OllinDMX
import OllinTestSupport

/// A receiver on a port another program holds (see the OSC twin for why).
@Suite
struct DMXListenerTests {

    @Test func aReceiverOnAHeldPortIsNotRunning() async throws {
        let held = try HeldPort(udp: true)
        let receiver = DMXReceiver(.artNet, port: held.port)
        defer { receiver.stop() }
        try receiver.start()
        _ = try await waitFor { receiver.isRunning ? nil : true }
        #expect(receiver.boundPort == nil)
        let reason = try #require(receiver.lastError)
        #expect(reason.contains("\(held.port)"), Comment(rawValue: reason))

        held.close()
        try receiver.start()
        let port = try await waitFor { receiver.boundPort }
        #expect(port == held.port)
        #expect(receiver.isRunning)
        #expect(receiver.lastError == nil)
    }
}
