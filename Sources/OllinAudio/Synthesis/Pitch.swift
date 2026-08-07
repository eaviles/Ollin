import Foundation
import os

/// A note's pitch, written the way you find it easiest.
///
/// ```swift
/// synth.play(60)        // MIDI numbers, if that is what you have
/// synth.play("C4")      // note names, if that is what you read
/// synth.play(Pitch(frequency: 440))
/// ```
///
/// The number is kept as a `Double` so a pitch can sit between the keys: bends,
/// glides, and tunings that are not the twelve equal steps all need somewhere
/// to land. `frequency` is derived from it, so moving a pitch by 12 always
/// doubles its frequency whatever it started from.
public struct Pitch: Sendable, Hashable, Comparable, CustomStringConvertible {
    /// The MIDI note number, where 60 is middle C and 69 is the A above it.
    /// Fractional values are legal and sound between the keys.
    public var midi: Double

    public init(_ midi: Double) { self.midi = midi }

    /// The pitch that sounds at a given frequency in Hz.
    public init(frequency: Double) {
        self.midi = frequency > 0 ? 69 + 12 * log2(frequency / 440) : 0
    }

    /// A pitch from a name such as `"C4"`, `"F#3"`, or `"Bb2"`.
    ///
    /// The octave is the scientific one, so `"C4"` is middle C. Both `#` and `b`
    /// are understood, and case does not matter. Returns nil if the name is not
    /// one, which is what separates this from the string literal form.
    public init?(name: String) {
        guard let midi = Pitch.midi(forName: name) else { return nil }
        self.midi = midi
    }

    /// Frequency in Hz, from A above middle C at 440.
    public var frequency: Double { 440 * pow(2, (midi - 69) / 12) }

    /// The same pitch moved by a number of semitones. Twelve is an octave.
    public func transposed(by semitones: Double) -> Pitch { Pitch(midi + semitones) }

    /// The nearest name for this pitch, sharps rather than flats.
    public var description: String {
        let rounded = Int(midi.rounded())
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        let octave = rounded / 12 - 1
        let index = ((rounded % 12) + 12) % 12
        return "\(names[index])\(octave)"
    }

    public static func < (a: Pitch, b: Pitch) -> Bool { a.midi < b.midi }

    /// Parses a note name, or nil.
    static func midi(forName name: String) -> Double? {
        var characters = Substring(name.trimmingCharacters(in: .whitespaces))
        guard let letter = characters.popFirst() else { return nil }
        let steps: [Character: Int] = ["c": 0, "d": 2, "e": 4, "f": 5, "g": 7, "a": 9, "b": 11]
        guard let step = steps[Character(letter.lowercased())] else { return nil }

        var accidental = 0
        while let next = characters.first, next == "#" || next == "b" || next == "♯" || next == "♭" {
            accidental += (next == "#" || next == "♯") ? 1 : -1
            characters.removeFirst()
        }

        // No octave means the one middle C sits in.
        let octave = characters.isEmpty ? 4 : Int(characters)
        guard let octave else { return nil }
        return Double((octave + 1) * 12 + step + accidental)
    }
}

extension Pitch: ExpressibleByIntegerLiteral {
    /// `synth.play(60)` reads the number as a MIDI note.
    public init(integerLiteral value: Int) { self.midi = Double(value) }
}

extension Pitch: ExpressibleByFloatLiteral {
    /// `synth.play(60.5)` sounds a quarter tone above middle C.
    public init(floatLiteral value: Double) { self.midi = value }
}

extension Pitch: ExpressibleByStringLiteral {
    /// `synth.play("C4")` reads the string as a note name.
    ///
    /// A literal cannot fail, so a name that is not one lands on middle C and
    /// says so once rather than stopping the sketch. Use `Pitch(name:)` where
    /// you want to be told in code instead.
    public init(stringLiteral value: String) {
        if let midi = Pitch.midi(forName: value) {
            self.midi = midi
        } else {
            audioNoteOnce("\"\(value)\" is not a note name (try \"C4\" or \"F#3\"); using middle C.")
            self.midi = 60
        }
    }
}

/// Prints a message the first time it comes up, so a mistake inside `draw()`
/// says so once instead of sixty times a second.
func audioNoteOnce(_ message: String) {
    let isNew = audioNotes.withLock { seen -> Bool in seen.insert(message).inserted }
    if isNew { print("Ollin: \(message)") }
}

private let audioNotes = OSAllocatedUnfairLock(initialState: Set<String>())
