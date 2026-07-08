import Accelerate
import AVFoundation
import os

/// The DSP behind every audio source: it turns a stream of audio samples into a
/// few values a sketch reads in `draw()`: an overall `amplitude`, a frequency
/// `spectrum`, the raw `waveform`, and band queries (`bass`/`mid`/`treble`,
/// `magnitude(in:)`). It is the typed core; `AudioInput`, `AudioPlayer`, and
/// `Tone` are thin sources that feed it.
///
/// Samples arrive on the audio render thread (the tap callback), while a sketch
/// reads the published values on the main thread. The split is the whole reason
/// for the locking here: `process(...)` runs serially on the audio thread and
/// owns the FFT scratch buffers exclusively; the results it publishes cross to
/// the reader through `stateLock`. That serial-producer / locked-handoff
/// invariant is what makes the `@unchecked Sendable` sound.
///
/// Every clock in here is the *sample* clock: positions counted in samples
/// since the analyzer started, divided by `sampleRate` when seconds are wanted.
/// Feeding the same samples always yields the same beats at the same times,
/// which is what makes detection testable and headless renders reproducible.
public final class AudioAnalyzer: @unchecked Sendable {

    // MARK: Configuration

    /// Number of frequency bins reported by `spectrum`: half the FFT size, since
    /// a real-signal FFT is symmetric. Bins span `0 ..< nyquist`, each
    /// `sampleRate / fftSize` Hz wide.
    public let binCount: Int

    /// Sample rate the analyzer was built for, in Hz (e.g. 44100). Sets the Hz
    /// span of each `spectrum` bin.
    public let sampleRate: Double

    private let fftSize: Int
    private let log2n: vDSP_Length
    private let fftSetup: FFTSetup
    private let binWidth: Double

    // Scratch, owned exclusively by `process(...)` (audio thread, serial).
    private var hann: [Float]
    private var windowed: [Float]
    private var realp: [Float]
    private var imagp: [Float]
    private var magnitudes: [Float]

    // The analysis window is a *rolling* ring of the last `fftSize` samples:
    // each incoming chunk slides it forward and the FFT re-runs over the full
    // window. That keeps the frequency resolution of the whole window even when
    // chunks are short (at 60 fps a chunk is ~735 samples), and it makes
    // `waveform` exactly what it claims to be: the most recent window of raw
    // samples. `fftSize` is a power of two, so wraparound is a mask.
    private var sampleRing: [Float]
    private var sampleRingHead: Int = 0     // next write position == oldest sample
    private var waveScratch: [Float]

    // Onset/beat-detection scratch (audio thread, serial). The detection
    // function is spectral flux (the per-window sum of positive bin-to-bin
    // magnitude increases) computed over *log-compressed* magnitudes,
    // `log(1 + λ·m)`: a gain change then shifts both windows' log magnitudes by
    // the same amount and cancels in the difference, so the flux scale (and the
    // additive threshold below) holds across quiet and loud material.
    private var logMagnitudes: [Float]
    private var prevLogMagnitudes: [Float]
    private let logCompression: Float = 200

    // Online peak-picking over the flux, past-only so it runs in real time.
    // A window is an onset when all three hold:
    //   1. its flux is the maximum of the last `localMaxEntries` windows;
    //   2. its flux exceeds the mean of the last `meanEntries` windows by an
    //      absolute margin (`onsetFloor × beatSensitivity`, additive rather
    //      than multiplicative, so near-steady material whose flux ripples
    //      around a small baseline can't self-trigger);
    //   3. a refractory gap (in samples) has passed since the last onset.
    // Missing history counts as zero flux, so an onset in the first window is
    // still detectable. The flux history is a small ring, newest at head-1.
    private var fluxRing: [Float]
    private var fluxRingHead: Int = 0
    private var fluxRingCount: Int = 0
    private let fluxRingCapacity = 16       // power of two ≥ meanEntries
    private let localMaxEntries = 3
    private let meanEntries = 10
    private let onsetFloor: Float = 3.0
    private var samplesSeen: Int = 0
    private var lastBeatSample: Int = -1_000_000    // far past: no refractory at start
    private let minBeatSamples: Int

