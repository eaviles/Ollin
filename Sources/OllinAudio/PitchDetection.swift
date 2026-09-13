import Accelerate
import Foundation

/// A pitch the analyzer heard: the fundamental of the most recent window, how
/// sure the detector is, and the nearest note with the offset from it.
///
/// ```swift
/// if let heard = mic.pitch {
///     drawText("\(heard.note)", width / 2, 80)          // "A4"
///     let y = map(heard.midi, 48, 84, height, 0)        // pitch as a position
/// }
/// ```
///
/// `note` and `cents` are the tuner's two numbers. `midi` is the pitch as a
/// fractional note number, the value to map onto a position, since equal steps
/// of it are equal steps of pitch to the ear where equal steps of `frequency`
/// are not.
public struct DetectedPitch: Sendable, Hashable {
    /// The fundamental, in Hz.
    public var frequency: Double

    /// How periodic the window was, `0...1`. A pure tone reads 1, a sung or
    /// bowed note above 0.9, and noise never reaches 0.5, which is where
    /// `pitch` stops reporting anything at all.
    public var confidence: Float

    /// The nearest equal-tempered note, with A4 at 440 Hz.
    public var note: Pitch

    /// How far the pitch sits above (`+`) or below (`-`) `note`, in cents,
    /// `-50...50`. A hundred cents is a semitone.
    public var cents: Double

    /// The pitch as a fractional MIDI note number, `note.midi + cents / 100`.
    public var midi: Double { note.midi + cents / 100 }

    /// The pitch as a `Pitch`, sitting between the keys where the sound did.
    public var pitch: Pitch { Pitch(midi) }

    public init(frequency: Double, confidence: Float) {
        self.frequency = frequency
        self.confidence = confidence
        let midi = Pitch(frequency: frequency).midi
        let nearest = midi.rounded()
        self.note = Pitch(nearest)
        self.cents = (midi - nearest) * 100
    }
}

/// The pitch estimator behind `AudioAnalyzer.pitch`: the YIN method of de
/// Cheveigné and Kawahara (2002), steps 1 to 5 as published. The difference
/// function over every lag in range, the cumulative mean normalization that
/// stops the shortest lags from winning by default, the absolute threshold that
/// takes the first dip under it (which is what keeps an octave below the note
/// from being reported, since the true period comes first), and a parabola
/// through the dip for a fraction of a sample. The sixth step, a search for the
/// best local estimate around the dip, is left out; on a window this long it
/// changes nothing a reader could hear.
///
/// The window is twice the longest lag, so the lowest pitch it reaches decides
/// its length: at 40 Hz and 44.1 kHz that is 2,204 samples, 50 ms. The cost is
/// one squared distance per lag over the whole lag range, about a million
/// multiply-adds, which is why the analyzer works it out only when a sketch
/// asks, once per window.
struct PitchDetector: Sendable {
    let sampleRate: Double
    /// The shortest lag searched, set by the highest pitch reported.
    let lagMin: Int
    /// The longest lag searched, set by the lowest pitch reported. The window
    /// is twice this.
    let lagMax: Int
    /// The paper's absolute threshold on the normalized difference: the first
    /// dip under it is the period.
    let threshold: Float
    /// Below this confidence nothing is reported; noise reads well under it.
    let confidenceFloor: Float = 0.5

    private var difference: [Float]
    private var normalized: [Float]

    var windowSize: Int { 2 * lagMax }

    init(sampleRate: Double, minFrequency: Double = 40, maxFrequency: Double = 5000,
         threshold: Float = 0.1) {
        self.sampleRate = sampleRate
        self.lagMax = max(4, Int((sampleRate / minFrequency).rounded(.up)))
        self.lagMin = max(2, min(lagMax - 2, Int((sampleRate / maxFrequency).rounded(.down))))
        self.threshold = threshold
        self.difference = [Float](repeating: 0, count: lagMax + 1)
        self.normalized = [Float](repeating: 1, count: lagMax + 1)
    }

    /// The pitch of a window of `windowSize` samples, or nil when the window
    /// is silent or nothing in it repeats.
    mutating func detect(_ window: UnsafePointer<Float>) -> DetectedPitch? {
        let w = lagMax

        // Steps 1 and 2: the difference function, the squared distance between
        // the window and itself moved by each lag.
        difference[0] = 0
        for lag in 1...lagMax {
            var d: Float = 0
            vDSP_distancesq(window, 1, window + lag, 1, &d, vDSP_Length(w))
            difference[lag] = d
        }

        // Step 3: cumulative mean normalized difference. A lag is judged
        // against the mean of every shorter lag, so the trivially small
        // distances at the shortest lags stop looking like periods.
        normalized[0] = 1
        var running: Float = 0
        for lag in 1...lagMax {
            running += difference[lag]
            normalized[lag] = running > 0 ? difference[lag] * Float(lag) / running : 1
        }

        // Step 4: the absolute threshold. The first lag whose normalized
        // difference dips under it, followed down to the bottom of that dip.
        // With no dip under the threshold, the lowest point in range stands
        // in, and its height says how unsure that is.
        var found = -1
        var lag = lagMin
        while lag < lagMax {
            if normalized[lag] < threshold {
                while lag + 1 <= lagMax, normalized[lag + 1] < normalized[lag] { lag += 1 }
                found = lag
                break
            }
            lag += 1
        }
        if found < 0 {
            var best = lagMin
            for candidate in lagMin...lagMax where normalized[candidate] < normalized[best] {
                best = candidate
            }
            found = best
        }

        // Step 5: a parabola through the dip and its two neighbors puts the
        // period between samples.
        var period = Double(found)
        var depth = normalized[found]
        if found > 0, found < lagMax {
            let a = normalized[found - 1], b = normalized[found], c = normalized[found + 1]
            let curvature = a - 2 * b + c
            if curvature > 0 {
                let delta = (a - c) / (2 * curvature)
                if abs(delta) < 1 {
                    period += Double(delta)
                    depth = b - (a - c) * (a - c) / (8 * curvature)
                }
            }
        }

        let confidence = 1 - max(0, min(1, depth))
        guard confidence >= confidenceFloor, period > 0 else { return nil }
        return DetectedPitch(frequency: sampleRate / period, confidence: confidence)
    }
}

