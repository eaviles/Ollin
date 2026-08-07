import Foundation

/// The shape an oscillator traces through one cycle, brightest last.
///
/// A geometric wave has corners, and a corner holds harmonics past every
/// sampling limit, so the naive shapes fold energy back down the spectrum as a
/// gritty ring that tracks pitch the wrong way. `Oscillator` suppresses that by
/// laying a polynomial residual over each discontinuity, so a sawtooth stays a
/// sawtooth at the top of the keyboard.
public enum Waveform: String, Sendable, Hashable, CaseIterable, Codable {
    /// One partial, no harmonics: the plain tone.
    case sine
    /// Odd harmonics falling away quickly: hollow, flute-like.
    case triangle
    /// Every harmonic: bright and buzzing, the classic string and brass source.
    case sawtooth
    /// Odd harmonics only: hollow and reedy, the classic wind and bass source.
    case square
    /// Every frequency at once: the source for breath, percussion, and wind.
    case noise
}

/// One oscillator's running state.
///
/// Held per voice and advanced a sample at a time. `phase` runs `0..<1` through
/// the cycle rather than in radians, because every correction below is written
/// against the fraction of a cycle a single sample covers.
struct Oscillator {
    /// Position through the current cycle, `0..<1`.
    private var phase: Double = 0
    /// The previous triangle output, which is integrated rather than evaluated.
    private var lastTriangle: Double = 0
    /// Noise generator state, seeded per voice so a render replays exactly.
    private var noiseState: UInt64

    init(seed: UInt64) {
        // A zero state would leave the generator stuck at zero forever.
        self.noiseState = seed | 1
    }

    /// Restarts the cycle. Called when a voice takes a new note so every note
    /// begins at the same point in the wave and two identical notes sound identical.
    mutating func reset() {
        phase = 0
        lastTriangle = 0
    }

    /// The next sample for `waveform`, advancing the phase by one step.
    ///
    /// `increment` is the fraction of a cycle one sample covers, frequency
    /// divided by sample rate.
    mutating func next(_ waveform: Waveform, increment: Double) -> Double {
        if waveform == .noise { return nextNoise() }

        let t = phase
        var value: Double

        switch waveform {
        case .sine:
            // A sine has no corners, so it needs no correction at all.
            value = sin(t * 2 * .pi)

        case .sawtooth:
            value = 2 * t - 1
            value -= polyBLEP(t, increment)

        case .square:
            value = t < 0.5 ? 1 : -1
            value += polyBLEP(t, increment)
            value -= polyBLEP(fract(t + 0.5), increment)

        case .triangle:
            // A triangle is the integral of a square, so it is built by
            // integrating the corrected square rather than drawn directly:
            // correcting the corners of the source wave is what keeps the
            // result clean. The leak makes the integrator forget its own drift,
            // and the gain is what puts the result back in -1...1 (a square of
            // +/-1 integrated at `4 * increment` per sample swings exactly 2
            // over the half cycle it holds each sign).
            var square = t < 0.5 ? 1.0 : -1.0
            square += polyBLEP(t, increment)
            square -= polyBLEP(fract(t + 0.5), increment)
            value = 4 * increment * square + (1 - 4 * increment) * lastTriangle
            lastTriangle = value

        case .noise:
            value = 0   // handled above
        }

        phase = fract(phase + increment)
        return value
    }

    /// White noise in `-1...1` from the voice's own generator.
    ///
    /// Seeded per voice rather than drawn from the sketch's `random`, so adding
    /// a noise voice cannot shift any other roll a sketch makes, and an offline
    /// render of the same notes produces the same samples.
    private mutating func nextNoise() -> Double {
        // SplitMix64: cheap, allocation-free, and good enough for audio noise.
        noiseState &+= 0x9E37_79B9_7F4A_7C15
        var z = noiseState
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z = z ^ (z >> 31)
        // Take the top 53 bits so the double is uniform across its mantissa.
        return Double(z >> 11) * (2.0 / 9_007_199_254_740_992.0) - 1.0
    }
}

/// The polynomial residual that rounds off one step discontinuity.
///
/// Returns zero except within one sample of the step, where it returns the
/// difference between the ideal band-limited step and the instantaneous one, so
/// adding it at a rising edge (or subtracting it at a falling one) removes the
/// energy that would otherwise fold back down the spectrum.
///
/// `t` is the phase `0..<1` measured from the step, `dt` the phase one sample
/// covers.
@inline(__always)
func polyBLEP(_ t: Double, _ dt: Double) -> Double {
    if t < dt {
        // Just after the step.
        let x = t / dt
        return x + x - x * x - 1
    } else if t > 1 - dt {
        // Just before the next one.
        let x = (t - 1) / dt
        return x * x + x + x + 1
    }
    return 0
}

/// The fractional part, always in `0..<1`.
@inline(__always)
private func fract(_ x: Double) -> Double { x - floor(x) }
