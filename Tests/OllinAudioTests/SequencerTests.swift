import Foundation
import Testing
@testable import Ollin
@testable import OllinAudio

/// The sequencer and the arpeggiator answer a beat position with notes and the
/// beats they land on, so their laws are read off those beats: swing moves only
/// the offbeats and by the fraction, a ratchet splits a step evenly, a chance is
/// a coin the same seed always tosses the same way, and held notes cycle in
/// order. The synth's wait, which is what lets those beats land between frames,
/// is checked on the renderer to the sample, and then the whole chain is heard:
/// a swung bar rendered through the export path has its onsets where the
/// numbers say.
@Suite struct SequencerLaws {

    // MARK: - StepSequencer

    @Test func sixteenRestsByDefaultAndTheyPlayNothing() {
        var sequencer = StepSequencer()
        #expect(sequencer.length == 16)
        let allRests = sequencer.steps.allSatisfy(\.isRest)
        #expect(allRests)
        #expect(sequencer.events(upTo: 8).isEmpty)
    }

    /// Straight, every step lands on its own multiple of the rate.
    @Test func everyStepLandsOnItsGridPlace() {
        var sequencer = StepSequencer(Array(repeating: Pitch(60), count: 16))
        let notes = sequencer.events(upTo: 3.99)
        #expect(notes.count == 16)
        for (index, note) in notes.enumerated() {
            #expect(note.step == index)
            #expect(abs(note.beat - Double(index) * 0.25) < 1e-12)
            #expect(note.pitch == Pitch(60))
            #expect(abs(note.length.beats - 0.125) < 1e-12)     // half the step
        }
    }

    /// The law the brief names: swing moves every other step, by the fraction,
    /// and leaves the downbeats where they were.
    @Test func swingMovesOnlyTheOffbeatsByTheFraction() {
        var straight = StepSequencer(Array(repeating: Pitch(60), count: 16))
        var swung = StepSequencer(Array(repeating: Pitch(60), count: 16), swing: 2.0 / 3)
        let a = straight.events(upTo: 3.99)
        let b = swung.events(upTo: 3.99)
        #expect(a.count == b.count)
        for (x, y) in zip(a, b) {
            if x.step % 2 == 0 {
                #expect(y.beat == x.beat)
            } else {
                // (2 * 2/3 - 1) of a sixteenth: a third of the step.
                #expect(abs((y.beat - x.beat) - 0.25 / 3) < 1e-12)
            }
        }
        // Half is straight: the twin with the default is the same to the bit.
        var half = StepSequencer(Array(repeating: Pitch(60), count: 16), swing: 0.5)
        #expect(half.events(upTo: 3.99).map(\.beat) == a.map(\.beat))
    }

    /// A swung offbeat can land after the point it was asked up to, which is
    /// what lets a frame ask for it early and the synth wait for it.
    @Test func aLookAheadHandsANoteBackBeforeItsBeat() {
        var swung = StepSequencer(Array(repeating: Pitch(60), count: 16), swing: 2.0 / 3)
        let notes = swung.events(upTo: 0.3)
        #expect(notes.map(\.step) == [0, 1])
        #expect(notes[1].beat > 0.3)
    }

    @Test func aRatchetSplitsTheStepEvenly() {
        var sequencer = StepSequencer(steps: [StepSequencer.Step(Pitch(60), ratchet: 3), .rest, .rest, .rest],
                                      gate: 0.5)
        let notes = sequencer.events(upTo: 0.99)
        #expect(notes.count == 3)
        for (index, note) in notes.enumerated() {
            #expect(note.step == 0)
            #expect(abs(note.beat - Double(index) * 0.25 / 3) < 1e-12)
            #expect(abs(note.length.beats - 0.25 / 3 * 0.5) < 1e-12)
        }
    }

