import Foundation

/// The pure part of following a beat: onset times in, musical time out.
///
/// Kept apart from anything that listens so it can be tested by handing it
/// times, which is the same reason the renderer knows nothing about an audio
/// engine. Nothing here reads a clock; every time it is told about arrives as
/// an argument.
public struct BeatEngine: Sendable, Hashable {

    /// The slowest and fastest it will believe, in beats per minute.
    ///
    /// Music outside this exists, but a detector hearing a bar as a beat or a
    /// sixteenth as a beat is the common failure, and folding into a range is
    /// what stops a steady tempo being reported at half or twice its value.
    public var range: ClosedRange<Double> = 60...160

    /// How many recent gaps between onsets are kept.
    public var memory: Int = 12

    /// The gaps between the onsets heard so far, newest last.
    private var gaps: [Double] = []
    private var lastOnset: Double?
    /// The musical position at the last onset, and when that was.
    private var anchorBeat: Double = 0
    private var anchorTime: Double = 0
    private var heard = 0

    public init(range: ClosedRange<Double> = 60...160, memory: Int = 12) {
        self.range = range
        self.memory = max(2, memory)
    }

    // MARK: Telling it what happened

    /// Says a beat was heard at `time`, in seconds.
    public mutating func hearBeat(at time: Double) {
        defer { lastOnset = time; heard += 1 }
        guard let lastOnset else {
            anchorTime = time
            anchorBeat = 0
            return
        }
        let gap = time - lastOnset
        // A gap far outside anything musical is a missed beat or a double
        // trigger rather than a tempo, so it teaches nothing.
        guard gap > 0.1, gap < 4 else { return }
        gaps.append(gap)
        if gaps.count > memory { gaps.removeFirst(gaps.count - memory) }

        // The beat is re-anchored on every onset, so the position follows the
        // room rather than drifting away from it, and it moves to the nearest
        // whole beat rather than always the next one: a missed onset should not
        // cost a beat.
        let elapsed = time - anchorTime
        let stepped = max(1, (elapsed / max(1e-6, secondsPerBeat)).rounded())
        anchorBeat += stepped
        anchorTime = time
        rememberOnset()
    }

    // MARK: Reading it

    /// The tempo it has settled on, in beats per minute.
    ///
    /// Zero until it has heard enough to have an opinion.
    public var tempo: Double {
        guard let seconds = typicalGap else { return 0 }
        return 60 / seconds
    }

    /// Whether it has heard enough to be worth following.
    public var isFollowing: Bool { gaps.count >= 3 }

    /// How steady what it is hearing has been, `0...1`.
    ///
    /// One is a machine. Low numbers mean the gaps disagree with each other,
    /// which is either a player breathing or a detector guessing.
    public var steadiness: Double {
        guard gaps.count >= 3, let typical = typicalGap, typical > 1e-9 else { return 0 }
        let spread = gaps.reduce(0) { $0 + abs($1 - typical) } / Double(gaps.count)
        return max(0, 1 - spread / typical)
    }

    /// Where the music has got to, in beats, at `time`.
    ///
    /// Carries on between onsets at the tempo it believes, and is pulled back
    /// onto the beat each time one arrives, so it can be handed straight to a
    /// `StepCounter`.
    public func beats(at time: Double) -> Double {
        guard isFollowing else { return 0 }
        return anchorBeat + (time - anchorTime) / max(1e-6, secondsPerBeat)
    }

    /// How many beats have been heard.
    public var beatCount: Int { heard }

    /// The length of one beat in seconds, folded into the believable range.
    public var secondsPerBeat: Double {
        guard let typical = typicalGap else { return 0.5 }
        return typical
    }

    /// The gap it believes, in seconds, folded into `range`.
    private var typicalGap: Double? {
        guard gaps.count >= 3 else { return nil }
        // The middle value rather than the average: one missed beat doubles a
        // gap, and an average is moved by that where a middle value is not.
        let sorted = gaps.sorted()
        var gap = sorted[sorted.count / 2]

        // Halving and doubling until it lands in the range is what keeps a
        // steady tempo from being reported an octave out. A detector that
        // fires on every eighth note hears twice the tempo, and that is the
        // same music.
        let slowest = 60 / range.lowerBound, fastest = 60 / range.upperBound
        var guard_ = 0
        while gap > slowest, guard_ < 8 { gap /= 2; guard_ += 1 }
        while gap < fastest, guard_ < 8 { gap *= 2; guard_ += 1 }
        return gap
    }

