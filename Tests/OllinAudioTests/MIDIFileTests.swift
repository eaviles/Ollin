import AVFoundation
import Foundation
import Ollin
import Testing
@testable import OllinAudio

/// Standard MIDI Files, read and written.
///
/// The invariants that matter are the ones a file has to keep to be worth anything:
/// what goes out comes back the same, a file written by hand somewhere else
/// says what its bytes say, and a file that is not one is refused rather than
/// half read.
@Suite
struct MIDIFileTests {

    /// A phrase to write out: three notes, one of them quiet and short.
    private var phrase: [ScheduledNote] {
        [
            ScheduledNote(Note("C4", velocity: 0.8, length: .quarter), beat: 0, step: 0),
            ScheduledNote(Note("E4", velocity: 1.0, length: .eighth), beat: 1, step: 1),
            ScheduledNote(Note("G4", velocity: 0.2, length: .half), beat: 1.5, step: 2),
        ]
    }

    // MARK: What goes out comes back

    @Test func aWrittenFileReadsBackTheSameNotes() throws {
        let written = MIDIFile(phrase, tempo: 112, name: "Phrase")
        let read = try MIDIFile(data: written.data())

        #expect(read.format == .parallelTracks)
        #expect(read.name == "Phrase")
        // The file holds a tempo as whole microseconds in a quarter note, so
        // one that does not divide comes back a fraction off.
        #expect(abs(read.tempo.beatsPerMinute - 112) < 1e-3)
        #expect(read.tracks.count == 1, "one part went in, so one part comes back")

        let notes = read.notes
        #expect(notes.count == phrase.count)
        for (original, returned) in zip(phrase, notes) {
            #expect(returned.pitch.midi == original.pitch.midi)
            #expect(abs(returned.beat - original.beat) < 1e-6, "a beat on the tick grid is exact")
            #expect(abs(returned.length.beats - original.length.beats) < 1e-6)
            // Loudness is a seventh of a percent apart at worst: the file
            // carries it in 127 steps.
            #expect(abs(returned.velocity - original.velocity) <= 1.0 / 127)
        }
    }

    @Test func theSwungAndTripletBeatsSurviveTheTickGrid() throws {
        // 960 ticks in a quarter note divides by three, which is what keeps a
        // triplet and a swung offbeat exactly where they were put.
        let third = 1.0 / 3
        let beats: [Double] = [0, third, 0.5, 2 * third, 2 * third + 1]
        let notes = beats.enumerated().map {
            ScheduledNote(Note(60, length: NoteLength(beats: third)), beat: $1, step: $0)
        }
        let read = try MIDIFile(data: MIDIFile(notes).data())
        for (original, returned) in zip(notes, read.notes) {
            #expect(abs(returned.beat - original.beat) < 1e-9)
            #expect(abs(returned.length.beats - original.length.beats) < 1e-9)
        }
    }

    @Test func partsOnOneTrackComeBackAsTheirOwnParts() throws {
        // Format 0 is the common single-file shape, and everything in it is on
        // one chunk. The channel is what says which instrument a note belongs
        // to, so that is what the parts come back split by.
        var file = MIDIFile(format: .oneTrack, name: "Both", tracks: [
            MIDIFile.Track(phrase, name: "Keys", channel: 1),
            MIDIFile.Track([ScheduledNote(Note(36, length: .quarter), beat: 0, step: 0)],
                           name: "Drums", channel: 10),
        ])
        file.tempoChanges = [MIDIFile.TempoChange(beat: 0, tempo: 120)]

        let read = try MIDIFile(data: file.data())
        #expect(read.format == .oneTrack)
        #expect(read.tracks.count == 2)
        #expect(read.tracks.map(\.channel) == [1, 10])
        #expect(read.tracks[0].notes.count == 3)
        #expect(read.tracks[1].notes.count == 1)
        #expect(read.tracks[1].notes[0].pitch.midi == 36)
    }

