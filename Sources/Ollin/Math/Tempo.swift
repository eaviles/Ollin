import Foundation

/// How fast the music goes: beats per minute, and how many beats make a bar.
///
/// The composition types answer a step number and own no clock, so turning the
/// sketch's seconds into beats, and a note's length in beats back into
/// seconds, is this value's job. It is the one number in the music that knows
/// what a second is:
///
/// ```swift
/// let tempo: Tempo = 104
///
/// for step in counter.steps(upTo: tempo.beats(at: time)) {   // seconds in, beats out
///     synth.play(scale[step], for: tempo.seconds(of: .eighth))   // a length in, seconds out
/// }
/// ```
///
/// A beat is a quarter note, the convention a metronome marking assumes, so
/// `NoteLength.quarter` lasts one beat and `.whole` four. `beatsPerBar` says how
/// many beats make a bar, four unless told otherwise; `seconds(bars:)` and
/// `bars(at:)` read it. A plain number stands in for a tempo wherever one is
/// expected, so `tempo: 120` reads as it always did.
public struct Tempo: Hashable, Sendable, Codable, CustomStringConvertible {
    /// Beats in a minute, the number on a metronome.
    public var beatsPerMinute: Double
    /// Beats in a bar. Four unless told otherwise.
    public var beatsPerBar: Int

    public init(_ beatsPerMinute: Double, beatsPerBar: Int = 4) {
        self.beatsPerMinute = beatsPerMinute
        self.beatsPerBar = beatsPerBar
    }

    /// How long one beat lasts.
    public var secondsPerBeat: Double { 60 / max(1e-6, beatsPerMinute) }

    /// How long one bar lasts.
    public var secondsPerBar: Double { secondsPerBeat * Double(max(1, beatsPerBar)) }

    /// Where the music has got to after `seconds`, in beats. What a
    /// `StepCounter` wants handed to it each frame.
    public func beats(at seconds: Double) -> Double {
        seconds * beatsPerMinute / 60
    }

    /// Where the music has got to after `seconds`, in bars, with the fraction.
    public func bars(at seconds: Double) -> Double {
        beats(at: seconds) / Double(max(1, beatsPerBar))
    }

    /// How long a number of beats lasts.
    public func seconds(beats: Double) -> Double {
        beats * 60 / max(1e-6, beatsPerMinute)
    }

    /// How long a number of bars lasts. Eight bars is a common loop.
    public func seconds(bars: Double) -> Double {
        seconds(beats: bars * Double(max(1, beatsPerBar)))
    }

    /// How long a note of this length lasts. What a synth's `for:` wants.
    public func seconds(of length: NoteLength) -> Double {
        seconds(beats: length.beats)
    }

    /// The tempo as a metronome would print it: `"104 bpm"`.
    public var description: String {
        "\(Tempo.plain(beatsPerMinute)) bpm"
    }

    /// A number without a trailing `.0`, and without exponent notation at any
    /// tempo a sketch would set.
    static func plain(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e9 ? String(Int(value)) : String(format: "%g", value)
    }
}

extension Tempo: ExpressibleByIntegerLiteral {
    /// `tempo: 120` reads the number as beats per minute, four to the bar.
    public init(integerLiteral value: Int) { self.init(Double(value)) }
}

extension Tempo: ExpressibleByFloatLiteral {
    /// `tempo: 118.5` reads the number as beats per minute, four to the bar.
    public init(floatLiteral value: Double) { self.init(value) }
}

/// How long a note lasts, in beats, where a beat is a quarter note.
///
/// The named lengths are the ones written on a stave, `.whole` down to
/// `.thirtySecond`, and two properties derive the rest: `.quarter.dotted` is a
/// beat and a half, and `.eighth.triplet` a third of a beat, three of them in
/// the time of two eighths. A plain number is a count of beats, so `length: 0.5`
/// still means half a beat, and `NoteLength(beats: 1.1)` holds a length no name
/// covers.
///
/// Nothing here knows how fast the music is going. A `Tempo` turns a length
/// into seconds, from either side: `tempo.seconds(of: .eighth)` and
/// `NoteLength.eighth.seconds(at: tempo)` are the same number.
public struct NoteLength: Hashable, Sendable, Codable, Comparable, CustomStringConvertible {
    /// The length in beats, a quarter note being one.
    public var beats: Double

    public init(beats: Double) { self.beats = beats }

    /// Four beats, a whole bar of four.
    public static let whole = NoteLength(beats: 4)
    /// Two beats.
    public static let half = NoteLength(beats: 2)
    /// One beat.
    public static let quarter = NoteLength(beats: 1)
    /// Half a beat.
    public static let eighth = NoteLength(beats: 0.5)
    /// A quarter of a beat, the step of a sixteen-step pattern.
    public static let sixteenth = NoteLength(beats: 0.25)
    /// An eighth of a beat.
    public static let thirtySecond = NoteLength(beats: 0.125)

    /// The same length and half again: the dot after a note on the stave.
    public var dotted: NoteLength { NoteLength(beats: beats * 1.5) }

    /// Three of these in the time of two: `.eighth.triplet` is a third of a beat.
    public var triplet: NoteLength { NoteLength(beats: beats * 2 / 3) }

    /// How long the note lasts at a tempo.
    public func seconds(at tempo: Tempo) -> Double { tempo.seconds(of: self) }

    /// A number of these back to back: `.quarter * 3` is three beats.
    public static func * (length: NoteLength, count: Double) -> NoteLength {
        NoteLength(beats: length.beats * count)
    }

    /// Two lengths tied together.
    public static func + (a: NoteLength, b: NoteLength) -> NoteLength {
        NoteLength(beats: a.beats + b.beats)
    }

    public static func < (a: NoteLength, b: NoteLength) -> Bool { a.beats < b.beats }

    /// The name on the stave when there is one (`"quarter"`, `"dotted eighth"`,
    /// `"eighth triplet"`), or the count of beats (`"1.1 beats"`).
    public var description: String {
        if let name = NoteLength.name(of: beats) { return name }
        if let name = NoteLength.name(of: beats / 1.5) { return "dotted \(name)" }
        if let name = NoteLength.name(of: beats * 1.5) { return "\(name) triplet" }
        return "\(Tempo.plain(beats)) beats"
    }

    private static let names: [(beats: Double, name: String)] = [
        (4, "whole"), (2, "half"), (1, "quarter"), (0.5, "eighth"),
        (0.25, "sixteenth"), (0.125, "thirty-second"),
    ]

    private static func name(of beats: Double) -> String? {
        names.first { abs($0.beats - beats) < 1e-9 }?.name
    }
}

extension NoteLength: ExpressibleByIntegerLiteral {
    /// `length: 2` reads the number as a count of beats.
    public init(integerLiteral value: Int) { self.init(beats: Double(value)) }
}

extension NoteLength: ExpressibleByFloatLiteral {
    /// `length: 0.5` reads the number as a count of beats.
    public init(floatLiteral value: Double) { self.init(beats: value) }
}
