import Foundation

/// Reading a chord written the way chords are written on paper.
///
/// ```swift
/// let chord: Chord = "Cmaj7"
/// synth.play(chord: Chord("F#m7").pitches, for: 1)
/// ```
///
/// The point is not to save typing over `Chord("C4", .majorSeventh)`. It is
/// that chord symbols are how chords are already written down everywhere else,
/// so a progression copied off a page arrives as itself.
public extension Chord {

    /// Reads a chord symbol, or nil if it is not one.
    ///
    /// A symbol is a root (`C`, `Bb`, `F#`), an optional octave (`C3`), an
    /// optional quality (`m7`, `maj7`, `dim`, `sus4`), and an optional bass
    /// after a slash (`C/G`). Anything left over makes it nil rather than a
    /// guess, so a typo is something you find out about.
    init?(symbol: String) {
        let text = symbol.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }

        // The bass note first, since a slash ends the rest of the symbol.
        var body = Substring(text)
        var slashBass: Substring?
        if let slash = body.firstIndex(of: "/") {
            slashBass = body[body.index(after: slash)...]
            body = body[..<slash]
        }

        // The root: a letter, then any accidentals.
        var index = body.startIndex
        guard index < body.endIndex, "ABCDEFGabcdefg".contains(body[index]) else { return nil }
        var name = String(body[index])
        index = body.index(after: index)
        while index < body.endIndex, "#b♯♭".contains(body[index]) {
            name.append(body[index])
            index = body.index(after: index)
        }
        // The quality is tried on the whole remainder first, and only if that
        // is not a quality is a trailing number considered an octave. Getting
        // this the other way round reads the 7 of "Cmaj7" as an octave and
        // leaves "maj", which is a different chord in a different register.
        var octave = ""
        let remainder = String(body[index...])
        if Chord.quality(remainder) == nil {
            var tail = body.endIndex
            while tail > index {
                let before = body.index(before: tail)
                guard body[before].isNumber || body[before] == "-" else { break }
                tail = before
            }
            let candidate = String(body[tail...])
            guard !candidate.isEmpty, let value = Int(candidate), (-1...9).contains(value),
                  Chord.quality(String(body[index..<tail])) != nil
            else { return nil }
            octave = candidate
            body = body[..<tail]
        }

        guard let root = Pitch(name: name + (octave.isEmpty ? "4" : octave)) else { return nil }
        guard let quality = Chord.quality(String(body[index...])) else { return nil }

        self.init(root, quality)

        // A named bass note is the chord turned until that note is lowest, or
        // simply added underneath when it is not in the chord at all.
        if let slashBass, let bass = Pitch(name: String(slashBass) + "0") {
            let wanted = ((Int(bass.midi.rounded()) % 12) + 12) % 12
            let members = quality.intervals.map {
                ((Int(root.midi.rounded()) + $0) % 12 + 12) % 12
            }
            if let position = members.firstIndex(of: wanted) {
                self.inversion = position
            }
        }
    }

    /// The quality a suffix names, or nil.
    ///
    /// Written out rather than derived, because chord suffixes are a
    /// convention with a long history and not a grammar: `m`, `min`, and `-`
    /// all mean the same thing and none of them follows from the others.
    static func quality(_ suffix: String) -> Quality? {
        switch suffix.trimmingCharacters(in: .whitespaces) {
        case "", "maj", "M", "major":            return .major
        case "m", "min", "-", "minor":           return .minor
        case "dim", "o", "°":                    return .diminished
        case "aug", "+":                         return .augmented
        case "sus2":                             return .sus2
        case "sus4", "sus":                      return .sus4
        case "5", "no3":                         return .fifth
        case "6", "maj6", "M6":                  return .sixth
        case "m6", "min6", "-6":                 return .minorSixth
        case "7", "dom7":                        return .dominantSeventh
        case "maj7", "M7", "Δ", "Δ7":            return .majorSeventh
        case "m7", "min7", "-7":                 return .minorSeventh
        case "mMaj7", "mM7", "minmaj7", "-Δ7":   return .minorMajorSeventh
        case "m7b5", "ø", "ø7", "halfdim":       return .halfDiminishedSeventh
        case "dim7", "o7", "°7":                 return .diminishedSeventh
        case "add9", "add2":                     return .addNine
        case "9", "dom9":                        return .ninth
        case "maj9", "M9":                       return .majorNinth
        case "m9", "min9", "-9":                 return .minorNinth
        case "11", "dom11":                      return .eleventh
        case "13", "dom13":                      return .thirteenth
        default:                                 return nil
        }
    }
}

extension Chord: ExpressibleByStringLiteral {
    /// A chord written as a symbol.
    ///
    /// A literal that is not a chord lands on C major and says so once rather
    /// than stopping the sketch, the same way a pitch name does. Use
    /// ``Chord/init(symbol:)``, which returns nil, where you want to be told
    /// about it in code.
    public init(stringLiteral value: String) {
        if let parsed = Chord(symbol: value) {
            self = parsed
        } else {
            audioNoteOnce("\"\(value)\" is not a chord symbol "
                          + "(try \"C\", \"Am7\", or \"F#maj7\"); using C major.")
            self = Chord("C4", .major)
        }
    }
}

public extension Progression {
    /// A progression written as chord symbols rather than as degrees.
    ///
    /// The other way of writing changes down, and the one to reach for when the
    /// chords do not all come from one key. Degrees survive a change of key and
    /// symbols do not, which is the trade.
    ///
    /// ```swift
    /// let changes = Progression(symbols: "Dm7 G7 Cmaj7 Cmaj7")
    /// ```
    init(symbols: String) {
        let written = symbols
            .split(whereSeparator: { $0 == " " || $0 == "," || $0 == "|" })
            .compactMap { Chord(symbol: String($0)) }
        self.init(written)
    }

    /// A progression from chords already in hand.
    ///
    /// Chords named outright rather than built from a key, so the progression
    /// carries its own qualities and ``scale`` is only what a bass line or a
    /// melody would be drawn from.
    init(_ chords: [Chord]) {
        let written = chords.isEmpty ? [Chord("C4", .major)] : chords
        self.init([], in: Scale(.chromatic, root: written[0].root))
        self.writtenChords = written
    }
}
