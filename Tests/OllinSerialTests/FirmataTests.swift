import Foundation
import Testing
import Ollin
@testable import OllinSerial

/// Firmata over the port, checked against the published protocol: every
/// message the board is sent has the bytes the spec gives, the parser turns
/// the board's stream into readings and survives any chunk boundary, and over
/// a pty pair a fake board sees what a sketch's reads and writes send and its
/// readings land where the sketch looks. No hardware, no GPU.
@Suite
struct FirmataTests {

    // MARK: The bytes sent

    @Test func encodesTheCommandsTheSpecGives() {
        #expect(FirmataCodec.setMode(pin: 13, mode: .output) == [0xF4, 13, 0x01])
        #expect(FirmataCodec.setMode(pin: 2, mode: .inputPullUp) == [0xF4, 2, 0x0B])
        #expect(FirmataCodec.reportAnalog(pin: 3) == [0xC3, 1])
        #expect(FirmataCodec.reportDigital(port: 1) == [0xD1, 1])
        #expect(FirmataCodec.digitalWrite(pin: 13, value: true) == [0xF5, 13, 1])
        #expect(FirmataCodec.digitalWrite(pin: 13, value: false) == [0xF5, 13, 0])
        #expect(FirmataCodec.firmwareQuery == [0xF0, 0x79, 0xF7])
    }

    @Test func splitsFourteenBitValuesLowSevenFirst() {
        // 200 = 0b1_1001000: low seven bits 0x48, then the eighth.
        #expect(FirmataCodec.analogWrite(pin: 9, value: 200) == [0xE9, 0x48, 0x01])
        #expect(FirmataCodec.analogWrite(pin: 0, value: 1023) == [0xE0, 0x7F, 0x07])
        // Past the sixteenth pin the pin number travels as data.
        #expect(FirmataCodec.analogWrite(pin: 20, value: 200) == [0xF0, 0x6F, 20, 0x48, 0x01, 0xF7])
        #expect(FirmataCodec.samplingInterval(19) == [0xF0, 0x7A, 19, 0, 0xF7])
        #expect(FirmataCodec.samplingInterval(200) == [0xF0, 0x7A, 0x48, 0x01, 0xF7])
    }

    @Test func sendsTextAsSevenBitPairs() {
        #expect(FirmataCodec.string("Hi") == [0xF0, 0x71, 0x48, 0, 0x69, 0, 0xF7])
        // And reads it back the same way, a high bit riding the second byte.
        #expect(FirmataCodec.unpack7([0x48, 0, 0x69, 0]) == Array("Hi".utf8))
        #expect(FirmataCodec.unpack7([0x00, 0x01]) == [0x80])
    }

    // MARK: The stream read

    @Test func decodesAnalogAndDigitalMessages() {
        var parser = FirmataParser()
        #expect(parser.ingest([0xE3, 0x7F, 0x07]) == [.analog(pin: 3, value: 1023)])
        #expect(parser.ingest([0xE0, 0x00, 0x04]) == [.analog(pin: 0, value: 512)])

        // The first word from a port reports every pin; the next only the
        // ones that changed. Bit 7 of the port rides the second byte.
        let first = parser.ingest([0x90, 0b0000101, 0])
        #expect(first.count == 8)
        #expect(first[0] == .digital(pin: 0, value: true))
        #expect(first[1] == .digital(pin: 1, value: false))
        #expect(first[2] == .digital(pin: 2, value: true))
        #expect(parser.ingest([0x90, 0b0000100, 0]) == [.digital(pin: 0, value: false)])
        #expect(parser.ingest([0x90, 0b0000100, 0]).isEmpty)
        let port1 = parser.ingest([0x91, 0x00, 0x01])
        #expect(port1.count == 8)
        #expect(port1[7] == .digital(pin: 15, value: true))
    }

