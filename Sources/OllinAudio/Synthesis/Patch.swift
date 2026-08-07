import Foundation

/// An instrument built rather than picked.
///
/// A ``Voice`` is a fixed chain: something makes a wave, an envelope shapes it,
/// a filter takes part of it away. That covers a great deal and it cannot be
/// rearranged. A `Patch` is the tier underneath, where the routing itself is
/// the value: several oscillators, and what each one does to the others.
///
/// ```swift
/// let bell = Patch.tone(.sine)
///     .modulated(by: .tone(.sine, ratio: 3.5), index: 4)
///
/// synth.voice = Voice(patch: bell, envelope: .percussive)
/// ```
///
/// The relationship is the one the drawing side already has. Bare calls sit on
/// a `Drawer` that can do more; the presets sit on this. Nothing about
/// `Synth(.pluck)` changes because this exists.
///
/// ### What an operator is
///
/// One oscillator with a frequency, a level, and possibly something modulating
/// it. Its frequency is a *ratio* of the note being played rather than a pitch,
/// so a patch is an instrument rather than a chord: ratio 1 is the note, 2 the
/// octave above, 3.5 something that is not a note at all and is where metallic
/// sounds come from.
///
/// An operator's `level` means one of two things depending on where it sits. On
/// an operator that reaches the output it is a mix level. On one that modulates
/// another it is how far it pushes, which is what makes the difference between
/// a slight waver and a bell.
///
/// ### Why it is a fixed size
///
/// A patch travels to the audio thread inside a note, through a queue of
/// preallocated slots, so it has to be something that can be copied a word at a
/// time: no arrays, no references, nothing to allocate. So the operators live
/// in fixed lanes and there are eight of them, the same bargain ``ModalBody``
/// makes with its sixteen tones. Eight is more than most instruments worth
/// having need, and a patch that would exceed it says so rather than growing.
public struct Patch: Sendable, Hashable, Codable {

    /// The most operators one patch may hold.
    public static let maxOperators = 8

    /// Each operator's frequency as a multiple of the note being played.
    var ratios: SIMD8<Double> = .zero
    /// Each operator's level, which is a mix level or a modulation depth.
    var levels: SIMD8<Double> = .zero
    /// How much of its own last output each operator is fed back into itself.
    var feedbacks: SIMD8<Double> = .zero
    /// Each operator's shape, as an index into `Waveform.allCases`.
    var shapes: SIMD8<UInt8> = .zero
    /// Which operator modulates each one, or -1 for none. Always an earlier
    /// lane, so one forward pass evaluates the whole patch.
    var modulators: SIMD8<Int8> = SIMD8(repeating: -1)
    /// Which operators reach the output, one bit each.
    var outputs: UInt8 = 0
    /// How many lanes are in use.
    var operatorCount: UInt8 = 0

    // MARK: Making one

    /// One oscillator, sounding on its own.
    ///
    /// - Parameters:
    ///   - waveform: the shape it traces. Sine is the one to reach for: almost
    ///     everything interesting here comes from sines pushing each other
    ///     around rather than from a complicated shape to begin with.
    ///   - ratio: its frequency as a multiple of the note. Whole numbers give
    ///     harmonics and stay musical; anything else gives the inharmonic tones
    ///     that bells and metal are made of.
    ///   - level: how loud it is, or how hard it pushes when it is modulating.
    public static func tone(_ waveform: Waveform = .sine,
                            ratio: Double = 1, level: Double = 1) -> Patch {
        var patch = Patch()
        patch.ratios[0] = max(0, ratio)
        patch.levels[0] = max(0, level)
        patch.shapes[0] = waveform.shapeIndex
        patch.outputs = 1
        patch.operatorCount = 1
        return patch
    }

    /// This patch with another pushing it around.
    ///
    /// The other patch stops being heard and starts being felt: its operators
    /// move where this one is read in its cycle rather than reaching the output
    /// themselves. That is the whole of frequency modulation, and the reason it
    /// is worth having is that it puts harmonics into a sine, which no amount
    /// of filtering can do.
    ///
    /// ```swift
    /// Patch.tone(.sine).modulated(by: .tone(.sine, ratio: 2), index: 3)
    /// ```
    ///
    /// - Parameters:
    ///   - other: what does the pushing.
    ///   - index: how hard. Small numbers waver; past about 2 it is a new
    ///     instrument rather than the old one wobbling.
    public func modulated(by other: Patch, index: Double) -> Patch {
        // The modulator's operators go in first, so every modulator sits in an
        // earlier lane than what it modulates and one pass evaluates the lot.
        guard var joined = Patch.joining(other, then: self) else { return self }

        let shift = Int(other.operatorCount)
        // What the modulator hands over is its own output, at the depth asked
        // for: an operator's level is its modulation index once it is pushing
        // something rather than being heard.
        var source: Int?
        for lane in 0..<Int(other.operatorCount) where other.reachesOutput(lane) {
            joined.levels[lane] = max(0, index)
            joined.outputs &= ~(1 << UInt8(lane))
            source = lane
        }
        guard let source else { return self }

        for lane in 0..<Int(operatorCount) where reachesOutput(lane) {
            joined.modulators[lane + shift] = Int8(source)
        }
        return joined
    }

    /// Both patches sounding at once.
    ///
    /// Additive rather than modulating: each keeps its own voice and the two
    /// are heard together, which is how a patch gets a body and a strike, or
    /// two detuned copies of itself.
    public func mixed(with other: Patch) -> Patch {
        Patch.joining(self, then: other) ?? self
    }

