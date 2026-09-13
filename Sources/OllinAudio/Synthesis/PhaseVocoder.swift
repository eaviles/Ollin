import Accelerate
import Foundation

// MARK: - The machine under the three

/// The short-time Fourier machinery under the pitch shift, the freeze, and
/// the stretch.
///
/// Sound is cut into overlapping windowed frames. Each frame is read as the
/// magnitude of every bin and the frequency that bin is really carrying,
/// which the change of phase since the last frame gives away. Frames are
/// written back by overlap-add, with the phase of every partial carried on
/// at whatever rate the operation asks: the frame's own rate for a stretch,
/// a moved one for a pitch shift, and the rate of one held instant for a
/// freeze.
///
/// Two things keep it from sounding like a phase vocoder. Bins are not
/// treated alone: the frame's peaks are found, each peak owns the bins
/// around it down to the valley on either side, and those bins take their
/// phase from the peak's rather than accumulating their own, so a partial
/// keeps the shape the window gave it. And a pitch shift moves each region
/// whole, by a whole number of bins, so the main lobe of every partial
/// arrives intact at its new place; the fraction of a bin left over is
/// absorbed by the peak's own phase advance, which costs less than a decibel
/// of level at worst and no ripple.
///
/// One object serves one channel. Everything it touches is allocated here,
/// once, so a frame runs on the audio thread with no heap in sight.
final class PhaseVocoder {
    /// The frame length, a power of two.
    let frameSize: Int
    /// Samples between one analysis frame and the next: an eighth of the
    /// frame, so eight frames overlap every sample.
    let hop: Int
    /// How many bins a frame has, `frameSize / 2 + 1`.
    let bins: Int

    private let log2n: vDSP_Length
    private let setup: FFTSetup
    /// Bins per radian per sample: how many bins a frequency difference is.
    private let binsPerRadian: Float

    /// The periodic Hann window, `frameSize` long.
    let window: UnsafeMutablePointer<Float>
    /// The frame going in, windowed, and the frame coming out, windowed.
    let frame: UnsafeMutablePointer<Float>
    private let packedReal: UnsafeMutablePointer<Float>
    private let packedImag: UnsafeMutablePointer<Float>
    private let real: UnsafeMutablePointer<Float>
    private let imag: UnsafeMutablePointer<Float>

    /// What the last analysis read: each bin's magnitude, its phase, and the
    /// frequency it is really carrying, in radians per sample.
    let magnitude: UnsafeMutablePointer<Float>
    let phase: UnsafeMutablePointer<Float>
    let frequency: UnsafeMutablePointer<Float>
    private let lastPhase: UnsafeMutablePointer<Float>
    private var hasLastPhase = false
    private let binFrequency: UnsafeMutablePointer<Float>

    /// The synthesis phase of every bin, carried from frame to frame.
    private let accumulated: UnsafeMutablePointer<Float>
    private let theta: UnsafeMutablePointer<Float>
    private let cosine: UnsafeMutablePointer<Float>
    private let sine: UnsafeMutablePointer<Float>
    private let targetBin: UnsafeMutablePointer<Int32>
    private let synthReal: UnsafeMutablePointer<Float>
    private let synthImag: UnsafeMutablePointer<Float>

    /// The peaks of the magnitudes last searched, and where each one's
    /// region ends.
    private(set) var peakCount = 0
    private let peaks: UnsafeMutablePointer<Int32>
    private let regionEnd: UnsafeMutablePointer<Int32>

    /// The frame length for a rate: about forty milliseconds, which is the
    /// usual trade between telling two low partials apart and smearing an
    /// attack.
    static func frameSize(for sampleRate: Double) -> Int {
        sampleRate > 50_000 ? 4096 : 2048
    }