    @Test func whatElseHappenedComesBackToo() throws {
        var file = MIDIFile(phrase, tempo: 120, name: "Moved")
        file.tracks[0].program = 42
        file.tracks[0].controls = [
            MIDIFile.ControlChange(beat: 0, controller: 1, value: 0),
            MIDIFile.ControlChange(beat: 2, controller: 1, value: 1),
        ]
        file.tracks[0].bends = [
            MIDIFile.PitchBend(beat: 0, position: 0),
            MIDIFile.PitchBend(beat: 1, position: 1),
            MIDIFile.PitchBend(beat: 2, position: -1),
        ]
        file.markers = [MIDIFile.Marker(beat: 2, text: "the turn")]

        let read = try MIDIFile(data: file.data())
        #expect(read.tracks[0].program == 42)
        #expect(read.tracks[0].controls.map(\.controller) == [1, 1])
        #expect(read.tracks[0].controls.map(\.value) == [0, 1])
        #expect(read.tracks[0].bends.map(\.beat) == [0, 1, 2])
        for (original, returned) in zip(file.tracks[0].bends, read.tracks[0].bends) {
            #expect(abs(returned.position - original.position) < 1e-3)
        }
        #expect(read.markers.map(\.text) == ["the turn"])
        #expect(read.markers[0].beat == 2)
    }

    @Test func aFileTimedToPictureKeepsItsClock() throws {
        var file = MIDIFile(phrase, tempo: 120, name: "Cut")
        file.division = .perSecond(framesPerSecond: 30, ticksPerFrame: 80)

        let read = try MIDIFile(data: file.data())
        #expect(read.division == .perSecond(framesPerSecond: 30, ticksPerFrame: 80))
        for (original, returned) in zip(phrase, read.notes) {
            #expect(abs(returned.beat - original.beat) < 1e-6)
            #expect(abs(returned.length.beats - original.length.beats) < 1e-6)
        }
    }

    @Test func aFileOnDiskComesBackFromDisk() throws {
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-midi-\(UUID().uuidString).mid").path
        defer { try? FileManager.default.removeItem(atPath: path) }

        try MIDIFile(phrase, tempo: 96, name: "Saved").write(to: path)
        let read = try MIDIFile(contentsOf: path)
        #expect(read.name == "Saved")
        #expect(read.notes.count == 3)
        #expect(read.tempo.beatsPerMinute == 96)
    }

    // MARK: A file written somewhere else

    /// A format 1 file written out by hand from the specification: a tempo
    /// track carrying 4/4 at 120 beats a minute, then two quarter notes at 96
    /// ticks to the quarter.
    private var handWritten: Data {
        var bytes: [UInt8] = []
        bytes += Array("MThd".utf8)
        bytes += [0, 0, 0, 6, 0, 1, 0, 2, 0, 96]
        bytes += Array("MTrk".utf8)
        bytes += [0, 0, 0, 19]
        bytes += [0x00, 0xFF, 0x58, 0x04, 0x04, 0x02, 0x18, 0x08]   // 4/4
        bytes += [0x00, 0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20]         // 500000us a quarter
        bytes += [0x00, 0xFF, 0x2F, 0x00]
        bytes += Array("MTrk".utf8)
        bytes += [0, 0, 0, 20]
        bytes += [0x00, 0x90, 0x3C, 0x40]   // C4 on, struck at 64
        bytes += [0x60, 0x80, 0x3C, 0x40]   // and off a beat later
        bytes += [0x00, 0x90, 0x40, 0x40]   // E4 on
        bytes += [0x60, 0x80, 0x40, 0x40]   // and off a beat later
        bytes += [0x00, 0xFF, 0x2F, 0x00]
        return Data(bytes)
    }

    @Test func aFileWrittenByHandSaysWhatItsBytesSay() throws {
        let file = try MIDIFile(data: handWritten)

        #expect(file.format == .parallelTracks)
        #expect(file.division == .perQuarter(96))
        #expect(file.tempo.beatsPerMinute == 120, "500,000 microseconds a quarter note is 120 a minute")
        #expect(file.timeSignature(at: 0).description == "4/4")
        #expect(file.tracks.count == 1, "the timing track carries no part")

        let notes = file.notes
        #expect(notes.count == 2)
        #expect(notes.map(\.pitch.midi) == [60, 64])
        #expect(notes.map(\.beat) == [0, 1])
        #expect(notes.map(\.length.beats) == [1, 1])
        #expect(abs(notes[0].velocity - 64.0 / 127) < 1e-9)
        #expect(file.lastBeat == 2)
        #expect(abs(file.duration - 1) < 1e-9, "two beats at 120 a minute is a second")
    }

    /// A track chunk around a run of event bytes, at 96 ticks to the quarter.
    private func oneTrackFile(_ events: [UInt8]) -> Data {
        var bytes: [UInt8] = []
        bytes += Array("MThd".utf8) + [0, 0, 0, 6, 0, 0, 0, 1, 0, 96]
        bytes += Array("MTrk".utf8) + [0, 0, 0, UInt8(events.count)] + events
        return Data(bytes)
    }

