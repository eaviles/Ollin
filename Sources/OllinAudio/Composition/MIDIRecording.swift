import Foundation
import Ollin
import QuartzCore

/// What a ``Synth`` was asked to play while a recording ran.
///
/// Notes are written down as they are asked for, against a clock that starts
/// with the recording, and turned into beats by the tempo it was started at.
/// A note given a length arrives whole; one held with `noteOn` waits for its
/// release, and anything still sounding when the recording stops is let go
/// there.
final class MIDIRecording {
    let tempo: Tempo
    let name: String
    private let started: Double
    private var notes: [ScheduledNote] = []
    /// Notes still sounding, by the number the sketch was handed. A note held
    /// by pitch alone is filed under its pitch instead, which is how the
    /// `noteOff(_ pitch:)` spelling finds it again.
    private var sounding: [Int: (beat: Double, pitch: Double, velocity: Double)] = [:]

    init(tempo: Tempo, name: String, now: Double = CACurrentMediaTime()) {
        self.tempo = tempo
        self.name = name
        self.started = now
    }

    /// Where the music is, in beats, when an event lands.
    private func beat(of event: SynthEvent, now: Double) -> Double {
        tempo.beats(at: max(0, now - started) + max(0, event.delaySeconds))
    }

    /// Writes an event down. Called from the one place every note passes
    /// through on its way to the speakers, so a recording catches what an
    /// export would and what the hardware would alike.
    func write(_ event: SynthEvent, seconds: Double, now: Double = CACurrentMediaTime()) {
        let beat = self.beat(of: event, now: now)
        switch event.kind {
        case .noteOn where seconds > 0:
            // Its length was decided when it was asked for.
            append(pitch: event.pitch, velocity: event.velocity,
                   beat: beat, length: tempo.beats(at: seconds))
        case .noteOn:
            let key = event.noteID != 0 ? event.noteID : -Int(event.pitch.rounded())
            sounding[key] = (beat: beat, pitch: event.pitch, velocity: event.velocity)
        case .noteOff:
            let key = event.noteID != 0 ? event.noteID : -Int(event.pitch.rounded())
            guard let held = sounding.removeValue(forKey: key) else { return }
            append(pitch: held.pitch, velocity: held.velocity,
                   beat: held.beat, length: beat - held.beat)
        case .allNotesOff:
            for (key, held) in sounding {
                append(pitch: held.pitch, velocity: held.velocity,
                       beat: held.beat, length: beat - held.beat)
                sounding[key] = nil
            }
        default:
            break   // Expression and voice changes are not part of a written piece.
        }
    }

    private func append(pitch: Double, velocity: Double, beat: Double, length: Double) {
        notes.append(ScheduledNote(
            Note(Pitch(pitch), velocity: velocity, length: NoteLength(beats: max(0, length))),
            beat: max(0, beat), step: notes.count))
    }

    /// The piece so far, with anything still sounding let go now.
    ///
    /// Reading it does not end the recording or the notes still under it, so a
    /// sketch can look at what it has without stopping.
    func file(now: Double = CACurrentMediaTime()) -> MIDIFile {
        let beat = tempo.beats(at: max(0, now - started))
        var written = notes
        for (_, held) in sounding {
            written.append(ScheduledNote(
                Note(Pitch(held.pitch), velocity: held.velocity,
                     length: NoteLength(beats: max(0, beat - held.beat))),
                beat: max(0, held.beat), step: written.count))
        }
        return MIDIFile(written.sorted { $0.beat < $1.beat }, tempo: tempo, name: name)
    }
}

extension Synth {

    /// Whether this instrument is writing down what it plays.
    public var isRecording: Bool { recording != nil }

    /// Starts writing down every note this instrument is asked for, so that
    /// what a sketch played can be opened in a program made for editing music.
    ///
    /// ```swift
    /// override func keyPressed() {
    ///     if key == "r" { synth.isRecording ? save() : synth.startRecording(tempo: tempo) }
    /// }
    ///
    /// func save() {
    ///     try? synth.stopRecording().write(to: "take.mid")
    /// }
    /// ```
    ///
    /// The notes are placed against a clock that starts here, so a phrase
    /// played by hand keeps its timing, and a sequencer's notes keep theirs
    /// down to the wait each one was asked with. Only notes are written: a
    /// bend, a press, or a slide belongs to the instrument that made the
    /// sound rather than to the music.
    ///
    /// - Parameters:
    ///   - tempo: what the beats in the file mean. It decides where the bar
    ///     lines fall around what was played, and nothing else.
    ///   - name: what to call the piece.
    public func startRecording(tempo: Tempo = 120, name: String = "") {
        recording = MIDIRecording(tempo: tempo, name: name)
    }

    /// Stops, and hands back what was played.
    ///
    /// A note still sounding is let go here. Stopping without having started
    /// gives an empty file rather than nothing, so a sketch that saves on a
    /// key press writes a file either way.
    @discardableResult
    public func stopRecording() -> MIDIFile {
        defer { recording = nil }
        return recording?.file() ?? MIDIFile([], tempo: 120)
    }

    /// What has been played so far, without stopping.
    public func recordedSoFar() -> MIDIFile {
        recording?.file() ?? MIDIFile([], tempo: 120)
    }
}