    init(frameSize: Int) {
        let n = frameSize
        self.frameSize = n
        hop = n / 8
        bins = n / 2 + 1
        log2n = vDSP_Length(log2(Double(n)).rounded())
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        binsPerRadian = Float(n) / (2 * .pi)

        func floats(_ count: Int) -> UnsafeMutablePointer<Float> {
            let pointer = UnsafeMutablePointer<Float>.allocate(capacity: count)
            pointer.initialize(repeating: 0, count: count)
            return pointer
        }
        func ints(_ count: Int) -> UnsafeMutablePointer<Int32> {
            let pointer = UnsafeMutablePointer<Int32>.allocate(capacity: count)
            pointer.initialize(repeating: 0, count: count)
            return pointer
        }
        window = floats(n)
        frame = floats(n)
        packedReal = floats(n / 2)
        packedImag = floats(n / 2)
        real = floats(bins)
        imag = floats(bins)
        magnitude = floats(bins)
        phase = floats(bins)
        frequency = floats(bins)
        lastPhase = floats(bins)
        binFrequency = floats(bins)
        accumulated = floats(bins)
        theta = floats(bins)
        cosine = floats(bins)
        sine = floats(bins)
        targetBin = ints(bins)
        synthReal = floats(bins)
        synthImag = floats(bins)
        peaks = ints(bins)
        regionEnd = ints(bins)

        // The periodic form, whose squares summed at any hop dividing a
        // quarter of the frame are a constant, which is what makes the
        // overlap-add exact.
        for index in 0..<n {
            window[index] = Float(0.5 * (1 - cos(2 * Double.pi * Double(index) / Double(n))))
        }
        for k in 0..<bins {
            binFrequency[k] = Float(2 * Double.pi * Double(k) / Double(n))
        }
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
        for pointer in [window, frame, packedReal, packedImag, real, imag, magnitude, phase,
                        frequency, lastPhase, binFrequency, accumulated, theta, cosine, sine,
                        synthReal, synthImag] {
            pointer.deallocate()
        }
        targetBin.deallocate()
        peaks.deallocate()
        regionEnd.deallocate()
    }

    // MARK: Reading a frame

