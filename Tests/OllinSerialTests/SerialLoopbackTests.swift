import Foundation
import Testing
import Ollin
@testable import OllinSerial

/// End-to-end checks over a pty pair: the replica side opens as a real
/// `SerialPort` (a pty is a tty, so the whole termios path runs), while the
/// test drives the manager side as the fake device. Exercises open, the
/// polling cache, the line drain, `@Param` binding, the write path, and the
/// EOF disconnect, all with no hardware. No GPU, so these run in CI too.
@Suite
struct SerialLoopbackTests {

    struct Timeout: Error {}

    /// Polls `probe` until it returns a non-nil value or the timeout elapses.
    ///
    /// The probe comes before the clock is read: a starved task can wake past
    /// its own deadline having never looked, and giving up then throws over an
    /// answer that is already there.
    func waitFor<T>(timeout: Double = 5.0, _ probe: () -> T?) async throws -> T {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let value = probe() { return value }
            if Date() >= deadline { throw Timeout() }
            try await Task.sleep(nanoseconds: 5_000_000)   // 5 ms
        }
    }

    /// One pty pair: the manager descriptor the test reads and writes, and
    /// the replica path a `SerialPort` opens as its device.
    struct Pty {
        let manager: Int32
        let path: String

        init() throws {
            let descriptor = posix_openpt(O_RDWR | O_NOCTTY)
            guard descriptor >= 0,
                  grantpt(descriptor) == 0,
                  unlockpt(descriptor) == 0,
                  let name = ptsname(descriptor) else {
                if descriptor >= 0 { close(descriptor) }
                throw Timeout()
            }
            // Raw on the manager side and non-blocking reads, so nothing the
            // port writes echoes back and the test can poll for it.
            var settings = termios()
            if tcgetattr(descriptor, &settings) == 0 {
                cfmakeraw(&settings)
                _ = tcsetattr(descriptor, TCSANOW, &settings)
            }
            _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
            manager = descriptor
            path = String(cString: name)
        }

        func send(_ text: String) {
            let bytes = Array(text.utf8)
            bytes.withUnsafeBufferPointer { _ = write(manager, $0.baseAddress, $0.count) }
        }

        /// Everything the port has written since the last call, decoded.
        func received() -> String {
            var buffer = [UInt8](repeating: 0, count: 4096)
            var collected: [UInt8] = []
            while true {
                let count = read(manager, &buffer, buffer.count)
                guard count > 0 else { break }
                collected.append(contentsOf: buffer[..<count])
            }
            return String(decoding: collected, as: UTF8.self)
        }
    }

    /// A port opened on a fresh pty and confirmed live.
    func makePair() async throws -> (pty: Pty, port: SerialPort) {
        let pty = try Pty()
        let port = SerialPort(path: pty.path, baudRate: 9600)
        port.open()
        _ = try await waitFor { port.isOpen ? true : nil }
        #expect(port.lastError == nil, "an open port has nothing to report")
        return (pty, port)
    }

    /// A path with no device at it is not silence any more: `open()` keeps
    /// trying, as it always did, and `lastError` says what it is waiting on.
    @Test func aPathWithNoDeviceSaysSo() async throws {
        let port = SerialPort(path: "/dev/ollin-no-such-device", baudRate: 9600)
        defer { port.close() }
        #expect(port.lastError == nil, "nothing has been tried yet")
        port.open()
        let reason = try await waitFor { port.lastError }
        #expect(reason.contains("/dev/ollin-no-such-device"), Comment(rawValue: reason))
        #expect(reason.contains("No such file"), Comment(rawValue: reason))
        #expect(!port.isOpen)
    }

    @Test func deliversLinesAndTypedValues() async throws {
        let (pty, port) = try await makePair()
        defer { port.close(); close(pty.manager) }

        pty.send("42\n512\r\n")
        _ = try await waitFor { port.latestLine == "512" ? true : nil }

        // The cache holds the latest line; the drain holds both, in order.
        #expect(port.int(default: 0) == 512)
        #expect(port.number(default: 0) == 512)
        #expect(port.lines() == ["42", "512"])
        #expect(port.lines().isEmpty)

        pty.send("on\r")
        _ = try await waitFor { port.bool() == true ? true : nil }
        #expect(port.bool(default: false) == true)
    }

    @Test func drainsRawBytesIndependently() async throws {
        let (pty, port) = try await makePair()
        defer { port.close(); close(pty.manager) }

        pty.send("ab\n")
        _ = try await waitFor { port.latestLine != nil ? true : nil }
        // The raw drain carries the terminator too, and draining it leaves
        // the line drain alone.
        #expect(port.bytes() == Array("ab\n".utf8))
        #expect(port.lines() == ["ab"])
    }

    @Test func bindsStreamToParam() async throws {
        let (pty, port) = try await makePair()
        defer { port.close(); close(pty.manager) }

        let parameter = Param(wrappedValue: 0.0, 0...100)
        port.bind(to: parameter)   // incoming 0...1023 into 0...100

        pty.send("512\n")
        let value = try await waitFor { () -> Double? in
            abs(parameter.wrappedValue - 50) < 0.5 ? parameter.wrappedValue : nil
        }
        #expect(abs(value - 50) < 0.5)

        // Unbinding stops further updates.
        port.unbind()
        pty.send("1023\n")
        _ = try await waitFor { port.latestLine == "1023" ? true : nil }
        #expect(abs(parameter.wrappedValue - 50) < 0.5)
    }

    @Test func writesReachTheDevice() async throws {
        let (pty, port) = try await makePair()
        defer { port.close(); close(pty.manager) }

        port.writeLine("led:on")
        port.write("raw")
        var collected = ""
        _ = try await waitFor { () -> Bool? in
            collected += pty.received()
            return collected == "led:on\nraw" ? true : nil
        }
    }

    @Test func deviceGoingAwayDropsTheConnection() async throws {
        let (pty, port) = try await makePair()
        defer { port.close() }

        // Closing the manager side is the device vanishing: the replica reads
        // EOF, and the port must drop to closed and start waiting.
        close(pty.manager)
        _ = try await waitFor { port.isOpen ? nil : true }
        #expect(!port.isOpen)
        #expect(port.lastError == "the device went away")

        // The retries start a second later and find nothing at the path (on
        // some machines it is gone by then; on others it lingers and refuses
        // the open). Neither says anything the sentence did not, so the
        // sentence stands rather than flipping to the system's own words.
        try await Task.sleep(nanoseconds: 1_600_000_000)
        #expect(!port.isOpen)
        #expect(port.lastError == "the device went away", Comment(rawValue: port.lastError ?? "nil"))
    }

    /// The rule behind it, with no device: an absence found after the device
    /// went away leaves the sentence standing, any other failure replaces it,
    /// and an absence found first is said as itself.
    @Test func absenceConfirmsGoingAwayAndNothingElseDoes() {
        let port = SerialPort(path: "/dev/ollin-no-such-device", baudRate: 9600)
        port.recordFailure("no device at /dev/ollin-no-such-device", confirmsAbsence: true)
        #expect(port.lastError == "no device at /dev/ollin-no-such-device")
        port.recordFailure(SerialPort.wentAwayMessage)
        port.recordFailure("/dev/ollin-no-such-device: No such file or directory", confirmsAbsence: true)
        #expect(port.lastError == "the device went away")
        port.recordFailure("/dev/ollin-no-such-device: Resource busy")
        #expect(port.lastError == "/dev/ollin-no-such-device: Resource busy")
    }
}