    // MARK: Published state (read on main, written on the audio thread)

    private struct State {
        var amplitude: Float = 0
        var spectrum: [Float]
        var waveform: [Float]
        var smoothing: Float
        // Beat detection: all positions on the sample clock.
        var beatCount: Int = 0
        var samplesSeen: Int = 0
        var lastBeatSample: Int = -1          // -1 = none yet
        var beatSensitivity: Float = 1.5
        // bands(_:) ergonomics: normalized, log-spaced, attack/release envelope.
        var bandEnvelope: [Float] = []
        var bandPeak: Float = 1e-4
        var bandCount: Int = 0
    }
    private let stateLock: OSAllocatedUnfairLock<State>

    /// Creates an analyzer.
    ///
    /// - Parameters:
    ///   - fftSize: FFT window length in samples; rounded up to a power of two.
    ///     Larger windows give finer frequency resolution but coarser timing.
    ///   - sampleRate: the audio sample rate in Hz.
    ///   - smoothing: how much each frame leans on the previous one, `0...1`
    ///     (0 = raw and twitchy, near 1 = heavily damped). Defaults to a calm
    ///     0.8, the kind of response a level meter wants.
    public init(fftSize: Int = 1024, sampleRate: Double = 44100, smoothing: Float = 0.8) {
        let size = AudioAnalyzer.roundedUpToPowerOfTwo(max(2, fftSize))
        self.fftSize = size
        self.binCount = size / 2
        self.sampleRate = sampleRate
        self.binWidth = sampleRate / Double(size)
        self.log2n = vDSP_Length(log2(Float(size)))
        self.fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!

        self.hann = [Float](repeating: 0, count: size)
        vDSP_hann_window(&hann, vDSP_Length(size), Int32(vDSP_HANN_NORM))
        self.windowed = [Float](repeating: 0, count: size)
        self.realp = [Float](repeating: 0, count: size / 2)
        self.imagp = [Float](repeating: 0, count: size / 2)
        self.magnitudes = [Float](repeating: 0, count: size / 2)
        self.sampleRing = [Float](repeating: 0, count: size)
        self.waveScratch = [Float](repeating: 0, count: size)
        self.logMagnitudes = [Float](repeating: 0, count: size / 2)
        self.prevLogMagnitudes = [Float](repeating: 0, count: size / 2)
        self.fluxRing = [Float](repeating: 0, count: fluxRingCapacity)
        // ~120 ms minimum between beats, so a single hit can't double-trigger.
        self.minBeatSamples = Int(0.12 * sampleRate)

        self.stateLock = OSAllocatedUnfairLock(
            initialState: State(
                spectrum: [Float](repeating: 0, count: size / 2),
                waveform: [Float](repeating: 0, count: size),
                smoothing: max(0, min(1, smoothing))
            )
        )
    }

    deinit { vDSP_destroy_fftsetup(fftSetup) }

    // MARK: Reads (main thread)

    /// Overall loudness this instant, a smoothed RMS level. Roughly `0...1` for
    /// normalized audio, though loud transients can exceed 1.
    public var amplitude: Float { stateLock.withLock { $0.amplitude } }

    /// Per-bin magnitudes, `binCount` of them, low frequency first. Each bin
    /// covers `sampleRate / fftSize` Hz. Magnitudes are smoothed but unnormalized.
    public var spectrum: [Float] { stateLock.withLock { $0.spectrum } }

    /// The most recent `fftSize` samples (`-1...1`), oldest first: a true
    /// rolling window, so an oscilloscope trace drawn from it is continuous
    /// across frames no matter how audio chunks arrive.
    public var waveform: [Float] { stateLock.withLock { $0.waveform } }

