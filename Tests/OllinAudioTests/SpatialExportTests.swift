import Foundation
import Testing
@testable import Ollin
@testable import OllinAudio

/// Placing a sound works live by rewiring the audio graph, which an export has
/// none of. So where the instrument was and where it was heard from are written
/// down as the frames go by, exactly the way the notes are, and the soundtrack
/// is rendered through a listener afterwards.
///
/// A sound cannot be snapshotted, so every check here is a twin: the same notes
/// and the same clock, differing only in where the sketch put the instrument.
@Suite(.serialized) struct SpatialExportTests {

    static let sampleRate = 44100.0

    /// A listener at the origin looking down −z, which is where a camera looks.
    static func listener(from eye: Vector3 = .zero) -> Camera3D {
        Camera3D(eye: eye, target: eye + Vector3(0, 0, -1))
    }

    @MainActor
    private func exporting(_ body: () -> Void) {
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        body()
    }

    /// Runs a sketch's worth of frames, letting the caller place the instrument
    /// and play notes on each one, then renders the soundtrack.
    @MainActor
    private func record(
        _ synth: Synth, seconds: Double, fps: Double = 60,
        frame: (Synth, Double) -> Void
    ) -> [Float] {
        exporting {
            let step = 1 / fps
            var elapsed = 0.0
            while elapsed < seconds {
                frame(synth, elapsed)
                synth.advance(by: step)
                elapsed += step
            }
        }
        return synth.renderExportAudio(upTo: seconds, sampleRate: Self.sampleRate)
    }

    /// Loudness of one channel over a window, from interleaved stereo.
    private func rms(_ samples: [Float], channel: Int, from: Double, to: Double) -> Double {
        let start = Int(from * Self.sampleRate)
        let end = min(samples.count / 2, Int(to * Self.sampleRate))
        guard end > start else { return 0 }
        var acc = 0.0
        for frame in start..<end {
            let value = Double(samples[frame * 2 + channel])
            acc += value * value
        }
        return (acc / Double(end - start)).squareRoot()
    }

    private func left(_ s: [Float], from: Double = 0.05, to: Double = 1.4) -> Double {
        rms(s, channel: 0, from: from, to: to)
    }

    private func right(_ s: [Float], from: Double = 0.05, to: Double = 1.4) -> Double {
        rms(s, channel: 1, from: from, to: to)
    }

    /// One note, held still somewhere, for a second and a half.
    @MainActor
    private func placed(at position: Vector3?, range: ClosedRange<Double> = 1...50) -> [Float] {
        let synth = Synth(.bell)
        synth.hearingRange = range
        return record(synth, seconds: 1.5) { synth, elapsed in
            if let position { synth.place(at: position, heardFrom: Self.listener()) }
            if elapsed == 0 { synth.play(72, velocity: 0.9, for: 1.0) }
        }
    }

    // MARK: - The inconsistency this closes

    /// The headline. The same note, the same clock, one placed to the left and
    /// one to the right: the export has to tell them apart.
    @MainActor
    @Test func aPlacedInstrumentIsPlacedInTheExportToo() {
        let toTheLeft = placed(at: Vector3(-6, 0, 0))
        let toTheRight = placed(at: Vector3(6, 0, 0))

        #expect(toTheLeft.contains { abs($0) > 0.005 })
        #expect(toTheRight.contains { abs($0) > 0.005 })
        // Each is louder in its own ear, and the two are mirror images.
        #expect(left(toTheLeft) > 2 * right(toTheLeft))
        #expect(right(toTheRight) > 2 * left(toTheRight))
    }

    /// The counterfactual for the whole feature: with no placing at all, the
    /// export is centered. This is what says the listener is only ever built for
    /// an instrument that asked for one.
    ///
    /// It is also the regression test for an instrument that reaches the file
    /// in one ear only. An unplaced instrument is built at the output's channel
    /// count, the way the live path builds it, so its one stream is written
    /// into both channels; handed to the mixer as mono it arrives in the left
    /// channel alone and the right is digital silence.
    @MainActor
    @Test func anUnplacedInstrumentStaysInTheMiddle() {
        let centered = placed(at: nil)
        #expect(centered.contains { abs($0) > 0.005 })

        // Both ears carry the sound, and carry the same sound.
        #expect(left(centered) > 0.005, "left is silent")
        #expect(right(centered) > 0.005, "right is silent")

        // The same sample for sample rather than merely the same loudness.
        let frames = centered.count / 2
        var identical = true
        for frame in 0..<frames where centered[frame * 2] != centered[frame * 2 + 1] {
            identical = false
            break
        }
        #expect(identical)
    }

    /// A placed instrument is a different graph, so this pins that the two
    /// paths really are different rather than the placing being ignored.
    @MainActor
    @Test func placingChangesTheSoundtrackAtAll() {
        let centered = placed(at: nil)
        let offToOneSide = placed(at: Vector3(-6, 0, 0))
        #expect(centered != offToOneSide)
    }

    // MARK: - What the listener does

    @MainActor
    @Test func somethingFurtherAwayIsQuieter() {
        let near = placed(at: Vector3(0, 0, -2))
        let far = placed(at: Vector3(0, 0, -20))

        let nearLevel = left(near) + right(near)
        let farLevel = left(far) + right(far)
        #expect(nearLevel > 2 * farLevel, "near \(nearLevel), far \(farLevel)")
    }

    /// `hearingRange` is the distance a sound stops fading over, so the same
    /// position at two ranges is two loudnesses.
    @MainActor
    @Test func theHearingRangeIsWhatSetsHowFarASoundCarries() {
        let carriesFar = placed(at: Vector3(0, 0, -12), range: 1...50)
        let dropsOffFast = placed(at: Vector3(0, 0, -12), range: 0.2...50)

        #expect(left(carriesFar) > 2 * left(dropsOffFast))
    }

