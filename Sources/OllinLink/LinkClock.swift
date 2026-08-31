import Foundation
import os

/// Joins the local network's shared tempo-and-phase session (the Link
/// protocol most music apps speak), so a sketch moves on the same beat as
/// everything else in the room: a DAW, a drum machine app on a phone, another
/// sketch on another Mac. No cabling, no setup: participants find each other
/// over UDP multicast, agree on one tempo, and align their bar phase.
///
/// Create one, `start()` it, then read musical time in `draw()`:
///
/// ```swift
/// let link = LinkClock(tempo: 120)
/// override func setup() { link.start() }
/// override func draw() {
///     let throb = 1 + 0.2 * link.beat                     // snaps on each beat, decays
///     drawCircle(width / 2, height / 2, 120 * throb)
///     let sweep = link.progress(over: 8)                  // a 0…1 ramp every 8 beats
///     rotate(sweep * .tau)
/// }
/// ```
///
/// The reads mirror `TempoClock`, the MIDI-clock sibling, so a sketch written
/// against one moves to the other unchanged: `tempo` (BPM), `beats`
/// (continuous musical time in quarter notes), `beatCount` / `phase` (its
/// whole and fractional parts), `bar` / `barPhase` (over `beatsPerBar`),
/// `beat` (a ready-made 0…1 pulse), and `progress(over:)` for a ramp across
/// any number of beats. `beatsPerBar` doubles as the session quantum: peers
/// that declare the same value land their downbeats together.
///
/// Two differences from the MIDI clock, both part of the protocol's model:
/// the beat grid never stops (there is no transport freeze; `beats` always
/// advances), and `tempo` is writable, because any participant may propose a
/// tempo and the session follows the latest change. `isPlaying` is the
/// session's shared start/stop flag: reading it follows the transport of apps
/// that use it, setting it starts or stops them, and a session that never
/// touches it simply stays `false` while the beat runs on.
///
/// Alone, the clock free-runs at its own tempo, so a sketch behaves the same
/// with or without a session to join. `peerCount` says which one is
/// happening.
///
/// The protocol and its clock sync are implemented independently from
/// published protocol documentation; nothing is vendored. Datagrams arrive on
/// a background queue and the sketch reads on the main thread; all shared
/// state is held behind locks, which is what makes this safe.
public final class LinkClock: @unchecked Sendable {

    // MARK: Stored state

    private struct Shared {
        var engine: LinkEngine
        var gateways: [UInt32: LinkGateway] = [:]
        var isRunning = false
        var quantumMicroBeats: Int64 = 4 * linkMicroBeatsPerBeat
        var ticksSinceRescan = 0
    }

    private let shared: OSAllocatedUnfairLock<Shared>
    private let queue = DispatchQueue(label: "com.ollin.link")
    private let timerStore = OSAllocatedUnfairLock<DispatchSourceTimer?>(uncheckedState: nil)
    /// Test seam: `true` keeps every socket on 127.0.0.1, so a test run never
    /// reaches (or is reached by) a real session on the studio network.
    private let restrictsToLoopback: Bool

    /// How often the housekeeping timer fires, and how many of those ticks
    /// sit between interface rescans (10 ms and 5 s).
    private static let tickInterval: DispatchTimeInterval = .milliseconds(10)
    private static let ticksPerRescan = 500

    // MARK: Lifecycle

    /// Creates a stopped clock with an initial tempo (BPM, clamped to
    /// 20…999). The tempo holds until `start()` finds a session to follow.
    public convenience init(tempo: Double = 120) {
        self.init(tempo: tempo, restrictsToLoopback: false)
    }

    init(tempo: Double, restrictsToLoopback: Bool) {
        self.restrictsToLoopback = restrictsToLoopback
        let engine = LinkEngine(tempo: LinkTempo(bpm: tempo), hostNowMicros: LinkHostClock.nowMicros)
        shared = OSAllocatedUnfairLock(initialState: Shared(engine: engine))
    }

    /// Joins the local network: starts announcing, discovering peers, and
    /// following the session. Starting always begins with a fresh identity,
    /// so a restarted sketch cannot impose stale state on a running session.
    public func start() {
        let now = LinkHostClock.nowMicros
        let alreadyRunning = shared.withLock { state -> Bool in
            if state.isRunning { return true }
            state.isRunning = true
            state.engine.start(hostNowMicros: now)
            return false
        }
        guard !alreadyRunning else { return }
        rescanInterfaces()
        startTimer()
    }

    /// Leaves the session: tells reachable peers goodbye and closes every
    /// socket. Safe to call when not running. The clock keeps its tempo and
    /// free-runs from here.
    public func stop() {
        stopTimer()
        let (gateways, farewell) = shared.withLock { state -> ([LinkGateway], Data?) in
            guard state.isRunning else { return ([], nil) }
            state.isRunning = false
            let open = Array(state.gateways.values)
            state.gateways.removeAll()
            let data = state.engine.byeByeDatagram()
            state.engine.clearNetworkState()
            return (open, data)
        }
        for gateway in gateways {
            if let farewell { gateway.sendMulticast(farewell) }
            gateway.close()
        }
    }