    /// This patch with its output operators pushing themselves.
    ///
    /// One operator modulating itself is the cheapest way to a bright, buzzing
    /// tone: at small amounts it is a warm sawtooth, and past about half it
    /// breaks up into noise, which is useful and is not a mistake.
    public func fedBack(_ amount: Double) -> Patch {
        var patch = self
        for lane in 0..<Int(operatorCount) where reachesOutput(lane) {
            patch.feedbacks[lane] = min(max(0, amount), 1)
        }
        return patch
    }

    /// This patch at a different level, for balancing one against another.
    public func at(level: Double) -> Patch {
        var patch = self
        for lane in 0..<Int(operatorCount) where reachesOutput(lane) {
            patch.levels[lane] = max(0, level)
        }
        return patch
    }

    /// This patch moved to a different frequency ratio.
    public func at(ratio: Double) -> Patch {
        var patch = self
        for lane in 0..<Int(operatorCount) where reachesOutput(lane) {
            patch.ratios[lane] = max(0, ratio)
        }
        return patch
    }

    // MARK: Reading it

    /// How many operators are in use.
    public var count: Int { Int(operatorCount) }

    /// Whether an operator's sound reaches the output rather than only pushing
    /// something else.
    func reachesOutput(_ lane: Int) -> Bool {
        guard lane >= 0, lane < Int(operatorCount) else { return false }
        return outputs & (1 << UInt8(lane)) != 0
    }

    /// Everything one operator is, for reading a patch back.
    public struct Operator: Sendable, Hashable {
        public var waveform: Waveform
        public var ratio: Double
        public var level: Double
        public var feedback: Double
        /// Which operator pushes this one, or nil.
        public var modulatedBy: Int?
        /// Whether it is heard rather than only felt.
        public var reachesOutput: Bool
    }

    /// The operators, in the order they are evaluated.
    public var operators: [Operator] {
        (0..<count).map { lane in
            Operator(waveform: Waveform(shapeIndex: shapes[lane]),
                     ratio: ratios[lane], level: levels[lane],
                     feedback: feedbacks[lane],
                     modulatedBy: modulators[lane] >= 0 ? Int(modulators[lane]) : nil,
                     reachesOutput: reachesOutput(lane))
        }
    }

    // MARK: Joining two

    /// Two patches side by side, the first's lanes then the second's.
    ///
    /// Nil when the two together would need more lanes than there are, which
    /// the callers turn into leaving the patch as it was. Refusing is better
    /// than quietly dropping an operator: a patch with a piece missing is a
    /// different instrument, and a silent one is worse than a note in the log.
    private static func joining(_ first: Patch, then second: Patch) -> Patch? {
        let total = Int(first.operatorCount) + Int(second.operatorCount)
        guard total <= maxOperators else {
            audioNoteOnce("a patch can hold \(maxOperators) operators and this one "
                          + "would need \(total), so the change was not made.")
            return nil
        }

        var joined = first
        let shift = Int(first.operatorCount)
        for lane in 0..<Int(second.operatorCount) {
            let moved = lane + shift
            joined.ratios[moved] = second.ratios[lane]
            joined.levels[moved] = second.levels[lane]
            joined.feedbacks[moved] = second.feedbacks[lane]
            joined.shapes[moved] = second.shapes[lane]
            // A modulator's lane number moves with it.
            joined.modulators[moved] = second.modulators[lane] >= 0
                ? Int8(Int(second.modulators[lane]) + shift) : -1
            if second.reachesOutput(lane) { joined.outputs |= 1 << UInt8(moved) }
        }
        joined.operatorCount = UInt8(total)
        return joined
    }

    // MARK: Named patches

    /// Two sines a fifth apart, which is about the plainest thing worth having.
    public static let simple = Patch.tone(.sine)

    /// A sine pushed by another at three and a half times its frequency, which
    /// is not a harmonic, so what comes out has no pitch class of its own and
    /// rings like struck metal.
    public static let bell = Patch.tone(.sine)
        .modulated(by: .tone(.sine, ratio: 3.5), index: 4)

    /// A sine pushed hard by one an octave up, which fills in the harmonics
    /// a filter would have had to take away from something brighter.
    public static let brass = Patch.tone(.sine)
        .modulated(by: .tone(.sine, ratio: 2), index: 2.4)

    /// Pushed at a ratio just off a whole number, so the two drift against each
    /// other and the tone moves without anything moving it.
    public static let glass = Patch.tone(.sine)
        .modulated(by: .tone(.sine, ratio: 5.01), index: 1.6)

    /// One operator pushing itself, which is the cheap way to a buzzing tone.
    public static let buzz = Patch.tone(.sine).fedBack(0.62)

    /// A body and a strike heard together rather than one pushing the other.
    public static let struck = Patch.tone(.sine, level: 0.7)
        .mixed(with: Patch.tone(.sine, ratio: 7.1, level: 0.25)
            .modulated(by: .tone(.sine, ratio: 3.1), index: 3))
}

extension Waveform {
    /// The shape's position in `allCases`, for the fixed lanes a patch uses.
    var shapeIndex: UInt8 {
        UInt8(Waveform.allCases.firstIndex(of: self) ?? 0)
    }

    /// The shape at a position, falling back to a sine.
    init(shapeIndex: UInt8) {
        let all = Waveform.allCases
        self = Int(shapeIndex) < all.count ? all[Int(shapeIndex)] : .sine
    }
}
