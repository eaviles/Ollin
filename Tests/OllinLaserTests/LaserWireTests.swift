import Foundation
import Testing
import Ollin
@testable import OllinLaser

/// The two published formats, pinned byte for byte: the ILDA file (big-endian,
/// 32-byte headers, 8-byte true-color records) and the DAC's own wire
/// (little-endian commands and 18-byte points). Files are read back through a
/// parser written here from the same specification, so a wrong writer cannot
/// be checked by a wrong reader.
@Suite
struct LaserWireTests {

    // MARK: The ILDA file

    @Test func theSectionHeaderIsTheSpecifiedThirtyTwoBytes() {
        let bytes = [UInt8](ILDAFile.header(records: 2, frame: 0, total: 1,
                                            name: "RING", company: "OLLIN", projector: 0))
        #expect(bytes.count == 32)
        #expect(Array(bytes[0..<4]) == Array("ILDA".utf8))
        #expect(Array(bytes[4..<7]) == [0, 0, 0])                 // reserved
        #expect(bytes[7] == 5)                                     // 2D, true color
        #expect(Array(bytes[8..<16]) == Array("RING".utf8) + [0, 0, 0, 0])
        #expect(Array(bytes[16..<24]) == Array("OLLIN".utf8) + [0, 0, 0])
        #expect(Array(bytes[24..<26]) == [0x00, 0x02])            // records, high byte first
        #expect(Array(bytes[26..<28]) == [0x00, 0x00])            // this frame
        #expect(Array(bytes[28..<30]) == [0x00, 0x01])            // frames in all
        #expect(bytes[30] == 0)                                    // projector head
        #expect(bytes[31] == 0)                                    // reserved
    }

    @Test func aNameLongerThanTheFieldIsCutToFit() {
        let bytes = [UInt8](ILDAFile.header(records: 0, frame: 0, total: 0,
                                            name: "A LONG FRAME NAME", company: "",
                                            projector: 0))
        #expect(Array(bytes[8..<16]) == Array("A LONG F".utf8))
        #expect(Array(bytes[16..<24]) == [0, 0, 0, 0, 0, 0, 0, 0])
    }

    @Test func aRecordIsEightBytesEndingInBlueGreenRed() {
        let point = LaserPoint(Vector2(1, -1), color: Color(red: 1, green: 0.5, blue: 0))
        let bytes = [UInt8](ILDAFile.record(point, isLast: false))
        #expect(bytes.count == 8)
        #expect(Array(bytes[0..<2]) == [0x7F, 0xFF])              // x: +1 of the field
        #expect(Array(bytes[2..<4]) == [0x80, 0x01])              // y: -1 of the field
        #expect(bytes[4] == 0)                                     // lit, not the last point
        #expect(bytes[5] == 0)                                     // blue
        #expect(bytes[6] == 128)                                   // green
        #expect(bytes[7] == 255)                                   // red
    }

    @Test func theStatusByteCarriesBlankingAndTheLastPoint() {
        let lit = LaserPoint(.zero, color: .white)
        #expect([UInt8](ILDAFile.record(lit, isLast: false))[4] == 0x00)
        #expect([UInt8](ILDAFile.record(lit, isLast: true))[4] == 0x80)
        let dark = LaserPoint(blankedAt: .zero)
        #expect([UInt8](ILDAFile.record(dark, isLast: false))[4] == 0x40)
        #expect([UInt8](ILDAFile.record(dark, isLast: true))[4] == 0xC0)
    }

    @Test func aBlankedPointCarriesNoColorWhateverItWasGiven() {
        var point = LaserPoint(.zero, color: .white)
        point.isBlanked = true
        let bytes = [UInt8](ILDAFile.record(point, isLast: false))
        #expect(Array(bytes[5..<8]) == [0, 0, 0])
    }

    @Test func aFileEndsWithAHeaderCarryingNoRecords() {
        let data = ILDAFile.data(LaserOptimizer().stream(square()))
        let sections = ILDAReader.sections(data)
        #expect(sections.count == 2)
        #expect(sections[0].records > 0)
        #expect(sections[1].records == 0)            // the null header
        #expect(data.count == 32 + sections[0].records * 8 + 32)
    }

