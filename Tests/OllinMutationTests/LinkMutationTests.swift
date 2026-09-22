import Foundation
import Testing
import OllinMutation
@testable import OllinLink

/// The two Link datagram families and the engine that acts on them, under the
/// mutation harness. The engine is driven with a synthetic clock, and the
/// endpoint the seeds name is the one a pong is answered from, so a mutated
/// pong lands on a measurement the mutated alive message started.
@Suite struct LinkMutationTests {

    static let session = LinkNodeId(raw: 0x4142_4344_4546_4748)
    static let sender = LinkNodeId(raw: 0x0102_0304_0506_0708)
    static let source = LinkEndpoint(address: 0xC0A8_010A, port: 54_321)

    static func seeds() -> [[UInt8]] {
        var state = Data()
        LinkWire.encodeTimeline(LinkTimeline(tempo: LinkTempo(bpm: 128), anchorMicroBeats: 42_000_000, anchorMicros: -7),
                                into: &state)
        LinkWire.encodeSession(session, into: &state)
        LinkWire.encodeStartStop(LinkStartStop(isPlaying: true, microBeats: 16_000_000, timestampMicros: 99),
                                 into: &state)
        LinkWire.encodeMeasurementEndpoint(source, into: &state)

        var pong = Data()
        LinkWire.encodeSession(session, into: &pong)
        LinkWire.encodeMicros(LinkPayloadKey.ghostTime, 1_000_000, into: &pong)
        LinkWire.encodeMicros(LinkPayloadKey.hostTime, 900_000, into: &pong)
        LinkWire.encodeMicros(LinkPayloadKey.previousGhostTime, 800_000, into: &pong)

        var ping = Data()
        LinkWire.encodeMicros(LinkPayloadKey.hostTime, 900_000, into: &ping)

        return [
            LinkWire.encodeDiscovery(kind: .alive, ttl: 5, sender: sender, payload: state),
            LinkWire.encodeDiscovery(kind: .response, ttl: 5, sender: sender, payload: state),
            LinkWire.encodeDiscovery(kind: .byeBye, ttl: 0, sender: sender, payload: Data()),
            LinkWire.encodeMeasurement(kind: .ping, payload: ping),
            LinkWire.encodeMeasurement(kind: .pong, payload: pong),
        ].map { [UInt8]($0) }
    }

    @Test func datagramsAndTheEngineThatReadsThem() {
        let gateway = LinkGatewayInfo(address: 0x0A00_0101,
                                      measurementEndpoint: LinkEndpoint(address: 0x0A00_0101, port: 20_808))
        let alive = Data(Self.seeds()[0])
        let report = MutationRun.run("link", seeds: Self.seeds(), count: 600) { bytes in
            let data = Data(bytes)
            var now: Int64 = 1_000_000
            // An engine of this case's own, told first about a peer in another
            // session that is measured at the endpoint the seeds name, so a
            // mutated pong lands on a live measurement.
            var engine = LinkEngine(tempo: LinkTempo(bpm: 120), hostNowMicros: now)
            _ = engine.handleDiscovery(alive, from: Self.source, gateway: gateway, hostNowMicros: now)
            now += 1_000
            let discovery = LinkWire.parseDiscovery(data)
            let measurement = LinkWire.parseMeasurement(data)
            _ = LinkWire.parsePayload(bytes[0...])
            _ = engine.handleDiscovery(data, from: Self.source, gateway: gateway, hostNowMicros: now)
            _ = engine.handleMeasurement(data, from: Self.source, gateway: gateway, hostNowMicros: now)
            // The measurement completes and the engine joins the peer's session,
            // so its timeline math runs on the numbers the peer sent; then the
            // mutated datagram arrives again, now for the engine's own session.
            engine.measurementSucceeded(LinkEngine.Measurement(sessionId: Self.session, gateway: gateway.address,
                                                               points: [1_000_000], deadlineMicros: now),
                                        hostNowMicros: now)
            now += 1_000
            _ = engine.handleDiscovery(data, from: Self.source, gateway: gateway, hostNowMicros: now)
            _ = engine.tick(hostNowMicros: now + 300_000, gateways: [gateway])
            _ = engine.clientTimeline.microBeats(at: now)
            _ = engine.clientTimeline.micros(at: 0)
            _ = linkPhaseEncodedBeats(engine.clientTimeline, at: now, quantum: 4_000_000)
            _ = linkTimeAtPhaseEncodedBeats(engine.clientTimeline, microBeats: 8_000_000, quantum: 4_000_000)
            _ = engine.sessionPeerCount
            return discovery != nil || measurement != nil
        }
        #expect(report.seedsRefused.isEmpty, "\(report)")
    }
}