    /// Where the onsets fell inside a cycle of `steps`, as a `Rhythm`.
    ///
    /// This is the room's own pattern, ready to be played back at. It is built
    /// from the beats heard rather than from the tempo, so a pattern that
    /// leaves a gap comes back with that gap in it.
    public func rhythm(steps: Int = 16, perBeat: Double = 1) -> Rhythm {
        let count = max(1, steps)
        var struck = [Bool](repeating: false, count: count)
        guard isFollowing else { return Rhythm(steps: struck) }
        for beat in onsetBeats {
            let step = Int((beat * perBeat).rounded()) % count
            struck[((step % count) + count) % count] = true
        }
        return Rhythm(steps: struck)
    }

    /// The musical positions the onsets landed on, kept for the pattern.
    private var onsetBeats: [Double] = []

    /// Records where an onset fell, called from `hearBeat`.
    private mutating func rememberOnset() {
        onsetBeats.append(anchorBeat)
        if onsetBeats.count > 64 { onsetBeats.removeFirst(onsetBeats.count - 64) }
    }

    /// Forgets everything, for when the music changes.
    public mutating func reset() {
        gaps.removeAll()
        onsetBeats.removeAll()
        lastOnset = nil
        anchorBeat = 0
        anchorTime = 0
        heard = 0
    }
}

/// Follows the beat in whatever a sketch is listening to, so the sketch can
/// play along with it.
///
/// ```swift
/// let mic = AudioInput()
/// lazy var room = BeatFollower(mic)
/// var counter = StepCounter(perBeat: 2)
///
/// override func draw() {
///     room.update(at: time)
///     for step in counter.steps(upTo: room.beats) {
///         synth.play(scale[step % 5], for: 0.2)     // in time with the room
///     }
/// }
/// ```
///
/// The detector underneath hears *arrivals* rather than the beat a drummer
/// would tap, so a steady loop is followed well and rubato is followed badly.
/// ``steadiness`` is how much to trust it.
@MainActor
public final class BeatFollower {

    private let source: any AudioSource
    private var engine: BeatEngine
    private var lastCount = 0

    /// - Parameters:
    ///   - source: anything that hears, usually a microphone or a player.
    ///   - range: the tempos to believe, in beats per minute.
    public init(_ source: any AudioSource, range: ClosedRange<Double> = 60...160) {
        self.source = source
        self.engine = BeatEngine(range: range)
    }

    /// Reads whatever has been heard since the last call. Call once a frame,
    /// handing it the sketch's own clock.
    public func update(at time: Double) {
        // Kept so the reads below can carry the beat forward between onsets
        // rather than answering where it was when the last one landed.
        lastUpdate = time
        // The detector counts beats rather than reporting them one at a time,
        // so what arrives here is how many went by since the last frame.
        let count = source.beatCount
        guard count > lastCount else { return }
        // Anything more than a couple in one frame is the analyzer catching up
        // rather than the room, and pretending they all landed now would teach
        // the engine a gap of zero.
        let missed = min(count - lastCount, 2)
        for index in 0..<missed {
            engine.hearBeat(at: time - Double(missed - 1 - index) * 0.001)
        }
        lastCount = count
    }

    /// The tempo it has settled on, in beats per minute. Zero until it has one.
    public var tempo: Double { engine.tempo }

    /// Where the music has got to, in beats. Hand this to a `StepCounter`.
    public var beats: Double { engine.beats(at: lastUpdate) }

    /// Whether it has heard enough to be worth following.
    public var isFollowing: Bool { engine.isFollowing }

    /// How steady what it is hearing has been, `0...1`.
    public var steadiness: Double { engine.steadiness }

    /// The room's own pattern, as something a sketch can play.
    public func rhythm(steps: Int = 16, perBeat: Double = 1) -> Rhythm {
        engine.rhythm(steps: steps, perBeat: perBeat)
    }

    /// Forgets everything, for when the music changes.
    public func reset() {
        engine.reset()
        lastCount = source.beatCount
    }

    private var lastUpdate: Double = 0
}