    @Test func aFrameReadsBackAsTheStreamItWasWritten() {
        var optimizer = LaserOptimizer()
        optimizer.spacing = 0.04
        let stream = optimizer.stream(square())
        let read = ILDAReader.frames(ILDAFile.data(stream))
        #expect(read.count == 1)
        #expect(read[0].count == stream.points.count)
        for (written, back) in zip(stream.points, read[0]) {
            // The format keeps 16 bits a coordinate and 8 bits a channel, so a
            // point comes back within one step of each.
            #expect(abs(written.position.x - back.position.x) < 1e-4)
            #expect(abs(written.position.y - back.position.y) < 1e-4)
            #expect(written.isBlanked == back.isBlanked)
            if !written.isBlanked {
                #expect(abs(written.color.red - back.color.red) < 1.0 / 255)
                #expect(abs(written.color.green - back.color.green) < 1.0 / 255)
            }
        }
        #expect(read[0].last.map { ILDAReader.lastPointFlagSet(ILDAFile.record($0, isLast: true)) } == true)
    }

    @Test func severalFramesAreWrittenAsAnAnimation() {
        let optimizer = LaserOptimizer()
        let frames = [optimizer.stream(square()), optimizer.stream(square())]
        let sections = ILDAReader.sections(ILDAFile.data(frames))
        #expect(sections.count == 3)                  // two frames plus the null header
        #expect(sections[0].frame == 0 && sections[0].total == 2)
        #expect(sections[1].frame == 1 && sections[1].total == 2)
    }

    @Test func aFileWritesToDiskWhole() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-laser-\(UUID().uuidString).ild")
        defer { try? FileManager.default.removeItem(at: url) }
        let written = try ILDAFile.write([LaserOptimizer().stream(square())], to: url)
        let read = try Data(contentsOf: url)
        #expect(read.count == written)
        #expect(ILDAReader.frames(read).count == 1)
    }

    // MARK: The DAC's commands

    @Test func theOneByteCommandsAreTheirOwnBytes() {
        #expect([UInt8](EtherDreamWire.ping()) == [0x3F])
        #expect([UInt8](EtherDreamWire.prepare()) == [0x70])
        #expect([UInt8](EtherDreamWire.stop()) == [0x73])
        #expect([UInt8](EtherDreamWire.emergencyStop()) == [0x00])
        #expect([UInt8](EtherDreamWire.clearEmergencyStop()) == [0x63])
    }

    @Test func startingPlaybackCarriesTheRateLowByteFirst() {
        // 30,000 points a second is 0x7530.
        #expect([UInt8](EtherDreamWire.begin(pointsPerSecond: 30_000))
                == [0x62, 0x00, 0x00, 0x30, 0x75, 0x00, 0x00])
    }

    @Test func aRateChangeIsCommandSeventyFour() {
        // The published table names this command after a letter that is not the
        // byte it lists; the byte is what the hardware reads.
        #expect([UInt8](EtherDreamWire.queueRateChange(pointsPerSecond: 1_000))
                == [0x74, 0xE8, 0x03, 0x00, 0x00])
    }

    @Test func aPointIsEighteenBytesInTheSpecifiedOrder() {
        let point = LaserPoint(Vector2(1, -1), color: Color(red: 1, green: 0, blue: 0))
        let bytes = [UInt8](EtherDreamWire.encode(point))
        #expect(bytes.count == 18)
        #expect(Array(bytes[0..<2]) == [0x00, 0x00])              // control
        #expect(Array(bytes[2..<4]) == [0xFF, 0x7F])              // x, low byte first
        #expect(Array(bytes[4..<6]) == [0x01, 0x80])              // y
        #expect(Array(bytes[6..<8]) == [0xFF, 0xFF])              // red
        #expect(Array(bytes[8..<10]) == [0x00, 0x00])             // green
        #expect(Array(bytes[10..<12]) == [0x00, 0x00])            // blue
        #expect(Array(bytes[12..<14]) == [0xFF, 0xFF])            // intensity: the brightest channel
        #expect(Array(bytes[14..<18]) == [0, 0, 0, 0])            // unused
    }

    @Test func aDataCommandCountsItsPointsLowByteFirst() {
        let points = Array(repeating: LaserPoint(.zero, color: .white), count: 300)
        let bytes = [UInt8](EtherDreamWire.write(points))
        #expect(bytes[0] == 0x64)
        #expect(Array(bytes[1..<3]) == [0x2C, 0x01])              // 300
        #expect(bytes.count == 3 + 300 * 18)
    }

    @Test func aBlankedPointGoesOutDark() {
        let bytes = [UInt8](EtherDreamWire.encode(LaserPoint(blankedAt: Vector2(0.5, 0.5))))
        #expect(Array(bytes[6..<14]) == [0, 0, 0, 0, 0, 0, 0, 0])
    }

    // MARK: What comes back

    @Test func aStatusBlockReadsBackAsItself() {
        let status = EtherDreamStatus(protocolVersion: 0, lightEngine: .warmup, playback: .playing,
                                      source: 1, lightEngineFlags: 0x0102, playbackFlags: 0x0304,
                                      sourceFlags: 0, bufferFullness: 1_200,
                                      pointRate: 30_000, pointCount: 123_456)
        let bytes = status.encode()
        #expect(bytes.count == 20)
        #expect([UInt8](bytes.prefix(4)) == [0, 1, 2, 1])
        #expect(EtherDreamStatus.decode(bytes) == status)
    }

    @Test func aResponseIsTwentyTwoBytesAndReadsBack() {
        let reply = EtherDreamResponse(code: .ack, command: 0x70, status: .idle)
        let bytes = reply.encode()
        #expect(bytes.count == 22)
        #expect(EtherDreamResponse.decode(bytes) == reply)
    }

    @Test func shortOrUnknownRepliesAreRefusedRatherThanTrapping() {
        #expect(EtherDreamResponse.decode(Data()) == nil)
        #expect(EtherDreamResponse.decode(Data(repeating: 0x61, count: 21)) == nil)
        var bad = EtherDreamResponse(code: .ack, command: 0, status: .idle).encode()
        bad[bad.startIndex] = 0x5A                       // a code the protocol has no name for
        #expect(EtherDreamResponse.decode(bad) == nil)
        var badState = bad
        badState[badState.startIndex] = 0x61
        badState[badState.startIndex + 3] = 0x09         // a light-engine state it does not define
        #expect(EtherDreamResponse.decode(badState) == nil)
    }

    @Test func anAnnouncementNamesTheMachineAndItsBuffer() {
        let device = EtherDreamDevice(host: "10.0.0.7", macAddress: "00:11:22:aa:bb:cc",
                                      hardwareRevision: 1, softwareRevision: 2,
                                      bufferCapacity: 1_799, maximumPointRate: 100_000,
                                      status: .idle)
        let bytes = device.encode()
        #expect(bytes.count == 36)
        #expect(EtherDreamDevice.decode(bytes, host: "10.0.0.7") == device)
        #expect(EtherDreamDevice.decode(bytes.prefix(20), host: "10.0.0.7") == nil)
    }

    @Test func aDacIsBuiltFromWhatItSaidAboutItself() {
        let device = EtherDreamDevice(host: "10.0.0.7", macAddress: "00:11:22:aa:bb:cc",
                                      hardwareRevision: 1, softwareRevision: 2,
                                      bufferCapacity: 900, maximumPointRate: 12_000,
                                      status: .idle)
        let dac = EtherDreamDAC(device: device)
        #expect(dac.host == "10.0.0.7")
        #expect(dac.bufferCapacity == 900)
        #expect(dac.pointsPerSecond == 12_000)           // held down to what it will take
    }
}

