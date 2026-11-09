import Foundation
import Testing
import Ollin
@testable import OllinOSC
import OllinTestSupport

/// A receiver on a port another program holds.
///
/// The system reports the failed bind to the listener's handler a moment after
/// `start()` returns, and the receivers used to read only the ready state off
/// it: a receiver whose port was taken stayed `isRunning`, with `boundPort`
/// `nil` for ever and nothing to say why. Now the failure is a state of the
/// receiver, `isRunning` turns false, `lastError` names the port, and the next
/// `start()` tries again.
@Suite
@MainActor
struct ListenerFailureTests {

    private final class Probe: Sketch {
        @Param(0...1) var level = 0.5
    }

    @Test func anOSCReceiverOnAHeldPortIsNotRunning() async throws {
        let held = try HeldPort(udp: true)
        let receiver = OSCReceiver(port: held.port)
        defer { receiver.stop() }
        try receiver.start()
        _ = try await waitFor { receiver.isRunning ? nil : true }
        #expect(receiver.boundPort == nil)
        let reason = try #require(receiver.lastError)
        #expect(reason.contains("\(held.port)"), Comment(rawValue: reason))

        // Once the port is free, the same receiver comes up on it.
        held.close()
        try receiver.start()
        let port = try await waitFor { receiver.boundPort }
        #expect(port == held.port)
        #expect(receiver.isRunning)
        #expect(receiver.lastError == nil)
    }

    @Test func aTUIOReceiverOnAHeldPortIsNotRunning() async throws {
        let held = try HeldPort(udp: true)
        let receiver = TUIOReceiver(port: held.port)
        defer { receiver.stop() }
        try receiver.start()
        _ = try await waitFor { receiver.isRunning ? nil : true }
        #expect(receiver.boundPort == nil)
        #expect(receiver.lastError != nil)
        held.close()
        try receiver.start()
        _ = try await waitFor { receiver.boundPort }
        #expect(receiver.isRunning)
    }

    /// The query server opens two ports at one number, and keeps a reason for
    /// each: the OSC half that would not open is said even while the HTTP
    /// half is up, where the HTTP half coming up used to wipe it.
    @Test func theQueryServerSaysWhichPortWouldNotOpen() async throws {
        let held = try HeldPort(udp: true)
        let sketch = Probe()
        let server = OSCQueryServer(port: held.port, name: "Probe")
        server.advertises = false
        server.setup(sketch)
        defer { server.stop() }

        let reason = try await waitFor { server.unavailableReason }
        #expect(reason.contains("\(held.port)"), Comment(rawValue: reason))
        // The namespace is served over TCP, which is free...
        _ = try await waitFor { server.boundPort }
        #expect(server.isRunning)
        // ...and the OSC port's failure is still said after it comes up.
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(server.unavailableReason != nil)
        #expect(!server.receiver.isRunning)

        held.close()
        server.start()
        _ = try await waitFor { server.receiver.boundPort }
        _ = try await waitFor { server.unavailableReason == nil ? true : nil }
    }
}
