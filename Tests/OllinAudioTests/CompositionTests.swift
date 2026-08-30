import Foundation
import Testing
@testable import OllinAudio

/// The composition types are pure values, so they are checked by what they
/// produce rather than by how they sound: a rhythm against the patterns the
/// published algorithm is known to give, everything else against a twin that
/// differs in exactly one setting.
@Suite struct CompositionTests {

    // MARK: - Rhythm

    /// The worked example in the paper that named these: five over thirteen.
    @Test func fiveOverThirteenMatchesTheWorkedExample() {
        #expect(Rhythm(5, in: 13).description == "x..x.x..x.x..")
    }

    /// The two most traveled rhythms the algorithm gives, by name.
    @Test func theCubanPairComeOutRight() {
        #expect(Rhythm(3, in: 8).description == "x..x..x.")     // tresillo
        #expect(Rhythm(5, in: 8).description == "x.xx.xx.")     // cinquillo
        #expect(Rhythm.tresillo.intervals == [3, 3, 2])
        #expect(Rhythm.cinquillo.intervals == [2, 1, 2, 1, 2])
    }

    /// Nine over sixteen, the longest pattern the paper prints in full.
    @Test func nineOverSixteenMatchesThePublishedPattern() {
        #expect(Rhythm(9, in: 16).description == "x.xx.x.x.xx.x.x.")
        #expect(Rhythm(9, in: 16).intervals == [2, 1, 2, 2, 2, 1, 2, 2, 2])
    }

    /// Seven over twelve is the one the bell pattern is a rotation of, and the
    /// paper gives its gaps as well as its pattern, so both are checked.
    @Test func sevenOverTwelveMatchesBothFormsInThePaper() {
        #expect(Rhythm(7, in: 12).description == "x.xx.x.xx.x.")
        #expect(Rhythm(7, in: 12).intervals == [2, 1, 2, 2, 1, 2, 2])
    }

    /// Seven over sixteen is the one place the paper's two notations disagree:
    /// the gaps it prints, (3223222), are the ones the construction gives, and
    /// the pattern printed beside them is not a rotation of it. The gaps win,
    /// because they are what the construction produces step by step.
    @Test func sevenOverSixteenFollowsTheGapsThePaperPrints() {
        #expect(Rhythm(7, in: 16).intervals == [3, 2, 2, 3, 2, 2, 2])
    }

    /// When the counts divide, the answer is the obvious one.
    @Test func anEvenDivisionIsPerfectlyRegular() {
        #expect(Rhythm(4, in: 16).description == "x...x...x...x...")
        #expect(Rhythm(3, in: 12).intervals == [4, 4, 4])
    }

    /// The property that makes these rhythms what they are: the gaps between
    /// strikes take at most two lengths, and those differ by exactly one. A
    /// spacing that got this wrong would still look plausible written out.
    @Test func everyRhythmIsAsEvenAsWholeStepsAllow() {
        for steps in 2...32 {
            for pulses in 1..<steps {
                let rhythm = Rhythm(pulses, in: steps)
                let gaps = Set(rhythm.intervals)
                #expect(rhythm.onsetCount == pulses, "E(\(pulses),\(steps)) lost a strike")
                #expect(rhythm.length == steps)
                #expect(rhythm.intervals.reduce(0, +) == steps)
                #expect(gaps.count <= 2, "E(\(pulses),\(steps)) has gaps \(gaps.sorted())")
                if let low = gaps.min(), let high = gaps.max() {
                    #expect(high - low <= 1, "E(\(pulses),\(steps)) has gaps \(gaps.sorted())")
                }
            }
        }
    }

    /// Rotating keeps the gaps and only moves where they start, which is what
    /// lets the named rhythms be each other begun somewhere else.
    @Test func rotationKeepsTheGapsAndOnlyMovesTheStart() {
        let base = Rhythm(7, in: 16)
        for offset in 1..<16 {
            let turned = base.rotated(by: offset)
            #expect(turned.onsetCount == base.onsetCount)
            #expect(Set(turned.intervals) == Set(base.intervals))
            #expect(turned.intervals.reduce(0, +) == 16)
        }
        #expect(base.rotated(by: 16) == base)
        #expect(base.rotated(by: 5).rotated(by: -5) == base)
    }

    /// The bell pattern is seven over twelve begun at its third strike, and the
    /// paper prints the result, so the rotation can be checked rather than
    /// trusted.
    @Test func theBellPatternIsTheRotationThePaperNames() {
        #expect(Rhythm.bellPattern.description == "x.x.xx.x.x.x")
    }