// MARK: - An ILDA reader, written from the same specification

/// Reads back what `ILDAFile` writes. Deliberately a second implementation
/// rather than a shared one: a file is only proved by a reader that does not
/// share the writer's assumptions.
enum ILDAReader {

    struct Section {
        var format: UInt8
        var records: Int
        var frame: Int
        var total: Int
        var offset: Int
    }

    static func sections(_ data: Data) -> [Section] {
        let bytes = [UInt8](data)
        var out: [Section] = []
        var i = 0
        while i + 32 <= bytes.count {
            guard Array(bytes[i..<(i + 4)]) == Array("ILDA".utf8) else { break }
            func u16(_ at: Int) -> Int { Int(bytes[i + at]) << 8 | Int(bytes[i + at + 1]) }
            let section = Section(format: bytes[i + 7], records: u16(24), frame: u16(26),
                                  total: u16(28), offset: i + 32)
            out.append(section)
            if section.records == 0 { break }
            i = section.offset + section.records * 8
        }
        return out
    }

    static func frames(_ data: Data) -> [[LaserPoint]] {
        let bytes = [UInt8](data)
        return sections(data).filter { $0.records > 0 }.map { section in
            (0..<section.records).map { r -> LaserPoint in
                let at = section.offset + r * 8
                let x = Int16(bitPattern: UInt16(bytes[at]) << 8 | UInt16(bytes[at + 1]))
                let y = Int16(bitPattern: UInt16(bytes[at + 2]) << 8 | UInt16(bytes[at + 3]))
                let status = bytes[at + 4]
                let position = Vector2(Double(x) / 32767, Double(y) / 32767)
                if status & 0x40 != 0 { return LaserPoint(blankedAt: position) }
                return LaserPoint(position, color: Color(red: Double(bytes[at + 7]) / 255,
                                                         green: Double(bytes[at + 6]) / 255,
                                                         blue: Double(bytes[at + 5]) / 255))
            }
        }
    }

    static func lastPointFlagSet(_ record: Data) -> Bool {
        [UInt8](record)[4] & 0x80 != 0
    }
}
