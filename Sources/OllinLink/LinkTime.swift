import Foundation

/// Microsecond reads of the machine's monotonic clock, the time base for every
/// computation in this module. Host timestamps mean something only on this
/// machine: the measurement exchange echoes them back verbatim, but a peer
/// never interprets them in its own clock frame.
enum LinkHostClock {
    private static let microsPerTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1_000
    }()

    /// Monotonic host time in microseconds, with an arbitrary machine epoch.
    static var nowMicros: Int64 { Int64(Double(mach_absolute_time()) * microsPerTick) }
}

/// The wire's beat resolution: beats travel as integer micro-beats, times as
/// integer microseconds. One micro-beat is the smallest representable nudge.
let linkMicroBeatsPerBeat: Int64 = 1_000_000

/// Euclidean remainder into `0..<quantum`, correct for negative values (a beat
/// left of the origin still lands on the right phase). A non-positive quantum
/// returns 0, which turns the phase machinery off.
func linkPhase(_ microBeats: Int64, quantum: Int64) -> Int64 {
    guard quantum > 0 else { return 0 }
    let remainder = microBeats % quantum
    return remainder < 0 ? remainder + quantum : remainder
}

/// A session tempo, held as fractional microseconds per beat (the unit the
/// wire carries) and clamped to the protocol's 20...999 BPM.
struct LinkTempo: Equatable {
    static let minBPM = 20.0
    static let maxBPM = 999.0

    var microsPerBeat: Double

    init(bpm: Double) {
        microsPerBeat = 60e6 / min(max(bpm, Self.minBPM), Self.maxBPM)
    }

    /// From a wire count of whole microseconds per beat; re-clamps.
    init(wire: Int64) {
        self.init(bpm: 60e6 / Double(max(wire, 1)))
    }

    var bpm: Double { 60e6 / microsPerBeat }

    /// What travels: whole microseconds per beat.
    var wire: Int64 { Int64(microsPerBeat.rounded()) }

    /// Equality at wire precision, the resolution at which tempo is
    /// transmitted and therefore semantically comparable.
    func wireEquals(_ other: LinkTempo) -> Bool { wire == other.wire }

    /// The beat span covering a microsecond duration at this tempo.
    func microBeats(inMicros micros: Int64) -> Int64 {
        Int64((Double(micros) / microsPerBeat * 1e6).rounded())
    }

    /// The microsecond duration of a beat span at this tempo.
    func micros(forMicroBeats microBeats: Int64) -> Int64 {
        Int64((Double(microBeats) / 1e6 * microsPerBeat).rounded())
    }
}

/// A beat grid: a tempo plus one anchor pairing a beat with an instant. The
/// session's shared grid anchors in ghost time (this is what travels in the
/// `tmln` entry); the client-facing copy anchors in host time. Beats are
/// micro-beats and instants are microseconds throughout; which clock frame a
/// timeline's instants live in is stated where it is stored.
struct LinkTimeline: Equatable {
    var tempo: LinkTempo
    var anchorMicroBeats: Int64
    var anchorMicros: Int64

    init(tempo: LinkTempo = LinkTempo(bpm: 120), anchorMicroBeats: Int64 = 0, anchorMicros: Int64 = 0) {
        self.tempo = tempo
        self.anchorMicroBeats = anchorMicroBeats
        self.anchorMicros = anchorMicros
    }

    func microBeats(at micros: Int64) -> Int64 {
        anchorMicroBeats + tempo.microBeats(inMicros: micros - anchorMicros)
    }

    func micros(at microBeats: Int64) -> Int64 {
        anchorMicros + tempo.micros(forMicroBeats: microBeats - anchorMicroBeats)
    }
}

/// The beat value reported for `micros` under `quantum`: the unique value
/// within half a quantum of the raw beat whose own residue mod `quantum` is
/// the grid phase (which is measured from the timeline's beat anchor, the
/// origin every participant shares). Reported beats and reported phase then
/// agree by construction, so a bar counter built on these values lands its
/// downbeats where the session lands them.
func linkPhaseEncodedBeats(_ timeline: LinkTimeline, at micros: Int64, quantum: Int64) -> Int64 {
    let raw = timeline.microBeats(at: micros)
    guard quantum > 0 else { return raw }
    // Residues repeat with period `quantum`, so searching upward from the
    // lower edge of the quantum-wide window centered on `raw` finds exactly
    // one value with the target residue.
    let target = raw - timeline.anchorMicroBeats
    let lower = raw - quantum / 2
    return lower + linkPhase(target - lower, quantum: quantum)
}

/// Inverse of `linkPhaseEncodedBeats`: the time at which the phase-encoded
/// beat value occurs.
func linkTimeAtPhaseEncodedBeats(_ timeline: LinkTimeline, microBeats: Int64, quantum: Int64) -> Int64 {
    guard quantum > 0 else { return timeline.micros(at: microBeats) }
    let fromAnchor = microBeats - timeline.anchorMicroBeats
    let raw = timeline.anchorMicroBeats
        + fromAnchor
        - linkPhase(fromAnchor, quantum: quantum)
        + linkPhase(microBeats, quantum: quantum)
    return timeline.micros(at: raw)
}

/// Re-derives the client-facing timeline after the session timing changed.
/// Two requirements shape it: the client's beat magnitude stays continuous at
/// `hostNowMicros` (a joining sketch never sees its own beat jump), and the
/// anchor lands on the host time of session beat zero, the shared origin of
/// the quantization grid, which is what lines bar phase up across peers.
func linkUpdatedClientTimeline(
    client: LinkTimeline,
    session: LinkTimeline,
    hostNowMicros: Int64,
    ghostOffsetMicros: Int64
) -> LinkTimeline {
    let carried = LinkTimeline(
        tempo: session.tempo,
        anchorMicroBeats: client.microBeats(at: hostNowMicros),
        anchorMicros: hostNowMicros
    )
    let hostBeatZero = session.micros(at: 0) - ghostOffsetMicros
    return LinkTimeline(
        tempo: session.tempo,
        anchorMicroBeats: carried.microBeats(at: hostBeatZero),
        anchorMicros: hostBeatZero
    )
}

/// The session transport: whether it plays, the session beat at the change,
/// and the ghost time the change happened at. The all-zero default compares
/// as oldest under the strictly-newer rule, so it is never adopted as an
/// update.
struct LinkStartStop: Equatable {
    var isPlaying = false
    var microBeats: Int64 = 0
    var timestampMicros: Int64 = 0
}
