import Foundation
import Testing
import Ollin
import OllinMutation
@testable import OllinDMX

/// Art-Net and sACN datagrams, and the receiver's ingest rules behind them,
/// under the mutation harness.
@Suite struct DMXMutationTests {

    static func seeds() -> [[UInt8]] {
        let channels = (0..<512).map { UInt8($0 & 0xFF) }
        return [
            ArtDMXPacket(universe: 1, channels: channels, sequence: 3, physical: 0).encode(),
            ArtDMXPacket(universe: 0x7FFF, channels: [255], sequence: 0).encode(),
            SACNDataPacket(universe: 1, channels: channels, sequence: 9, priority: 100,
                           sourceName: "Ollin probe", componentID: UUID(), startCode: 0).encode(),
            SACNDataPacket(universe: 63_999, channels: [1, 2, 3], sequence: 200, priority: 200,
                           sourceName: String(repeating: "n", count: 70), isPreview: true, isTerminated: true,
                           forcesSynchronization: true, synchronizationAddress: 12).encode(),
        ].map { [UInt8]($0) }
    }

    @Test func artNetAndSACN() {
        let sacn = DMXReceiver(.sACN)
        let artNet = DMXReceiver(.artNet)
        let report = MutationRun.run("dmx", seeds: Self.seeds(), count: 600) { bytes in
            let data = Data(bytes)
            let art = ArtDMXPacket(data: data)
            let acn = SACNDataPacket(data: data)
            if let art { _ = art.encode() }
            if let acn {
                _ = acn.encode()
                _ = SACNDataPacket.multicastGroup(universe: acn.universe)
            }
            sacn.handle(data)
            artNet.handle(data)
            for universe in [1, 63_999, 0x7FFF, 0] {
                _ = sacn.channel(1, universe: universe)
                _ = sacn.level(512, universe: universe)
                _ = artNet.color(510, universe: universe)
                _ = artNet.channel(513, universe: universe)
            }
            _ = sacn.universeNumbers
            _ = sacn.universe(1)
            return art != nil || acn != nil
        }
        #expect(report.seedsRefused.isEmpty, "\(report)")
    }
}