    @Test func aRunOfMessagesMayLeaveOutTheKindItRepeats() throws {
        // Running status: a message with no kind of its own takes the kind of
        // the one before it. Both notes are let go at a release of 64 rather
        // than 0, so a run read as the wrong kind cannot come out right by
        // being a note-off in the other spelling.
        let spelled = oneTrackFile([
            0x00, 0x90, 0x3C, 0x40,
            0x00, 0x90, 0x40, 0x40,
            0x60, 0x80, 0x3C, 0x40,
            0x00, 0x80, 0x40, 0x40,
            0x00, 0xFF, 0x2F, 0x00,
        ])
        let running = oneTrackFile([
            0x00, 0x90, 0x3C, 0x40,
            0x00, 0x40, 0x40,         // the kind is the one before it
            0x60, 0x80, 0x3C, 0x40,
            0x00, 0x40, 0x40,         // and again, now a note let go
            0x00, 0xFF, 0x2F, 0x00,
        ])

        let plain = try MIDIFile(data: spelled)
        let terse = try MIDIFile(data: running)
        #expect(plain.notes.count == 2)
        #expect(terse.notes.count == plain.notes.count)
        #expect(terse.notes.map(\.pitch.midi) == plain.notes.map(\.pitch.midi))
        #expect(terse.notes.map(\.beat) == plain.notes.map(\.beat))
        #expect(terse.notes.map(\.length.beats) == plain.notes.map(\.length.beats))
        #expect(terse.notes.map(\.length.beats) == [1, 1])
    }

    @Test func aNoteStruckWithNoLoudnessIsANoteLetGo() throws {
        let file = try MIDIFile(data: oneTrackFile([
            0x00, 0x90, 0x3C, 0x40,
            0x60, 0x90, 0x3C, 0x00,   // the format's other spelling of a release
            0x00, 0xFF, 0x2F, 0x00,
        ]))
        #expect(file.notes.count == 1)
        #expect(file.notes[0].length.beats == 1)
    }

    @Test func oneNoteStruckTwiceIsLetGoInTheOrderItWasStruck() throws {
        var bytes: [UInt8] = []
        bytes += Array("MThd".utf8) + [0, 0, 0, 6, 0, 0, 0, 1, 0, 96]
        let events: [UInt8] = [
            0x00, 0x90, 0x3C, 0x40,   // struck
            0x60, 0x90, 0x3C, 0x50,   // struck again a beat later, the first still held
            0x60, 0x80, 0x3C, 0x00,   // one let go
            0x60, 0x80, 0x3C, 0x00,   // the other let go
            0x00, 0xFF, 0x2F, 0x00,
        ]
        bytes += Array("MTrk".utf8) + [0, 0, 0, UInt8(events.count)] + events

        let notes = try MIDIFile(data: Data(bytes)).notes
        #expect(notes.count == 2)
        // The one that had been sounding longest is the one let go first, so
        // the first note is two beats long and the second is two as well.
        #expect(notes.map(\.beat) == [0, 1])
        #expect(notes.map(\.length.beats) == [2, 2])
    }

    @Test func aNoteNeverLetGoEndsWithItsTrack() throws {
        var bytes: [UInt8] = []
        bytes += Array("MThd".utf8) + [0, 0, 0, 6, 0, 0, 0, 1, 0, 96]
        // 192 ticks, two beats, written the way the format writes a number
        // that does not fit in seven bits.
        let events: [UInt8] = [0x00, 0x90, 0x3C, 0x40, 0x81, 0x40, 0xFF, 0x2F, 0x00]
        bytes += Array("MTrk".utf8) + [0, 0, 0, UInt8(events.count)] + events

        let notes = try MIDIFile(data: Data(bytes)).notes
        #expect(notes.count == 1)
        #expect(notes[0].length.beats == 2, "held to the end of the track, which is two beats in")
    }

    @Test func aChunkNobodyKnowsIsSteppedOver() throws {
        var bytes: [UInt8] = []
        bytes += Array("MThd".utf8) + [0, 0, 0, 6, 0, 0, 0, 1, 0, 96]
        bytes += Array("XFIR".utf8) + [0, 0, 0, 3, 1, 2, 3]
        let events: [UInt8] = [0x00, 0x90, 0x3C, 0x40, 0x60, 0x80, 0x3C, 0x00, 0x00, 0xFF, 0x2F, 0x00]
        bytes += Array("MTrk".utf8) + [0, 0, 0, UInt8(events.count)] + events

        #expect(try MIDIFile(data: Data(bytes)).notes.count == 1)
    }