    @Test func degenerateCountsDoTheObviousThing() {
        #expect(Rhythm(0, in: 8).onsets.isEmpty)
        #expect(Rhythm(8, in: 8).onsetCount == 8)
        #expect(Rhythm(12, in: 8).onsetCount == 8)
        #expect(Rhythm(-3, in: 8).onsets.isEmpty)
        #expect(Rhythm(3, in: 0).length == 0)
        #expect(Rhythm(3, in: 0)[5] == false)
        #expect(Rhythm(3, in: 0).intervals.isEmpty)
    }

    @Test func theCycleWrapsInBothDirections() {
        let rhythm = Rhythm(3, in: 8)
        #expect(rhythm[0] == rhythm[8])
        #expect(rhythm[0] == rhythm[-8])
        #expect(rhythm[-1] == rhythm[7])
        #expect(rhythm[100] == rhythm[100 % 8])
    }

    @Test func writtenOutAndReadBackAreTheSame() {
        let rhythm = Rhythm(5, in: 16)
        #expect(Rhythm(pattern: rhythm.description) == rhythm)
        #expect(Rhythm(pattern: "x..x..x.") == Rhythm.tresillo)
        #expect(Rhythm(pattern: "1--1--1-") == Rhythm.tresillo)
        #expect(Rhythm(pattern: "x..q") == nil)
        #expect(("x..x..x." as Rhythm) == Rhythm.tresillo)
        #expect(Rhythm(3, in: 8).inverted().description == ".xx.xx.x")
    }

    // MARK: - Scale

    @Test func degreesRunBothWaysAndPastTheEnds() {
        let scale = Scale(.major, root: "C4")
        #expect(scale[0].midi == 60)
        #expect(scale[7].midi == 72)      // an octave up, seven notes along
        #expect(scale[-7].midi == 48)
        #expect(scale[-1].midi == 59)     // the note below the root
        #expect(scale[4].midi == 67)      // the fifth

        let pentatonic = Scale(.minorPentatonic, root: "A3")
        #expect(pentatonic[5].midi == pentatonic[0].midi + 12)
        #expect(pentatonic[-5].midi == pentatonic[0].midi - 12)
    }

    /// The same call on two degrees of one scale gives two different chords.
    /// That is the whole point of building a chord out of a key: the quality is
    /// a consequence of where you started, not something chosen.
    @Test func aChordsQualityFallsOutOfWhereInTheScaleItStarts() {
        let major = Scale(.major, root: "C4")
        let onTheRoot = major.chord(on: 0).map { $0.midi - major[0].midi }
        let onTheSecond = major.chord(on: 1).map { $0.midi - major[1].midi }
        #expect(onTheRoot == [0, 4, 7])       // major
        #expect(onTheSecond == [0, 3, 7])     // minor, from the same call
        #expect(major.chord(on: 0, noteCount: 4).count == 4)
        #expect(major.chord(on: 0, noteCount: 4).map { $0.midi - 60 } == [0, 4, 7, 11])
    }

    /// Snapping moves a pitch onto the scale, and the twin that contains every
    /// pitch moves nothing.
    @Test func snappingMovesOnlyWhatIsOutOfKey() {
        let pentatonic = Scale(.minorPentatonic, root: "A3")   // A C D E G
        let chromatic = Scale(.chromatic, root: "A3")

        for midi in stride(from: 45.0, through: 81.0, by: 0.5) {
            let pitch = Pitch(midi)
            let snapped = pentatonic.snap(pitch)
            #expect(pentatonic.contains(snapped), "\(midi) snapped off the scale")
            #expect(abs(snapped.midi - midi) <= 1.5)
            #expect(chromatic.snap(pitch).midi == Pitch(midi.rounded()).midi || midi != midi.rounded())
        }
        // Something already in key must not move at all.
        for degree in -10...10 {
            #expect(pentatonic.snap(pentatonic[degree]).midi == pentatonic[degree].midi)
        }
    }