    /// A chance is a coin the same seed always tosses the same way: replaying
    /// a bar plays the same steps, and another seed plays others.
    @Test func probabilityIsAChanceYouCanReplay() {
        func plays(_ probability: Double, seed: Int, steps: Int = 400) -> [Int] {
            var sequencer = StepSequencer(
                steps: [StepSequencer.Step(Pitch(60), probability: probability)], seed: seed
            )
            sequencer.maxCatchUp = steps
            return sequencer.events(upTo: Double(steps) * 0.25 - 0.01).map(\.step)
        }
        #expect(plays(0, seed: 1).isEmpty)
        #expect(plays(1, seed: 1).count == 400)

        let half = plays(0.5, seed: 1)
        #expect(half.count > 150 && half.count < 250)
        #expect(half == plays(0.5, seed: 1))
        #expect(half != plays(0.5, seed: 2))

        // A quarter plays fewer than a half, which is the whole point of the number.
        #expect(plays(0.25, seed: 1).count < half.count)
    }

    @Test func velocityAndPitchTravelWithTheStep() {
        var sequencer = StepSequencer(steps: [
            StepSequencer.Step(Pitch(36), velocity: 1),
            StepSequencer.Step(Pitch(38), velocity: 0.3),
        ])
        let notes = sequencer.events(upTo: 0.49)
        #expect(notes.map(\.pitch) == [Pitch(36), Pitch(38)])
        #expect(notes.map(\.velocity) == [1, 0.3])
    }

    @Test func theBarIsReadBackAsItWasWritten() {
        let written = StepSequencer(pattern: "C3 . E3 36 - _")
        #expect(written?.description == "C3 . E3 C2 . .")
        #expect(written?.length == 6)
        #expect(StepSequencer(pattern: "C3 x E3") == nil)

        let literal: StepSequencer = "A1 . . A1"
        #expect(literal.description == "A1 . . A1")
        let broken: StepSequencer = "A1 ? A1"
        #expect(broken.length == 0)
    }

    @Test func aRhythmMakesADrumLane() {
        var lane = StepSequencer(.tresillo, pitch: 36)
        #expect(lane.length == 8)
        #expect(lane.events(upTo: 1.99).map(\.step) == [0, 3, 6])
    }

    /// Changing the rate carries on from where the music is, rather than
    /// replaying a stretch under the new count or emptying it into one frame.
    @Test func theRateChangesWithoutAJump() {
        var sequencer = StepSequencer(Array(repeating: Pitch(60), count: 16))
        #expect(sequencer.events(upTo: 0.99).count == 4)
        sequencer.rate = .eighth
        // The sixteenths ran to 0.99; the first eighth after that is at 1.0.
        let after = sequencer.events(upTo: 2)
        #expect(after.map(\.beat) == [1.0, 1.5, 2.0])
    }

    @Test func resetSkipsSilentlyAndTheSubscriptWrapsBothWays() {
        var sequencer = StepSequencer(Array(repeating: Pitch(60), count: 16))
        sequencer.reset(to: 8)
        let notes = sequencer.events(upTo: 8.5)
        #expect(notes.map(\.step) == [33, 34])
        let allAfter = notes.allSatisfy { $0.beat > 8 }
        #expect(allAfter)

        sequencer[17] = .rest
        #expect(sequencer[1].isRest)
        #expect(sequencer[-15].isRest)
        #expect(!sequencer[2].isRest)
    }

    // MARK: - Arpeggiator

    @Test func heldNotesCycleInOrder() {
        var arp = Arpeggiator([Pitch(64), Pitch(60), Pitch(67)])
        let notes = arp.events(upTo: 1.49)
        #expect(notes.map(\.pitch) == [60, 64, 67, 60, 64, 67].map { Pitch($0) })
        #expect(notes.map(\.beat) == [0, 0.25, 0.5, 0.75, 1, 1.25])
    }

    /// A note added while the others are still held joins the ladder where it
    /// belongs, and the figure neither restarts nor repeats a note.
    @Test func aNoteAddedWhileHoldingJoinsWithoutRestarting() {
        var arp = Arpeggiator([Pitch(60), Pitch(64), Pitch(67)])
        #expect(arp.events(upTo: 0.49).map(\.pitch) == [Pitch(60), Pitch(64)])
        arp.hold(Pitch(71))
        #expect(arp.events(upTo: 1.24).map(\.pitch) == [Pitch(67), Pitch(71), Pitch(60)])
        arp.release(Pitch(64))
        #expect(arp.events(upTo: 1.99).map(\.pitch) == [Pitch(67), Pitch(71), Pitch(60)])
    }

