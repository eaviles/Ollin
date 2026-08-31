import Foundation
import Testing
@testable import OllinLink

/// The session state machine, driven with synthetic clocks and crafted
/// datagrams so every scenario is deterministic: no sockets, no real time.
/// Covers the priority rules, the transport race rules, session arbitration,
/// the continuity reset, the local-edit grace period, the announcement
/// cadence, and a complete ping/pong measurement run.
@Suite
struct LinkEngineTests {

    let t0: Int64 = 1_000_000_000
    let gateway = LinkGatewayInfo(
        address: 0x0A00_0001,
        measurementEndpoint: LinkEndpoint(address: 0x0A00_0001, port: 9_999)
    )
    let remoteSource = LinkEndpoint(address: 0x0A00_0002, port: 4_242)

    func startedEngine(bpm: Double = 120) -> LinkEngine {
        var engine = LinkEngine(tempo: LinkTempo(bpm: bpm), hostNowMicros: t0)
        engine.start(hostNowMicros: t0)
        return engine
    }

    /// A crafted announcement from a remote node.
    func alive(
        from node: LinkNodeId,
        session: LinkNodeId,
        timeline: LinkTimeline,
        startStop: LinkStartStop = LinkStartStop(),
        endpoint: LinkEndpoint? = nil
    ) -> Data {
        var payload = Data()
        LinkWire.encodeTimeline(timeline, into: &payload)
        LinkWire.encodeSession(session, into: &payload)
        LinkWire.encodeStartStop(startStop, into: &payload)
        if let endpoint {
            LinkWire.encodeMeasurementEndpoint(endpoint, into: &payload)
        }
        return LinkWire.encodeDiscovery(kind: .alive, ttl: 5, sender: node, payload: payload)
    }

    // MARK: Timeline priority

    @Test func clientTempoChangePromotesTheSessionTimeline() {
        var engine = startedEngine()
        let oldAnchor = engine.sessionTimeline.anchorMicroBeats
        let client = engine.clientTimeline
        engine.setClientTimeline(
            LinkTimeline(tempo: LinkTempo(bpm: 140), anchorMicroBeats: client.anchorMicroBeats, anchorMicros: client.anchorMicros),
            hostNowMicros: t0 + 1_000
        )
        #expect(engine.sessionTimeline.anchorMicroBeats > oldAnchor)
        #expect(engine.sessionTimeline.tempo.wireEquals(LinkTempo(bpm: 140)))
        #expect(engine.clientTimeline.tempo.wireEquals(LinkTempo(bpm: 140)))
        #expect(engine.dirty)
    }

    @Test func incomingTimelineNeedsAStrictlyLargerAnchorBeat() {
        var engine = startedEngine()
        let before = engine.sessionTimeline

        // An equal anchor beat is not adopted, even at another tempo.
        let sameRank = LinkTimeline(
            tempo: LinkTempo(bpm: 150),
            anchorMicroBeats: before.anchorMicroBeats,
            anchorMicros: before.anchorMicros
        )
        engine.applySessionState(timeline: sameRank, startStop: LinkStartStop(), hostNowMicros: t0 + 10)
        #expect(engine.sessionTimeline == before)

        // A strictly larger anchor beat is adopted and marked for relay.
        var outranking = sameRank
        outranking.anchorMicroBeats += 1
        engine.applySessionState(timeline: outranking, startStop: LinkStartStop(), hostNowMicros: t0 + 20)
        #expect(engine.sessionTimeline == outranking)
        #expect(engine.dirty)

        // A strictly newer transport stamp is adopted too.
        let transport = LinkStartStop(isPlaying: true, microBeats: 0, timestampMicros: t0 + 30 + engine.ghostOffsetMicros)
        engine.applySessionState(timeline: outranking, startStop: transport, hostNowMicros: t0 + 30)
        #expect(engine.startStop.isPlaying)
    }