    // MARK: The tempo map

    @Test func beatsAndSecondsAreEachOthersInverse() {
        var file = MIDIFile(phrase, tempo: 120)
        file.tempoChanges = [
            MIDIFile.TempoChange(beat: 0, tempo: 120),
            MIDIFile.TempoChange(beat: 4, tempo: 60),
            MIDIFile.TempoChange(beat: 8, tempo: 240),
        ]

        #expect(file.seconds(at: 0) == 0)
        #expect(abs(file.seconds(at: 4) - 2) < 1e-9, "four beats at 120 a minute is two seconds")
        #expect(abs(file.seconds(at: 8) - 6) < 1e-9, "four more at 60 a minute is four seconds")
        #expect(abs(file.seconds(at: 12) - 7) < 1e-9, "four more at 240 a minute is one second")

        #expect(abs(file.beats(at: 6) - 8) < 1e-9)
        for step in 0 ... 40 {
            let beat = Double(step) * 0.35
            #expect(abs(file.beats(at: file.seconds(at: beat)) - beat) < 1e-9,
                    "seconds and beats have to be the same walk read from either end")
        }
        #expect(file.tempo(at: 5).beatsPerMinute == 60)
        #expect(file.tempo(at: 100).beatsPerMinute == 240)
    }

    @Test func aChangeOfSpeedSurvivesTheFile() throws {
        var file = MIDIFile(phrase, tempo: 120, name: "Slowing")
        file.tempoChanges = [
            MIDIFile.TempoChange(beat: 0, tempo: 120),
            MIDIFile.TempoChange(beat: 2, tempo: 60),
        ]
        let read = try MIDIFile(data: file.data())
        #expect(read.tempoChanges.count == 2)
        #expect(read.tempoChanges.map(\.beat) == [0, 2])
        #expect(read.tempoChanges.map(\.tempo.beatsPerMinute) == [120, 60])
    }

    @Test func theBarsComeFromTheTimeSignature() throws {
        var file = MIDIFile(phrase, tempo: 120)
        file.timeSignatures = [MIDIFile.TimeSignature(beat: 0, count: 6, unit: .eighth)]
        let read = try MIDIFile(data: file.data())
        #expect(read.timeSignature(at: 0).description == "6/8")
        #expect(read.timeSignature(at: 0).barLength.beats == 3, "six eighths is three beats")
        #expect(read.tempo.beatsPerBar == 3)
    }

    @Test func theNotesInAStretchAreTheOnesThatStartInIt() {
        let file = MIDIFile(phrase, tempo: 120)
        #expect(file.notes(from: 0, to: 1).map(\.pitch.midi) == [60])
        #expect(file.notes(from: 1, to: 2).map(\.pitch.midi) == [64, 67])
        #expect(file.notes(from: 1.5, to: 1.5).isEmpty, "an empty stretch holds nothing")
        #expect(file.notes(from: 0, to: 100).count == 3)
    }

    @Test func somebodyElsesReaderAcceptsWhatWeWrote() throws {
        // AVMIDIPlayer is Apple's own parser, and it has never seen this code.
        // A chunk length, a header field, or a delta time wrong in a way our
        // own reader happens to tolerate is what this catches, and nothing
        // else here can.
        let path = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-outside-\(UUID().uuidString).mid").path
        defer { try? FileManager.default.removeItem(atPath: path) }

        var file = MIDIFile(phrase, tempo: 120, name: "Outside")
        file.tempoChanges = [
            MIDIFile.TempoChange(beat: 0, tempo: 120),
            MIDIFile.TempoChange(beat: 2, tempo: 60),
        ]
        try file.write(to: path)

        let player = try AVMIDIPlayer(contentsOf: URL(fileURLWithPath: path), soundBankURL: nil)
        #expect(abs(player.duration - file.duration) < 0.05,
                "another reader has to agree on how long the piece is, tempo change and all")
    }

    // MARK: Refusals

    @Test func somethingThatIsNotAMIDIFileIsRefused() {
        #expect(throws: MIDIFile.ReadError.self) {
            try MIDIFile(data: Data("this is a text file, not music".utf8))
        }
        let error = try? #require(throws: MIDIFile.ReadError.self) {
            try MIDIFile(data: Data("this is a text file, not music".utf8))
        }
        #expect(error?.offset == 0)
        #expect(error?.description.contains("MThd") == true)
    }

    @Test func aTrackThatPromisesMoreThanTheFileHoldsIsRefused() {
        var bytes: [UInt8] = []
        bytes += Array("MThd".utf8) + [0, 0, 0, 6, 0, 0, 0, 1, 0, 96]
        bytes += Array("MTrk".utf8) + [0, 0, 0, 40] + [0x00, 0x90, 0x3C, 0x40]
        let error = try? #require(throws: MIDIFile.ReadError.self) {
            try MIDIFile(data: Data(bytes))
        }
        #expect(error?.problem.contains("ends first") == true)
    }

    @Test func aHeaderWithNoTicksInItIsRefused() {
        var bytes: [UInt8] = []
        bytes += Array("MThd".utf8) + [0, 0, 0, 6, 0, 0, 0, 1, 0, 0]
        #expect(throws: MIDIFile.ReadError.self) { try MIDIFile(data: Data(bytes)) }
    }

    @Test func aFileThatIsNotThereIsRefusedByName() {
        let error = try? #require(throws: MIDIFile.ReadError.self) {
            try MIDIFile(contentsOf: "/nowhere/at/all.mid")
        }
        #expect(error?.description.contains("/nowhere/at/all.mid") == true)
    }
}

