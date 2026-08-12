import Foundation
import Testing
@testable import OllinDMX

/// Wire-format correctness for both protocols: encodes pinned byte-for-byte
/// against the published packet layouts (Art-Net 4 for ArtDmx, ANSI E1.31
/// Table 4-1 for sACN), decode round-trips, and malformed input rejected
/// without trapping. No sockets, no GPU, so it all runs in CI.
@Suite
struct DMXWireTests {

    // MARK: ArtDmx

    @Test func artDmxEncodesTheSpecifiedLayout() {
        let packet = ArtDmxPacket(universe: 0x1234, channels: [1, 2, 3, 4], sequence: 7, physical: 2)
        let bytes = [UInt8](packet.encode())
        #expect(Array(bytes[0..<8]) == [0x41, 0x72, 0x74, 0x2D, 0x4E, 0x65, 0x74, 0x00])
        #expect(Array(bytes[8..<10]) == [0x00, 0x50])   // OpOutput, low byte first
        #expect(Array(bytes[10..<12]) == [0x00, 14])    // protocol revision, high byte first
        #expect(bytes[12] == 7)                          // sequence
        #expect(bytes[13] == 2)                          // physical
        #expect(bytes[14] == 0x34)                       // SubUni: Port-Address low byte
        #expect(bytes[15] == 0x12)                       // Net: top 7 bits
        #expect(Array(bytes[16..<18]) == [0x00, 0x04])  // length, high byte first
        #expect(Array(bytes[18...]) == [1, 2, 3, 4])
    }

    @Test func artDmxPadsOddDataToAnEvenLength() {
        let bytes = [UInt8](ArtDmxPacket(universe: 1, channels: [9]).encode())
        #expect(Array(bytes[16..<18]) == [0x00, 0x02])
        #expect(Array(bytes[18...]) == [9, 0])
    }

    @Test func artDmxRoundTrips() {
        let sent = ArtDmxPacket(
            universe: 32767, channels: [UInt8](0...255) + [UInt8](0...255),
            sequence: 255, physical: 3
        )
        let received = ArtDmxPacket(data: sent.encode())
        #expect(received == sent)
    }

    @Test func artDmxIgnoresTrailingBytes() {
        // The spec: extra bytes at the end of a valid packet are ignored.
        var data = ArtDmxPacket(universe: 5, channels: [10, 20]).encode()
        data.append(contentsOf: [0xFF, 0xFF, 0xFF])
        #expect(ArtDmxPacket(data: data)?.channels == [10, 20])
    }

    @Test func artDmxRejectsMalformedDatagrams() {
        let good = ArtDmxPacket(universe: 1, channels: [1, 2]).encode()
        #expect(ArtDmxPacket(data: Data()) == nil)
        #expect(ArtDmxPacket(data: good.prefix(17)) == nil)          // too short
        var badID = good
        badID[0] = 0x42
        #expect(ArtDmxPacket(data: badID) == nil)                    // not Art-Net
        var badOp = good
        badOp[9] = 0x20                                              // ArtPoll, not ArtDmx
        #expect(ArtDmxPacket(data: badOp) == nil)
        var badLength = good
        badLength[17] = 200                                          // claims more data than sent
        #expect(ArtDmxPacket(data: badLength) == nil)
        var zeroLength = good
        zeroLength[16] = 0
        zeroLength[17] = 0
        #expect(ArtDmxPacket(data: zeroLength) == nil)
    }

    // MARK: sACN

    @Test func sacnEncodesTheSpecifiedLayout() {
        let cid = UUID(uuidString: "0F0E0D0C-0B0A-0908-0706-050403020100")!
        let packet = SACNDataPacket(
            universe: 1, channels: [UInt8](repeating: 128, count: 512),
            sequence: 5, priority: 100, sourceName: "Ollin", cid: cid
        )
        let bytes = [UInt8](packet.encode())
        #expect(bytes.count == 638)                                  // the full-payload size the spec names
        #expect(Array(bytes[0..<2]) == [0x00, 0x10])                 // preamble size
        #expect(Array(bytes[2..<4]) == [0x00, 0x00])                 // post-amble size
        #expect(Array(bytes[4..<16]) == [0x41, 0x53, 0x43, 0x2D, 0x45, 0x31, 0x2E, 0x31, 0x37, 0x00, 0x00, 0x00])
        #expect(Array(bytes[16..<18]) == [0x72, 0x6E])               // root: 0x7 flags, length 622
        #expect(Array(bytes[18..<22]) == [0x00, 0x00, 0x00, 0x04])   // VECTOR_ROOT_E131_DATA
        #expect(Array(bytes[22..<38]) == [UInt8](withUnsafeBytes(of: cid.uuid) { Data($0) }))
        #expect(Array(bytes[38..<40]) == [0x72, 0x58])               // framing: length 600
        #expect(Array(bytes[40..<44]) == [0x00, 0x00, 0x00, 0x02])   // VECTOR_E131_DATA_PACKET
        #expect(Array(bytes[44..<49]) == Array("Ollin".utf8))
        #expect(Array(bytes[49..<108]).allSatisfy { $0 == 0 })       // name zero-padded to 64
        #expect(bytes[108] == 100)                                   // priority
        #expect(Array(bytes[109..<111]) == [0, 0])                   // synchronization address
        #expect(bytes[111] == 5)                                     // sequence
        #expect(bytes[112] == 0)                                     // options
        #expect(Array(bytes[113..<115]) == [0x00, 0x01])             // universe
        #expect(Array(bytes[115..<117]) == [0x72, 0x0B])             // DMP: length 523
        #expect(bytes[117] == 0x02)                                  // VECTOR_DMP_SET_PROPERTY
        #expect(bytes[118] == 0xA1)                                  // address & data type
        #expect(Array(bytes[119..<123]) == [0x00, 0x00, 0x00, 0x01]) // first address, increment
        #expect(Array(bytes[123..<125]) == [0x02, 0x01])             // property count 513
        #expect(bytes[125] == 0)                                     // START code
        #expect(Array(bytes[126...]) == [UInt8](repeating: 128, count: 512))
    }