    @Test func aDegreeAndItsPitchAreTheSameFactRoundTripped() {
        for mode in Scale.Mode.allCases {
            let scale = Scale(mode, root: "D3")
            for degree in -8...8 {
                #expect(scale.degree(nearest: scale[degree]) == degree,
                        "\(mode) lost degree \(degree)")
            }
        }
    }

    @Test func everyNamedScaleIsAscendingAndInsideOneOctave() {
        for mode in Scale.Mode.allCases {
            let intervals = mode.intervals
            #expect(intervals.first == 0, "\(mode) does not start on its root")
            #expect(intervals == intervals.sorted(), "\(mode) is out of order")
            #expect(Set(intervals).count == intervals.count, "\(mode) repeats a note")
            #expect(intervals.allSatisfy { (0..<12).contains($0) }, "\(mode) leaves the octave")
        }
    }

    @Test func aCustomScaleIsTidiedUpRatherThanTakenLiterally() {
        #expect(Scale(intervals: [7, 0, 16, 4]).intervals == [0, 4, 7])
        #expect(Scale(intervals: []).intervals == [0])
        #expect(Scale(intervals: [-5]).intervals == [7])
    }

    // MARK: - Chord

    @Test func aChordIsItsRootAndTheShapeOnIt() {
        #expect(Chord("C4").pitches.map(\.midi) == [60, 64, 67])
        #expect(Chord("C4", .minorSeventh).pitches.map(\.midi) == [60, 63, 67, 70])
        #expect(Chord("C4").transposed(by: 2).pitches.map(\.midi) == [62, 66, 69])
    }

    /// Inverting keeps the notes and changes which one is lowest. The twin is
    /// the same chord uninverted.
    @Test func invertingKeepsTheNotesAndRaisesTheBass() {
        let plain = Chord("C4", .majorSeventh)
        let once = plain.inverted()

        #expect(once.pitches.count == plain.pitches.count)
        #expect(once.pitches[0].midi > plain.pitches[0].midi)
        let classes = { (chord: Chord) in Set(chord.pitches.map { Int($0.midi) % 12 }) }
        #expect(classes(once) == classes(plain))
        // All the way round is the same chord an octave up.
        let fullTurn = plain.inverted(plain.pitches.count)
        #expect(fullTurn.pitches.map(\.midi) == plain.pitches.map { $0.midi + 12 })
    }

    @Test func spreadingAChordWidensItWithoutAddingNotes() {
        let chord = Chord("C3", .minor)
        let spread = chord.spread(over: 3)
        #expect(spread.count == chord.pitches.count * 3)
        #expect(spread == spread.sorted())
        #expect(Set(spread.map { Int($0.midi) % 12 }) == Set(chord.pitches.map { Int($0.midi) % 12 }))
        #expect(chord.spread(over: 1) == chord.pitches)
    }

    // MARK: - Arpeggio

    @Test func upAndDownAreEachOthersReverse() {
        let notes: [Pitch] = [60, 64, 67]
        #expect(Arpeggio(notes, .up).order.map(\.midi) == [60, 64, 67])
        #expect(Arpeggio(notes, .down).order.map(\.midi) == [67, 64, 60])
    }

    /// The turnaround is the thing an arpeggiator gets wrong: playing the top
    /// note twice in a row reads as a stutter, not a turn.
    @Test func theTurnaroundDoesNotPlayEitherEndTwice() {
        let order = Arpeggio([60, 64, 67], .upDown).order.map(\.midi)
        #expect(order == [60, 64, 67, 64])

        // And it still holds where the figure wraps back to its own start.
        for count in 2...6 {
            let notes = (0..<count).map { Pitch(Double(60 + $0)) }
            for pattern in [Arpeggio.Pattern.upDown, .downUp] {
                let arp = Arpeggio(notes, pattern)
                for step in 0..<(arp.length * 3) {
                    #expect(arp[step].midi != arp[step + 1].midi,
                            "\(pattern) over \(count) notes repeats at step \(step)")
                }
            }
        }
    }

    @Test func octavesStackTheLadderRatherThanStretchIt() {
        let one = Arpeggio([60, 64, 67], .up)
        let two = Arpeggio([60, 64, 67], .up, octaves: 2)
        #expect(two.spreadPitches.count == one.spreadPitches.count * 2)
        #expect(two.spreadPitches.map(\.midi) == [60, 64, 67, 72, 76, 79])
        #expect(two.spreadPitches == two.spreadPitches.sorted())
    }

    /// `asPlayed` is the only pattern that keeps a hand made voicing. Its twin
    /// is the same notes read as a ladder.
    @Test func asPlayedKeepsAnOrderThatUpWouldSort() {
        let voicing: [Pitch] = [67, 60, 64]
        #expect(Arpeggio(voicing, .asPlayed).order.map(\.midi) == [67, 60, 64])
        #expect(Arpeggio(voicing, .up).order.map(\.midi) == [60, 64, 67])
    }

    @Test func convergeAndDivergeAreOneOrderReadBothWays() {
        let notes: [Pitch] = [60, 62, 64, 65]
        #expect(Arpeggio(notes, .converge).order.map(\.midi) == [60, 65, 62, 64])
        #expect(Arpeggio(notes, .diverge).order.map(\.midi) == [64, 62, 65, 60])
        #expect(Arpeggio([60, 62, 64], .converge).order.map(\.midi) == [60, 64, 62])
    }

    /// A random figure has to repeat exactly when asked twice, differ when the
    /// seed differs, and never leave the notes it was given.
    @Test func aRandomFigureIsSeededAndStaysInTheChord() {
        let notes: [Pitch] = [60, 63, 67, 70]
        let one = Arpeggio(notes, .random, octaves: 2, seed: 7)
        let same = Arpeggio(notes, .random, octaves: 2, seed: 7)
        let other = Arpeggio(notes, .random, octaves: 2, seed: 8)

        let first = (0..<64).map { one[$0].midi }
        #expect(first == (0..<64).map { same[$0].midi })
        #expect(first != (0..<64).map { other[$0].midi })
        #expect(first.allSatisfy { midi in one.spreadPitches.contains { $0.midi == midi } })
        // Over enough steps it should reach every note it was given.
        #expect(Set(first).count == one.spreadPitches.count)
    }

    @Test func theFigureWrapsForeverAndNeverRunsOut() {
        let arp = Arpeggio(Chord("C4", .minorSeventh), .upDown, octaves: 2)
        for step in 0..<200 {
            #expect(arp[step].midi == arp[step + arp.length].midi)
        }
        #expect(Arpeggio([], .up)[3].midi == 60)
    }

    // MARK: - MarkovChain

    @Test func aChainWithOneWayThroughRepeatsItExactly() {
        var chain = MarkovChain(learning: [0, 1, 2], seed: 1, loops: true)
        chain.start(at: 0)
        #expect(chain.next(9) == [1, 2, 0, 1, 2, 0, 1, 2, 0])
    }

    /// Looking back further is the whole reason `order` exists. This sequence
    /// is ambiguous at order 1 and completely determined at order 2, so the two
    /// chains are a counterfactual pair over identical training data.
    @Test func alongerMemoryResolvesWhatAShortOneCannot() {
        let source = ["a", "b", "a", "c"]

        var deep = MarkovChain(learning: source, order: 2, seed: 3, loops: true)
        deep.start(with: ["c", "a"])
        #expect(deep.next(8) == ["b", "a", "c", "a", "b", "a", "c", "a"])

        // At order 1, "a" is followed by "b" half the time and "c" the other
        // half, so the same walk cannot come out fixed.
        var shallow = MarkovChain(learning: source, order: 1, seed: 3, loops: true)
        shallow.start(at: "a")
        let afterA = shallow.next(200).enumerated().filter { $0.offset.isMultiple(of: 2) }.map(\.element)
        #expect(Set(afterA) == ["b", "c"])
    }

    @Test func theSameSeedWalksTheSameWayAndAnotherDoesNot() {
        let source = [0, 1, 0, 2, 0, 3, 1, 2, 3, 0, 2, 1]
        var one = MarkovChain(learning: source, seed: 11)
        var same = MarkovChain(learning: source, seed: 11)
        var other = MarkovChain(learning: source, seed: 12)
        one.start(at: 0); same.start(at: 0); other.start(at: 0)

        let walk = one.next(300)
        #expect(walk == same.next(300))
        #expect(walk != other.next(300))
        // Resetting rewinds the randomness as well as the position.
        one.reset()
        one.start(at: 0)
        #expect(one.next(300) == walk)
    }

    @Test func anUnseenContextFallsBackRatherThanStopping() {
        var chain = MarkovChain(learning: [1, 2, 3], order: 2, seed: 5)
        chain.start(with: [99, 98])          // never seen, at any length
        let next = chain.next()
        #expect(next != nil)
        #expect([1, 2, 3].contains(next!))

        var empty = MarkovChain<Int>(seed: 1)
        #expect(empty.next() == nil)
        #expect(empty.isEmpty)
    }

    /// The counts a chain learned are readable, which is what lets a sketch
    /// draw one. They come back most likely first.
    @Test func whatItLearnedCanBeReadBackAsProbabilities() {
        var chain = MarkovChain<String>(seed: 1)
        chain.learn(["x", "y", "x", "y", "x", "y", "x", "z"])

        let after = chain.continuations(after: ["x"])
        #expect(after.count == 2)
        #expect(after[0].element == "y")
        #expect(abs(after[0].probability - 0.75) < 1e-9)
        #expect(abs(after[1].probability - 0.25) < 1e-9)
        #expect(abs(after.reduce(0) { $0 + $1.probability } - 1) < 1e-9)
    }

    /// Nothing a chain decides may depend on the order a dictionary happens to
    /// hand its keys back, so the vocabulary is kept in the order it was first
    /// seen and every choice is made over an array.
    @Test func theVocabularyIsInTheOrderItWasFirstSeen() {
        var chain = MarkovChain<String>(seed: 1)
        chain.learn(["c", "a", "b", "a", "c"])
        #expect(chain.vocabulary == ["c", "a", "b"])
    }

    @Test func learningTheSamePhraseTwiceMakesItTwiceAsLikely() {
        var chain = MarkovChain<Int>(seed: 1)
        chain.learn([0, 1])
        chain.learn([0, 1])
        chain.learn([0, 2])
        let after = chain.continuations(after: [0])
        #expect(after[0].element == 1)
        #expect(abs(after[0].probability - 2.0 / 3.0) < 1e-9)
    }

    // MARK: - StepCounter

    @Test func theFirstCallStartsOnTheDownbeat() {
        var counter = StepCounter(perBeat: 4)
        #expect(Array(counter.steps(upTo: 0)) == [0])
        #expect(Array(counter.steps(upTo: 0)).isEmpty)
        #expect(Array(counter.steps(upTo: 0.2)).isEmpty)
        #expect(Array(counter.steps(upTo: 0.25)) == [1])
    }

    /// Every step is reported once, in order, whatever size the frames are.
    /// The two counters are a twin pair: same music, different frame rate.
    @Test func noStepIsEverSkippedOrPlayedTwice() {
        for frame in [1.0 / 240, 1.0 / 60, 1.0 / 12, 0.31] {
            var counter = StepCounter(perBeat: 4, maxCatchUp: 64)
            var seen = [Int]()
            var beats = 0.0
            while true {
                // The last call lands on the same position whatever the frame
                // size, so all four runs have heard exactly the same music.
                seen += counter.steps(upTo: min(beats, 8))
                if beats >= 8 { break }
                beats += frame
            }
            #expect(seen == Array(0...32), "frame \(frame) reported \(seen)")
        }
    }

    /// A long stall is time jumping, not music passing, so it lands rather than
    /// emptying the whole pattern into one frame. The twin allows the catch up.
    @Test func aStallLandsWhereItStoppedRatherThanFiringEverything() {
        var strict = StepCounter(perBeat: 4, maxCatchUp: 8)
        _ = strict.steps(upTo: 0)
        #expect(Array(strict.steps(upTo: 10)) == [40])

        var patient = StepCounter(perBeat: 4, maxCatchUp: 64)
        _ = patient.steps(upTo: 0)
        #expect(Array(patient.steps(upTo: 10)) == Array(1...40))
    }

    @Test func aLoopComingRoundStillPlaysItsDownbeat() {
        var counter = StepCounter(perBeat: 4)
        _ = counter.steps(upTo: 4)
        #expect(Array(counter.steps(upTo: 0)) == [0])
        #expect(Array(counter.steps(upTo: 0)).isEmpty)
    }

    @Test func resettingSkipsSilentlyToAPosition() {
        var counter = StepCounter(perBeat: 4)
        _ = counter.steps(upTo: 0)
        counter.reset(to: 4)
        #expect(Array(counter.steps(upTo: 4)).isEmpty)
        #expect(Array(counter.steps(upTo: 4.25)) == [17])
    }

    @Test func timeBeforeTheStartIsTreatedAsTheStart() {
        var counter = StepCounter(perBeat: 4)
        #expect(Array(counter.steps(upTo: -5)) == [0])
    }

    // MARK: - Note

    @Test func aNoteReadsItsLengthInBeatsAtATempo() {
        let note = Note(60, velocity: 0.5, length: 0.5)
        #expect(abs(note.seconds(at: 120) - 0.25) < 1e-12)
        #expect(abs(note.seconds(at: 60) - 0.5) < 1e-12)
        #expect(note.transposed(by: 12).pitch.midi == 72)
        #expect(note.transposed(by: 12).velocity == 0.5)
    }
}