/// Writing down what an instrument was asked to play.
@Suite
@MainActor
struct MIDIRecordingTests {

    @Test func anInstrumentWritesDownWhatItIsAskedToPlay() {
        let synth = Synth(.nylon)
        // The engine takes its own time to start, and it starts on the first
        // note. Paid here, so what is measured is the recording's clock.
        synth.start()
        #expect(!synth.isRecording)
        synth.startRecording(tempo: 120, name: "Take")
        #expect(synth.isRecording)

        // Both notes are asked for in one breath, the second with half a
        // second of lead, which at 120 a minute is one beat. The clock is a
        // real one, so the gap between them is the invariant rather than either
        // note's own place.
        synth.play("C4", velocity: 0.8, for: 0.25)
        synth.play("E4", velocity: 0.5, for: 0.25, after: 0.5)

        let file = synth.stopRecording()
        #expect(!synth.isRecording)
        #expect(file.name == "Take")
        #expect(file.tempo.beatsPerMinute == 120)

        let notes = file.notes
        #expect(notes.count == 2)
        #expect(notes.map(\.pitch.midi) == [60, 64])
        #expect(notes[0].beat < 0.2, "the first note lands where the recording started")
        #expect(abs((notes[1].beat - notes[0].beat) - 1) < 0.05,
                "half a second of lead at 120 a minute is a beat apart")
        #expect(abs(notes[0].length.beats - 0.5) < 1e-6, "a quarter of a second is half a beat")
        #expect(abs(notes[1].velocity - 0.5) < 1e-9)
    }

    @Test func aHeldNoteIsWrittenDownWhenItIsLetGo() {
        let synth = Synth(.nylon)
        synth.startRecording(tempo: 120)
        let note = synth.noteOn("A4", velocity: 0.7)
        #expect(synth.recordedSoFar().notes.count == 1, "a note still sounding is in the piece already")
        synth.noteOff(note)

        let file = synth.stopRecording()
        #expect(file.notes.count == 1)
        #expect(file.notes[0].pitch.midi == 69)
        #expect(file.notes[0].length.beats >= 0)
    }

    @Test func readingWhatIsThereDoesNotEndTheRecording() {
        let synth = Synth(.nylon)
        synth.startRecording(tempo: 120)
        synth.play("C4", for: 0.1)
        #expect(synth.recordedSoFar().notes.count == 1)
        #expect(synth.isRecording)
        synth.play("D4", for: 0.1)
        #expect(synth.recordedSoFar().notes.count == 2)
        #expect(synth.stopRecording().notes.count == 2)
    }

    @Test func stoppingWithoutStartingGivesAnEmptyPiece() {
        let synth = Synth(.nylon)
        #expect(synth.stopRecording().notes.isEmpty)
        #expect(synth.recordedSoFar().notes.isEmpty)
    }

    @Test func aRecordedTakeWritesAFileThatReadsBack() throws {
        let synth = Synth(.nylon)
        synth.startRecording(tempo: 100, name: "Improvised")
        synth.play("C4", for: 0.3)
        synth.play("G4", for: 0.3, after: 0.6)
        let file = synth.stopRecording()

        let read = try MIDIFile(data: file.data())
        #expect(read.name == "Improvised")
        #expect(read.tempo.beatsPerMinute == 100)
        #expect(read.notes.map(\.pitch.midi) == [60, 67])
    }
}
