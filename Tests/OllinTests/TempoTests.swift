import Foundation
import Testing
@testable import Ollin

/// Pure checks on `Tempo` and `NoteLength`, the two values that turn the
/// sketch's seconds into beats and a note's length back into seconds. Every
/// conversion is checked against the arithmetic the sketches wrote by hand
/// before the types existed, so a sketch that adopts them plays the same.
struct TempoTests {

    // MARK: - Tempo

    @Test func secondsAndBeatsReadOffTheMetronomeNumber() {
        let tempo = Tempo(120)
        #expect(tempo.beatsPerMinute == 120)
        #expect(tempo.beatsPerBar == 4)
        #expect(tempo.secondsPerBeat == 0.5)
        #expect(tempo.secondsPerBar == 2)
        #expect(tempo.beats(at: 3) == 6)
        #expect(tempo.bars(at: 3) == 1.5)
        #expect(tempo.seconds(beats: 3) == 1.5)
        #expect(tempo.seconds(bars: 8) == 16)
    }

    @Test func beatsPerBarChangesTheBarAndNothingElse() {
        let waltz = Tempo(90, beatsPerBar: 3)
        #expect(waltz.secondsPerBeat == Tempo(90).secondsPerBeat)
        #expect(waltz.secondsPerBar == 2)
        #expect(waltz.seconds(bars: 4) == 8)
        #expect(waltz.bars(at: 2) == 1)
        #expect(waltz.beats(at: 2) == Tempo(90).beats(at: 2))
    }

    /// The examples wrote `time * tempo / 60` and `beats * 60 / tempo` by hand.
    /// The type keeps that order of operations, so a sketch that switches to
    /// it lands on the same step in the same frame and plays the same length.
    @Test func conversionsMatchTheHandWrittenArithmeticBitForBit() {
        for bpm in stride(from: 40.0, through: 200, by: 7.5) {
            let tempo = Tempo(bpm)
            for seconds in stride(from: 0.0, through: 600, by: 0.7) {
                #expect(tempo.beats(at: seconds) == seconds * bpm / 60)
            }
            for beats in stride(from: 0.0, through: 16, by: 0.3) {
                #expect(tempo.seconds(beats: beats) == beats * 60 / bpm)
            }
        }
    }

    @Test func aStoppedTempoNeverDividesByZero() {
        let stopped = Tempo(0)
        #expect(stopped.beats(at: 10) == 0)
        #expect(stopped.secondsPerBeat.isFinite)
        #expect(stopped.seconds(of: .quarter).isFinite)
        #expect(Tempo(120, beatsPerBar: 0).bars(at: 1).isFinite)
    }

    @Test func aNumberStandsInForATempo() {
        let whole: Tempo = 120
        let fractional: Tempo = 118.5
        #expect(whole == Tempo(120))
        #expect(fractional.beatsPerMinute == 118.5)
        #expect(whole.description == "120 bpm")
        #expect(fractional.description == "118.5 bpm")
    }

    // MARK: - NoteLength

    @Test func theStaveNamesAreCountsOfBeats() {
        #expect(NoteLength.whole.beats == 4)
        #expect(NoteLength.half.beats == 2)
        #expect(NoteLength.quarter.beats == 1)
        #expect(NoteLength.eighth.beats == 0.5)
        #expect(NoteLength.sixteenth.beats == 0.25)
        #expect(NoteLength.thirtySecond.beats == 0.125)
        #expect(NoteLength.whole > NoteLength.half)
        #expect(NoteLength.sixteenth < NoteLength.eighth)
    }

    @Test func dottedAndTripletDeriveTheRest() {
        #expect(NoteLength.quarter.dotted.beats == 1.5)
        #expect(NoteLength.half.dotted.beats == 3)
        #expect(abs(NoteLength.eighth.triplet.beats - 1.0 / 3) < 1e-12)
        // Three triplets fill the time of two of the plain length.
        #expect(abs((NoteLength.eighth.triplet * 3).beats - (NoteLength.eighth * 2).beats) < 1e-12)
        #expect((NoteLength.quarter + .eighth).beats == 1.5)
        #expect(NoteLength.quarter + .eighth == NoteLength.quarter.dotted)
    }

    @Test func aLengthReadsAsItsNameWhenItHasOne() {
        #expect(NoteLength.quarter.description == "quarter")
        #expect(NoteLength.thirtySecond.description == "thirty-second")
        #expect(NoteLength.eighth.dotted.description == "dotted eighth")
        #expect(NoteLength.quarter.triplet.description == "quarter triplet")
        #expect(NoteLength(beats: 1.1).description == "1.1 beats")
        #expect(NoteLength(beats: 3).description == "dotted half")
        let plain: NoteLength = 2
        #expect(plain == .half)
        let fraction: NoteLength = 0.25
        #expect(fraction == .sixteenth)
    }

    @Test func aLengthAndATempoMeetFromEitherSide() {
        let tempo = Tempo(96)
        #expect(tempo.seconds(of: .quarter) == 0.625)
        #expect(tempo.seconds(of: .whole) == 2.5)
        #expect(NoteLength.eighth.seconds(at: tempo) == tempo.seconds(of: .eighth))
        #expect(tempo.seconds(of: .quarter.dotted) == 0.9375)
    }

    // MARK: - As parameters

    @Test func aTempoParameterIsASliderInBeatsPerMinute() {
        let p = Param(wrappedValue: Tempo(104, beatsPerBar: 3), 60...160)
        guard case .slider(let control) = p.control else {
            Issue.record("a Tempo parameter should present as a slider")
            return
        }
        #expect(control.range == 60...160)
        #expect(control.read() == 104)

        // A move through the slider, a clamp, and a binding all keep the bar.
        control.write(130)
        #expect(p.wrappedValue == Tempo(130, beatsPerBar: 3))
        p.wrappedValue = Tempo(999, beatsPerBar: 3)
        #expect(p.wrappedValue == Tempo(160, beatsPerBar: 3))
        #expect(p.range == 60...160)
    }

    /// The payload is a plain number, the same one a `Double` parameter
    /// persists, so every host surface reads it as a number; the beats per bar
    /// come back from the value the parameter already holds.
    @Test func aTempoPersistsAsANumberAndKeepsItsBarOnRestore() {
        let p = Param(wrappedValue: Tempo(104, beatsPerBar: 3), 60...160)
        #expect(p.stored == .number(104))
        p.restore(.number(88))
        #expect(p.wrappedValue == Tempo(88, beatsPerBar: 3))
        p.restore(.boolean(true))                      // the wrong kind is ignored
        #expect(p.wrappedValue == Tempo(88, beatsPerBar: 3))
        #expect(Tempo.restored(.number(72)) == Tempo(72))
    }

    @Test func aNoteLengthParameterIsAMenuOfTheNamedLengths() {
        let p = Param(wrappedValue: NoteLength.eighth)
        guard case .menu(let control) = p.control else {
            Issue.record("a NoteLength parameter should present as a menu")
            return
        }
        #expect(control.options.contains("Dotted Quarter"))
        #expect(p.stored == .option("eighth"))
        p.restore(.option("dottedQuarter"))
        #expect(p.wrappedValue == NoteLength.quarter.dotted)
        // A length off the menu reads as the first entry, the ParamChoices rule.
        p.wrappedValue = NoteLength(beats: 1.1)
        #expect(control.read() == 0)
    }
}