    @Test func aLocalEditIsGuardedForASecond() {
        var engine = startedEngine()
        let client = engine.clientTimeline
        engine.setClientTimeline(
            LinkTimeline(tempo: LinkTempo(bpm: 130), anchorMicroBeats: client.anchorMicroBeats, anchorMicros: client.anchorMicros),
            hostNowMicros: t0
        )
        var incoming = engine.sessionTimeline
        incoming.anchorMicroBeats += 1_000
        incoming.tempo = LinkTempo(bpm: 90)

        // Inside the grace period the outranking timeline is ignored.
        engine.applySessionState(timeline: incoming, startStop: LinkStartStop(), hostNowMicros: t0 + 500_000)
        #expect(engine.sessionTimeline.tempo.wireEquals(LinkTempo(bpm: 130)))

        // Past it, the same timeline is adopted.
        engine.applySessionState(timeline: incoming, startStop: LinkStartStop(), hostNowMicros: t0 + 1_000_001)
        #expect(engine.sessionTimeline.tempo.wireEquals(LinkTempo(bpm: 90)))
    }

    // MARK: Transport

    @Test func transportIsLastWriterWins() {
        var engine = startedEngine()
        engine.setTransport(isPlaying: true, atHostMicros: t0 + 100)
        let stamp = engine.startStop.timestampMicros
        #expect(engine.startStop.isPlaying)

        // An older stamp must not win.
        engine.setTransport(isPlaying: false, atHostMicros: t0 + 100 - 10_000_000)
        #expect(engine.startStop.isPlaying)
        #expect(engine.startStop.timestampMicros == stamp)

        // An equal stamp nudges forward so a rapid toggle still lands.
        engine.setTransport(isPlaying: false, atHostMicros: t0 + 100)
        #expect(!engine.startStop.isPlaying)
        #expect(engine.startStop.timestampMicros == stamp + 1)
    }

    // MARK: Discovery handling