    @Test func decodesSysexMessages() {
        var parser = FirmataParser()
        let firmware: [UInt8] = [0xF0, 0x79, 2, 5, 0x53, 0, 0x74, 0, 0xF7]
        #expect(parser.ingest(firmware)
                == [.firmware(FirmataFirmware(name: "St", majorVersion: 2, minorVersion: 5))])
        #expect(parser.ingest([0xF0, 0x71, 0x6F, 0, 0x6B, 0, 0xF7]) == [.string("ok")])
        #expect(parser.ingest([0xF0, 0x6F, 17, 0x7F, 0x07, 0xF7]) == [.analog(pin: 17, value: 1023)])
        #expect(parser.ingest([0xF0, 0x6C, 1, 2, 3, 0xF7]) == [.sysex(command: 0x6C, data: [1, 2, 3])])
    }

    @Test func survivesAnyChunkBoundary() {
        let stream: [UInt8] = [0xE3, 0x7F, 0x07, 0xF0, 0x71, 0x6F, 0, 0x6B, 0, 0xF7, 0x90, 0x01, 0x00]
        var whole = FirmataParser()
        let expected = whole.ingest(stream)
        #expect(expected.count == 10)
        var byOne = FirmataParser()
        var collected: [FirmataMessage] = []
        for byte in stream { collected.append(contentsOf: byOne.ingest([byte])) }
        #expect(collected == expected)
    }

    @Test func resynchronizesOnAStreamJoinedMidMessage() {
        var parser = FirmataParser()
        // Two data bytes with no command before them, then a whole message:
        // the strays are dropped, the message is read.
        #expect(parser.ingest([0x12, 0x34, 0xE1, 1, 2]) == [.analog(pin: 1, value: 1 | (2 << 7))])
        // A command byte in the middle of a sysex ends it without a message.
        #expect(parser.ingest([0xF0, 0x71, 0x6F, 0xE1, 3, 0]) == [.analog(pin: 1, value: 3)])
    }

    // MARK: Over a wire

    struct Timeout: Error {}

    /// Polls `probe` until it answers or the timeout elapses; the probe runs
    /// before the clock is read.
    func waitFor<T>(timeout: Double = 5.0, _ probe: () -> T?) async throws -> T {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let value = probe() { return value }
            if Date() >= deadline { throw Timeout() }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    /// The fake board's end of a pty pair, reading raw bytes.
    final class FakeBoard {
        let manager: Int32
        let path: String
        private var collected: [UInt8] = []

        init() throws {
            let descriptor = posix_openpt(O_RDWR | O_NOCTTY)
            guard descriptor >= 0, grantpt(descriptor) == 0, unlockpt(descriptor) == 0,
                  let name = ptsname(descriptor) else {
                if descriptor >= 0 { close(descriptor) }
                throw Timeout()
            }
            var settings = termios()
            if tcgetattr(descriptor, &settings) == 0 {
                cfmakeraw(&settings)
                _ = tcsetattr(descriptor, TCSANOW, &settings)
            }
            _ = fcntl(descriptor, F_SETFL, fcntl(descriptor, F_GETFL) | O_NONBLOCK)
            manager = descriptor
            path = String(cString: name)
        }

        deinit { close(manager) }

        func send(_ bytes: [UInt8]) {
            bytes.withUnsafeBufferPointer { _ = write(manager, $0.baseAddress, $0.count) }
        }

        /// Everything received so far, kept until `forget()`.
        func received() -> [UInt8] {
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = read(manager, &buffer, buffer.count)
                guard count > 0 else { break }
                collected.append(contentsOf: buffer[..<count])
            }
            return collected
        }

        func forget() { collected.removeAll() }

        /// Whether `bytes` appear in order somewhere in what was received.
        func heard(_ bytes: [UInt8]) -> Bool {
            let all = received()
            guard all.count >= bytes.count else { return false }
            return (0 ... all.count - bytes.count).contains { i in
                Array(all[i ..< i + bytes.count]) == bytes
            }
        }
    }

    func makePair() async throws -> (fake: FakeBoard, board: FirmataBoard) {
        let fake = try FakeBoard()
        let board = FirmataBoard(path: fake.path)
        board.open()
        _ = try await waitFor { board.isOpen ? true : nil }
        return (fake, board)
    }

    @Test func asksTheBoardWhatItRunsOnConnection() async throws {
        let (fake, board) = try await makePair()
        defer { board.close() }
        _ = try await waitFor { fake.heard(FirmataCodec.firmwareQuery) ? true : nil }
        #expect(board.firmware == nil)
        fake.send([0xF0, 0x79, 2, 5] + Array("StandardFirmata.ino".utf8).flatMap { [$0 & 0x7F, $0 >> 7] } + [0xF7])
        let firmware = try await waitFor { board.firmware }
        #expect(firmware == FirmataFirmware(name: "StandardFirmata.ino", majorVersion: 2, minorVersion: 5))
        #expect(board.messages().contains(.firmware(firmware)))
    }

    @Test func askingAPinTurnsItOnAndReadsIt() async throws {
        let (fake, board) = try await makePair()
        defer { board.close() }

        #expect(board.analog(0) == nil)
        _ = try await waitFor { fake.heard([0xC0, 1]) ? true : nil }
        fake.send([0xE0, 0x00, 0x04])   // A0 reads 512
        let level = try await waitFor { board.analog(0) }
        #expect(abs(level - 512.0 / 1023) < 1e-9)
        #expect(board.analog(0, default: 0) == level)
        #expect(board.messages() == [.analog(pin: 0, value: 512)])

        #expect(board.digital(2, pullUp: true) == nil)
        _ = try await waitFor { fake.heard([0xF4, 2, 0x0B]) && fake.heard([0xD0, 1]) ? true : nil }
        fake.send([0x90, 0b0000100, 0])
        let pressed = try await waitFor { board.digital(2) }
        #expect(pressed == true)
        #expect(board.digital(2, default: false) == true)
        // The mode was set on the first ask; later reads, with or without
        // the pull-up flag, send nothing new.
        fake.forget()
        _ = board.digital(2, pullUp: true)
        _ = board.digital(2)
        _ = board.analog(0)
        try await Task.sleep(nanoseconds: 50_000_000)
        #expect(fake.received().isEmpty)
    }

    @Test func writesSetTheModeOnceThenTheValue() async throws {
        let (fake, board) = try await makePair()
        defer { board.close() }
        _ = try await waitFor { fake.heard(FirmataCodec.firmwareQuery) ? true : nil }
        fake.forget()

        board.write(13, true)
        board.write(13, false)
        _ = try await waitFor { fake.heard([0xF5, 13, 0]) ? true : nil }
        #expect(fake.received() == [0xF4, 13, 1, 0xF5, 13, 1, 0xF5, 13, 0])

        fake.forget()
        board.write(9, 0.5)
        _ = try await waitFor { fake.heard([0xE9, 0x00, 0x01]) ? true : nil }
        #expect(fake.received() == [0xF4, 9, 3, 0xE9, 0x00, 0x01])   // 128 = 0b1_0000000

        fake.forget()
        board.write(10, angle: 90)
        _ = try await waitFor { fake.heard([0xEA, 90, 0]) ? true : nil }
        #expect(fake.received() == [0xF4, 10, 4, 0xEA, 90, 0])

        fake.forget()
        board.send(text: "Hi")
        _ = try await waitFor { fake.heard(FirmataCodec.string("Hi")) ? true : nil }
    }

    @Test func bindsAnAnalogPinToAParam() async throws {
        let (fake, board) = try await makePair()
        defer { board.close() }

        let parameter = Param(wrappedValue: 0.0, 0...100)
        board.bind(analog: 2, to: parameter)
        _ = try await waitFor { fake.heard([0xC2, 1]) ? true : nil }
        fake.send([0xE2, 0x7F, 0x07])   // full scale
        let value = try await waitFor { () -> Double? in
            abs(parameter.wrappedValue - 100) < 1e-6 ? parameter.wrappedValue : nil
        }
        #expect(abs(value - 100) < 1e-6)

        board.unbind(analog: 2)
        fake.send([0xE2, 0x00, 0x00])
        _ = try await waitFor { board.analog(2) == 0 ? true : nil }
        #expect(abs(parameter.wrappedValue - 100) < 1e-6)
    }

    @Test func aBoardThatAnnouncesItselfIsToldEverythingAgain() async throws {
        let (fake, board) = try await makePair()
        defer { board.close() }

        _ = board.analog(1)
        _ = board.digital(4)
        board.write(13, true)
        board.setSamplingInterval(50)
        _ = try await waitFor { fake.heard([0xF0, 0x7A, 50, 0, 0xF7]) ? true : nil }
        fake.forget()

        // The board resets and announces itself: every mode, report, and
        // the interval come again, so a replugged board picks up where the
        // sketch is.
        fake.send([0xF0, 0x79, 2, 5, 0xF7])
        _ = try await waitFor { fake.heard([0xF0, 0x7A, 50, 0, 0xF7]) ? true : nil }
        let again = fake.received()
        #expect(again.contains(where: { _ in true }))
        for expected in [[0xF4, 4, 0x00], [0xF4, 13, 0x01], [0xC1, 1], [0xD0, 1]] as [[UInt8]] {
            #expect(fake.heard(expected), "\(expected) was not restated")
        }
        _ = again
    }
}