    /// Reads one frame of `frameSize` samples: the magnitude and phase of
    /// every bin, and the frequency each bin is really carrying, worked out
    /// from how far its phase moved since the last frame `advance` samples
    /// ago. The first frame has nothing to compare against, so it reports
    /// each bin at its own center.
    func analyze(_ input: UnsafePointer<Float>, advance: Int) {
        let n = frameSize
        let half = n / 2
        vDSP_vmul(input, 1, window, 1, frame, 1, vDSP_Length(n))

        var split = DSPSplitComplex(realp: packedReal, imagp: packedImag)
        frame.withMemoryRebound(to: DSPComplex.self, capacity: half) {
            vDSP_ctoz($0, 2, &split, 1, vDSP_Length(half))
        }
        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))

        // The packed form keeps the two real-only bins in one slot; spread
        // them out so every bin reads the same way.
        real[0] = packedReal[0]
        imag[0] = 0
        for k in 1..<half {
            real[k] = packedReal[k]
            imag[k] = packedImag[k]
        }
        real[half] = packedImag[0]
        imag[half] = 0

        var spread = DSPSplitComplex(realp: real, imagp: imag)
        vDSP_zvabs(&spread, 1, magnitude, 1, vDSP_Length(bins))
        vDSP_zvphas(&spread, 1, phase, 1, vDSP_Length(bins))

        if hasLastPhase {
            let step = Float(max(1, advance))
            for k in 0..<bins {
                let expected = binFrequency[k] * step
                let deviation = PhaseVocoder.wrapped(phase[k] - lastPhase[k] - expected)
                frequency[k] = binFrequency[k] + deviation / step
            }
        } else {
            for k in 0..<bins { frequency[k] = binFrequency[k] }
        }
        lastPhase.update(from: phase, count: bins)
        hasLastPhase = true
    }

    /// Starts the synthesis phases so that the next ``propagate`` lands on
    /// `phases` exactly: each bin is set one advance short, since carrying
    /// the phases forward adds `frequency * hop` before anything is written.
    /// With the phases and frequencies just read, the frame written back is
    /// the frame that came in.
    func resetAccumulated(to phases: UnsafePointer<Float>, frequency frequencies: UnsafePointer<Float>,
                          hop: Float) {
        for k in 0..<bins {
            accumulated[k] = PhaseVocoder.wrapped(phases[k] - frequencies[k] * hop)
        }
    }

    /// Forgets the last frame, so the next one reads as a first.
    func forgetHistory() {
        hasLastPhase = false
    }

    // MARK: Peaks

    /// Finds the peaks of a set of magnitudes and gives each one the bins
    /// around it, out to the quietest bin between it and the next peak.
    ///
    /// A peak is a bin louder than the two on either side of it. Nothing
    /// under a ten-thousandth of the frame's loudest bin counts, so silence
    /// has no peaks and every bin then carries itself.
    func findPeaks(in magnitude: UnsafePointer<Float>) {
        var loudest: Float = 0
        vDSP_maxv(magnitude, 1, &loudest, vDSP_Length(bins))
        let floor = max(loudest * 1e-4, 1e-7)
        var count = 0
        let last = bins - 1
        var k = 2
        while k < last - 1 {
            let value = magnitude[k]
            if value > floor,
               value > magnitude[k - 1], value >= magnitude[k + 1],
               value > magnitude[k - 2], value >= magnitude[k + 2] {
                peaks[count] = Int32(k)
                count += 1
                // The next two bins cannot be peaks by the same test.
                k += 2
            } else {
                k += 1
            }
        }
        peakCount = count
        guard count > 0 else { return }
        for index in 0..<(count - 1) {
            let from = Int(peaks[index]), to = Int(peaks[index + 1])
            var valley = from + 1
            var quietest = magnitude[valley]
            var j = from + 2
            while j < to {
                if magnitude[j] < quietest {
                    quietest = magnitude[j]
                    valley = j
                }
                j += 1
            }
            regionEnd[index] = Int32(valley)
        }
        regionEnd[count - 1] = Int32(bins)
    }

    // MARK: Writing a frame

    /// Carries the phases forward by `hop` samples and lays the spectrum out
    /// for synthesis.
    ///
    /// The magnitudes, phases, and frequencies can be the ones just read or
    /// a set held from an earlier frame; the peaks used are the ones last
    /// found. Each peak's phase advances at its own frequency times `ratio`,
    /// its region rides along with it, and the whole region lands `ratio`
    /// times as high, to the nearest bin. A `ratio` of 1 moves nothing, and
    /// with a `hop` equal to the analysis hop puts the frame back exactly.
    func propagate(magnitude source: UnsafePointer<Float>, phase phases: UnsafePointer<Float>,
                   frequency frequencies: UnsafePointer<Float>, hop: Float, ratio: Float) {
        vDSP_vclr(synthReal, 1, vDSP_Length(bins))
        vDSP_vclr(synthImag, 1, vDSP_Length(bins))
        let limit = bins

        if peakCount == 0 {
            for k in 0..<bins {
                let moved = frequencies[k] * ratio
                let shift = Int(((moved - frequencies[k]) * binsPerRadian).rounded())
                let target = k + shift
                guard target >= 0, target < limit else {
                    targetBin[k] = -1
                    continue
                }
                let angle = PhaseVocoder.wrapped(accumulated[target] + moved * hop)
                accumulated[target] = angle
                theta[k] = angle
                targetBin[k] = Int32(target)
            }
        } else {
            var start = 0
            for index in 0..<peakCount {
                let peak = Int(peaks[index])
                let end = Int(regionEnd[index])
                let moved = frequencies[peak] * ratio
                let shift = Int(((moved - frequencies[peak]) * binsPerRadian).rounded())
                let movedPeak = peak + shift
                guard movedPeak >= 0, movedPeak < limit else {
                    for j in start..<end { targetBin[j] = -1 }
                    start = end
                    continue
                }
                let peakAngle = PhaseVocoder.wrapped(accumulated[movedPeak] + moved * hop)
                accumulated[movedPeak] = peakAngle
                let peakPhase = phases[peak]
                for j in start..<end {
                    let target = j + shift
                    guard target >= 0, target < limit else {
                        targetBin[j] = -1
                        continue
                    }
                    if j == peak {
                        theta[j] = peakAngle
                    } else {
                        let angle = PhaseVocoder.wrapped(peakAngle + phases[j] - peakPhase)
                        accumulated[target] = angle
                        theta[j] = angle
                    }
                    targetBin[j] = Int32(target)
                }
                start = end
            }
        }

        var count = Int32(bins)
        vvsincosf(sine, cosine, theta, &count)
        for k in 0..<bins {
            let target = Int(targetBin[k])
            guard target >= 0 else { continue }
            synthReal[target] += source[k] * cosine[k]
            synthImag[target] += source[k] * sine[k]
        }
    }

    /// Turns the spectrum laid out by ``propagate`` back into `frameSize`
    /// windowed samples in ``frame``, ready to overlap-add.
    func synthesize() {
        let n = frameSize
        let half = n / 2
        packedReal[0] = synthReal[0]
        packedImag[0] = synthReal[half]
        for k in 1..<half {
            packedReal[k] = synthReal[k]
            packedImag[k] = synthImag[k]
        }
        var split = DSPSplitComplex(realp: packedReal, imagp: packedImag)
        vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_INVERSE))
        frame.withMemoryRebound(to: DSPComplex.self, capacity: half) {
            vDSP_ztoc(&split, 1, $0, 2, vDSP_Length(half))
        }
        // The forward transform comes back doubled and the inverse comes
        // back `frameSize` times too large.
        var scale = 1 / Float(2 * n)
        vDSP_vsmul(frame, 1, &scale, frame, 1, vDSP_Length(n))
        vDSP_vmul(frame, 1, window, 1, frame, 1, vDSP_Length(n))
    }

    /// An angle brought back into `-π...π`.
    @inline(__always)
    static func wrapped(_ angle: Float) -> Float {
        let turn = 2 * Float.pi
        return angle - turn * (angle / turn).rounded()
    }

    // MARK: A whole recording, offline

    /// One channel of samples, `factor` times as long, at the same pitch.
    ///
    /// The frames are read `hop / factor` samples apart and written back
    /// `hop` apart, so the sound covers `factor` times the ground. The read
    /// positions are whole samples, and the phase of every bin is worked out
    /// against the distance really stepped, so no rounding leaks into the
    /// pitch. A factor of 1 gives the samples back.
    static func stretch(_ samples: [Float], by factor: Double, sampleRate: Double) -> [Float] {
        let count = samples.count
        guard count > 0 else { return [] }
        let held = min(max(0.25, factor), 16)
        let n = frameSize(for: sampleRate)
        let vocoder = PhaseVocoder(frameSize: n)
        let hop = vocoder.hop

        // A frame of silence either side, so the first and last samples sit
        // under a full stack of windows like every other.
        var padded = [Float](repeating: 0, count: count + 2 * n)
        padded.replaceSubrange(n..<(n + count), with: samples)
        let analysisHop = Double(hop) / held
        let outputCount = Int((Double(count) * held).rounded())
        let paddedOutput = Int((Double(padded.count) * held).rounded()) + 2 * n
        var sum = [Float](repeating: 0, count: paddedOutput)
        var energy = [Float](repeating: 0, count: paddedOutput)

        padded.withUnsafeBufferPointer { input in
            var index = 0
            var lastStart = 0
            while true {
                let start = Int((Double(index) * analysisHop).rounded())
                if start + n > input.count { break }
                vocoder.analyze(input.baseAddress! + start, advance: index == 0 ? hop : start - lastStart)
                if index == 0 {
                    vocoder.resetAccumulated(to: vocoder.phase, frequency: vocoder.frequency, hop: Float(hop))
                }
                vocoder.findPeaks(in: vocoder.magnitude)
                vocoder.propagate(magnitude: vocoder.magnitude, phase: vocoder.phase,
                                  frequency: vocoder.frequency, hop: Float(hop), ratio: 1)
                vocoder.synthesize()
                let out = index * hop
                if out + n > sum.count { break }
                sum.withUnsafeMutableBufferPointer { total in
                    energy.withUnsafeMutableBufferPointer { weight in
                        for j in 0..<n {
                            total[out + j] += vocoder.frame[j]
                            weight[out + j] += vocoder.window[j] * vocoder.window[j]
                        }
                    }
                }
                lastStart = start
                index += 1
            }
        }

        let front = Int((Double(n) * held).rounded())
        var result = [Float](repeating: 0, count: outputCount)
        for i in 0..<outputCount {
            let position = front + i
            guard position < sum.count, energy[position] > 1e-6 else { continue }
            result[i] = sum[position] / energy[position]
        }
        return result
    }
}