    @Test func anAnnouncementRegistersThePeerAndDrawsAReply() throws {
        var engine = startedEngine()
        let remote = LinkNodeId(raw: 42)
        let data = alive(from: remote, session: remote, timeline: LinkTimeline())
        let actions = engine.handleDiscovery(data, from: remoteSource, gateway: gateway, hostNowMicros: t0)

        #expect(engine.peers.count == 1)
        // The reply is a unicast RESPONSE carrying this node's full state.
        let reply = try #require(actions.first { action in
            if case .unicastDiscovery(_, let to, _) = action { return to == remoteSource }
            return false
        })
        guard case .unicastDiscovery(let gatewayAddress, _, let bytes) = reply else {
            Issue.record("expected a discovery reply")
            return
        }
        #expect(gatewayAddress == gateway.address)
        let parsed = try #require(LinkWire.parseDiscovery(bytes))
        #expect(parsed.kind == .response)
        #expect(parsed.sender == engine.nodeId)
        #expect(parsed.payload.session == engine.sessionId)
        #expect(parsed.payload.measurementEndpoint == gateway.measurementEndpoint)
    }

    @Test func aForeignSessionWithAnEndpointStartsAMeasurement() throws {
        var engine = startedEngine()
        let remote = LinkNodeId(raw: 42)
        let mep = LinkEndpoint(address: 0x0A00_0002, port: 7_777)
        let data = alive(from: remote, session: remote, timeline: LinkTimeline(), endpoint: mep)
        let actions = engine.handleDiscovery(data, from: remoteSource, gateway: gateway, hostNowMicros: t0)

        #expect(engine.otherSessions[remote] != nil)
        #expect(engine.measurements[mep] != nil)
        let ping = try #require(actions.first { action in
            if case .unicastMeasurement(_, let to, _) = action { return to == mep }
            return false
        })
        guard case .unicastMeasurement(_, _, let bytes) = ping else { return }
        let parsed = try #require(LinkWire.parseMeasurement(bytes))
        #expect(parsed.kind == .ping)
        let entries = try #require(LinkWire.parsePayload([UInt8](parsed.payload)[0...]))
        #expect(entries.hostTimeMicros == t0)

        // A second sighting of the same session does not start a second run.
        let again = engine.handleDiscovery(data, from: remoteSource, gateway: gateway, hostNowMicros: t0 + 1_000)
        #expect(engine.measurements.count == 1)
        #expect(!again.contains { if case .unicastMeasurement = $0 { return true }; return false })
    }

    @Test func aFarewellRemovesThePeer() {
        var engine = startedEngine()
        let remote = LinkNodeId(raw: 42)
        _ = engine.handleDiscovery(
            alive(from: remote, session: remote, timeline: LinkTimeline()),
            from: remoteSource, gateway: gateway, hostNowMicros: t0
        )
        #expect(engine.peers.count == 1)
        let farewell = LinkWire.encodeDiscovery(kind: .byeBye, ttl: 0, sender: remote, payload: Data())
        _ = engine.handleDiscovery(farewell, from: remoteSource, gateway: gateway, hostNowMicros: t0 + 1_000)
        #expect(engine.peers.isEmpty)
    }

    @Test func expiredPeersArePruned() {
        var engine = startedEngine()
        let remote = LinkNodeId(raw: 42)
        _ = engine.handleDiscovery(
            alive(from: remote, session: remote, timeline: LinkTimeline()),
            from: remoteSource, gateway: gateway, hostNowMicros: t0
        )
        // Inside ttl + padding the peer stays.
        _ = engine.tick(hostNowMicros: t0 + 5_900_000, gateways: [gateway])
        #expect(engine.peers.count == 1)
        // Past it, the peer is gone.
        _ = engine.tick(hostNowMicros: t0 + 6_000_001, gateways: [gateway])
        #expect(engine.peers.isEmpty)
    }

    // MARK: The continuity reset

    @Test func losingTheLastSessionPeerKeepsTheBeatAndTheTempo() {
        var engine = startedEngine(bpm: 111)
        engine.setTransport(isPlaying: true, atHostMicros: t0)
        let remote = LinkNodeId(raw: 42)
        // A peer in this node's own session (it adopted ours).
        _ = engine.handleDiscovery(
            alive(from: remote, session: engine.sessionId, timeline: engine.sessionTimeline),
            from: remoteSource, gateway: gateway, hostNowMicros: t0
        )
        #expect(engine.sessionPeerCount == 1)
        let oldNode = engine.nodeId

        let leaveTime = t0 + 2_000_000
        let beatsBefore = engine.clientTimeline.microBeats(at: leaveTime)
        let farewell = LinkWire.encodeDiscovery(kind: .byeBye, ttl: 0, sender: remote, payload: Data())
        _ = engine.handleDiscovery(farewell, from: remoteSource, gateway: gateway, hostNowMicros: leaveTime)

        #expect(engine.sessionPeerCount == 0)
        #expect(engine.nodeId != oldNode)
        #expect(engine.isSessionFounder)
        // Ghost time re-anchors at zero, the tempo holds, the beat carries.
        #expect(engine.sessionTimeline.anchorMicros == 0)
        #expect(engine.sessionTimeline.tempo.wireEquals(LinkTempo(bpm: 111)))
        #expect(abs(engine.clientTimeline.microBeats(at: leaveTime) - beatsBefore) <= 2)
        // The playing flag survives, stamped oldest so any real change wins.
        #expect(engine.startStop.isPlaying)
        #expect(engine.startStop.timestampMicros == 0)
    }

    // MARK: Arbitration

    func finishedRun(session: LinkNodeId, offset: Int64) -> LinkEngine.Measurement {
        LinkEngine.Measurement(
            sessionId: session,
            gateway: gateway.address,
            points: [Int64](repeating: offset, count: 101),
            deadlineMicros: 0,
            retries: 0
        )
    }

    @Test func arbitrationPrefersTheOlderSessionThenTheSmallerId() {
        var engine = startedEngine()
        let hostNow = t0 + 1_000

        // A session whose ghost clock reads 10 s more is older: join it.
        let older = LinkNodeId(raw: 0xAAAA_AAAA_AAAA_AAAA)
        _ = engine.handleDiscovery(
            alive(from: older, session: older, timeline: LinkTimeline(tempo: LinkTempo(bpm: 99))),
            from: remoteSource, gateway: gateway, hostNowMicros: t0
        )
        engine.measurementSucceeded(
            finishedRun(session: older, offset: engine.ghostOffsetMicros + 10_000_000),
            hostNowMicros: hostNow
        )
        #expect(engine.sessionId == older)
        #expect(engine.sessionTimeline.tempo.wireEquals(LinkTempo(bpm: 99)))
        #expect(engine.startStop == LinkStartStop())   // transport resets on join

        // A same-age session with a larger id does not win over it.
        let bigger = LinkNodeId(raw: 0xEEEE_EEEE_EEEE_EEEE)
        _ = engine.handleDiscovery(
            alive(from: bigger, session: bigger, timeline: LinkTimeline()),
            from: remoteSource, gateway: gateway, hostNowMicros: hostNow
        )
        engine.measurementSucceeded(
            finishedRun(session: bigger, offset: engine.ghostOffsetMicros),
            hostNowMicros: hostNow + 1_000
        )
        #expect(engine.sessionId == older)

        // A same-age session with a smaller id does.
        let smaller = LinkNodeId(raw: 0x0000_0000_0000_0001)
        _ = engine.handleDiscovery(
            alive(from: smaller, session: smaller, timeline: LinkTimeline()),
            from: remoteSource, gateway: gateway, hostNowMicros: hostNow
        )
        engine.measurementSucceeded(
            finishedRun(session: smaller, offset: engine.ghostOffsetMicros),
            hostNowMicros: hostNow + 2_000
        )
        #expect(engine.sessionId == smaller)
    }

    // MARK: A complete measurement run

    /// Feeds the engine an announcement from an older foreign session, then
    /// answers its pings with crafted pongs from a responder whose ghost
    /// clock sits at a known offset. The chain must converge on that offset
    /// and join the session, tempo and all.
    @Test func aMeasurementRunConvergesAndJoins() throws {
        var engine = startedEngine()
        let remote = LinkNodeId(raw: 42)
        let mep = LinkEndpoint(address: 0x0A00_0002, port: 7_777)
        let foreignTempo = LinkTempo(bpm: 87)
        let trueOffset = engine.ghostOffsetMicros + 60_000_000   // 60 s older

        var actions = engine.handleDiscovery(
            alive(from: remote, session: remote, timeline: LinkTimeline(tempo: foreignTempo), endpoint: mep),
            from: remoteSource, gateway: gateway, hostNowMicros: t0
        )
        // The exchange is instantaneous on purpose (ping, pong, and receipt
        // all at `now`), so every data point reads the exact offset and the
        // median must land on it.
        let now = t0
        var exchanges = 0
        while engine.measurements[mep] != nil {
            exchanges += 1
            try #require(exchanges < 200, "the chain must terminate")
            let ping = try #require(actions.compactMap { action -> Data? in
                if case .unicastMeasurement(_, let to, let data) = action, to == mep { return data }
                return nil
            }.first)
            let parsed = try #require(LinkWire.parseMeasurement(ping))
            #expect(parsed.kind == .ping)
            var body = Data()
            LinkWire.encodeSession(remote, into: &body)
            LinkWire.encodeMicros(LinkPayloadKey.ghostTime, now + trueOffset, into: &body)
            body.append(parsed.payload)   // the verbatim echo
            let pong = LinkWire.encodeMeasurement(kind: .pong, payload: body)
            actions = engine.handleMeasurement(pong, from: mep, gateway: gateway, hostNowMicros: now)
        }

        #expect(engine.sessionId == remote)
        #expect(engine.sessionTimeline.tempo.wireEquals(foreignTempo))
        // The measured transform is the responder's exact offset (the crafted
        // exchange is symmetric, so every point agrees).
        #expect(abs(engine.ghostOffsetMicros - trueOffset) <= 1)
        // The client timeline follows the session tempo without a beat jump.
        #expect(engine.clientTimeline.tempo.wireEquals(foreignTempo))
    }

    @Test func aFailedMeasurementForgetsTheForeignSession() {
        var engine = startedEngine()
        let remote = LinkNodeId(raw: 42)
        let mep = LinkEndpoint(address: 0x0A00_0002, port: 7_777)
        _ = engine.handleDiscovery(
            alive(from: remote, session: remote, timeline: LinkTimeline(), endpoint: mep),
            from: remoteSource, gateway: gateway, hostNowMicros: t0
        )
        #expect(engine.otherSessions[remote] != nil)

        // Five timeouts retry with fresh pings; the sixth gives up.
        var now = t0
        for round in 0 ..< 6 {
            now += LinkEngine.pingTimeout + 1
            let actions = engine.tick(hostNowMicros: now, gateways: [gateway])
            let pinged = actions.contains { if case .unicastMeasurement = $0 { return true }; return false }
            #expect(pinged == (round < 5), "round \(round)")
        }
        #expect(engine.measurements.isEmpty)
        #expect(engine.otherSessions[remote] == nil)
    }

    // MARK: Cadence

    @Test func announcementsFollowTheCadence() {
        var engine = startedEngine()

        // First tick announces at once, on every gateway.
        let first = engine.tick(hostNowMicros: t0, gateways: [gateway])
        #expect(first.contains { if case .multicast = $0 { return true }; return false })

        // 100 ms later nothing is due.
        let quiet = engine.tick(hostNowMicros: t0 + 100_000, gateways: [gateway])
        #expect(quiet.isEmpty)

        // 250 ms later the periodic announcement fires.
        let periodic = engine.tick(hostNowMicros: t0 + 251_000, gateways: [gateway])
        #expect(periodic.contains { if case .multicast = $0 { return true }; return false })

        // A state change rebroadcasts early, but not before 50 ms have passed.
        engine.setTransport(isPlaying: true, atHostMicros: t0 + 260_000)
        let tooSoon = engine.tick(hostNowMicros: t0 + 280_000, gateways: [gateway])
        #expect(tooSoon.isEmpty)
        let early = engine.tick(hostNowMicros: t0 + 302_000, gateways: [gateway])
        #expect(early.contains { if case .multicast = $0 { return true }; return false })
    }

    @Test func aPingIsAnsweredWithTheSessionAndGhostTime() throws {
        var engine = startedEngine()
        var body = Data()
        LinkWire.encodeMicros(LinkPayloadKey.hostTime, 777, into: &body)
        let ping = LinkWire.encodeMeasurement(kind: .ping, payload: body)
        let actions = engine.handleMeasurement(ping, from: remoteSource, gateway: gateway, hostNowMicros: t0)

        let reply = try #require(actions.first)
        guard case .unicastMeasurement(_, let to, let bytes) = reply else {
            Issue.record("expected a pong")
            return
        }
        #expect(to == remoteSource)
        let parsed = try #require(LinkWire.parseMeasurement(bytes))
        #expect(parsed.kind == .pong)
        let entries = try #require(LinkWire.parsePayload([UInt8](parsed.payload)[0...]))
        #expect(entries.session == engine.sessionId)
        #expect(entries.ghostTimeMicros == t0 + engine.ghostOffsetMicros)
        #expect(entries.hostTimeMicros == 777)   // the echo

        // An oversized ping payload is not answered.
        var large = Data()
        LinkWire.encodeMicros(LinkPayloadKey.hostTime, 777, into: &large)
        LinkWire.encodeMicros(LinkPayloadKey.previousGhostTime, 1, into: &large)
        LinkWire.encodeMicros(LinkPayloadKey.ghostTime, 2, into: &large)
        let oversized = LinkWire.encodeMeasurement(kind: .ping, payload: large)
        #expect(engine.handleMeasurement(oversized, from: remoteSource, gateway: gateway, hostNowMicros: t0).isEmpty)
    }

    @Test func ownAnnouncementsAndAliensAreIgnored() {
        var engine = startedEngine()
        // Our own multicast comes back through loopback: no peer, no reply.
        let own = engine.stateMessage(kind: .alive, measurementEndpoint: gateway.measurementEndpoint)
        #expect(engine.handleDiscovery(own, from: remoteSource, gateway: gateway, hostNowMicros: t0).isEmpty)
        #expect(engine.peers.isEmpty)
        // Garbage is ignored without effect.
        #expect(engine.handleDiscovery(Data([1, 2, 3]), from: remoteSource, gateway: gateway, hostNowMicros: t0).isEmpty)
    }
}