    /// Damping applied to `amplitude` and `spectrum`, `0...1`. Settable live.
    public var smoothing: Float {
        get { stateLock.withLock { $0.smoothing } }
        set { let v = max(0, min(1, newValue)); stateLock.withLock { $0.smoothing = v } }
    }

    /// Average magnitude across the bins overlapping a frequency range, in Hz.
    /// Out-of-range or empty ranges return 0.
    public func magnitude(in range: ClosedRange<Double>) -> Float {
        let lo = max(0, Int((range.lowerBound / binWidth).rounded(.down)))
        let hi = min(binCount - 1, Int((range.upperBound / binWidth).rounded(.up)))
        guard lo <= hi else { return 0 }
        let spec = spectrum
        var sum: Float = 0
        for i in lo...hi { sum += spec[i] }
        return sum / Float(hi - lo + 1)
    }

    /// Energy in the low band (20–250 Hz).
    public var bass: Float { magnitude(in: 20...250) }
    /// Energy in the mid band (250–2000 Hz).
    public var mid: Float { magnitude(in: 250...2000) }
    /// Energy in the high band (2000–8000 Hz).
    public var treble: Float { magnitude(in: 2000...8000) }

    // MARK: Bands (normalized, log-spaced: the ready-to-draw spectrum)

    /// `count` frequency bands spread *logarithmically* (octave-like) from ~40 Hz
    /// up toward the Nyquist, each value normalized to roughly `0...1` by an
    /// adaptive gain and smoothed with a fast-attack / slow-release envelope. This
    /// is the spectrum shaped for drawing: spaced the way hearing is, auto-scaled
    /// so you don't hand-tune a gain, and steady enough to map straight to bar
    /// heights. Call it once per frame with a fixed `count`.
    public func bands(_ count: Int) -> [Float] {
        let count = max(1, count)
        let loHz = 40.0
        let hiHz = min(16000.0, sampleRate * 0.5 * 0.98)
        let ratio = hiHz / loHz

        return stateLock.withLock { state in
            if state.bandCount != count {
                state.bandCount = count
                state.bandEnvelope = [Float](repeating: 0, count: count)
                state.bandPeak = 1e-4
            }

            var raw = [Float](repeating: 0, count: count)
            var rawMax: Float = 0
            for b in 0..<count {
                let f0 = loHz * pow(ratio, Double(b) / Double(count))
                let f1 = loHz * pow(ratio, Double(b + 1) / Double(count))
                var lo = Int((f0 / binWidth).rounded(.down))
                var hi = Int((f1 / binWidth).rounded(.up))
                lo = max(0, min(binCount - 1, lo))
                hi = max(lo, min(binCount - 1, hi))
                var power: Float = 0
                for i in lo...hi { let m = state.spectrum[i]; power += m * m }
                let value = (power / Float(hi - lo + 1)).squareRoot()   // band RMS
                raw[b] = value
                if value > rawMax { rawMax = value }
            }

            // Adaptive normalization against a slowly-decaying peak, then a
            // fast-up / slow-down envelope so bars rise sharply and fall gently.
            state.bandPeak = max(max(state.bandPeak * 0.999, rawMax), 1e-4)
            for b in 0..<count {
                let target = min(raw[b] / state.bandPeak, 1)
                let cur = state.bandEnvelope[b]
                let coeff: Float = target > cur ? 0.5 : 0.12
                state.bandEnvelope[b] = cur + (target - cur) * coeff
            }
            return state.bandEnvelope
        }
    }

    // MARK: Beat (onset detection)

    /// How many beats (onsets) have been detected since the analyzer started.
    /// Compare it to a stored value to fire once per beat:
    /// `if source.beatCount > last { last = source.beatCount; … }`.
    public var beatCount: Int { stateLock.withLock { $0.beatCount } }

