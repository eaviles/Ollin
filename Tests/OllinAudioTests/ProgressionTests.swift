import Foundation
import Testing
@testable import OllinAudio

/// The composition tier deals in pure values with no clock and no randomness it
/// did not bring itself, so everything here is an exact expectation or a twin.
@Suite struct ProgressionTests {

    static let key = Scale(.major, root: "C4")

    // MARK: - Progressions

    @Test func romanNumeralsReadAsDegrees() {
        #expect(Progression.parse("I vi IV V") == [0, 5, 3, 4])
        // The separator does not matter, because anything that is not a
        // numeral simply ends the one being read.
        #expect(Progression.parse("I-vi-IV-V") == [0, 5, 3, 4])
        #expect(Progression.parse("I, vi, IV, V") == [0, 5, 3, 4])
        #expect(Progression.parse("i VII VI V") == [0, 6, 5, 4])
        // Case is accepted and ignored: the key decides major or minor.
        #expect(Progression.parse("I vi") == Progression.parse("i VI"))
        // Anything unreadable is skipped rather than guessed at.
        #expect(Progression.parse("I zzz V") == [0, 4])
        #expect(Progression.parse("").isEmpty)
    }

    /// The reason to write degrees rather than chord names: the quality falls
    /// out of the key, so the same progression is minor in a minor key with
    /// nothing said about it.
    @Test func theQualityComesOutOfTheKey() {
        let major = Progression("I", in: Scale(.major, root: "C4"))
        let minor = Progression("I", in: Scale(.minor, root: "C4"))

        // Same root, different third: four semitones up against three.
        #expect(major.pitches(at: 0)[0].midi == minor.pitches(at: 0)[0].midi)
        #expect(major.pitches(at: 0)[1].midi - major.pitches(at: 0)[0].midi == 4)
        #expect(minor.pitches(at: 0)[1].midi - minor.pitches(at: 0)[0].midi == 3)
    }

    @Test func aProgressionWrapsSoAStepNumberCanClimbForever() {
        let changes = Progression("I vi IV V", in: Self.key)
        #expect(changes.count == 4)
        #expect(changes.degree(at: 0) == 0)
        #expect(changes.degree(at: 4) == 0)
        #expect(changes.degree(at: 401) == changes.degree(at: 1))
        // And backwards, for a sketch counting down.
        #expect(changes.degree(at: -1) == 4)
        #expect(changes.degree(at: -4) == 0)
    }

    @Test func aProgressionMovesToAnotherKeyWhole() {
        let changes = Progression("I vi IV V", in: Self.key)
        let up = changes.transposed(by: 5)
        #expect(up.degrees == changes.degrees)
        for step in 0..<4 {
            for (a, b) in zip(changes.pitches(at: step), up.pitches(at: step)) {
                #expect(abs(b.midi - a.midi - 5) < 1e-9)
            }
        }
    }

    @Test func rotatingStartsTheCycleSomewhereElse() {
        let changes = Progression("I vi IV V", in: Self.key)
        let later = changes.rotated(by: 1)
        #expect(later.degrees == [5, 3, 4, 0])
        #expect(changes.rotated(by: 4).degrees == changes.degrees)
        #expect(changes.rotated(by: -1).degrees == [4, 0, 5, 3])
    }

    @Test func namedProgressionsAreTheOnesTheyAreNamedAfter() {
        #expect(Progression.pop(in: Self.key).degrees == [0, 4, 5, 3])
        #expect(Progression.fifties(in: Self.key).degrees == [0, 5, 3, 4])
        #expect(Progression.twoFiveOne(in: Self.key).degrees == [1, 4, 0])
        #expect(Progression.blues(in: Self.key).count == 12)
        // The four note ones really are four notes.
        #expect(Progression.twoFiveOne(in: Self.key).pitches(at: 0).count == 4)
    }

    // MARK: - Wandering

