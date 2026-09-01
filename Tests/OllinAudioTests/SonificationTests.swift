import Foundation
import Testing
@testable import Ollin
@testable import OllinAudio

/// Reading numbers out as notes. There is no randomness anywhere in here, so
/// every check is an exact value or a twin differing in one setting.
@Suite struct SonificationTests {

    // MARK: - How the mapping is made

    /// The headline decision, and the one that is wrong if you write the
    /// obvious thing. Hearing is logarithmic, so a series is spread evenly in
    /// semitones. Spread evenly in hertz instead, the middle of the data would
    /// land far higher than the middle of the range.
    @Test func pitchIsSpreadEvenlyInSemitonesNotInHertz() {
        let reading = Sonification([0, 0.5, 1], pitches: "C3"..."C6")
        let low = reading.pitch(for: 0), middle = reading.pitch(for: 0.5)
        let high = reading.pitch(for: 1)

        #expect(low == Pitch("C3"))
        #expect(high == Pitch("C6"))
        // Halfway through the data is halfway through the range in semitones.
        #expect(abs(middle.midi - low.midi) == abs(high.midi - middle.midi))
        #expect(abs(middle.midi - (low.midi + high.midi) / 2) < 1e-9)

        // Spread evenly in hertz, the middle value would land here instead,
        // most of an octave higher. This is what the test is ruling out.
        let byFrequency = Pitch(69 + 12 * log2(
            (low.frequency + high.frequency) / 2 / 440))
        #expect(byFrequency.midi - middle.midi > 8,
                "the two mappings must be far apart or this proves nothing")
    }

    /// Loudness is spread in decibels for the same reason, so the quietest
    /// note is a real fraction of full rather than silence.
    @Test func loudnessIsSpreadInDecibels() {
        let reading = Sonification([0, 1]).amplified(by: [0, 1], levels: -18...0)
        // 0 dB is full level; 18 dB down is a tenth of the power, which is
        // this fraction of the amplitude.
        #expect(abs(reading.velocity(at: 1) - 1) < 1e-9)
        #expect(abs(reading.velocity(at: 0) - pow(10, -18.0 / 20)) < 1e-9)
        #expect(reading.velocity(at: 0) > 0.12 && reading.velocity(at: 0) < 0.13)
    }

    /// Loudness stays out of the way unless it is asked for, because how loud
    /// something sounds depends on how high it is as well as how strong.
    @Test func nothingIsReadOutAsLoudnessUnlessAskedFor() {
        let reading = Sonification([0, 0.3, 1])
        #expect(reading.loudness == nil)
        for step in 0 ..< reading.count {
            #expect(reading.velocity(at: step) == 1)
        }
    }

    /// The twin for the whole point of snapping: the same numbers with and
    /// without a scale.
    @Test func aScaleKeepsTheReadingInKey() {
        let numbers = (0 ..< 40).map { Double($0) * 0.025 }
        let scale = Scale(.minorPentatonic, root: "A3")
        let inKey = Sonification(numbers, in: scale, pitches: "A3"..."A6")
        let chromatic = Sonification(numbers, pitches: "A3"..."A6")

        // Every note of the snapped reading belongs to the scale.
        for step in 0 ..< inKey.count {
            let pitch = inKey[step]!.pitch
            let offset = ((pitch.midi - scale.root.midi).rounded()
                .truncatingRemainder(dividingBy: 12) + 12)
                .truncatingRemainder(dividingBy: 12)
            #expect(scale.intervals.contains(Int(offset)),
                    "step \(step) landed on \(pitch) which is out of key")
        }
        // And the unsnapped one genuinely does leave the scale, so the check
        // above is not passing by accident.
        let strays = (0 ..< chromatic.count).filter { step in
            let pitch = chromatic[step]!.pitch
            let offset = ((pitch.midi - scale.root.midi).rounded()
                .truncatingRemainder(dividingBy: 12) + 12)
                .truncatingRemainder(dividingBy: 12)
            return !scale.intervals.contains(Int(offset))
        }
        #expect(!strays.isEmpty)
    }

    /// Snapping must not destroy the shape: a rising series still rises.
    @Test func snappingKeepsTheShapeOfTheData() {
        let numbers = (0 ..< 24).map { Double($0) }
        let reading = Sonification(numbers, in: Scale(.major, root: "C3"),
                                   pitches: "C3"..."C6")
        var previous = -Double.infinity
        for step in 0 ..< reading.count {
            let midi = reading[step]!.pitch.midi
            #expect(midi >= previous, "step \(step) went down")
            previous = midi
        }
        #expect(reading[reading.count - 1]!.pitch.midi
                > reading[0]!.pitch.midi + 24)
    }

    // MARK: - Which way round

    @Test func polarityTurnsTheReadingOver() {
        let up = Sonification([0, 1], pitches: "C3"..."C6")
        let down = up.inverted()
        #expect(up.pitch(for: 0) == down.pitch(for: 1))
        #expect(up.pitch(for: 1) == down.pitch(for: 0))
        #expect(down.pitch(for: 0).midi > down.pitch(for: 1).midi)
    }

    // MARK: - Where the ends go

    /// One wild reading should not flatten everything else into a single note.
    /// The twin is the same data read by its extremes.
    @Test func robustBoundsSurviveAnOutlier() {
        var numbers = (0 ..< 100).map { Double($0) / 99 }
        numbers.append(1000)                       // one bad sensor reading

        let byExtremes = Sonification(numbers, pitches: "C3"..."C6")
        let robust = Sonification(numbers, pitches: "C3"..."C6",
                                  bounds: .robust(ignoring: 0.05))

        // Read by its extremes, the real data is squashed into almost nothing.
        let squashedSpan = byExtremes.pitch(for: 1).midi - byExtremes.pitch(for: 0).midi
        let robustSpan = robust.pitch(for: 1).midi - robust.pitch(for: 0).midi
        #expect(squashedSpan < 1, "the counterfactual should be squashed, got \(squashedSpan)")
        #expect(robustSpan > 30, "the robust reading should use the range, got \(robustSpan)")
    }

    @Test func afixedDomainMakesTwoReadingsComparable() {
        let quiet = Sonification([0.1, 0.2], pitches: "C3"..."C6",
                                 bounds: .fixed(0...1))
        let loud = Sonification([0.8, 0.9], pitches: "C3"..."C6",
                                bounds: .fixed(0...1))
        // The same value reads as the same note in both, which is what a shared
        // domain is for. Read by their own extremes they would not.
        #expect(quiet.pitch(for: 0.5) == loud.pitch(for: 0.5))
        #expect(loud.pitch(for: 0.85).midi > quiet.pitch(for: 0.15).midi)
    }

    /// Values outside the domain are held at the ends rather than running off
    /// into an inaudible pitch.
    @Test func valuesOutsideTheRangeAreHeldAtTheEnds() {
        let reading = Sonification([0, 1], pitches: "C3"..."C6", bounds: .fixed(0...1))
        #expect(reading.pitch(for: -50) == Pitch("C3"))
        #expect(reading.pitch(for: 50) == Pitch("C6"))
    }

    /// A series that never changes has no range to spread over, so it reads in
    /// the middle rather than dividing by zero.
    @Test func aflatSeriesReadsInTheMiddle() {
        let reading = Sonification([5, 5, 5, 5], pitches: "C3"..."C6")
        let expected = (Pitch("C3").midi + Pitch("C6").midi) / 2
        for step in 0 ..< reading.count {
            #expect(abs(reading[step]!.pitch.midi - expected) < 1e-9)
        }
    }

    @Test func anEmptyReadingPlaysNothing() {
        let reading = Sonification([])
        #expect(reading.isEmpty)
        #expect(reading.count == 0)
        #expect(reading[0] == nil)
        #expect(reading.notes().isEmpty)
    }

    @Test func thereIsNoNotePastTheEnd() {
        let reading = Sonification([1, 2, 3])
        #expect(reading[2] != nil)
        #expect(reading[3] == nil)
        #expect(reading[-1] == nil)
        #expect(reading.notes().count == 3)
    }

    // MARK: - The reference tone

    /// A reference sounds a named value on exactly the same footing as the
    /// reading, which is what lets a listener hear a note as above or below
    /// something rather than having to know what it means.
    @Test func aReferenceLandsWhereThatValueWouldInTheReading() {
        let reading = Sonification([0, 10, 20, 30], pitches: "C3"..."C6")
        let halfway = reading.reference(at: 15)
        #expect(halfway.pitch == reading.pitch(for: 15))
        // And it sits between the notes for the values either side of it.
        #expect(halfway.pitch.midi > reading[1]!.pitch.midi)
        #expect(halfway.pitch.midi < reading[2]!.pitch.midi)
    }

    // MARK: - What it reads from

    @Test func aTableColumnIsReadInRowOrder() throws {
        let csv = "city,temp\nOaxaca,31\nPuebla,22\nToluca,17\n"
        let table = try #require(Table(text: csv))
        let reading = Sonification(table, column: "temp", pitches: "C3"..."C6")
        #expect(reading.count == 3)
        #expect(reading.values == [31, 22, 17])
        // Warmest is highest, since more is higher by default.
        #expect(reading[0]!.pitch == Pitch("C6"))
        #expect(reading[2]!.pitch == Pitch("C3"))
    }

    @Test func aterrainRowIsReadLeftToRight() {
        // A ramp across, flat down, so a row is 0 ... 1 and a column is flat.
        let field = Heightfield(columns: 8, rows: 4) { u, _ in u }
        let across = Sonification(field, row: 2, pitches: "C3"..."C6")
        #expect(across.count == 8)
        #expect(across[0]!.pitch == Pitch("C3"))
        #expect(across[7]!.pitch == Pitch("C6"))

        let down = Sonification(field, column: 3, pitches: "C3"..."C6")
        #expect(down.count == 4)
        // Flat down the column, so every note is the same.
        #expect(Set(down.notes().map(\.pitch)).count == 1)
    }

    @Test func alineAcrossATerrainCanRunAtAnyAngle() {
        let field = Heightfield(columns: 16, rows: 16) { u, v in (u + v) / 2 }
        let diagonal = Sonification(field, from: Vector2(0, 0), to: Vector2(1, 1),
                                    count: 9, pitches: "C3"..."C6")
        #expect(diagonal.count == 9)
        // Climbing the whole way, since both coordinates rise together.
        for step in 1 ..< diagonal.count {
            #expect(diagonal[step]!.pitch.midi >= diagonal[step - 1]!.pitch.midi)
        }
        #expect(diagonal[0]!.pitch == Pitch("C3"))
        #expect(diagonal[8]!.pitch == Pitch("C6"))
    }

    @Test func apictureRowIsReadAsBrightness() {
        var image = Image(width: 4, height: 2, color: .black)
        image[0, 0] = .black
        image[1, 0] = Color(white: 0.25)
        image[2, 0] = Color(white: 0.5)
        image[3, 0] = .white
        let reading = Sonification(image, row: 0, pitches: "C3"..."C6")
        #expect(reading.count == 4)
        #expect(reading[0]!.pitch == Pitch("C3"))
        #expect(reading[3]!.pitch == Pitch("C6"))
        // Brightness rises the whole way across.
        for step in 1 ..< reading.count {
            #expect(reading[step]!.pitch.midi > reading[step - 1]!.pitch.midi)
        }
    }

    /// Brightness is weighed the way the eye weighs it, so two colors of the
    /// same numeric size do not read as the same note.
    @Test func brightnessIsWeighedTheWayTheEyeWeighsIt() {
        var image = Image(width: 2, height: 1, color: .black)
        image[0, 0] = Color(red: 0, green: 1, blue: 0)
        image[1, 0] = Color(red: 0, green: 0, blue: 1)
        let reading = Sonification(image, row: 0, pitches: "C3"..."C6")
        // Green is far brighter than blue, so it rings higher.
        #expect(reading[0]!.pitch.midi > reading[1]!.pitch.midi)
    }

    // MARK: - The tier's own rules

    /// Length is in beats, because nothing in this tier knows how fast the
    /// music is going.
    @Test func lengthIsInBeatsAndTheTempoJoinsLater() {
        let reading = Sonification([1, 2], noteLength: 0.5)
        let note = reading[0]!
        #expect(note.length == 0.5)
        #expect(abs(note.seconds(at: 120) - 0.25) < 1e-9)
        #expect(abs(note.seconds(at: 60) - 0.5) < 1e-9)
    }

    /// Nothing here rolls anything, so the same numbers read the same way
    /// every time and an export can be repeated.
    @Test func thesameNumbersReadTheSameWayEveryTime() {
        let numbers = (0 ..< 50).map { sin(Double($0) * 0.3) }
        let once = Sonification(numbers, in: Scale(.dorian, root: "D3"))
        let again = Sonification(numbers, in: Scale(.dorian, root: "D3"))
        #expect(once == again)
        #expect(once.notes() == again.notes())
    }
}