    @Test func aNewChordAfterSilenceStartsFromItsFirstNote() {
        var arp = Arpeggiator([Pitch(60), Pitch(64), Pitch(67)])
        #expect(arp.events(upTo: 0.49).count == 2)
        arp.notes = []
        #expect(arp.events(upTo: 0.99).isEmpty)
        #expect(arp.next == nil)
        arp.notes = [Pitch(65), Pitch(62)]
        #expect(arp.next == Pitch(62))
        #expect(arp.events(upTo: 1.49).map(\.pitch) == [Pitch(62), Pitch(65)])
    }

    @Test func latchKeepsTheChordAfterTheKeysGoUp() {
        var arp = Arpeggiator([Pitch(60), Pitch(64), Pitch(67)], latches: true)
        #expect(arp.events(upTo: 0.24).map(\.pitch) == [Pitch(60)])
        arp.notes = []
        #expect(arp.playing == [Pitch(60), Pitch(64), Pitch(67)])
        #expect(arp.events(upTo: 0.99).map(\.pitch) == [Pitch(64), Pitch(67), Pitch(60)])
        // The next key down is a new chord, and starts it.
        arp.hold(Pitch(62))
        #expect(arp.events(upTo: 1.49).map(\.pitch) == [Pitch(62), Pitch(62)])
        // Latch off, silence follows the last release.
        arp.latches = false
        arp.notes = []
        #expect(arp.events(upTo: 2.99).isEmpty)
    }

    @Test func asPlayedKeepsTheOrderTheKeysCame() {
        var arp = Arpeggiator(.asPlayed)
        arp.hold(Pitch(67))
        arp.hold(Pitch(60))
        arp.hold(Pitch(64))
        arp.hold(Pitch(60))     // already held: no change
        #expect(arp.notes.count == 3)
        #expect(arp.events(upTo: 0.74).map(\.pitch) == [Pitch(67), Pitch(60), Pitch(64)])
    }

    @Test func octavesStackTheLadderAndTheGateSetsTheLength() {
        var arp = Arpeggiator([Pitch(60), Pitch(64)], .up, octaves: 2, rate: .eighth, gate: 0.25)
        let notes = arp.events(upTo: 1.99)
        #expect(notes.map(\.pitch) == [60, 64, 72, 76].map { Pitch($0) })
        let quarterOfAnEighth = notes.allSatisfy { abs($0.length.beats - 0.125) < 1e-12 }
        #expect(quarterOfAnEighth)
        #expect(arp.figure.order == [60, 64, 72, 76].map { Pitch($0) })
    }

    /// Nothing held for a while, then a chord: the first note lands on the
    /// grid rather than on the moment the keys went down.
    @Test func theGridHoldsThroughSilence() {
        var arp = Arpeggiator()
        #expect(arp.events(upTo: 1.1).isEmpty)
        arp.notes = [Pitch(60)]
        let notes = arp.events(upTo: 1.4)
        #expect(notes.map(\.beat) == [1.25])
        #expect(notes.map(\.step) == [5])
    }

    @Test func randomIsSeededAndStaysInTheChord() {
        var one = Arpeggiator([Pitch(60), Pitch(64), Pitch(67)], .random, seed: 3)
        var same = Arpeggiator([Pitch(60), Pitch(64), Pitch(67)], .random, seed: 3)
        var other = Arpeggiator([Pitch(60), Pitch(64), Pitch(67)], .random, seed: 4)
        one.maxCatchUp = 64
        same.maxCatchUp = 64
        other.maxCatchUp = 64
        let a = one.events(upTo: 7.99).map(\.pitch)
        #expect(a.count == 32)
        #expect(a == same.events(upTo: 7.99).map(\.pitch))
        #expect(a != other.events(upTo: 7.99).map(\.pitch))
        #expect(Set(a).isSubset(of: [Pitch(60), Pitch(64), Pitch(67)]))
    }

    @Test func swingLeansTheArpeggiatorTheSameWay() {
        var arp = Arpeggiator([Pitch(60)], swing: 0.6)
        let notes = arp.events(upTo: 0.99)
        #expect(notes.count == 4)
        for (beat, expected) in zip(notes.map(\.beat), [0, 0.3, 0.5, 0.8]) {
            #expect(abs(beat - expected) < 1e-12)
        }
    }

