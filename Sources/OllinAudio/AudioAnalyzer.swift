import Accelerate
import AVFoundation
import os

/// The DSP behind every audio source: it turns a stream of audio samples into a
/// few values a sketch reads in `draw()` — an overall `amplitude`, a frequency
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
public final class AudioAnalyzer: @unchecked Sendable {

    // MARK: Configuration

    /// Number of frequency bins reported by `spectrum` — half the FFT size, since
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

    // MARK: Published state (read on main, written on the audio thread)

    private struct State {
        var amplitude: Float = 0
        var spectrum: [Float]
        var waveform: [Float]
        var smoothing: Float
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

    /// The most recent window of raw samples (`-1...1`), oldest first — handy for
    /// drawing an oscilloscope trace.
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

    // MARK: Processing (audio thread, serial)

    /// Analyze a buffer of mono float samples. Called from the audio render
    /// thread; see the type note on why that's the only writer.
    public func process(samples: UnsafePointer<Float>, count: Int) {
        guard count > 0 else { return }
        let n = fftSize
        let take = min(count, n)

        // RMS over what arrived, before any windowing.
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(take))

        // Copy (zero-padded) into the window scratch and apply a Hann window so
        // the FFT doesn't smear energy across bins.
        windowed.withUnsafeMutableBufferPointer { dst in
            if take < n { vDSP_vclr(dst.baseAddress!, 1, vDSP_Length(n)) }
            vDSP_vmul(samples, 1, hann, 1, dst.baseAddress!, 1, vDSP_Length(take))
        }

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

        // Snapshot the new values into Sendable locals: the lock body is
        // `@Sendable`, so it can't reach a raw pointer or a mutated local var.
        let rmsValue = rms
        let mags = magnitudes
        var wave = [Float](repeating: 0, count: n)
        for i in 0..<take { wave[i] = samples[i] }
        let waveSnapshot = wave

        // Publish, smoothing toward the new values.
        stateLock.withLock { state in
            let a = state.smoothing
            state.amplitude = a * state.amplitude + (1 - a) * rmsValue
            for i in 0..<state.spectrum.count {
                state.spectrum[i] = a * state.spectrum[i] + (1 - a) * mags[i]
            }
            state.waveform = waveSnapshot
        }
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
        // Down-mix to mono into the windowed scratch's leading frames.
        let take = min(frames, fftSize)
        var mono = [Float](repeating: 0, count: take)
        let inv = Float(1) / Float(channelCount)
        for c in 0..<channelCount {
            let src = channels[c]
            for i in 0..<take { mono[i] += src[i] * inv }
        }
        mono.withUnsafeBufferPointer { process(samples: $0.baseAddress!, count: take) }
    }

    private static func roundedUpToPowerOfTwo(_ n: Int) -> Int {
        var p = 1
        while p < n { p <<= 1 }
        return p
    }
}
