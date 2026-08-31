import Foundation

/// One network interface the engine speaks on: its IPv4 address and the
/// measurement endpoint advertised for it. The socket work lives in
/// `LinkGateway`; the engine only names interfaces by address.
struct LinkGatewayInfo: Equatable {
    var address: UInt32
    var measurementEndpoint: LinkEndpoint
}

/// A UDP send the engine wants performed. The engine is pure (state in,
/// actions out), so every packet leaves as one of these and the caller does
/// the sending after its lock is released.
enum LinkAction: Equatable {
    case multicast(gateway: UInt32, data: Data)
    case unicastDiscovery(gateway: UInt32, to: LinkEndpoint, data: Data)
    case unicastMeasurement(gateway: UInt32, to: LinkEndpoint, data: Data)
}

/// The session state machine: peer registry, discovery handling, ping/pong
/// clock-offset measurement, session arbitration, timeline priority, and
/// start/stop propagation. Deliberately free of sockets and real clocks: every
/// entry point takes the current host time in microseconds, so tests drive it
/// with synthetic clocks and crafted datagrams, the `TempoEngine` discipline.
struct LinkEngine {

    // Protocol timing, all in microseconds unless named otherwise.
    static let peerTTLSeconds: UInt8 = 5
    static let alivePeriod: Int64 = 250_000
    static let minRebroadcastInterval: Int64 = 50_000
    static let prunePadding: Int64 = 1_000_000
    static let pingTimeout: Int64 = 50_000
    static let maxPingRetries = 5
    /// A measurement finishes when it holds strictly more points than this.
    static let measurementPoints = 100
    static let remeasurePeriod: Int64 = 30_000_000
    /// Two sessions within this ghost-time distance count as the same age.
    static let sessionEps: Int64 = 500_000
    /// After a local timeline edit, incoming timelines are ignored this long.
    static let gracePeriod: Int64 = 1_000_000
    /// A ping payload past this size is not answered.
    static let maxPingPayload = 32

    struct PeerKey: Hashable {
        var node: LinkNodeId
        var gateway: UInt32
    }

    /// What is known about one peer on one interface. Timelines are a session
    /// property and are held once per session, never cached per peer.
    struct Peer {
        var sessionId: LinkNodeId
        var measurementEndpoint: LinkEndpoint?
        var expiresMicros: Int64
    }

    /// A foreign session being tracked: its timeline is needed if this node
    /// joins it; its transport state resets on join.
    struct ForeignSession {
        var timeline = LinkTimeline()
        var startStop = LinkStartStop()
    }

    /// An in-flight ping/pong exchange, keyed by the responder's endpoint.
    /// Each data point estimates (responder ghost micros - our host micros).
    struct Measurement {
        var sessionId: LinkNodeId
        var gateway: UInt32
        var points: [Int64] = []
        var deadlineMicros: Int64
        var retries = 0
    }

    private(set) var nodeId: LinkNodeId
    private(set) var sessionId: LinkNodeId
    /// The session timeline, in the ghost frame (what travels in `tmln`).
    private(set) var sessionTimeline: LinkTimeline
    private(set) var startStop = LinkStartStop()
    /// ghost = host + offset; the sole crossing between the two clock frames.
    private(set) var ghostOffsetMicros: Int64
    /// The client-facing timeline, in the host frame.
    private(set) var clientTimeline: LinkTimeline
    private(set) var peers: [PeerKey: Peer] = [:]
    private(set) var otherSessions: [LinkNodeId: ForeignSession] = [:]
    private(set) var measurements: [LinkEndpoint: Measurement] = [:]
    private var nextOwnMeasureMicros: Int64?
    private var guardUntilMicros: Int64?
    /// A state change happened; rebroadcast at the next opportunity.
    private(set) var dirty = false
    private var lastBroadcastMicros: Int64?

    init(tempo: LinkTempo, hostNowMicros: Int64) {
        let id = LinkNodeId.random()
        nodeId = id
        sessionId = id
        sessionTimeline = LinkTimeline(tempo: tempo)
        ghostOffsetMicros = -hostNowMicros
        clientTimeline = LinkTimeline(tempo: tempo, anchorMicroBeats: 0, anchorMicros: hostNowMicros)
    }

    var isSessionFounder: Bool { sessionId == nodeId }

