import Foundation
import Ollin

/// Something struck, described by the frequencies it rings at.
///
/// A struck object does not make a wave. It makes a handful of pure tones at
/// once, each fading at its own rate, and which tones those are is decided by
/// the object's shape. That is why a bar and a drum and a bell are recognisably
/// different things whatever they are made of, and it is why a shape you drew
/// can be struck:
///
/// ```swift
/// let bell = ModalBody(shape: outline)
/// let synth = Synth(Voice(body: bell))
/// synth.play("C4")
/// ```
///
/// The frequencies come out of the geometry rather than being chosen. A round
/// shape rings at the ratios a drumhead does, a square one at the ratios a
/// square membrane does, and a shape nobody has a name for rings at whatever
/// its own geometry implies. The note you play decides where that set of ratios
/// sits; the shape decides the set.
public struct ModalBody: Sendable, Hashable, Codable {

    /// The most tones one body can ring at.
    ///
    /// A struck sound is a handful of partials, not a spectrum, and the cap is
    /// what lets a body travel to the audio thread without allocating.
    public static let maxModes = 16

    /// One of the tones a body rings at.
    public struct Mode: Sendable, Hashable, Codable {
        /// Its frequency, as a multiple of the first one. The first is 1.
        public var ratio: Double
        /// How much of it the strike puts into the sound, `0...1`.
        public var gain: Double

        public init(ratio: Double, gain: Double = 1) {
            self.ratio = max(0, ratio)
            self.gain = max(0, gain)
        }
    }

    private var ratios: SIMD16<Double>
    private var gains: SIMD16<Double>

    /// How many tones this body rings at.
    public private(set) var count: Int

    /// How long the first tone takes to fade, in seconds.
    public var decay: Double

    /// How much sooner the higher tones go than the first, `0...3`.
    ///
    /// At 0 they all fade together, which is a bell: the whole sound stays
    /// where it started. At 1 a tone twice as high goes twice as fast, which is
    /// most struck things. Past that it is a knock rather than a note, because
    /// everything but the bottom is gone before you have heard it.
    public var damping: Double

    /// How hard the strike is, `0...1`.
    ///
    /// A hard, small mallet is over in a moment and sets everything ringing; a
    /// soft one leans on the object and only the low tones answer. This is the
    /// same distinction as a fingertip against a plectrum on a string, and it
    /// is the difference between a click and a thump.
    public var hardness: Double

    /// A body from a set of tones you already have.
    public init(modes: [Mode], decay: Double = 2.0, damping: Double = 1.0, hardness: Double = 0.7) {
        var ratios = SIMD16<Double>()
        var gains = SIMD16<Double>()
        // The first mode is what everything else is measured against, so the
        // list is put in order and normalized against its lowest member.
        let ordered = modes.filter { $0.ratio > 0 && $0.gain > 0 }
            .sorted { $0.ratio < $1.ratio }
            .prefix(ModalBody.maxModes)
        let lowest = ordered.first?.ratio ?? 1
        let loudest = ordered.map(\.gain).max() ?? 1
        for (index, mode) in ordered.enumerated() {
            ratios[index] = mode.ratio / lowest
            gains[index] = mode.gain / loudest
        }
        self.ratios = ratios
        self.gains = gains
        self.count = ordered.count
        self.decay = max(0.02, decay)
        self.damping = min(max(0, damping), 3)
        self.hardness = min(max(0, hardness), 1)
    }

    /// The tones this body rings at, lowest first.
    public var modes: [Mode] {
        (0..<count).map { Mode(ratio: ratios[$0], gain: gains[$0]) }
    }

    /// The frequency of a mode, given the note being played.
    public func frequency(of index: Int, playing pitch: Pitch) -> Double {
        guard index >= 0, index < count else { return 0 }
        return pitch.frequency * ratios[index]
    }

    /// Read by the render side, which wants the raw lanes rather than an array.
    func lanes() -> (ratios: SIMD16<Double>, gains: SIMD16<Double>, count: Int) {
        (ratios, gains, count)
    }

