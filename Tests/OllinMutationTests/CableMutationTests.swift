import Foundation
import Testing
import OllinMutation
@testable import OllinBluetooth
@testable import OllinSerial
@testable import OllinUSBMux

/// What comes up a cable or over the air and is read as bytes: the Firmata
/// stream a board sends, the text lines a serial device sends, the Bluetooth
/// characteristic formats, and the usbmux reply, under the mutation harness.
@Suite struct CableMutationTests {

    static func firmwareReport(_ name: String) -> [UInt8] {
        var bytes: [UInt8] = [FirmataCodec.startSysex, 0x79, 2, 5]
        for byte in name.utf8 {
            bytes.append(byte & 0x7F)
            bytes.append((byte >> 7) & 0x7F)
        }
        bytes.append(FirmataCodec.endSysex)
        return bytes
    }

    @Test func firmataOffTheBoard() {
        let seeds: [[UInt8]] = [
            [0xE3, 0x7F, 0x03],                                  // analog pin 3
            [0x90, 0x55, 0x01],                                  // digital port 0
            [0xE0, 0x00, 0x00, 0xE1, 0x7F, 0x7F],                // two analog reports in one chunk
            Self.firmwareReport("StandardFirmata"),
            FirmataCodec.string("hello from the board"),
            [FirmataCodec.startSysex, 0x6F, 0x02, 0x7F, 0x07, FirmataCodec.endSysex],   // extended analog
            [FirmataCodec.startSysex, 0x66, 1, 2, 3, FirmataCodec.endSysex],            // a sysex nothing decodes
        ]
        var parser = FirmataParser()
        let report = MutationRun.run("firmata", seeds: seeds, count: 600) { bytes in
            let messages = parser.ingest(bytes)
            for message in messages {
                switch message {
                case .analog(let pin, let value): _ = pin; _ = value
                case .digital(let pin, let value): _ = pin; _ = value
                case .string(let text): _ = text.count
                case .firmware(let firmware): _ = firmware.name
                case .sysex(let command, let data): _ = command; _ = data.count
                }
            }
            return !messages.isEmpty
        }
        #expect(report.seedsRefused.isEmpty, "\(report)")
    }

    @Test func linesOffASerialDevice() {
        let seeds = ["21.4\n", "temp=21.4\r\n", "x\r", "héllo wörld\r\n", "1,2,3\n\n"].map { Array($0.utf8) }
        var lines = LineAssembler()
        let report = MutationRun.run("serial-lines", seeds: seeds, count: 400) { bytes in
            let out = lines.ingest(bytes)
            for line in out {
                _ = Double(line.trimmingCharacters(in: .whitespacesAndNewlines))
                _ = Int(line.trimmingCharacters(in: .whitespacesAndNewlines))
                _ = line.split(separator: ",").compactMap { Double($0) }
            }
            return !out.isEmpty
        }
        #expect(report.seedsRefused.isEmpty, "\(report)")
    }

    @Test func bluetoothFormats() {
        let formats: [BluetoothFormat] = [
            .uint8, .uint16, .uint32, .int8, .int16, .int32, .unsigned(bytes: 8, scale: 1),
            .signed(bytes: 7, scale: 0.01), .signed(bytes: 8, scale: 1), .unsigned(bytes: 0, scale: 1),
            .unsigned(bytes: 9, scale: 1), .float32, .text, .raw, .heartRate,
        ]
        let seeds: [[UInt8]] = [[0x16, 0x50], [0x00, 0x50], [0x01, 0x50, 0x00], [UInt8](repeating: 0xFF, count: 8),
                                Array("Ollin".utf8)]
        let report = MutationRun.run("bluetooth-format", seeds: seeds, count: 300) { bytes in
            for format in formats {
                _ = format.number(from: bytes)
                _ = format.text(from: bytes)
            }
            return true
        }
        #expect(report.cases > 0, "\(report)")
    }

    static func plist(_ object: Any, _ format: PropertyListSerialization.PropertyListFormat) -> [UInt8] {
        [UInt8]((try? PropertyListSerialization.data(fromPropertyList: object, format: format, options: 0)) ?? Data())
    }

    @Test func theUSBMuxReply() {
        let list: [String: Any] = [
            "MessageType": "Result",
            "DeviceList": [
                ["DeviceID": 3, "MessageType": "Attached",
                 "Properties": ["SerialNumber": "00008130-000A1B2C3D4E", "ConnectionType": "USB", "DeviceID": 3]],
                ["DeviceID": 4, "MessageType": "Attached", "Properties": ["ConnectionType": "Network"]],
            ],
        ]
        let connect: [String: Any] = ["MessageType": "Result", "Number": 0]
        let seeds = [Self.plist(list, .xml), Self.plist(list, .binary), Self.plist(connect, .xml), Self.plist(connect, .binary)]
        let report = MutationRun.run("usbmux-reply", seeds: seeds, count: 400) { bytes in
            guard let reply = USBMux.reply(body: Data(bytes)) else { return false }
            _ = USBMux.devices(in: reply)
            _ = reply["Number"] as? Int
            return true
        }
        #expect(report.seedsRefused.isEmpty, "\(report)")

        var headers: [[UInt8]] = []
        for total in [UInt32(16), 17, 300, 16 << 20, UInt32.max] {
            var header: [UInt8] = []
            for value in [total, 1, 8, 1] {
                withUnsafeBytes(of: value.littleEndian) { header.append(contentsOf: $0) }
            }
            headers.append(header)
        }
        let heads = MutationRun.run("usbmux-header", seeds: headers, count: 200) { bytes in
            USBMux.replyBodyLength(header: Data(bytes)) != nil
        }
        #expect(heads.seedsRefused == [4], "\(heads)")   // a header claiming four gigabytes is refused
    }
}