    /// Unique peers in this node's own session.
    var sessionPeerCount: Int {
        Set(peers.filter { $0.value.sessionId == sessionId }.map(\.key.node)).count
    }

    // MARK: Lifecycle

    /// Starting always resets to a fresh identity first, so a restarted node
    /// cannot impose stale state on an existing session.
    mutating func start(hostNowMicros: Int64) {
        clearNetworkState()
        reset(keepingBeat: false, hostNowMicros: hostNowMicros)
    }

    /// The farewell datagram; the caller multicasts it on every gateway.
    func byeByeDatagram() -> Data {
        LinkWire.encodeDiscovery(kind: .byeBye, ttl: 0, sender: nodeId, payload: Data())
    }

    mutating func clearNetworkState() {
        peers.removeAll()
        measurements.removeAll()
        otherSessions.removeAll()
        guardUntilMicros = nil
        nextOwnMeasureMicros = nil
        lastBroadcastMicros = nil
    }

    /// Back to a fresh node and session identity, ghost time re-anchored at
    /// zero. Keeping the beat carries the current position and the playing
    /// flag forward (losing the last peer must not read as a transport stop);
    /// otherwise the timeline restarts at beat zero.
    private mutating func reset(keepingBeat: Bool, hostNowMicros: Int64) {
        let oldTimeline = sessionTimeline
        let oldOffset = ghostOffsetMicros
        let oldPlaying = startStop.isPlaying

        let id = LinkNodeId.random()
        nodeId = id
        sessionId = id
        let newOffset = -hostNowMicros
        let anchorBeat = keepingBeat ? oldTimeline.microBeats(at: hostNowMicros + oldOffset) : 0
        sessionTimeline = LinkTimeline(tempo: oldTimeline.tempo, anchorMicroBeats: anchorBeat, anchorMicros: 0)
        // The zero timestamp compares as oldest, so a kept playing flag never
        // outranks a real transport change heard later.
        startStop = keepingBeat && oldPlaying
            ? LinkStartStop(isPlaying: true, microBeats: anchorBeat, timestampMicros: 0)
            : LinkStartStop()
        ghostOffsetMicros = newOffset
        clientTimeline = linkUpdatedClientTimeline(
            client: clientTimeline,
            session: sessionTimeline,
            hostNowMicros: hostNowMicros,
            ghostOffsetMicros: newOffset
        )
        otherSessions.removeAll()
        measurements.removeAll()
        guardUntilMicros = nil
        nextOwnMeasureMicros = nil
        dirty = true
    }

    /// Runs a mutation that may change session membership; dropping the last
    /// peer of the session triggers the beat-continuous reset. The single home
    /// of that rule.
    private mutating func watchingMembership(hostNowMicros: Int64, _ body: (inout LinkEngine) -> Void) {
        let before = sessionPeerCount
        body(&self)
        if before > 0 && sessionPeerCount == 0 {
            reset(keepingBeat: true, hostNowMicros: hostNowMicros)
        }
    }

    private mutating func removePeers(_ keys: [PeerKey], hostNowMicros: Int64) {
        guard !keys.isEmpty else { return }
        watchingMembership(hostNowMicros: hostNowMicros) { engine in
            for key in keys { engine.peers.removeValue(forKey: key) }
        }
    }

    /// A gateway went away: its peers drop as if they had said goodbye, and
    /// its in-flight measurements fail.
    mutating func gatewayClosed(_ address: UInt32, hostNowMicros: Int64) {
        let gone = peers.keys.filter { $0.gateway == address }
        removePeers(gone, hostNowMicros: hostNowMicros)
        for (endpoint, run) in measurements where run.gateway == address {
            measurements.removeValue(forKey: endpoint)
            measurementFailed(run, hostNowMicros: hostNowMicros)
        }
    }

    // MARK: Session timing

    private mutating func updateSessionTiming(
        _ timeline: LinkTimeline,
        ghostOffset: Int64,
        hostNowMicros: Int64
    ) {
        sessionTimeline = timeline
        ghostOffsetMicros = ghostOffset
        clientTimeline = linkUpdatedClientTimeline(
            client: clientTimeline,
            session: timeline,
            hostNowMicros: hostNowMicros,
            ghostOffsetMicros: ghostOffset
        )
    }

