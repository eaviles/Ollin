import Foundation
import Testing
@testable import OllinSerial

/// Pure correctness for the serial satellite: line reassembly over every
/// line-ending convention and chunking, device matching, and value parsing.
/// No device, no GPU, so these run everywhere including CI.
@Suite
struct SerialUnitTests {

    private func lines(_ chunks: [String]) -> [String] {
        var assembler = LineAssembler()
        return chunks.flatMap { assembler.ingest(Array($0.utf8)) }
    }

    @Test func assemblesEveryLineEnding() {
        #expect(lines(["a\nb\n"]) == ["a", "b"])
        #expect(lines(["a\r\nb\r\n"]) == ["a", "b"])
        #expect(lines(["a\rb\r"]) == ["a", "b"])
        #expect(lines(["a\r\nb\nc\r"]) == ["a", "b", "c"])
    }

    @Test func assemblesAcrossChunkBoundaries() {
        var assembler = LineAssembler()
        #expect(assembler.ingest(Array("he".utf8)).isEmpty)
        #expect(assembler.ingest(Array("llo\nwo".utf8)) == ["hello"])
        #expect(assembler.ingest(Array("rld\r\n".utf8)) == ["world"])
    }

    @Test func crlfSplitAcrossChunksSwallowsTheLF() {
        var assembler = LineAssembler()
        #expect(assembler.ingest(Array("a\r".utf8)) == ["a"])
        // The LF opening this chunk completes the CRLF pair, not a new line.
        #expect(assembler.ingest(Array("\nb\n".utf8)) == ["b"])
    }

    @Test func deliversEmptyLines() {
        #expect(lines(["\n\n"]) == ["", ""])
    }

    @Test func decodesMultiByteCharactersSplitAcrossChunks() {
        var assembler = LineAssembler()
        // "é" is two UTF-8 bytes; feed them in separate chunks.
        #expect(assembler.ingest([0xC3]).isEmpty)
        #expect(assembler.ingest([0xA9, 0x0A]) == ["é"])
    }

    @Test func resetDropsThePartialLine() {
        var assembler = LineAssembler()
        _ = assembler.ingest(Array("abc".utf8))
        assembler.reset()
        #expect(assembler.ingest(Array("def\n".utf8)) == ["def"])
    }

    @Test func capsANeverTerminatingLine() {
        var assembler = LineAssembler()
        _ = assembler.ingest([UInt8](repeating: UInt8(ascii: "x"), count: 5000))
        let assembled = assembler.ingest([0x0A])
        #expect(assembled.count == 1)
        #expect(assembled[0].count == 4096)
    }

    @Test func parsesNumbersFromLines() {
        #expect(SerialPort.number(in: " 512 ") == 512)
        #expect(SerialPort.number(in: "3.25") == 3.25)
        #expect(SerialPort.number(in: "-40") == -40)
        #expect(SerialPort.number(in: "hello") == nil)
        #expect(SerialPort.number(in: "") == nil)
    }

    @Test func matchesDevicesByNameOrPathCaseInsensitively() {
        let devices = [
            SerialDevice(path: "/dev/cu.Bluetooth-Incoming-Port", name: "cu.Bluetooth-Incoming-Port"),
            SerialDevice(path: "/dev/cu.usbmodem101", name: "Feather M4"),
        ]
        #expect(SerialPort.firstPath(matching: "USBMODEM", in: devices) == "/dev/cu.usbmodem101")
        #expect(SerialPort.firstPath(matching: "feather", in: devices) == "/dev/cu.usbmodem101")
        #expect(SerialPort.firstPath(matching: "bluetooth", in: devices) == "/dev/cu.Bluetooth-Incoming-Port")
        #expect(SerialPort.firstPath(matching: "missing", in: devices) == nil)
    }

    @Test func discoveryReturnsCalloutPaths() {
        // The machine's device list varies (and may be empty in CI); what must
        // hold is that discovery never crashes and only reports callout paths.
        for device in SerialPort.availableDevices() {
            #expect(device.path.hasPrefix("/dev/cu."))
            #expect(!device.name.isEmpty)
        }
    }
}