// MARK: - Stretching what you have

extension SampledInstrument.Recording {
    /// The same recording, `factor` times as long, at the same pitch.
    ///
    /// A sampler moves pitch and length together, like a tape: a note an
    /// octave down lasts twice as long. This is the other axis. The length
    /// changes and the pitch does not, so a recording can be slowed into a
    /// drone or hurried into a grace note and still play at the note it was
    /// recorded at. `factor` runs `0.25...16`; 2 is twice as long.
    ///
    /// It changes the length, so it is a thing done to a recording rather
    /// than an effect in the chain. Do it in `setup()`: it costs about what
    /// the recording's own length costs to play.
    ///
    /// ```swift
    /// let slow = recording.stretched(by: 4)
    /// synth.instrument = SampledInstrument(recordings: [slow])
    /// ```
    public func stretched(by factor: Double) -> SampledInstrument.Recording {
        var copy = self
        copy.frames = PhaseVocoder.stretch(frames, by: factor, sampleRate: sampleRate)
        return copy
    }
}

extension ImpulseResponse {
    /// The same room, `factor` times as long, ringing at the same pitches.
    ///
    /// Slowing a recording of a room makes it a bigger room rather than a
    /// lower one: every echo lands later and every resonance rings longer,
    /// and nothing moves in pitch. `factor` runs `0.25...16`. The result is
    /// still cut at ``maxSeconds``.
    public func stretched(by factor: Double) -> ImpulseResponse {
        var copy = self
        let limit = Int(ImpulseResponse.maxSeconds * sampleRate)
        copy.channels = channels.map { side in
            let longer = PhaseVocoder.stretch(side, by: factor, sampleRate: sampleRate)
            return longer.count > limit ? Array(longer[0..<limit]) : longer
        }
        return copy
    }
}