    /// Seconds of *audio* since the last detected beat (very large if none yet);
    /// drive a decaying flash from it, or read `beat` for a ready-made 0…1 pulse.
    /// Measured on the sample clock, so it advances as samples arrive: it tracks
    /// wall time while audio streams, holds still if the stream pauses, and is
    /// reproducible when the same samples are fed again.
    public var timeSinceBeat: Double {
        let (seen, last) = stateLock.withLock { ($0.samplesSeen, $0.lastBeatSample) }
        guard last >= 0 else { return .greatestFiniteMagnitude }
        return Double(seen - last) / sampleRate
    }

    /// A 0…1 pulse that snaps to 1 on each beat and decays over ~0.25 s: the
    /// ready-to-use "make it throb on the beat" value.
    public var beat: Float {
        let t = timeSinceBeat
        guard t.isFinite else { return 0 }
        return Float(max(0, 1 - t / 0.25))
    }

    /// Beat-detection threshold: how far the flux must rise above its own recent
    /// average to count as an onset. Higher = fewer, stronger beats; lower = more
    /// eager. Default 1.5. The margin is absolute (the flux scale is loudness-
    /// invariant), so steady material can't drift into false triggers.
    public var beatSensitivity: Float {
        get { stateLock.withLock { $0.beatSensitivity } }
        set { let v = max(0.1, newValue); stateLock.withLock { $0.beatSensitivity = v } }
    }

    // MARK: Processing (audio thread, serial)

    /// Analyze a buffer of mono float samples. Drive this from one source only
    /// (the audio render thread, via the source's tap): it owns the FFT and onset
    /// scratch lock-free, so a second concurrent caller would race it. See the type
    /// note on why that single writer is the safe contract.
    public func process(samples: UnsafePointer<Float>, count: Int) {
        guard count > 0 else { return }
        // A chunk longer than the window contributes its most recent windowful;
        // the sample clock still advances by everything that arrived.
        let take = min(count, fftSize)
        analyze(samples: samples + (count - take), take: take, advance: count)
    }

    private func analyze(samples: UnsafePointer<Float>, take: Int, advance: Int) {
        let n = fftSize
        let mask = n - 1

        // RMS over what arrived, before any windowing.
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(take))

        // Slide the rolling window: write the new samples into the ring, then
        // unroll it oldest-first (head points at the oldest sample).
        var idx = sampleRingHead
        sampleRing.withUnsafeMutableBufferPointer { ring in
            for i in 0..<take {
                ring[idx] = samples[i]
                idx = (idx + 1) & mask
            }
        }
        sampleRingHead = idx
        let head = sampleRingHead
        waveScratch.withUnsafeMutableBufferPointer { dst in
            sampleRing.withUnsafeBufferPointer { src in
                dst.baseAddress!.update(from: src.baseAddress! + head, count: n - head)
                (dst.baseAddress! + (n - head)).update(from: src.baseAddress!, count: head)
            }
        }

        // Hann window over the full rolling window, so the FFT doesn't smear
        // energy across bins.
        vDSP_vmul(waveScratch, 1, hann, 1, &windowed, 1, vDSP_Length(n))