    // MARK: - The synth's wait, on the renderer

    static let sampleRate = 48000.0

    /// A voice whose notes start from silence and go back to it quickly, so
    /// an onset is the first nonzero sample after a run of zeros.
    static let click = Voice(
        waveform: .square,
        envelope: Envelope(attack: 0.0005, decay: 0, sustain: 1, release: 0.002),
        gain: 0.5
    )

    /// A note asked for with a wait starts on that sample, inside a block or
    /// across one, rather than on the next block boundary.
    @Test func aWaitLandsANoteOnItsOwnSample() {
        for wait in [0, 100, 511, 512, 1000, 5000] {
            let ring = EventRing()
            let renderer = SynthRenderer(voice: Self.click, polyphony: 4, sampleRate: Self.sampleRate, events: ring)
            ring.push(SynthEvent(kind: .noteOn, pitch: 60, durationSamples: 200, delaySamples: wait))
            let samples = render(renderer, seconds: 0.25)
            let onset = firstOnset(of: samples)
            #expect(onset != nil, "no note at wait \(wait)")
            if let onset {
                // Where a note with no wait starts, plus the wait.
                let base = baselineOnset()
                #expect(onset == base + wait, "wait \(wait) landed at \(onset - base)")
            }
        }
    }

    @Test func waitingNotesKeepTheirOrderAndTheirSpacing() {
        let ring = EventRing()
        let renderer = SynthRenderer(voice: Self.click, polyphony: 8, sampleRate: Self.sampleRate, events: ring)
        for wait in [1200, 300, 900, 600] {
            ring.push(SynthEvent(kind: .noteOn, pitch: 60, durationSamples: 40, delaySamples: wait))
        }
        let onsets = allOnsets(of: render(renderer, seconds: 0.1))
        let base = baselineOnset()
        #expect(onsets.map { $0 - base } == [300, 600, 900, 1200])
    }

    /// A note still waiting to start is dropped by letting everything go, the
    /// way a sequencer stopping expects.
    @Test func lettingEverythingGoDropsAWaitingNote() {
        let ring = EventRing()
        let renderer = SynthRenderer(voice: Self.click, polyphony: 4, sampleRate: Self.sampleRate, events: ring)
        ring.push(SynthEvent(kind: .noteOn, pitch: 60, durationSamples: 200, delaySamples: 2000))
        ring.push(SynthEvent(kind: .allNotesOff))
        let samples = render(renderer, seconds: 0.2)
        let silent = samples.allSatisfy { $0 == 0 }
        #expect(silent)
    }

    // MARK: - Heard, through the export path