    @Test func sacnLengthsFollowAPartialUniverse() {
        // The three layer lengths count from each layer's own flags field.
        let bytes = [UInt8](SACNDataPacket(universe: 9, channels: [1, 2, 3]).encode())
        #expect(bytes.count == 129)
        #expect(Array(bytes[16..<18]) == [0x70, 0x71])   // 129 - 16 = 113
        #expect(Array(bytes[38..<40]) == [0x70, 0x5B])   // 129 - 38 = 91
        #expect(Array(bytes[115..<117]) == [0x70, 0x0E]) // 129 - 115 = 14
        #expect(Array(bytes[123..<125]) == [0x00, 0x04]) // START code + 3 slots
    }

    @Test func sacnRoundTrips() {
        let sent = SACNDataPacket(
            universe: 63999, channels: [UInt8](1...200),
            sequence: 250, priority: 200, sourceName: "Rig ✺", cid: UUID(),
            startCode: 0, isPreview: true, isTerminated: true,
            forcesSynchronization: true, synchronizationAddress: 7
        )
        let received = SACNDataPacket(data: sent.encode())
        #expect(received == sent)
    }

    @Test func sacnRejectsMalformedDatagrams() {
        let good = SACNDataPacket(universe: 1, channels: [1, 2, 3]).encode()
        #expect(SACNDataPacket(data: Data()) == nil)
        #expect(SACNDataPacket(data: good.prefix(100)) == nil)       // too short
        var badID = good
        badID[4] = 0x42
        #expect(SACNDataPacket(data: badID) == nil)                  // not ACN
        var badRoot = good
        badRoot[21] = 0x08                                           // extended, not data
        #expect(SACNDataPacket(data: badRoot) == nil)
        var badFraming = good
        badFraming[43] = 0x01                                        // synchronization vector
        #expect(SACNDataPacket(data: badFraming) == nil)
        var badType = good
        badType[118] = 0xA2
        #expect(SACNDataPacket(data: badType) == nil)
        var badCount = good
        badCount[123] = 0x02                                         // claims 513+ slots, data has 3
        #expect(SACNDataPacket(data: badCount) == nil)
    }

    @Test func sacnMulticastGroupCarriesTheUniverseBytes() {
        #expect(SACNDataPacket.multicastGroup(universe: 1) == "239.255.0.1")
        #expect(SACNDataPacket.multicastGroup(universe: 256) == "239.255.1.0")
        #expect(SACNDataPacket.multicastGroup(universe: 63999) == "239.255.249.255")
    }

    // MARK: DMXUniverse

    @Test func universeChannelsAreOneBased() {
        var universe = DMXUniverse()
        universe[1] = 255
        universe[512] = 7
        #expect(universe.channels[0] == 255)
        #expect(universe.channels[511] == 7)
        // Out of range reads 0 and writes are ignored, never a trap.
        universe[0] = 9
        universe[513] = 9
        #expect(universe[0] == 0)
        #expect(universe[513] == 0)
        #expect(universe.channels.allSatisfy { $0 == 255 || $0 == 7 || $0 == 0 })
    }

    @Test func universeLevelsScaleToBytes() {
        var universe = DMXUniverse()
        universe.set(3, level: 0.5)
        #expect(universe[3] == 128)
        universe.set(3, level: 2.0)     // clamped
        #expect(universe[3] == 255)
        universe.set(3, level: -1)
        #expect(universe[3] == 0)
        universe.set(4, to: 51)
        #expect(abs(universe.level(4) - 0.2) < 0.001)
    }