/// The pitch-class profile behind `AudioAnalyzer.chroma`: twelve bins, one per
/// note name, with every octave folded onto them. It follows the peak form of
/// the profile (Fujishima's pitch class profile of 1999, read off spectral
/// peaks the way Gómez's harmonic profile of 2006 does): each peak of the
/// window's spectrum lands its power on the class of its interpolated
/// frequency, so a note sits in one bin rather than leaking across three, and
/// the twelve are scaled so the strongest reads 1.
final class ChromaProfile: @unchecked Sendable {
    let sampleRate: Double
    let windowSize: Int
    private let fftSize: Int
    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private let lowestBin: Int
    private let highestBin: Int
    /// A peak this far under the strongest one is left out: a window's own
    /// sidelobes sit below it, and the quietest note of a chord sits above.
    private let floorRatio: Float = 1 / 300

    private var hann: [Float]
    private var windowed: [Float]
    private var realp: [Float]
    private var imagp: [Float]
    private var power: [Float]

    init(sampleRate: Double, windowSize: Int, lowestFrequency: Double = 55,
         highestFrequency: Double = 5000) {
        self.sampleRate = sampleRate
        self.windowSize = windowSize
        var size = 2
        while size < windowSize { size <<= 1 }
        // Twice the window, so a peak's neighbors sit close enough for the
        // parabola through them to place it well.
        size <<= 1
        self.fftSize = size
        self.log2n = vDSP_Length(log2(Float(size)))
        self.setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        let binWidth = sampleRate / Double(size)
        self.lowestBin = max(1, Int((lowestFrequency / binWidth).rounded(.up)))
        self.highestBin = min(size / 2 - 2, Int((highestFrequency / binWidth).rounded(.down)))
        self.hann = [Float](repeating: 0, count: windowSize)
        vDSP_hann_window(&hann, vDSP_Length(windowSize), Int32(vDSP_HANN_NORM))
        self.windowed = [Float](repeating: 0, count: size)
        self.realp = [Float](repeating: 0, count: size / 2)
        self.imagp = [Float](repeating: 0, count: size / 2)
        self.power = [Float](repeating: 0, count: size / 2)
    }

    deinit { vDSP_destroy_fftsetup(setup) }

    /// The twelve classes, C first, over a window of `windowSize` samples.
    func profile(_ window: UnsafePointer<Float>) -> [Float] {
        let n = fftSize
        vDSP_vmul(window, 1, hann, 1, &windowed, 1, vDSP_Length(windowSize))
        // The rest of the buffer is padding and stays zero.
        realp.withUnsafeMutableBufferPointer { rp in
            imagp.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBufferPointer { win in
                    win.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { cplx in
                        vDSP_ctoz(cplx, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                ip[0] = 0
                vDSP_zvmags(&split, 1, &power, 1, vDSP_Length(n / 2))
            }
        }

        var classes = [Float](repeating: 0, count: 12)
        guard lowestBin < highestBin else { return classes }
        var strongest: Float = 0
        for bin in lowestBin...highestBin where power[bin] > strongest { strongest = power[bin] }
        guard strongest > 0 else { return classes }
        let floor = strongest * floorRatio
        let binWidth = sampleRate / Double(n)

        for bin in lowestBin...highestBin {
            let p = power[bin]
            guard p >= floor, p > power[bin - 1], p >= power[bin + 1] else { continue }
            // A parabola through the peak's neighbors in log power, which is
            // the interpolation a windowed peak wants.
            let a = log(max(power[bin - 1], 1e-30))
            let b = log(p)
            let c = log(max(power[bin + 1], 1e-30))
            let curvature = a - 2 * b + c
            let delta = curvature < 0 ? Double((a - c) / (2 * curvature)) : 0
            let frequency = (Double(bin) + delta) * binWidth
            let semitones = (12 * log2(frequency / 440)).rounded()
            let index = ((Int(semitones) + 9) % 12 + 12) % 12
            classes[index] += p
        }

        let top = classes.max() ?? 0
        guard top > 0 else { return classes }
        return classes.map { $0 / top }
    }
}