    /// Whether the clock is participating in the network.
    public var isRunning: Bool { shared.withLock { $0.isRunning } }

    /// How many other participants are in the session right now. `0` means
    /// the clock free-runs on its own.
    public var peerCount: Int { shared.withLock { $0.engine.sessionPeerCount } }

    deinit { stop() }

    // MARK: Tempo & transport

    /// The session tempo in beats per minute. Setting it proposes the change
    /// to the whole session, effective now; the session follows the latest
    /// proposal from any participant.
    public var tempo: Double {
        get { shared.withLock { $0.engine.clientTimeline.tempo.bpm } }
        set {
            let now = LinkHostClock.nowMicros
            shared.withLock { state in
                let timeline = state.engine.clientTimeline
                state.engine.setClientTimeline(
                    LinkTimeline(
                        tempo: LinkTempo(bpm: newValue),
                        anchorMicroBeats: timeline.microBeats(at: now),
                        anchorMicros: now
                    ),
                    hostNowMicros: now
                )
            }
        }
    }

    /// The session's shared start/stop flag. Apps that use transport sync
    /// start and stop together on it; the beat grid runs regardless. Setting
    /// it sends the change to the session, stamped now.
    public var isPlaying: Bool {
        get { shared.withLock { $0.engine.startStop.isPlaying } }
        set {
            let now = LinkHostClock.nowMicros
            shared.withLock { $0.engine.setTransport(isPlaying: newValue, atHostMicros: now) }
        }
    }

    // MARK: Reading musical time

    /// Continuous musical time in quarter notes: `2.5` is halfway through the
    /// third beat. Between peers the fractional part is what aligns; each
    /// participant counts its own total from around zero at its own start.
    public var beats: Double {
        let now = LinkHostClock.nowMicros
        let (timeline, quantum) = shared.withLock { ($0.engine.clientTimeline, $0.quantumMicroBeats) }
        return Double(linkPhaseEncodedBeats(timeline, at: now, quantum: quantum)) / 1e6
    }

    /// Which beat the position is on, counted from zero.
    public var beatCount: Int { Int(beats.rounded(.down)) }

    /// Progress through the current beat, `0…1`.
    public var phase: Double {
        let fraction = beats.truncatingRemainder(dividingBy: 1)
        return fraction < 0 ? fraction + 1 : fraction
    }

    /// A 0…1 pulse that snaps to 1 on each beat and decays over ~0.25 s: the
    /// ready-to-use "make it throb on the beat" value.
    public var beat: Double {
        let since = timeSinceBeat
        guard since.isFinite else { return 0 }
        return max(0, 1 - since / 0.25)
    }

    /// Seconds since the last beat landed; drive a decaying flash from it, or
    /// read `beat` for the ready-made pulse.
    public var timeSinceBeat: Double {
        let bpm = tempo
        guard bpm > 0 else { return .greatestFiniteMagnitude }
        return phase * (60 / bpm)
    }

    // MARK: Bars

    /// Beats per bar (default 4). This is also the session quantum: every
    /// participant that declares the same value lands bar phase together, so
    /// two sketches set to 4 hit their downbeats at the same instant.
    public var beatsPerBar: Int {
        get { shared.withLock { Int($0.quantumMicroBeats / linkMicroBeatsPerBeat) } }
        set { shared.withLock { $0.quantumMicroBeats = Int64(max(1, newValue)) * linkMicroBeatsPerBeat } }
    }

    /// Which bar the position is in, counted from zero.
    public var bar: Int { Int((beats / Double(beatsPerBar)).rounded(.down)) }

    /// Progress through the current bar, `0…1`, aligned across the session
    /// for peers sharing the same `beatsPerBar`.
    public var barPhase: Double {
        let now = LinkHostClock.nowMicros
        let (timeline, quantum) = shared.withLock { ($0.engine.clientTimeline, $0.quantumMicroBeats) }
        let encoded = linkPhaseEncodedBeats(timeline, at: now, quantum: quantum)
        return Double(linkPhase(encoded, quantum: quantum)) / Double(quantum)
    }

    // MARK: Ramps

    /// A `0…1` sawtooth across `length` beats, the musical-time sibling of
    /// `loopProgress(over:phase:)`: `progress(over: 8)` ramps once every eight
    /// beats and wraps. `phase` is a fraction-of-cycle head start.
    public func progress(over length: Double, phase: Double = 0) -> Double {
        guard length > 0 else { return 0 }
        let raw = (beats / length + phase).truncatingRemainder(dividingBy: 1)
        return raw < 0 ? raw + 1 : raw
    }