    // MARK: - Bodies with names

    /// A round drumhead. Its tones are not whole multiples of each other, which
    /// is why a drum has a pitch you can argue about.
    public static let drum = ModalBody(
        modes: zip(besselZeros, [1.0, 0.82, 0.66, 0.55, 0.5, 0.42, 0.36, 0.32,
                                 0.28, 0.26, 0.22, 0.2, 0.19, 0.16, 0.15, 0.14])
            .map { Mode(ratio: $0 / ModalBody.besselZeros[0], gain: $1) },
        decay: 0.9, damping: 1.2, hardness: 0.75
    )

    /// A square plate, struck. Nearer to whole multiples than a drum is, so it
    /// has more of a note to it.
    public static let plate = ModalBody(
        modes: squareRatios.enumerated().map { index, ratio in
            Mode(ratio: ratio, gain: pow(0.82, Double(index)))
        },
        decay: 1.6, damping: 0.9, hardness: 0.7
    )

    /// A bar free at both ends, which is what a xylophone key is. Its tones are
    /// far apart and not related by anything simple, so it reads as a pitch with
    /// a knock on the front rather than a chord.
    public static let bar = ModalBody(
        modes: [
            Mode(ratio: 1, gain: 1), Mode(ratio: 2.756, gain: 0.42),
            Mode(ratio: 5.404, gain: 0.2), Mode(ratio: 8.933, gain: 0.1),
            Mode(ratio: 13.344, gain: 0.05), Mode(ratio: 18.639, gain: 0.03),
        ],
        decay: 1.1, damping: 1.4, hardness: 0.85
    )

    /// A bell, tuned the way founders tune one: a hum an octave below, and a
    /// minor third that is what makes a bell sound like a bell.
    public static let bell = ModalBody(
        modes: [
            Mode(ratio: 0.5, gain: 0.6), Mode(ratio: 1.0, gain: 1.0),
            Mode(ratio: 1.2, gain: 0.85), Mode(ratio: 1.5, gain: 0.6),
            Mode(ratio: 2.0, gain: 0.75), Mode(ratio: 2.5, gain: 0.4),
            Mode(ratio: 2.67, gain: 0.3), Mode(ratio: 3.0, gain: 0.35),
            Mode(ratio: 4.0, gain: 0.28), Mode(ratio: 5.33, gain: 0.16),
        ],
        decay: 6.0, damping: 0.35, hardness: 0.6
    )

    /// A block of wood. The same tones as a bar, gone almost at once.
    public static let wood = ModalBody(
        modes: ModalBody.bar.modes, decay: 0.16, damping: 1.6, hardness: 1.0
    )

    /// A glass, rung rather than struck: very little at the front and a long
    /// pure tone behind it.
    public static let glass = ModalBody(
        modes: [
            Mode(ratio: 1, gain: 1), Mode(ratio: 2.32, gain: 0.35),
            Mode(ratio: 4.25, gain: 0.14), Mode(ratio: 6.63, gain: 0.06),
        ],
        decay: 5.5, damping: 0.5, hardness: 0.35
    )

    /// The first sixteen zeros of the Bessel functions, in order, which are what
    /// a round drumhead rings at.
    static let besselZeros: [Double] = [
        2.404826, 3.831706, 5.135622, 5.520078, 6.380162, 7.015587, 7.588342,
        8.417244, 8.653728, 8.771484, 9.761023, 9.936110, 10.173468, 11.064709,
        11.086370, 11.619841,
    ]

    /// What a square membrane rings at: the square roots of `m² + n²`, measured
    /// against the lowest of them.
    static let squareRatios: [Double] = {
        var values = [Double]()
        for m in 1...6 {
            for n in 1...6 { values.append((Double(m * m + n * n) / 2).squareRoot()) }
        }
        return Array(values.sorted().prefix(ModalBody.maxModes))
    }()
}
