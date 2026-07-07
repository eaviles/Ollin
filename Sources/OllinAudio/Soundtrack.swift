import Foundation
import Ollin
import os

/// Analyzes the sound of any tappable source, most usefully a playing video's
/// soundtrack, so a sketch can react to the audio of what it's showing the
/// same way it reacts to a microphone or an audio file.
///
/// ```swift
/// let video = try VideoPlayer(resource: "clip", withExtension: "mp4", in: .module)
/// let sound = Soundtrack(of: video)
/// override func setup() { video.play() }
/// override func draw() {
///     drawCircle(center: center, radius: 200 + Double(sound.beat) * 80)
/// }
/// ```
///
/// The source delivers mono PCM through the core `AudioTapSource` seam;
/// `Soundtrack` owns that slot (installing another consumer replaces it) and
/// feeds an `AudioAnalyzer`, so the whole `AudioSource` read surface
/// (`amplitude` / `spectrum` / `bands` / `beat` / …) works here too. Analysis
/// hears the soundtrack itself, not the output mix: turn the source's volume
/// all the way down and the visuals keep reacting. (A hard mute is different:
/// `isMuted = true` stops the source's audio processing altogether, and the
/// analysis falls silent with it. Prefer `volume = 0`.)
///
/// Analysis runs while the source actually plays, which means a *headless
/// export* (video frames pulled by the export clock, nothing audible playing)
/// reads as silence.
@MainActor
public final class Soundtrack: AudioSource {

    /// The DSP the tap feeds. Rebuilt once to match the source's real sample
    /// rate when the first audio arrives (it isn't knowable earlier), keeping
    /// the band and beat math honest; the store hides the swap.
    public nonisolated var analyzer: AudioAnalyzer { store.current }

    private let source: any AudioTapSource
    private let store: SoundtrackAnalyzerStore

    /// Starts analyzing `source`'s audio. `fftSize` and `smoothing` mirror the
    /// other audio sources' knobs.
    public init(of source: any AudioTapSource, fftSize: Int = 1024, smoothing: Float = 0.8) {
        self.source = source
        let store = SoundtrackAnalyzerStore(fftSize: fftSize, smoothing: smoothing)
        self.store = store
        source.audioTap = makeSoundtrackTap(store: store)
    }

    /// Stops analyzing, releasing the source's tap slot.
    public func detach() {
        source.audioTap = nil
    }
}

/// Holds the soundtrack's analyzer behind a lock so the audio thread can swap
/// it for one built at the stream's real sample rate. `@unchecked Sendable`:
/// every access goes through the lock, and `AudioAnalyzer` is itself Sendable.
final class SoundtrackAnalyzerStore: @unchecked Sendable {

    private let fftSize: Int
    private let smoothing: Float
    private let lock: OSAllocatedUnfairLock<AudioAnalyzer>

    init(fftSize: Int, smoothing: Float) {
        self.fftSize = fftSize
        self.smoothing = smoothing
        // A reasonable rate until the tap reports the real one.
        self.lock = OSAllocatedUnfairLock(
            initialState: AudioAnalyzer(fftSize: fftSize, sampleRate: 48000, smoothing: smoothing))
    }

    var current: AudioAnalyzer { lock.withLock { $0 } }

    /// The analyzer for `rate`, rebuilding once if the placeholder guessed
    /// wrong. Tuning made on the placeholder (`smoothing`, `beatSensitivity`)
    /// carries over to the replacement.
    func analyzer(matching rate: Double) -> AudioAnalyzer {
        lock.withLock { current in
            if rate > 0, abs(current.sampleRate - rate) > 1 {
                let rebuilt = AudioAnalyzer(fftSize: fftSize, sampleRate: rate, smoothing: smoothing)
                rebuilt.smoothing = current.smoothing
                rebuilt.beatSensitivity = current.beatSensitivity
                current = rebuilt
            }
            return current
        }
    }
}

/// Forms the tap in a free function so the closure stays non-isolated: the
/// source calls it on its audio thread, and a main-actor closure would trap
/// there (the render-thread rule).
private func makeSoundtrackTap(store: SoundtrackAnalyzerStore) -> AudioTap {
    { samples, sampleRate in
        guard let base = samples.baseAddress, samples.count > 0 else { return }
        store.analyzer(matching: sampleRate).process(samples: base, count: samples.count)
    }
}
