import Foundation
import Testing
@testable import Ollin
@testable import OllinAudio

/// An export has no speakers and no clock, so an instrument writes its notes
/// down instead and renders them at the end. What is checked here is that the
/// sound lands where the picture asked for it, that it comes out the same way
/// twice, and that a sketch making no sound is left exactly as it was.
@Suite(.serialized) struct SoundExportTests {

    static let sampleRate = 44100.0

    /// Runs a body with the sketch pretending to be exported, the way the
    /// offline drivers do.
    @MainActor
    private func exporting(_ body: () -> Void) {
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        body()
    }

    /// Plays notes on an instrument at given times, as an export would.
    @MainActor
    private func record(
        _ synth: Synth, notes: [(at: Double, pitch: Double, length: Double)],
        seconds: Double, fps: Double = 60
    ) -> [Float] {
        exporting {
            var pending = notes.sorted { $0.at < $1.at }
            let frame = 1 / fps
            var elapsed = 0.0
            while elapsed < seconds {
                while let next = pending.first, next.at <= elapsed {
                    synth.play(Pitch(next.pitch), velocity: 0.9, for: next.length)
                    pending.removeFirst()
                }
                synth.advance(by: frame)
                elapsed += frame
            }
        }
        return synth.renderExportAudio(upTo: seconds, sampleRate: Self.sampleRate)
    }

    private func rms(_ samples: ArraySlice<Float>) -> Double {
        guard !samples.isEmpty else { return 0 }
        return (samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count))
            .squareRoot()
    }

    // MARK: - What it produces

    @MainActor
    @Test func aSketchThatPlayedNothingExportsNothing() {
        let synth = Synth(.pluck)
        #expect(!synth.hasExportAudio)
        // A track was never asked for, so nothing renders and the file stays
        // the file it would have been.
        #expect(!synth.hasExportAudio)
    }

    @MainActor
    @Test func theSoundtrackIsExactlyAsLongAsThePicture() {
        let synth = Synth(.bell)
        let samples = record(synth, notes: [(at: 0.1, pitch: 60, length: 0.4)], seconds: 2)
        #expect(synth.hasExportAudio)
        // Interleaved stereo, so two numbers a frame.
        #expect(samples.count == Int(2 * Self.sampleRate)  * 2)
        #expect(samples.contains { abs($0) > 0.02 })
    }

    /// A note asked for during a frame has to land where that frame is. The
    /// twin is the same note asked for later.
    @MainActor
    @Test func aNoteLandsWhereTheFrameThatAskedForItDoes() {
        let early = record(Synth(.stab), notes: [(at: 0.1, pitch: 72, length: 0.2)], seconds: 1.5)
        let late = record(Synth(.stab), notes: [(at: 1.0, pitch: 72, length: 0.2)], seconds: 1.5)

        func loudness(_ samples: [Float], from: Double, to: Double) -> Double {
            let start = Int(from * Self.sampleRate) * 2
            let end = min(samples.count, Int(to * Self.sampleRate) * 2)
            guard end > start else { return 0 }
            return rms(samples[start..<end])
        }

        // Each is loud in its own window and quiet in the other's.
        #expect(loudness(early, from: 0.12, to: 0.3) > 20 * loudness(early, from: 1.02, to: 1.2))
        #expect(loudness(late, from: 1.02, to: 1.2) > 20 * loudness(late, from: 0.12, to: 0.3))
        // And nothing is heard before either was asked for.
        #expect(loudness(early, from: 0, to: 0.09) < 0.002)
        #expect(loudness(late, from: 0, to: 0.9) < 0.002)
    }

    /// The whole point of the renderer having no clock: the same sketch renders
    /// the same soundtrack, so an exported file can be exported again.
    @MainActor
    @Test func thesameNotesRenderToTheSameSoundtrackEveryTime() {
        let notes: [(at: Double, pitch: Double, length: Double)] = [
            (0.05, 60, 0.3), (0.4, 64, 0.3), (0.75, 67, 0.5), (0.75, 71, 0.5),
        ]
        let once = record(Synth(.pluck), notes: notes, seconds: 1.6)
        let again = record(Synth(.pluck), notes: notes, seconds: 1.6)
        #expect(once == again)
        #expect(once.contains { abs($0) > 0.02 })
    }

    /// The rate the file is written at is not the rate the hardware happens to
    /// be running at, so a note's length has to survive the change.
    @MainActor
    @Test func aNotesLengthSurvivesADifferentSampleRate() {
        let synth = Synth(.stab)
        _ = record(synth, notes: [(at: 0.05, pitch: 60, length: 0.5)], seconds: 1.2)

        for rate in [22050.0, 44100.0, 48000.0] {
            let fresh = Synth(.stab)
            fresh.recorded = synth.recorded
            let samples = fresh.renderExportAudio(upTo: 1.2, sampleRate: rate)
            #expect(samples.count == Int(1.2 * rate) * 2, "at \(rate)")
            // Sounding in the middle of the note and gone well after its end.
            let inside = rms(samples[(Int(0.3 * rate) * 2)..<(Int(0.45 * rate) * 2)])
            let after = rms(samples[(Int(1.0 * rate) * 2)..<(Int(1.15 * rate) * 2)])
            #expect(inside > 20 * after, "at \(rate): \(inside) then \(after)")
        }
    }

    /// Nothing is written down when a sketch is simply running, so the live
    /// path is untouched.
    @MainActor
    @Test func nothingIsWrittenDownWhenTheSketchIsJustRunning() {
        let synth = Synth(.pluck)
        synth.advance(by: 1)          // outside an export, this does nothing
        #expect(synth.exportClock == 0)
        // Playing outside an export would start the engine, which a test
        // should not do, so only the clock is checked here.
        #expect(!synth.isRecordingForExport)
    }

    // MARK: - The sketch's side

    @MainActor
    @Test func aSketchFindsTheInstrumentsItIsHolding() {
        let sketch = TwoInstruments()
        #expect(sketch.exportAudioSources().count == 2)
        // Nothing played, so the track it renders is silence rather than music.
        let quiet = sketch.renderSoundtrack(upTo: 0.2, sampleRate: Self.sampleRate,
                                            sources: sketch.exportAudioSources())
        #expect(quiet.allSatisfy { abs($0) < 1e-6 })
    }

    /// Two instruments at once are mixed, and the mix is brought down rather
    /// than reshaped if it would clip.
    @MainActor
    @Test func severalInstrumentsAreMixedWithoutClipping() {
        let sketch = TwoInstruments()
        exporting {
            for _ in 0..<60 {
                sketch.bass.advance(by: 1.0 / 60)
                sketch.lead.advance(by: 1.0 / 60)
            }
            sketch.bass.play(36, velocity: 1, for: 1)
            sketch.lead.play(72, velocity: 1, for: 1)
        }
        let mixed = sketch.renderSoundtrack(upTo: 2, sampleRate: Self.sampleRate,
                                            sources: sketch.exportAudioSources())
        #expect(mixed.count == Int(2 * Self.sampleRate) * 2)
        #expect(mixed.allSatisfy { abs($0) <= 1.0 })
        #expect(mixed.contains { abs($0) > 0.05 })
    }

    @MainActor
    final class TwoInstruments: Sketch {
        let bass = Synth(.bass)
        let lead = Synth(.bell)
    }
}