    /// Where the listener is matters as much as where the sound is: the same
    /// position is on the other side if you stand on the other side of it.
    @MainActor
    @Test func movingTheListenerMovesTheSound() {
        @MainActor func heardFrom(_ eye: Vector3) -> [Float] {
            let synth = Synth(.bell)
            return record(synth, seconds: 1.5) { synth, elapsed in
                synth.place(at: .zero, heardFrom: Self.listener(from: eye))
                if elapsed == 0 { synth.play(72, velocity: 0.9, for: 1.0) }
            }
        }
        // The sound sits at the origin. Standing to its right, it is on the
        // left; standing to its left, it is on the right.
        let fromTheRight = heardFrom(Vector3(6, 0, 0))
        let fromTheLeft = heardFrom(Vector3(-6, 0, 0))

        #expect(left(fromTheRight) > 2 * right(fromTheRight))
        #expect(right(fromTheLeft) > 2 * left(fromTheLeft))
    }

    /// Taking an instrument out of the scene puts it back in the middle, which
    /// is the same as never having placed it.
    @MainActor
    @Test func unplacingPutsItBackInTheMiddle() {
        let synth = Synth(.bell)
        let samples = record(synth, seconds: 1.5) { synth, elapsed in
            if elapsed < 0.2 {
                synth.place(at: Vector3(-8, 0, 0), heardFrom: Self.listener())
            } else {
                synth.unplace()
            }
            if elapsed == 0 { synth.play(72, velocity: 0.9, for: 1.2) }
        }
        // Off to one side while it was placed...
        #expect(left(samples, from: 0.02, to: 0.18) > 2 * right(samples, from: 0.02, to: 0.18))
        // ...and even between the ears once it was not.
        let l = left(samples, from: 0.6, to: 1.2), r = right(samples, from: 0.6, to: 1.2)
        #expect(abs(l - r) < 0.2 * max(l, r), "left \(l), right \(r)")
    }

    // MARK: - Moving

    /// The pose is recorded every frame, not just the first one, so an
    /// instrument that walks past has to walk past in the export as well.
    @MainActor
    @Test func aMovingInstrumentMovesInTheExport() {
        let synth = Synth(.pad)
        let seconds = 2.0
        let samples = record(synth, seconds: seconds) { synth, elapsed in
            // Crosses from the left ear to the right over the whole take.
            let x = -8 + 16 * (elapsed / seconds)
            synth.place(at: Vector3(x, 0, -1), heardFrom: Self.listener())
            if elapsed == 0 { synth.play(60, velocity: 0.9, for: seconds) }
        }
        // Measured as the balance between the ears rather than as a level: a
        // note has an envelope of its own, and comparing loudness across
        // windows would be reading that instead of the crossing.
        func balance(from: Double, to: Double) -> Double {
            let r = right(samples, from: from, to: to)
            return r > 1e-9 ? left(samples, from: from, to: to) / r : .infinity
        }
        // Left at the start, right at the end, and passing through the middle
        // on the way rather than jumping at one moment.
        let start = balance(from: 0.1, to: 0.4)
        let middle = balance(from: 0.85, to: 1.15)
        let end = balance(from: 1.5, to: 1.9)
        #expect(start > 1.5, "start balance \(start)")
        #expect(end < 1 / 1.5, "end balance \(end)")
        #expect(start > middle && middle > end,
                "balance should fall through the take: \(start), \(middle), \(end)")
    }

    /// A sketch calls `place` every frame whether or not anything moved, so a
    /// still instrument must not cost a pose per frame.
    @MainActor
    @Test func aStillInstrumentIsRecordedOnce() {
        let synth = Synth(.bell)
        exporting {
            for _ in 0..<600 {
                synth.place(at: Vector3(1, 2, 3), heardFrom: Self.listener())
                synth.advance(by: 1.0 / 60)
            }
        }
        #expect(synth.recordedPoses.count == 1)

        // And one that moves is recorded as often as it moved.
        let walker = Synth(.bell)
        exporting {
            for step in 0..<600 {
                walker.place(at: Vector3(Double(step) * 0.01, 0, 0), heardFrom: Self.listener())
                walker.advance(by: 1.0 / 60)
            }
        }
        #expect(walker.recordedPoses.count == 600)
    }

    /// Nothing is written down when the sketch is simply running, so the live
    /// path is left exactly as it was.
    @MainActor
    @Test func nothingIsRecordedWhenTheSketchIsJustRunning() {
        let synth = Synth(.bell)
        synth.hearingRange = 2...30
        #expect(synth.recordedPoses.isEmpty)
        #expect(synth.placementRange == 2...30)
    }

    /// The renderer has no clock and the poses are a list, so a placed export
    /// comes out the same way twice, which is what makes it exportable at all.
    @MainActor
    @Test func aPlacedSoundtrackRendersTheSameWayTwice() {
        let once = placed(at: Vector3(-4, 1, -3))
        let again = placed(at: Vector3(-4, 1, -3))
        #expect(once == again)
        #expect(once.contains { abs($0) > 0.005 })
    }

    /// A sketch reading back where it put something gets the same answer during
    /// an export as it does live.
    @MainActor
    @Test func theInstrumentKnowsWhereItIsDuringAnExport() {
        let synth = Synth(.bell)
        exporting {
            #expect(synth.position == nil)
            synth.place(at: Vector3(3, 0, -2), heardFrom: Self.listener())
            #expect(synth.position == Vector3(3, 0, -2))
            synth.unplace()
            #expect(synth.position == nil)
        }
    }
}