    // MARK: Housekeeping

    private func startTimer() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + Self.tickInterval, repeating: Self.tickInterval, leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in self?.houseTick() }
        timerStore.withLock { existing in
            existing?.cancel()
            existing = timer
        }
        timer.activate()
    }

    private func stopTimer() {
        timerStore.withLock { existing in
            existing?.cancel()
            existing = nil
        }
    }

    private func houseTick() {
        let rescanDue = shared.withLock { state -> Bool in
            guard state.isRunning else { return false }
            state.ticksSinceRescan += 1
            if state.ticksSinceRescan >= Self.ticksPerRescan {
                state.ticksSinceRescan = 0
                return true
            }
            return false
        }
        if rescanDue { rescanInterfaces() }

        let now = LinkHostClock.nowMicros
        let sends = shared.withLock { state -> [(LinkGateway, LinkAction)] in
            guard state.isRunning else { return [] }
            let infos = state.gateways.values.map(\.info)
            return Self.resolve(state.engine.tick(hostNowMicros: now, gateways: infos), in: state)
        }
        Self.perform(sends)
    }

    /// Opens gateways for interfaces that appeared and closes gateways whose
    /// interface went away. Socket setup happens outside the lock, so it
    /// never stalls a read of the clock.
    private func rescanInterfaces() {
        let all = LinkGateway.usableInterfaceAddresses()
        let addresses = restrictsToLoopback ? all.filter { $0 == LinkGateway.loopbackAddress } : all
        let now = LinkHostClock.nowMicros
        let (closing, missing) = shared.withLock { state -> ([LinkGateway], [UInt32]) in
            guard state.isRunning else { return ([], []) }
            let current = Set(addresses)
            var gone: [LinkGateway] = []
            for (address, gateway) in state.gateways where !current.contains(address) {
                state.gateways.removeValue(forKey: address)
                state.engine.gatewayClosed(address, hostNowMicros: now)
                gone.append(gateway)
            }
            return (gone, current.filter { state.gateways[$0] == nil }.sorted())
        }
        closing.forEach { $0.close() }

        for address in missing {
            guard let gateway = try? LinkGateway(address: address) else { continue }
            gateway.start(
                queue: queue,
                onDiscovery: { [weak self] data, source in
                    self?.receiveDiscovery(data, from: source, gatewayAddress: address)
                },
                onMeasurement: { [weak self] data, source in
                    self?.receiveMeasurement(data, from: source, gatewayAddress: address)
                }
            )
            let inserted = shared.withLock { state -> Bool in
                guard state.isRunning, state.gateways[address] == nil else { return false }
                state.gateways[address] = gateway
                return true
            }
            if !inserted { gateway.close() }
        }
    }

    // MARK: Receiving (background queue)

    private func receiveDiscovery(_ data: Data, from source: LinkEndpoint, gatewayAddress: UInt32) {
        let now = LinkHostClock.nowMicros
        let sends = shared.withLock { state -> [(LinkGateway, LinkAction)] in
            guard state.isRunning, let gateway = state.gateways[gatewayAddress] else { return [] }
            let actions = state.engine.handleDiscovery(data, from: source, gateway: gateway.info, hostNowMicros: now)
            return Self.resolve(actions, in: state)
        }
        Self.perform(sends)
    }

    private func receiveMeasurement(_ data: Data, from source: LinkEndpoint, gatewayAddress: UInt32) {
        let now = LinkHostClock.nowMicros
        let sends = shared.withLock { state -> [(LinkGateway, LinkAction)] in
            guard state.isRunning, let gateway = state.gateways[gatewayAddress] else { return [] }
            let actions = state.engine.handleMeasurement(data, from: source, gateway: gateway.info, hostNowMicros: now)
            return Self.resolve(actions, in: state)
        }
        Self.perform(sends)
    }

    /// Pairs each action with its gateway while the lock is held; the sends
    /// themselves happen after it is released.
    private static func resolve(_ actions: [LinkAction], in state: Shared) -> [(LinkGateway, LinkAction)] {
        actions.compactMap { action in
            let address: UInt32
            switch action {
            case .multicast(let gateway, _),
                 .unicastDiscovery(let gateway, _, _),
                 .unicastMeasurement(let gateway, _, _):
                address = gateway
            }
            guard let gateway = state.gateways[address] else { return nil }
            return (gateway, action)
        }
    }

    private static func perform(_ sends: [(LinkGateway, LinkAction)]) {
        for (gateway, action) in sends {
            switch action {
            case .multicast(_, let data):
                gateway.sendMulticast(data)
            case .unicastDiscovery(_, let to, let data):
                gateway.sendDiscovery(data, to: to)
            case .unicastMeasurement(_, let to, let data):
                gateway.sendMeasurement(data, to: to)
            }
        }
    }
}