    /// The brief's proof: a swung bar rendered as sound has its onsets where
    /// the numbers say, alternating long and short gaps in the ratio the swing
    /// names, and a ratchet's strikes an even split apart. The export path is
    /// used because it is exact to the sample, and the same wait carries the
    /// live path's notes between the frames.
    @MainActor
    @Test func aSwungBarIsHeardWithItsOnsetsWhereTheNumbersSay() {
        let tempo: Tempo = 120
        func onsets(swing: Double, ratchet: Int = 1) -> [Int] {
            var sequencer = StepSequencer(Array(repeating: Pitch(60), count: 8), swing: swing, gate: 0.15)
            sequencer[4] = StepSequencer.Step(Pitch(60), ratchet: ratchet)
            let synth = Synth(Self.click)
            OllinApp.isRenderingHeadless = true
            defer { OllinApp.isRenderingHeadless = false }
            let frame = 1.0 / 60
            for index in 0..<60 {
                let t = Double(index) * frame
                let now = tempo.beats(at: t)
                let ahead = tempo.beats(at: t + frame)
                synth.play(sequencer.events(upTo: ahead), tempo: tempo, from: now)
                synth.advance(by: frame)
            }
            let stereo = synth.renderExportAudio(upTo: 1.0, sampleRate: 44100)
            let left = stride(from: 0, to: stereo.count, by: 2).map { stereo[$0] }
            return allOnsets(of: left)
        }

        // Straight: eight notes a sixteenth apart, 125 ms at 120 bpm.
        let straight = onsets(swing: 0.5)
        #expect(straight.count == 8)
        let sixteenth = 0.125 * 44100
        for (a, b) in zip(straight, straight.dropFirst()) {
            #expect(abs(Double(b - a) - sixteenth) <= 2)
        }

        // Swung by two thirds: the gaps alternate 2:1, long then short.
        let swung = onsets(swing: 2.0 / 3)
        #expect(swung.count == 8)
        for (index, pair) in zip(swung, swung.dropFirst()).enumerated() {
            let expected = index % 2 == 0 ? sixteenth * 4 / 3 : sixteenth * 2 / 3
            #expect(abs(Double(pair.1 - pair.0) - expected) <= 2, "gap \(index)")
        }
        // The downbeats did not move.
        for step in stride(from: 0, to: 8, by: 2) {
            #expect(abs(swung[step] - straight[step]) <= 1)
        }

        // A ratchet of three on the fifth step: ten onsets, and the three
        // strikes a third of a sixteenth apart.
        let rolled = onsets(swing: 0.5, ratchet: 3)
        #expect(rolled.count == 10)
        if rolled.count == 10 {
            #expect(abs(Double(rolled[5] - rolled[4]) - sixteenth / 3) <= 2)
            #expect(abs(Double(rolled[6] - rolled[5]) - sixteenth / 3) <= 2)
            #expect(abs(Double(rolled[7] - rolled[6]) - sixteenth / 3) <= 2)
        }
    }

    /// The export writes a waited note down where its wait says, even when a
    /// note asked for later lands earlier.
    @MainActor
    @Test func theExportPlacesAWaitedNoteByItsWait() {
        let synth = Synth(Self.click)
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        let frame = 1.0 / 60
        // Frame 0: a note 100 ms out. Frame 1: a note now, which lands first.
        synth.play(Pitch(60), for: 0.01, after: 0.1)
        synth.advance(by: frame)
        synth.play(Pitch(60), for: 0.01)
        synth.advance(by: frame)
        let stereo = synth.renderExportAudio(upTo: 0.5, sampleRate: 44100)
        let left = stride(from: 0, to: stereo.count, by: 2).map { stereo[$0] }
        let onsets = allOnsets(of: left)
        #expect(onsets.count == 2)
        if onsets.count == 2 {
            #expect(abs(Double(onsets[1] - onsets[0]) - (0.1 - frame) * 44100) <= 2)
        }
    }

    // MARK: Helpers

    private func render(_ renderer: SynthRenderer, seconds: Double) -> [Float] {
        let frames = Int(seconds * Self.sampleRate)
        var samples = [Float](repeating: 0, count: frames)
        samples.withUnsafeMutableBufferPointer { buffer in
            var offset = 0
            while offset < frames {
                let count = min(512, frames - offset)
                let slice = UnsafeMutableBufferPointer(start: buffer.baseAddress! + offset, count: count)
                renderer.render(into: slice, frameCount: count)
                offset += count
            }
        }
        return samples
    }

    /// Where a note with no wait on it starts, measured the same way.
    private func baselineOnset() -> Int {
        let ring = EventRing()
        let renderer = SynthRenderer(voice: Self.click, polyphony: 4, sampleRate: Self.sampleRate, events: ring)
        ring.push(SynthEvent(kind: .noteOn, pitch: 60, durationSamples: 200))
        return firstOnset(of: render(renderer, seconds: 0.05)) ?? 0
    }

    private func firstOnset(of samples: [Float]) -> Int? {
        samples.firstIndex { $0 != 0 }
    }

    /// Every place the signal comes back from a run of silence.
    private func allOnsets(of samples: [Float]) -> [Int] {
        var onsets = [Int]()
        var silent = 0
        for (index, sample) in samples.enumerated() {
            if sample == 0 {
                silent += 1
            } else {
                if silent >= 32 || index == 0 { onsets.append(index) }
                silent = 0
            }
        }
        if let first = samples.firstIndex(where: { $0 != 0 }), onsets.first != first {
            onsets.insert(first, at: 0)
        }
        return onsets
    }
}
