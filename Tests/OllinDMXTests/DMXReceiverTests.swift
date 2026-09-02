import Foundation
import Testing
import Ollin
@testable import OllinDMX

/// The receiver's ingest rules, driven deterministically: crafted datagrams go
/// straight through `handle(_:)` with no sockets, so priority arbitration,
/// sequence ordering, termination, and the ignore rules are all exact.
@Suite
struct DMXReceiverTests {

    private func packet(
        universe: Int = 1, channels: [UInt8], sequence: UInt8 = 0,
        priority: UInt8 = 100, componentID: UUID = UUID(),
        startCode: UInt8 = 0, isPreview: Bool = false, isTerminated: Bool = false
    ) -> Data {
        SACNDataPacket(
            universe: universe, channels: channels, sequence: sequence,
            priority: priority, componentID: componentID, startCode: startCode,
            isPreview: isPreview, isTerminated: isTerminated
        ).encode()
    }

    @Test func readsTheLatestUniverse() {
        let receiver = DMXReceiver()
        receiver.handle(packet(channels: [10, 128, 255]))
        #expect(receiver.channel(1) == 10)
        #expect(abs(receiver.level(2) - 128.0 / 255) < 0.001)
        #expect(receiver.universe(1)?[3] == 255)
        #expect(receiver.universe(2) == nil)
        #expect(receiver.universeNumbers() == [1])
        // A channel past what the packet carried reads 0.
        #expect(receiver.channel(400) == 0)
        #expect(receiver.channel(0) == 0)
    }

    @Test func colorSpansThreeChannels() {
        let receiver = DMXReceiver()
        receiver.handle(packet(channels: [255, 128, 0]))
        let color = receiver.color(1)
        #expect(abs(color.red - 1) < 0.01)
        #expect(abs(color.green - 0.5) < 0.01)
        #expect(abs(color.blue - 0) < 0.01)
    }

    @Test func higherPriorityOutranksALiveSource() {
        let receiver = DMXReceiver()
        let deck = UUID(), backup = UUID()
        receiver.handle(packet(channels: [10], priority: 100, componentID: deck))
        // A lower-priority second source is ignored while the first is live.
        receiver.handle(packet(channels: [99], priority: 50, componentID: backup))
        #expect(receiver.channel(1) == 10)
        // A higher-priority source takes over at once.
        receiver.handle(packet(channels: [200], priority: 150, componentID: backup))
        #expect(receiver.channel(1) == 200)
    }

    @Test func staleSequenceNumbersAreDropped() {
        let receiver = DMXReceiver()
        let componentID = UUID()
        receiver.handle(packet(channels: [1], sequence: 10, componentID: componentID))
        // A straggler from the recent past (within the standard's window of
        // 20) is dropped; the held data stands.
        receiver.handle(packet(channels: [2], sequence: 5, componentID: componentID))
        #expect(receiver.channel(1) == 1)
        // The next in order is taken.
        receiver.handle(packet(channels: [3], sequence: 11, componentID: componentID))
        #expect(receiver.channel(1) == 3)
        // A big jump backward reads as a source reset and is accepted.
        receiver.handle(packet(channels: [4], sequence: 200, componentID: componentID))
        #expect(receiver.channel(1) == 4)
    }

    @Test func terminationForgetsTheUniverse() {
        let receiver = DMXReceiver()
        let componentID = UUID()
        receiver.handle(packet(channels: [42], sequence: 1, componentID: componentID))
        #expect(receiver.universe(1) != nil)
        receiver.handle(packet(channels: [], sequence: 2, componentID: componentID, isTerminated: true))
        #expect(receiver.universe(1) == nil)
        #expect(receiver.channel(1) == 0)
    }

    @Test func previewAndAlternateStartCodesAreIgnored() {
        let receiver = DMXReceiver()
        receiver.handle(packet(channels: [9], isPreview: true))
        #expect(receiver.universe(1) == nil)
        receiver.handle(packet(channels: [9], startCode: 0xCC))   // RDM, not dimmer data
        #expect(receiver.universe(1) == nil)
    }

    @Test func artNetPacketsReadBack() {
        let receiver = DMXReceiver(.artNet)
        receiver.handle(ArtDMXPacket(universe: 3, channels: [7, 8]).encode())
        #expect(receiver.channel(1, universe: 3) == 7)
        #expect(receiver.channel(2, universe: 3) == 8)
        // Sequence 0 means sequencing is off: any order is accepted.
        receiver.handle(ArtDMXPacket(universe: 3, channels: [70, 80]).encode())
        #expect(receiver.channel(1, universe: 3) == 70)
    }

    @Test func artNetSequenceWindowDropsStragglers() {
        let receiver = DMXReceiver(.artNet)
        receiver.handle(ArtDMXPacket(universe: 1, channels: [1], sequence: 10).encode())
        receiver.handle(ArtDMXPacket(universe: 1, channels: [2], sequence: 5).encode())
        #expect(receiver.channel(1) == 1)
        receiver.handle(ArtDMXPacket(universe: 1, channels: [3], sequence: 11).encode())
        #expect(receiver.channel(1) == 3)
    }

    @Test func wrongProtocolAndGarbageAreIgnored() {
        let receiver = DMXReceiver()   // expects sACN
        receiver.handle(ArtDMXPacket(universe: 1, channels: [1]).encode())
        receiver.handle(Data([0x00, 0x01, 0x02]))
        receiver.handle(Data())
        #expect(receiver.universeNumbers().isEmpty)
    }

    @Test func bindingDrivesAParam() {
        let receiver = DMXReceiver()
        let parameter = Param(wrappedValue: 0.0, 0...100)
        receiver.bind(channel: 2, to: parameter)
        receiver.handle(packet(channels: [0, 51], sequence: 1))
        #expect(abs(parameter.wrappedValue - 20) < 0.1)   // 51/255 of the range
        receiver.unbind(channel: 2)
        receiver.handle(packet(channels: [0, 255], sequence: 2))
        #expect(abs(parameter.wrappedValue - 20) < 0.1)
    }
}
