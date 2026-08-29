import Foundation
import Testing
import Ollin
@testable import OllinDMX

/// End-to-end checks over real UDP on `127.0.0.1`: a `DMXSender` to a
/// `DMXReceiver` for both protocols. Each test takes an ephemeral port
/// (port 0), so they're independent and can run in parallel. No GPU, so they
/// run in CI too.
@Suite
struct DMXLoopbackTests {

    struct Timeout: Error {}

    /// Polls `probe` until it returns a non-nil value or the timeout elapses.
    ///
    /// The probe comes before the clock is read: a starved task can wake past
    /// its own deadline having never looked, and giving up then throws over an
    /// answer that is already there.
    func waitFor<T>(timeout: Double = 3.0, _ probe: () -> T?) async throws -> T {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let value = probe() { return value }
            if Date() >= deadline { throw Timeout() }
            try await Task.sleep(nanoseconds: 5_000_000)   // 5 ms
        }
    }

    @Test func sacnRoundTripsOverLoopback() async throws {
        let receiver = DMXReceiver(.sACN, port: 0)
        try receiver.start()
        let port = try await waitFor { receiver.boundPort }
        let sender = DMXSender(sACN: "127.0.0.1", port: port)
        defer { receiver.stop(); sender.close() }

        var rig = DMXUniverse()
        rig[1] = 200
        rig.set(2, level: 1)
        // Resend until it lands; the payload changes per attempt (channel 3
        // counts up) so the sender's change detection keeps transmitting.
        var attempt: UInt8 = 0
        _ = try await waitFor { () -> Bool? in
            attempt &+= 1
            rig[3] = attempt
            sender.send(rig)
            return receiver.channel(1) == 200 ? true : nil
        }
        #expect(receiver.channel(2) == 255)
        #expect(receiver.universes() == [1])
    }

    @Test func artNetRoundTripsOverLoopback() async throws {
        let receiver = DMXReceiver(.artNet, port: 0)
        try receiver.start()
        let port = try await waitFor { receiver.boundPort }
        let sender = DMXSender(artNet: "127.0.0.1", port: port)
        defer { receiver.stop(); sender.close() }

        var attempt: UInt8 = 0
        _ = try await waitFor { () -> Bool? in
            attempt &+= 1
            sender.send(channels: [90, attempt], universe: 4)
            return receiver.channel(1, universe: 4) == 90 ? true : nil
        }
        #expect(receiver.universes() == [4])
    }

    @Test func bindingDrivesAParamOverLoopback() async throws {
        let receiver = DMXReceiver(.sACN, port: 0)
        try receiver.start()
        let port = try await waitFor { receiver.boundPort }
        let sender = DMXSender(sACN: "127.0.0.1", port: port)
        defer { receiver.stop(); sender.close() }

        let knob = Param(wrappedValue: 0.0, 0...100)
        receiver.bind(channel: 1, to: knob)

        var attempt: UInt8 = 0
        _ = try await waitFor { () -> Double? in
            attempt &+= 1
            sender.send(channels: [255, attempt])
            return knob.wrappedValue > 99 ? knob.wrappedValue : nil
        }
        #expect(abs(knob.wrappedValue - 100) < 0.01)
    }

    @Test func closingAnSACNSenderSaysGoodbye() async throws {
        let receiver = DMXReceiver(.sACN, port: 0)
        try receiver.start()
        let port = try await waitFor { receiver.boundPort }
        let sender = DMXSender(sACN: "127.0.0.1", port: port)

        var attempt: UInt8 = 0
        _ = try await waitFor { () -> Bool? in
            attempt &+= 1
            sender.send(channels: [1, attempt])
            return receiver.universe(1) != nil ? true : nil
        }
        // The three stream-terminated packets clear the receiver's slot.
        sender.close()
        _ = try await waitFor { receiver.universe(1) == nil ? true : nil }
        receiver.stop()
    }
}
