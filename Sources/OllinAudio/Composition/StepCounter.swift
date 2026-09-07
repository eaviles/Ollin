import Foundation

/// Turns musical time into step numbers.
///
/// Everything else here answers a step number and nothing here has a clock, so
/// this is the piece in between: hand it where the music has got to, in beats,
/// and it hands back the steps that have just gone by.
///
/// ```swift
/// let tempo: Tempo = 120
/// var counter = StepCounter(perBeat: 4)
///
/// override func draw() {
///     for step in counter.steps(upTo: tempo.beats(at: time)) {
///         if rhythm[step] { synth.play(scale[step]) }
///     }
/// }
/// ```
///
/// It returns a range rather than one step because a frame is longer than a
/// step at any decent tempo, and a step that fell inside a frame still has to
/// be played. Which is also why the beat number comes from outside: from the
/// sketch clock through a `Tempo`, from a beat detected in the music, or from
/// a `TempoClock` following a drum machine. This tier stays out of it.
///
/// If time jumps a long way, because the machine stalled or the sketch was
/// dragged somewhere else, it skips ahead to the step it landed on rather than
/// firing every step in between at once. ``maxCatchUp`` is where that line is.
public struct StepCounter: Sendable, Hashable {

    /// How many steps go by in one beat. Four is sixteenth notes.
    public var perBeat: Double

    /// The most steps to hand out for a single frame before deciding that time
    /// jumped rather than passed.
    public var maxCatchUp: Int

    /// The next step that has not been handed out yet.
    public private(set) var nextStep = 0

    public init(perBeat: Double = 4, maxCatchUp: Int = 16) {
        self.perBeat = perBeat
        self.maxCatchUp = max(1, maxCatchUp)
    }

    /// The steps reached since the last call.
    ///
    /// Empty when no step has gone by, which is most frames. The first call
    /// always includes step 0, so a pattern starts on the downbeat.
    public mutating func steps(upTo beats: Double) -> Range<Int> {
        let rate = max(1e-6, perBeat)
        let position = max(0, beats)
        let end = Int((position * rate).rounded(.down)) + 1

        if end == nextStep { return nextStep..<nextStep }

        // Time going backwards means a loop came round or the sketch was
        // seeked. Report the step it landed on, so a repeating figure still
        // begins, and carry on from there.
        if end < nextStep {
            nextStep = end
            return max(0, end - 1)..<end
        }

        // Too many at once is a stall, not a passage of music. Playing them all
        // would empty the pattern into a single frame.
        if end - nextStep > maxCatchUp {
            nextStep = end
            return (end - 1)..<end
        }

        let reached = nextStep..<end
        nextStep = end
        return reached
    }

    /// Moves the counter to a position without reporting the steps in between.
    ///
    /// The next call reports only what happens after this point, so a sketch
    /// can start the music somewhere other than the beginning without hearing
    /// everything it skipped.
    public mutating func reset(to beats: Double = 0) {
        let rate = max(1e-6, perBeat)
        nextStep = Int((max(0, beats) * rate).rounded(.down)) + 1
    }
}