    /// Incoming state for this node's own session. The timeline is adopted
    /// only when its anchor beat is strictly larger (that is the priority
    /// rule the whole session agrees on); transport is last writer wins on a
    /// strictly newer stamp. Adopted changes mark the state dirty, so nodes
    /// relay what they adopt.
    mutating func applySessionState(
        timeline: LinkTimeline,
        startStop incoming: LinkStartStop,
        hostNowMicros: Int64
    ) {
        let guarded = guardUntilMicros.map { hostNowMicros < $0 } ?? false
        if !guarded && timeline.anchorMicroBeats > sessionTimeline.anchorMicroBeats {
            updateSessionTiming(timeline, ghostOffset: ghostOffsetMicros, hostNowMicros: hostNowMicros)
            dirty = true
        }
        if incoming.timestampMicros > startStop.timestampMicros {
            startStop = incoming
            dirty = true
        }
    }

    private mutating func processPeerState(
        sessionId incoming: LinkNodeId,
        timeline: LinkTimeline,
        startStop incomingStartStop: LinkStartStop,
        measurementEndpoint: LinkEndpoint?,
        gateway: LinkGatewayInfo,
        hostNowMicros: Int64,
        actions: inout [LinkAction]
    ) {
        if incoming == sessionId {
            applySessionState(timeline: timeline, startStop: incomingStartStop, hostNowMicros: hostNowMicros)
        } else if var known = otherSessions[incoming] {
            // The same priority rules as for one's own session.
            if timeline.anchorMicroBeats > known.timeline.anchorMicroBeats {
                known.timeline = timeline
            }
            if incomingStartStop.timestampMicros > known.startStop.timestampMicros {
                known.startStop = incomingStartStop
            }
            otherSessions[incoming] = known
        } else {
            otherSessions[incoming] = ForeignSession(timeline: timeline, startStop: incomingStartStop)
            if let endpoint = measurementEndpoint {
                startMeasurement(
                    endpoint: endpoint,
                    sessionId: incoming,
                    gateway: gateway.address,
                    hostNowMicros: hostNowMicros,
                    actions: &actions
                )
            }
        }
    }

    // MARK: Discovery

    mutating func handleDiscovery(
        _ data: Data,
        from source: LinkEndpoint,
        gateway: LinkGatewayInfo,
        hostNowMicros: Int64
    ) -> [LinkAction] {
        guard let message = LinkWire.parseDiscovery(data), message.sender != nodeId else { return [] }
        var actions: [LinkAction] = []
        switch message.kind {
        case .byeBye:
            removePeers([PeerKey(node: message.sender, gateway: gateway.address)], hostNowMicros: hostNowMicros)
        case .alive, .response:
            // A state message without a session id is useless; the other
            // entries fall back to their defaults.
            guard let incomingSession = message.payload.session else { break }
            let timeline = message.payload.timeline ?? LinkTimeline()
            let incomingStartStop = message.payload.startStop ?? LinkStartStop()
            let endpoint = message.payload.measurementEndpoint
            // A peer switching to another session can strand this node just
            // like a timeout would, hence the membership watch on the upsert.
            watchingMembership(hostNowMicros: hostNowMicros) { engine in
                engine.peers[PeerKey(node: message.sender, gateway: gateway.address)] = Peer(
                    sessionId: incomingSession,
                    measurementEndpoint: endpoint,
                    expiresMicros: hostNowMicros + Int64(message.ttl) * 1_000_000
                )
                engine.processPeerState(
                    sessionId: incomingSession,
                    timeline: timeline,
                    startStop: incomingStartStop,
                    measurementEndpoint: endpoint,
                    gateway: gateway,
                    hostNowMicros: hostNowMicros,
                    actions: &actions
                )
            }
            if message.kind == .alive {
                actions.append(.unicastDiscovery(
                    gateway: gateway.address,
                    to: source,
                    data: stateMessage(kind: .response, measurementEndpoint: gateway.measurementEndpoint)
                ))
            }
        }
        return actions
    }

