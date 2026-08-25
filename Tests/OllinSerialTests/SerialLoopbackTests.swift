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
    func waitFor<T>(timeout: Double = 5.0, _ probe: () -> T?) async throws -> T {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let value = probe() { return value }
            try await Task.sleep(nanoseconds: 5_000_000)   // 5 ms
        }
        throw Timeout()
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
        return (pty, port)
    }

    @Test func deliversLinesAndTypedValues() async throws {
        let (pty, port) = try await makePair()
        defer { port.close(); close(pty.manager) }

        pty.send("42\n512\r\n")
        _ = try await waitFor { port.latestLine == "512" ? true : nil }

        // The cache holds the latest line; the drain holds both, in order.
        #expect(port.int(default: 0) == 512)
        #expect(port.float(default: 0) == 512)
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

        let knob = Param(wrappedValue: 0.0, 0...100)
        port.bind(to: knob)   // incoming 0...1023 into 0...100

        pty.send("512\n")
        let value = try await waitFor { () -> Double? in
            abs(knob.wrappedValue - 50) < 0.5 ? knob.wrappedValue : nil
        }
        #expect(abs(value - 50) < 0.5)

        // Unbinding stops further updates.
        port.unbind()
        pty.send("1023\n")
        _ = try await waitFor { port.latestLine == "1023" ? true : nil }
        #expect(abs(knob.wrappedValue - 50) < 0.5)
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
    }
}