    @Test func universeColorsSpanThreeChannels() {
        var universe = DMXUniverse()
        universe.set(10, color: .init(red: 1, green: 0.5, blue: 0))
        #expect(universe[10] == 255)
        #expect(universe[11] == 128)
        #expect(universe[12] == 0)
        let back = universe.color(at: 10)
        #expect(abs(back.red - 1) < 0.01 && abs(back.green - 0.5) < 0.01 && abs(back.blue - 0) < 0.01)
    }

    @Test func universeInitPadsAndTruncates() {
        #expect(DMXUniverse(channels: [1, 2]).channels.count == 512)
        #expect(DMXUniverse(channels: [UInt8](repeating: 1, count: 600)).channels.count == 512)
        var cleared = DMXUniverse(channels: [1, 2, 3])
        cleared.clear()
        #expect(cleared == DMXUniverse())
    }

    // MARK: DMXFixture

    @Test func fixturesPatchInChannelOrder() {
        let par = DMXFixture.rgb(at: 1)
        let wash = DMXFixture.rgbw(at: par.nextAddress)
        #expect(par.channelCount == 3)
        #expect(wash.address == 4)
        #expect(wash.nextAddress == 8)
        #expect(wash.channel(of: .white) == 7)
        #expect(wash.channel(of: .pan) == nil)
    }

    @Test func fixtureColorLandsOnItsRoles() {
        var universe = DMXUniverse()
        universe.set(DMXFixture.rgb(at: 5), color: .init(red: 1, green: 0, blue: 0))
        #expect(universe[5] == 255 && universe[6] == 0 && universe[7] == 0)
    }

    @Test func rgbwSplitsTheSharedPartIntoWhite() {
        var universe = DMXUniverse()
        let wash = DMXFixture.rgbw(at: 1)
        universe.set(wash, color: .init(red: 1, green: 0.5, blue: 0.25))
        #expect(universe[1] == 191)    // 0.75 after the white split
        #expect(universe[2] == 64)     // 0.25
        #expect(universe[3] == 0)
        #expect(universe[4] == 64)     // white takes min(r, g, b) = 0.25
    }

    @Test func dimmerRoleTakesTheDimmerAndLeavesColorFull() {
        var universe = DMXUniverse()
        universe.set(DMXFixture.drgb(at: 1), color: .init(red: 1, green: 1, blue: 1), dimmer: 0.5)
        #expect(universe[1] == 128)    // the dimmer channel carries brightness
        #expect(universe[2] == 255 && universe[3] == 255 && universe[4] == 255)
    }

    @Test func dimmerlessFixtureScalesItsColorInstead() {
        var universe = DMXUniverse()
        universe.set(DMXFixture.rgb(at: 1), color: .init(red: 1, green: 1, blue: 1), dimmer: 0.5)
        #expect(universe[1] == 128 && universe[2] == 128 && universe[3] == 128)
    }

    @Test func rolesAddressTheRightChannels() {
        var universe = DMXUniverse()
        let head = DMXFixture(at: 20, .pan, .tilt, .unused, .dimmer)
        universe.set(head, .tilt, level: 1)
        universe.set(head, .dimmer, to: 40)
        #expect(universe[20] == 0)
        #expect(universe[21] == 255)
        #expect(universe[22] == 0)
        #expect(universe[23] == 40)
    }

    // MARK: Send cadence

    @Test func pacerSendsChangesAndSuppressesRepeats() {
        var pacer = DMXPacer()
        let a: [UInt8] = [1], b: [UInt8] = [2]
        // (The #expect macro can't call a mutating member, so each decision
        // lands in a local first.)
        let first = pacer.shouldSend(a, now: 0)
        #expect(first)                                    // first data always goes
        let tooSoon = pacer.shouldSend(b, now: 0.001)
        #expect(!tooSoon)                                 // changed, but faster than the rate cap
        let change = pacer.shouldSend(b, now: 0.03)
        #expect(change)                                   // changed, window open
        // Unchanged data still repeats three times (the E1.31 tail) ...
        let repeats = [
            pacer.shouldSend(b, now: 0.06),
            pacer.shouldSend(b, now: 0.09),
            pacer.shouldSend(b, now: 0.12),
        ]
        #expect(repeats == [true, true, true])
        // ... then suppression holds until the keep-alive interval.
        let suppressed = [pacer.shouldSend(b, now: 0.15), pacer.shouldSend(b, now: 1.0)]
        #expect(suppressed == [false, false])
        let keepAlive = pacer.shouldSend(b, now: 0.12 + 0.9)
        #expect(keepAlive)
        let afterKeepAlive = pacer.shouldSend(b, now: 0.12 + 0.95)
        #expect(!afterKeepAlive)
    }

    @Test func pacerHonorsTheRateCeiling() {
        var pacer = DMXPacer()
        pacer.maximumRate = 10
        let first = pacer.shouldSend([1], now: 0)
        #expect(first)
        let tooSoon = pacer.shouldSend([2], now: 0.05)
        #expect(!tooSoon)                                 // under 1/10 s since the last send
        let afterWindow = pacer.shouldSend([2], now: 0.11)
        #expect(afterWindow)
    }
}