    /// The full state payload every announcement carries.
    func stateMessage(kind: LinkDiscoveryKind, measurementEndpoint: LinkEndpoint) -> Data {
        var payload = Data()
        LinkWire.encodeTimeline(sessionTimeline, into: &payload)
        LinkWire.encodeSession(sessionId, into: &payload)
        LinkWire.encodeStartStop(startStop, into: &payload)
        LinkWire.encodeMeasurementEndpoint(measurementEndpoint, into: &payload)
        return LinkWire.encodeDiscovery(kind: kind, ttl: Self.peerTTLSeconds, sender: nodeId, payload: payload)
    }

    // MARK: Measurement

    private func pingDatagram(hostNowMicros: Int64, previousGhostMicros: Int64?) -> Data {
        var payload = Data()
        LinkWire.encodeMicros(LinkPayloadKey.hostTime, hostNowMicros, into: &payload)
        if let previous = previousGhostMicros {
            LinkWire.encodeMicros(LinkPayloadKey.previousGhostTime, previous, into: &payload)
        }
        return LinkWire.encodeMeasurement(kind: .ping, payload: payload)
    }

    private mutating func startMeasurement(
        endpoint: LinkEndpoint,
        sessionId target: LinkNodeId,
        gateway: UInt32,
        hostNowMicros: Int64,
        actions: inout [LinkAction]
    ) {
        guard measurements[endpoint] == nil,
              !measurements.values.contains(where: { $0.sessionId == target }) else { return }
        measurements[endpoint] = Measurement(
            sessionId: target,
            gateway: gateway,
            deadlineMicros: hostNowMicros + Self.pingTimeout
        )
        actions.append(.unicastMeasurement(
            gateway: gateway,
            to: endpoint,
            data: pingDatagram(hostNowMicros: hostNowMicros, previousGhostMicros: nil)
        ))
    }

    mutating func handleMeasurement(
        _ data: Data,
        from source: LinkEndpoint,
        gateway: LinkGatewayInfo,
        hostNowMicros: Int64
    ) -> [LinkAction] {
        guard let (kind, payload) = LinkWire.parseMeasurement(data) else { return [] }
        switch kind {
        case .ping:
            // The responder is stateless: answer with the session, our ghost
            // time, and a verbatim echo of whatever the ping carried.
            guard payload.count <= Self.maxPingPayload else { return [] }
            var body = Data()
            LinkWire.encodeSession(sessionId, into: &body)
            LinkWire.encodeMicros(LinkPayloadKey.ghostTime, hostNowMicros + ghostOffsetMicros, into: &body)
            body.append(payload)
            return [.unicastMeasurement(
                gateway: gateway.address,
                to: source,
                data: LinkWire.encodeMeasurement(kind: .pong, payload: body)
            )]
        case .pong:
            return handlePong(payload, from: source, gateway: gateway, hostNowMicros: hostNowMicros)
        }
    }

    /// The initiator side: each pong yields one or two offset estimates, the
    /// next ping is chained at once, and past the point count the median of
    /// the estimates becomes the ghost transform.
    private mutating func handlePong(
        _ payload: Data,
        from source: LinkEndpoint,
        gateway: LinkGatewayInfo,
        hostNowMicros: Int64
    ) -> [LinkAction] {
        guard let entries = LinkWire.parsePayload([UInt8](payload)[0...]),
              var run = measurements[source] else { return [] }
        guard entries.session == run.sessionId else {
            // The responder is no longer in the session this run set out to
            // measure.
            measurements.removeValue(forKey: source)
            measurementFailed(run, hostNowMicros: hostNowMicros)
            return []
        }
        let ghostSend = entries.ghostTimeMicros ?? 0
        let pingSend = entries.hostTimeMicros ?? 0   // our own echoed send time
        let ghostPrevious = entries.previousGhostTimeMicros ?? 0
        if ghostSend != 0 && pingSend != 0 {
            run.points.append(ghostSend - (hostNowMicros + pingSend) / 2)
            if ghostPrevious != 0 {
                run.points.append((ghostSend + ghostPrevious) / 2 - pingSend)
            }
        }
        if run.points.count > Self.measurementPoints {
            measurements.removeValue(forKey: source)
            measurementSucceeded(run, hostNowMicros: hostNowMicros)
            return []
        }
        run.deadlineMicros = hostNowMicros + Self.pingTimeout
        run.retries = 0
        measurements[source] = run
        return [.unicastMeasurement(
            gateway: gateway.address,
            to: source,
            data: pingDatagram(hostNowMicros: hostNowMicros, previousGhostMicros: ghostSend)
        )]
    }

