import Foundation
import Testing
import Ollin
@testable import OllinOSC

/// End-to-end checks over real UDP on `127.0.0.1`: an `OSCSender` to an
/// `OSCReceiver`, exercising the polling cache, the message-queue drain, and
/// `@Param` binding. Each test takes an ephemeral port (port 0), so they're
/// independent and can run in parallel. No GPU, so they run in CI too.
@Suite
struct OSCLoopbackTests {

    struct Timeout: Error {}

    /// Polls `probe` until it returns a non-nil value or the timeout elapses.
    ///
    /// The probe comes before the clock is read: a starved task can wake past
    /// its own deadline having never looked, and giving up then throws over a
    /// message that already arrived.
    func waitFor<T>(timeout: Double = 3.0, _ probe: () -> T?) async throws -> T {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let value = probe() { return value }
            if Date() >= deadline { throw Timeout() }
            try await Task.sleep(nanoseconds: 5_000_000)   // 5 ms
        }
    }

    /// Brings up a sender→receiver pair on a fresh loopback port, with the link
    /// confirmed live (a warmup message has made the round trip and been drained).
    func makePair() async throws -> (sender: OSCSender, receiver: OSCReceiver) {
        let receiver = OSCReceiver(port: 0)
        try receiver.start()
        let port = try await waitFor { receiver.boundPort }
        let sender = OSCSender(host: "127.0.0.1", port: port)
        // Resend a warmup until one lands, so the UDP flow is established.
        _ = try await waitFor {
            sender.send("/warmup", 1)
            return receiver.number("/warmup")
        }
        // Then drain repeatedly until quiet, flushing any resent warmups still in
        // flight, so drain tests start from a clean inbox.
        for _ in 0..<20 {
            try await Task.sleep(nanoseconds: 20_000_000)   // 20 ms
            if receiver.messages().isEmpty { break }
        }
        return (sender, receiver)
    }

    @Test func deliversTypedValues() async throws {
        let (sender, receiver) = try await makePair()
        defer { receiver.stop(); sender.close() }

        let level = try await waitFor {
            sender.send("/level", 0.5, 42, "go")
            return receiver.number("/level")
        }
        // The typed getters read the *first* argument; the rest come off the array.
        #expect(level == 0.5)
        let args = receiver.arguments("/level")
        #expect(args?.count == 3)
        #expect(args?[1].int == 42)
        #expect(args?[2].text == "go")
        #expect(receiver.number("/missing", default: -1) == -1)
    }

    @Test func drainsMessageQueueInOrder() async throws {
        let (sender, receiver) = try await makePair()
        defer { receiver.stop(); sender.close() }

        sender.send("/a", 1)
        sender.send("/b", 2)
        sender.send("/c", 3)

        // Wait until the last one shows in the cache, then drain everything.
        _ = try await waitFor { receiver.int("/c") }
        let drained = receiver.messages()
        #expect(drained.map(\.address) == ["/a", "/b", "/c"])
        // Draining clears the queue.
        #expect(receiver.messages().isEmpty)
    }

    @Test func bindsAddressToParam() async throws {
        let (sender, receiver) = try await makePair()
        defer { receiver.stop(); sender.close() }

        let parameter = Param(wrappedValue: 0.0, 0...100)
        receiver.bind("/radius", to: parameter)   // incoming 0…1 → 0…100

        let value = try await waitFor(timeout: 3.0) { () -> Double? in
            sender.send("/radius", 0.5)
            return abs(parameter.wrappedValue - 50) < 0.01 ? parameter.wrappedValue : nil
        }
        #expect(abs(value - 50) < 0.01)

        // Unbinding stops further updates.
        receiver.unbind("/radius")
        sender.send("/radius", 1.0)
        try await Task.sleep(nanoseconds: 100_000_000)   // 100 ms grace
        #expect(abs(parameter.wrappedValue - 50) < 0.01)
    }

    @Test func deliversBundle() async throws {
        let (sender, receiver) = try await makePair()
        defer { receiver.stop(); sender.close() }

        sender.send(OSCBundle(.immediate, messages: [
            OSCMessage("/bundle/x", 0.1),
            OSCMessage("/bundle/y", 0.9),
        ]))
        _ = try await waitFor { receiver.number("/bundle/y") }
        #expect(receiver.number("/bundle/x") == Double(Float(0.1)))
        #expect(receiver.number("/bundle/y") == Double(Float(0.9)))
    }

    /// A tempo binds the way a number does, into its range in beats per
    /// minute, and the address never touches the beats per bar.
    @Test func bindsAddressToATempoParam() async throws {
        let (sender, receiver) = try await makePair()
        defer { receiver.stop(); sender.close() }

        let tempo = Param(wrappedValue: Tempo(90, beatsPerBar: 3), 60...160)
        receiver.bind("/tempo", to: tempo)   // incoming 0…1 → 60…160 bpm

        let value = try await waitFor(timeout: 3.0) { () -> Tempo? in
            sender.send("/tempo", 0.5)
            return abs(tempo.wrappedValue.beatsPerMinute - 110) < 0.01 ? tempo.wrappedValue : nil
        }
        #expect(abs(value.beatsPerMinute - 110) < 0.01)
        #expect(value.beatsPerBar == 3)
    }
}