        // Real FFT via split-complex packing of the windowed signal.
        realp.withUnsafeMutableBufferPointer { rp in
            imagp.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                windowed.withUnsafeBufferPointer { win in
                    win.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { cplx in
                        vDSP_ctoz(cplx, 2, &split, 1, vDSP_Length(n / 2))
                    }
                }
                vDSP_fft_zrip(fftSetup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                // Zero out the packed Nyquist term that lives in imagp[0].
                ip[0] = 0
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(n / 2))
                // vDSP_fft_zrip returns values scaled by 2; normalize by the size.
                var scale = Float(1) / Float(n)
                vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(n / 2))
            }
        }

        // Spectral flux over log-compressed magnitudes: the sum of positive
        // bin-to-bin increases since the previous window. A sudden broadband
        // rise (a drum hit, a plucked note) spikes it; a gain change cancels.
        let n2 = n / 2
        var one: Float = 1
        var lambda = logCompression
        vDSP_vsmsa(magnitudes, 1, &lambda, &one, &logMagnitudes, 1, vDSP_Length(n2))
        var count32 = Int32(n2)
        vvlogf(&logMagnitudes, logMagnitudes, &count32)
        var flux: Float = 0
        for i in 0..<n2 {
            let d = logMagnitudes[i] - prevLogMagnitudes[i]
            if d > 0 { flux += d }
            prevLogMagnitudes[i] = logMagnitudes[i]
        }
        samplesSeen += advance

        // Push the flux into its history ring and evaluate the three onset
        // conditions over the trailing windows (missing history reads as 0).
        fluxRing[fluxRingHead] = flux
        fluxRingHead = (fluxRingHead + 1) & (fluxRingCapacity - 1)
        fluxRingCount = min(fluxRingCount + 1, fluxRingCapacity)
        var maxFlux: Float = 0
        var meanSum: Float = 0
        for k in 0..<min(meanEntries, fluxRingCount) {
            let f = fluxRing[(fluxRingHead - 1 - k + fluxRingCapacity) & (fluxRingCapacity - 1)]
            if k < localMaxEntries, f > maxFlux { maxFlux = f }
            meanSum += f
        }
        let fluxMean = meanSum / Float(meanEntries)
        let isLocalMax = flux >= maxFlux
        let canBeat = (samplesSeen - lastBeatSample) >= minBeatSamples
        let loudEnough = rms > 0.01

        // Snapshot the new values into Sendable locals: the lock body is
        // `@Sendable`, so it can't reach a raw pointer or a mutated local var.
        let rmsValue = rms
        let mags = magnitudes
        let waveSnapshot = waveScratch
        let fluxValue = flux
        let samplesSeenValue = samplesSeen

        // Publish, smoothing toward the new values, and register a beat if the
        // flux cleared its threshold. The closure is `@Sendable`, so it returns
        // the onset rather than mutating an outer var.
        let onset = stateLock.withLock { state -> Bool in
            let a = state.smoothing
            state.amplitude = a * state.amplitude + (1 - a) * rmsValue
            for i in 0..<state.spectrum.count {
                state.spectrum[i] = a * state.spectrum[i] + (1 - a) * mags[i]
            }
            state.waveform = waveSnapshot
            state.samplesSeen = samplesSeenValue

            if canBeat && loudEnough && isLocalMax
                && fluxValue >= fluxMean + self.onsetFloor * state.beatSensitivity {
                state.beatCount += 1
                state.lastBeatSample = samplesSeenValue
                return true
            }
            return false
        }
        if onset { lastBeatSample = samplesSeen }
    }

    /// Convenience over an `AVAudioPCMBuffer`: averages channels to mono and
    /// forwards to `process(samples:count:)`.
    public func process(_ buffer: AVAudioPCMBuffer) {
        guard let channels = buffer.floatChannelData else { return }
        let frames = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frames > 0 else { return }

        if channelCount == 1 {
            process(samples: channels[0], count: frames)
            return
        }
        // Down-mix the most recent windowful to mono; the sample clock still
        // advances by the full buffer.
        let take = min(frames, fftSize)
        let skip = frames - take
        var mono = [Float](repeating: 0, count: take)
        let inv = Float(1) / Float(channelCount)
        for c in 0..<channelCount {
            let src = channels[c] + skip
            for i in 0..<take { mono[i] += src[i] * inv }
        }
        mono.withUnsafeBufferPointer { analyze(samples: $0.baseAddress!, take: take, advance: frames) }
    }

    private static func roundedUpToPowerOfTwo(_ n: Int) -> Int {
        var p = 1
        while p < n { p <<= 1 }
        return p
    }
}