    mutating func measurementSucceeded(_ run: Measurement, hostNowMicros: Int64) {
        let sorted = run.points.sorted()
        guard !sorted.isEmpty else { return }
        let offset = sorted.count % 2 == 1
            ? sorted[sorted.count / 2]
            : (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2

        if run.sessionId == sessionId {
            // A periodic re-measurement of the session already joined: track
            // clock drift, keep the timeline.
            updateSessionTiming(sessionTimeline, ghostOffset: offset, hostNowMicros: hostNowMicros)
            nextOwnMeasureMicros = hostNowMicros + Self.remeasurePeriod
            return
        }
        guard let foreign = otherSessions[run.sessionId] else { return }
        // Arbitration: the older session wins. Ghost time starts at zero when
        // a session is founded, so the older one reads the larger ghost time;
        // within half a second of each other, the smaller session id wins.
        let ghostDiff = offset - ghostOffsetMicros
        let join = ghostDiff > Self.sessionEps
            || (abs(ghostDiff) < Self.sessionEps && run.sessionId < sessionId)
        guard join else { return }
        // Keep the abandoned session cached so it is not measured again.
        otherSessions[sessionId] = ForeignSession(timeline: sessionTimeline, startStop: startStop)
        otherSessions.removeValue(forKey: run.sessionId)
        sessionId = run.sessionId
        startStop = LinkStartStop()   // transport resets on join
        updateSessionTiming(foreign.timeline, ghostOffset: offset, hostNowMicros: hostNowMicros)
        nextOwnMeasureMicros = hostNowMicros + Self.remeasurePeriod
        dirty = true
    }

    private mutating func measurementFailed(_ run: Measurement, hostNowMicros: Int64) {
        if run.sessionId == sessionId {
            nextOwnMeasureMicros = hostNowMicros + Self.remeasurePeriod
        } else {
            // Forget the foreign session; a later sighting measures it again.
            otherSessions.removeValue(forKey: run.sessionId)
        }
    }

    // MARK: Periodic work

    mutating func tick(hostNowMicros: Int64, gateways: [LinkGatewayInfo]) -> [LinkAction] {
        var actions: [LinkAction] = []
        prunePeers(hostNowMicros: hostNowMicros)
        tickMeasurements(hostNowMicros: hostNowMicros, gateways: gateways, actions: &actions)
        tickOwnMeasure(hostNowMicros: hostNowMicros, gateways: gateways, actions: &actions)
        tickBroadcast(hostNowMicros: hostNowMicros, gateways: gateways, actions: &actions)
        return actions
    }

    /// Drops peers whose advertised lifetime and the one-second grace padding
    /// have both elapsed.
    private mutating func prunePeers(hostNowMicros: Int64) {
        let expired = peers.filter { hostNowMicros >= $0.value.expiresMicros + Self.prunePadding }.map(\.key)
        removePeers(expired, hostNowMicros: hostNowMicros)
    }

    /// Ping timeouts: retry with a fresh ping, fail past the retry budget or
    /// when the run's gateway is gone.
    private mutating func tickMeasurements(
        hostNowMicros: Int64,
        gateways: [LinkGatewayInfo],
        actions: inout [LinkAction]
    ) {
        var failed: [LinkEndpoint] = []
        for (endpoint, var run) in measurements where hostNowMicros >= run.deadlineMicros {
            run.retries += 1
            let gatewayAlive = gateways.contains { $0.address == run.gateway }
            if gatewayAlive && run.retries <= Self.maxPingRetries {
                run.deadlineMicros = hostNowMicros + Self.pingTimeout
                measurements[endpoint] = run
                actions.append(.unicastMeasurement(
                    gateway: run.gateway,
                    to: endpoint,
                    data: pingDatagram(hostNowMicros: hostNowMicros, previousGhostMicros: nil)
                ))
            } else {
                measurements[endpoint] = run
                failed.append(endpoint)
            }
        }
        for endpoint in failed {
            guard let run = measurements.removeValue(forKey: endpoint) else { continue }
            measurementFailed(run, hostNowMicros: hostNowMicros)
        }
    }

    /// The periodic re-measurement of the joined session, skipped when this
    /// node founded it (its own clock defines ghost time then).
    private mutating func tickOwnMeasure(
        hostNowMicros: Int64,
        gateways: [LinkGatewayInfo],
        actions: inout [LinkAction]
    ) {
        guard let due = nextOwnMeasureMicros, hostNowMicros >= due else { return }
        nextOwnMeasureMicros = hostNowMicros + Self.remeasurePeriod
        guard !isSessionFounder,
              !measurements.values.contains(where: { $0.sessionId == sessionId }) else { return }
        // Prefer the session founder, otherwise any member with an endpoint.
        let candidates = peers.filter { $0.value.sessionId == sessionId && $0.value.measurementEndpoint != nil }
        let target = candidates.max { a, b in
            (a.key.node == sessionId ? 1 : 0) < (b.key.node == sessionId ? 1 : 0)
        }
        guard let target,
              let endpoint = target.value.measurementEndpoint,
              gateways.contains(where: { $0.address == target.key.gateway }) else { return }
        startMeasurement(
            endpoint: endpoint,
            sessionId: sessionId,
            gateway: target.key.gateway,
            hostNowMicros: hostNowMicros,
            actions: &actions
        )
    }

    /// The announcement cadence: every 250 ms, or sooner after a state change
    /// but never more often than every 50 ms.
    private mutating func tickBroadcast(
        hostNowMicros: Int64,
        gateways: [LinkGatewayInfo],
        actions: inout [LinkAction]
    ) {
        let due: Bool
        if let last = lastBroadcastMicros {
            let elapsed = hostNowMicros - last
            due = elapsed >= Self.alivePeriod || (dirty && elapsed >= Self.minRebroadcastInterval)
        } else {
            due = true
        }
        guard due, !gateways.isEmpty else { return }
        for gateway in gateways {
            actions.append(.multicast(
                gateway: gateway.address,
                data: stateMessage(kind: .alive, measurementEndpoint: gateway.measurementEndpoint)
            ))
        }
        dirty = false
        lastBroadcastMicros = hostNowMicros
    }

    // MARK: Client-driven changes

    /// Turns a client edit into a session timeline that outranks the current
    /// one by the smallest possible margin, and arms the grace period so the
    /// edit is not immediately overwritten by traffic already in flight.
    mutating func setClientTimeline(_ edited: LinkTimeline, hostNowMicros: Int64) {
        let ghostBeatZero = ghostTimeOfBeatZero(of: edited)
        if sessionTimeline.microBeats(at: ghostBeatZero) == 0
            && edited.tempo.wireEquals(sessionTimeline.tempo) {
            clientTimeline = edited   // no session-visible change
            return
        }
        let newAnchorBeat = max(
            sessionTimeline.microBeats(at: hostNowMicros + ghostOffsetMicros),
            sessionTimeline.anchorMicroBeats + 1
        )
        let rebased = LinkTimeline(tempo: edited.tempo, anchorMicroBeats: 0, anchorMicros: ghostBeatZero)
        sessionTimeline = LinkTimeline(
            tempo: edited.tempo,
            anchorMicroBeats: newAnchorBeat,
            anchorMicros: rebased.micros(at: newAnchorBeat)
        )
        clientTimeline = linkUpdatedClientTimeline(
            client: edited,
            session: sessionTimeline,
            hostNowMicros: hostNowMicros,
            ghostOffsetMicros: ghostOffsetMicros
        )
        guardUntilMicros = hostNowMicros + Self.gracePeriod
        dirty = true
    }

    private func ghostTimeOfBeatZero(of timeline: LinkTimeline) -> Int64 {
        timeline.micros(at: 0) + ghostOffsetMicros
    }

    /// A local transport change, stamped in ghost time and applied only when
    /// newer than the session's current state. Rapid toggles can land in the
    /// same microsecond, so an equal stamp is nudged forward by one; genuinely
    /// older stamps still lose.
    mutating func setTransport(isPlaying: Bool, atHostMicros: Int64) {
        var stamp = atHostMicros + ghostOffsetMicros
        if stamp == startStop.timestampMicros {
            stamp += 1
        }
        guard stamp > startStop.timestampMicros else { return }
        startStop = LinkStartStop(
            isPlaying: isPlaying,
            microBeats: sessionTimeline.microBeats(at: stamp),
            timestampMicros: stamp
        )
        dirty = true
    }
}