    /// A wander is only allowed the moves the original made, so it belongs to
    /// the same music even where it goes somewhere the original never did.
    @Test func awanderOnlyMakesMovesTheOriginalMade() {
        let changes = Progression("I vi IV V ii V", in: Self.key)
        let allowed = Set(changes.degrees)
        let wandered = changes.wandering(64, seed: 3)

        #expect(wandered.count == 64)
        #expect(wandered.degrees.allSatisfy { allowed.contains($0) })
        // And it genuinely wandered rather than repeating the cycle.
        #expect(wandered.degrees.prefix(6) != ArraySlice(changes.degrees)
                || wandered.degrees.dropFirst(6).prefix(6) != ArraySlice(changes.degrees))
    }

    /// Seeded per call rather than from the sketch, so a progression a sketch
    /// liked can be asked for again and be the same one.
    @Test func thesameSeedGivesTheSameWander() {
        let changes = Progression("I vi IV V ii", in: Self.key)
        #expect(changes.wandering(32, seed: 7).degrees == changes.wandering(32, seed: 7).degrees)
        #expect(changes.wandering(32, seed: 7).degrees != changes.wandering(32, seed: 8).degrees)
    }

    @Test func aprogressionWithOneChordHasNowhereToWander() {
        let stuck = Progression("I", in: Self.key)
        #expect(stuck.wandering(16).degrees == [0])
    }

    // MARK: - Chord symbols

    @Test func chordSymbolsReadAsChords() throws {
        let plain = try #require(Chord(symbol: "C"))
        #expect(plain.quality == .major)
        #expect(plain.root == Pitch("C4"))

        #expect(Chord(symbol: "Am")?.quality == .minor)
        #expect(Chord(symbol: "Cmaj7")?.quality == .majorSeventh)
        #expect(Chord(symbol: "G7")?.quality == .dominantSeventh)
        #expect(Chord(symbol: "Dm7")?.quality == .minorSeventh)
        #expect(Chord(symbol: "Bm7b5")?.quality == .halfDiminishedSeventh)
        #expect(Chord(symbol: "Csus4")?.quality == .sus4)
        #expect(Chord(symbol: "C5")?.quality == .fifth)
        #expect(Chord(symbol: "Cdim7")?.quality == .diminishedSeventh)

        // Accidentals, and the several spellings of one quality.
        #expect(Chord(symbol: "F#m7")?.root == Pitch("F#4"))
        #expect(Chord(symbol: "Bb")?.root == Pitch("Bb4"))
        #expect(Chord(symbol: "Cmin7")?.quality == .minorSeventh)
        #expect(Chord(symbol: "C-7")?.quality == .minorSeventh)
    }

    /// An octave has to be told from the number in a quality, which is the one
    /// genuinely ambiguous thing about the notation.
    @Test func anOctaveIsToldFromTheNumberInAQuality() {
        // A trailing number after a real quality is an octave.
        #expect(Chord(symbol: "Cm3")?.root == Pitch("C3"))
        #expect(Chord(symbol: "Cm3")?.quality == .minor)
        #expect(Chord(symbol: "C3")?.root == Pitch("C3"))
        // But the 7 of a seventh is not an octave, and neither is the 4 of a sus.
        #expect(Chord(symbol: "C7")?.quality == .dominantSeventh)
        #expect(Chord(symbol: "C7")?.root == Pitch("C4"))
        #expect(Chord(symbol: "Csus4")?.root == Pitch("C4"))
        #expect(Chord(symbol: "Cmaj7")?.root == Pitch("C4"))
    }

    /// A typo is something you find out about rather than something that
    /// quietly becomes a different chord.
    @Test func somethingThatIsNotAChordSymbolIsNil() {
        #expect(Chord(symbol: "") == nil)
        #expect(Chord(symbol: "H") == nil)
        #expect(Chord(symbol: "Cwobble") == nil)
        #expect(Chord(symbol: "7") == nil)
    }

    @Test func aSlashBassTurnsTheChordUntilThatNoteIsLowest() throws {
        let overG = try #require(Chord(symbol: "C/G"))
        #expect(overG.quality == .major)
        // G is the fifth of C, which is the third note, so the chord is turned
        // twice to put it at the bottom.
        #expect(overG.inversion == 2)
        #expect(overG.pitches.first?.midi.truncatingRemainder(dividingBy: 12)
                == Pitch("G4").midi.truncatingRemainder(dividingBy: 12))
    }

    @Test func aChordCanBeWrittenAsALiteral() {
        let chord: Chord = "Am7"
        #expect(chord.quality == .minorSeventh)
        #expect(chord.root == Pitch("A4"))
    }

    @Test func aProgressionCanBeWrittenAsChordSymbols() {
        let changes = Progression(symbols: "Dm7 G7 Cmaj7")
        #expect(changes.count == 3)
        #expect(changes.chord(at: 0)?.quality == .minorSeventh)
        #expect(changes.chord(at: 1)?.quality == .dominantSeventh)
        #expect(changes.chord(at: 2)?.quality == .majorSeventh)
        // It wraps like any other, and the roots are the ones written.
        #expect(changes.chord(at: 3)?.root == changes.chord(at: 0)?.root)
        #expect(changes.root(at: 1) == Pitch("G4"))
        #expect(changes.pitches(at: 1).count == 4)
    }

    /// A progression written as degrees carries no chords of its own, which is
    /// what says the two forms really are different things.
    @Test func degreesAndSymbolsAreDifferentForms() {
        #expect(Progression("I vi", in: Self.key).chord(at: 0) == nil)
        #expect(Progression(symbols: "C Am").chord(at: 0) != nil)
        // Both still answer with notes.
        #expect(!Progression("I vi", in: Self.key).pitches(at: 0).isEmpty)
        #expect(!Progression(symbols: "C Am").pitches(at: 0).isEmpty)
    }

    // MARK: - Tunings

    /// Twelve equal steps is the ordinary keyboard, so it has to come out as
    /// the ordinary keyboard.
    @Test func twelveEqualStepsIsTheOrdinaryKeyboard() {
        let tuning = Tuning.equal(12, root: "C4")
        for degree in -24...24 {
            let expected = Pitch("C4").midi + Double(degree)
            #expect(abs(tuning[degree].midi - expected) < 1e-9,
                    "degree \(degree) landed on \(tuning[degree].midi)")
        }
    }

    /// The whole point of just intonation: the intervals are whole number
    /// ratios, which the equal ones are not.
    @Test func justIntonationIsWholeNumberRatios() {
        let just = Tuning.just.rooted(at: "C4")
        // The fifth is exactly three halves, where the equal one is 1.4983.
        #expect(abs(just.frequency(4) / just.frequency(0) - 1.5) < 1e-12)
        // And the major third is exactly five quarters.
        #expect(abs(just.frequency(2) / just.frequency(0) - 1.25) < 1e-12)

        // Said in cents, which is how the difference is usually seen: the just
        // third is about fourteen cents flat of the equal one.
        let cents = Tuning.just.cents
        #expect(abs(cents[2] - 386.31) < 0.01)
        #expect(abs(cents[4] - 701.955) < 0.01)
        // Index 2 of a seven note scale is its third; the equal one's third is
        // index 4 of twelve, which is the round 400 the just one is flat of.
        #expect(abs(Tuning.equal(12).cents[4] - 400) < 1e-9)
    }

    @Test func anEqualTuningDividesItsPeriodEvenly() {
        for count in [5, 12, 19, 24, 31] {
            let tuning = Tuning.equal(count)
            #expect(tuning.degreeCount == count)
            // One period up is exactly a doubling.
            #expect(abs(tuning.frequency(count) / tuning.frequency(0) - 2) < 1e-9)
            // And the steps are all the same size.
            let cents = tuning.cents
            for index in 1..<cents.count {
                #expect(abs((cents[index] - cents[index - 1]) - 1200 / Double(count)) < 1e-6)
            }
        }
    }

    /// A tuning whose period is not an octave, which is the case that says the
    /// type is really about ratios rather than about keyboards.
    @Test func atuningNeedNotHaveAnOctaveInIt() {
        let bp = Tuning.bohlenPierce.rooted(at: "C4")
        #expect(bp.degreeCount == 13)
        // Thirteen steps is a tripling, not a doubling, so there is no octave.
        #expect(abs(bp.frequency(13) / bp.frequency(0) - 3) < 1e-9)
        let hasOctave = (0...13).contains { abs(bp.frequency($0) / bp.frequency(0) - 2) < 0.01 }
        #expect(!hasOctave)
    }

    @Test func degreesRunPastBothEndsOfATuning() {
        let tuning = Tuning.just.rooted(at: "C4")
        // A period up and a period down are exact doublings and halvings.
        #expect(abs(tuning.frequency(7) / tuning.frequency(0) - 2) < 1e-9)
        #expect(abs(tuning.frequency(-7) / tuning.frequency(0) - 0.5) < 1e-9)
        #expect(tuning[-1].midi < tuning[0].midi)
    }

    /// How a pitch decided by something that is not music joins the tuning.
    @Test func snappingFindsTheNearestPitchInTheTuning() {
        let tuning = Tuning.equal(12, root: "C4")
        #expect(abs(tuning.snap(Pitch(60.4)).midi - 60) < 1e-9)
        #expect(abs(tuning.snap(Pitch(60.6)).midi - 61) < 1e-9)

        // In a tuning with more steps, the same stray pitch has somewhere
        // nearer to go, which is the counterfactual.
        let quarter = Tuning.quarterTones.rooted(at: "C4")
        let stray = Pitch(60.5)
        #expect(abs(quarter.snap(stray).midi - 60.5) < 1e-9)
        #expect(abs(tuning.snap(stray).midi - 60.5) > 0.4)
    }

    @Test func ratiosAreFoldedIntoOnePeriodAndDeduplicated() {
        // The same tuning written three ways.
        let plain = Tuning(ratios: [1, 1.5])
        let wide = Tuning(ratios: [1, 1.5, 3])          // 3 folds onto 1.5
        let low = Tuning(ratios: [0.5, 1.5])            // 0.5 folds onto 1
        #expect(plain.ratios == wide.ratios)
        #expect(plain.ratios == low.ratios)
        #expect(plain.ratios.count == 2)
        // And it is always sorted, whatever order it arrived in.
        #expect(Tuning(ratios: [1.5, 1.25, 1]).ratios == [1, 1.25, 1.5])
    }

    @Test func anEmptyTuningIsStillPlayable() {
        let empty = Tuning(ratios: [])
        #expect(empty.ratios == [1])
        #expect(empty.degreeCount == 1)
        // Every degree is a period apart, which is the only thing it can mean.
        #expect(abs(empty.frequency(1) / empty.frequency(0) - 2) < 1e-9)
    }

    // MARK: - Following a beat

    /// The engine takes times and gives back musical time, so it can be tested
    /// by handing it a beat rather than by playing one at it.
    @Test func aSteadyBeatIsFollowed() {
        var engine = BeatEngine()
        // Two beats a second is 120 bpm.
        for index in 0..<12 {
            engine.hearBeat(at: Double(index) * 0.5)
        }
        #expect(engine.isFollowing)
        #expect(abs(engine.tempo - 120) < 0.5, "read \(engine.tempo) bpm")
        #expect(engine.steadiness > 0.95)

        // The position carries on between beats at the tempo it believes.
        let atLastBeat = engine.beats(at: 11 * 0.5)
        #expect(abs(engine.beats(at: 11 * 0.5 + 0.25) - atLastBeat - 0.5) < 1e-6)
    }

    @Test func nothingIsFollowedUntilEnoughHasBeenHeard() {
        var engine = BeatEngine()
        #expect(!engine.isFollowing)
        #expect(engine.tempo == 0)
        engine.hearBeat(at: 0)
        engine.hearBeat(at: 0.5)
        #expect(!engine.isFollowing)
        engine.hearBeat(at: 1.0)
        engine.hearBeat(at: 1.5)
        #expect(engine.isFollowing)
    }

    /// The failure this is really guarding against: a detector that fires twice
    /// a beat reads as twice the tempo, and that is the same music.
    @Test func atempoOutsideTheRangeIsFoldedIntoIt() {
        var fast = BeatEngine(range: 60...160)
        for index in 0..<12 { fast.hearBeat(at: Double(index) * 0.125) }   // 480 bpm
        #expect(abs(fast.tempo - 120) < 1, "read \(fast.tempo) bpm")

        // And a detector that only fires on every other beat reads half the
        // tempo, which doubles back into the range at its bottom.
        var slow = BeatEngine(range: 60...160)
        for index in 0..<12 { slow.hearBeat(at: Double(index) * 2.0) }     // 30 bpm
        #expect(abs(slow.tempo - 60) < 1, "read \(slow.tempo) bpm")
    }

    /// One missed beat should cost nothing, which is what the middle value
    /// rather than the average buys.
    @Test func aMissedBeatDoesNotMoveTheTempo() {
        var engine = BeatEngine()
        var time = 0.0
        for index in 0..<14 {
            engine.hearBeat(at: time)
            // Every fifth beat goes unheard, so that gap is twice as long.
            time += index % 5 == 4 ? 1.0 : 0.5
        }
        #expect(abs(engine.tempo - 120) < 1, "read \(engine.tempo) bpm")
    }

    /// A wobbling player and a machine should not be reported with the same
    /// confidence. The twin is the same number of beats, evenly spaced.
    @Test func steadinessTellsAMachineFromAPlayer() {
        var machine = BeatEngine()
        for index in 0..<12 { machine.hearBeat(at: Double(index) * 0.5) }

        var player = BeatEngine()
        var time = 0.0
        let wobble = [0.42, 0.58, 0.47, 0.61, 0.44, 0.56, 0.49, 0.6, 0.41, 0.59, 0.52]
        for gap in wobble { player.hearBeat(at: time); time += gap }
        player.hearBeat(at: time)

        #expect(machine.steadiness > player.steadiness)
        #expect(machine.steadiness > 0.95)
        #expect(player.steadiness < 0.92)
    }

    /// The room's own pattern comes back as something a sketch can play.
    @Test func whatWasHeardComesBackAsARhythm() {
        var engine = BeatEngine()
        // Four to the bar, so a four step cycle is struck on every step.
        for index in 0..<12 { engine.hearBeat(at: Double(index) * 0.5) }
        let steady = engine.rhythm(steps: 4)
        #expect(steady.steps.allSatisfy { $0 })

        // Nothing heard is nothing to play, rather than a guess.
        let silent = BeatEngine().rhythm(steps: 8)
        #expect(silent.steps.allSatisfy { !$0 })
        #expect(silent.steps.count == 8)
    }

    @Test func forgettingPutsItBackWhereItStarted() {
        var engine = BeatEngine()
        for index in 0..<12 { engine.hearBeat(at: Double(index) * 0.5) }
        #expect(engine.isFollowing)
        engine.reset()
        #expect(!engine.isFollowing)
        #expect(engine.tempo == 0)
        #expect(engine.beatCount == 0)
    }
}
