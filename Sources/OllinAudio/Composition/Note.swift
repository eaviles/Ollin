import Foundation
import Ollin

/// One note, decided but not yet played.
///
/// The composition types deal in pitches and step numbers, which is all most
/// sketches need. A `Note` is for when loudness and length were decided along
/// with the pitch and want to travel with it: a phrase read out of a chain, a
/// figure a sketch built and is holding on to.
///
/// Its length is a `NoteLength`, in beats rather than seconds, because nothing
/// in this tier knows how fast the music is going. The `Tempo` joins when it
/// is played.
///
/// ```swift
/// let note = Note(scale[3], velocity: 0.9, length: .eighth)
/// synth.play(note, tempo: 120)
/// ```
public struct Note: Sendable, Hashable {
    /// Which note.
    public var pitch: Pitch
    /// How hard it is struck, `0...1`.
    public var velocity: Double
    /// How long it lasts, in beats. A plain number is a count of beats.
    public var length: NoteLength

    public init(_ pitch: Pitch, velocity: Double = 0.8, length: NoteLength = .quarter) {
        self.pitch = pitch
        self.velocity = velocity
        self.length = length
    }

    /// The same note moved by a number of semitones.
    public func transposed(by semitones: Double) -> Note {
        Note(pitch.transposed(by: semitones), velocity: velocity, length: length)
    }

    /// How long the note lasts in seconds at a tempo.
    public func seconds(at tempo: Tempo) -> Double {
        tempo.seconds(of: length)
    }
}

extension Synth {
    /// Plays a note, reading its length in beats at this tempo.
    ///
    /// - Parameters:
    ///   - note: what to play.
    ///   - tempo: how fast the music is going, which is what turns the note's
    ///     length in beats into a length in seconds. A plain number is beats
    ///     per minute.
    public func play(_ note: Note, tempo: Tempo = 120) {
        play(note.pitch, velocity: note.velocity, for: note.seconds(at: tempo))
    }

    /// Plays several notes at once.
    public func play(_ notes: [Note], tempo: Tempo = 120) {
        for note in notes { play(note, tempo: tempo) }
    }
}
