import Foundation

/// A sampled instrument's map, read from an `.sfz` file.
///
/// SFZ is a plain text format: a list of regions, each naming an audio file and
/// the notes and velocities it answers to. It is the format most freely
/// licensed sample libraries ship in, which is the reason to read it rather
/// than invent something.
///
/// ```
/// <region> sample=piano_c4.wav lokey=58 hikey=64 pitch_keycenter=60
/// ```
///
/// **What is read, and what is passed over.** The opcodes below are the ones
/// that decide which file plays and at what pitch, which is what a sampler
/// needs to sound right. SFZ has hundreds of others covering filters,
/// envelopes, round robins and modulation; an unknown opcode is skipped rather
/// than refused, so a library that uses them loads and plays, without the parts
/// this does not model.
///
/// | Opcode | What it does |
/// |---|---|
/// | `sample` | the audio file, relative to the `.sfz` |
/// | `lokey` / `hikey` / `key` | which notes this region answers to |
/// | `pitch_keycenter` | the note the file was recorded at |
/// | `lovel` / `hivel` | how hard a note has to be struck to reach it |
/// | `tune` / `transpose` | corrections in cents and semitones |
/// | `volume` | the region's own level, in decibels |
/// | `loop_mode` / `loop_start` / `loop_end` | whether and where it repeats |
///
/// Note names are accepted as well as numbers (`c4`, `f#3`), since libraries
/// use both.
struct SFZFile {
    var regions: [SFZRegion] = []

    /// Reads a file, or nil if it cannot be read at all.
    ///
    /// A malformed line is skipped rather than refused: sample libraries are
    /// written by hand as often as by a tool, and one bad line should cost one
    /// region rather than the instrument.
    init?(contentsOf url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8)
                ?? String(contentsOf: url, encoding: .isoLatin1) else { return nil }
        self.init(text: text)
    }

    init(text: String) {
        // Opcodes fall under whichever header last opened, and a `<group>`'s
        // settings are inherited by every region under it, which is how
        // libraries avoid repeating themselves. A `<global>` covers the lot.
        var global: [String: String] = [:]
        var group: [String: String] = [:]
        var current: [String: String] = [:]
        var section = ""
        var lastKey: String?

        func closeRegion() {
            guard section == "region" else { return }
            var merged = global
            group.forEach { merged[$0.key] = $0.value }
            current.forEach { merged[$0.key] = $0.value }
            if let region = SFZRegion(merged) { regions.append(region) }
        }

        func store(_ key: String, _ value: String) {
            switch section {
            case "global": global[key] = value
            case "group":  group[key] = value
            default:       current[key] = value
            }
        }

        func read(_ key: String) -> String {
            switch section {
            case "global": return global[key] ?? ""
            case "group":  return group[key] ?? ""
            default:       return current[key] ?? ""
            }
        }

        for rawLine in text.split(whereSeparator: \.isNewline) {
            // Everything after `//` is a comment.
            var line = Substring(rawLine)
            if let comment = line.range(of: "//") { line = line[..<comment.lowerBound] }
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }

            // A line can hold a header and several opcodes, so it is walked
            // token by token rather than split on the first thing found.
            for token in line.split(whereSeparator: { $0 == " " || $0 == "\t" }) {
                if token.hasPrefix("<"), token.hasSuffix(">") {
                    closeRegion()
                    section = String(token.dropFirst().dropLast())
                    lastKey = nil
                    switch section {
                    case "global": global = [:]; group = [:]; current = [:]
                    case "group":  group = [:]; current = [:]
                    default:       current = [:]
                    }
                    continue
                }
                guard let split = token.firstIndex(of: "=") else {
                    // A token with no `=` is the rest of the value before it,
                    // which is how a file name with a space in it arrives.
                    guard let lastKey else { continue }
                    store(lastKey, read(lastKey) + " " + token)
                    continue
                }
                let key = String(token[..<split]).lowercased()
                store(key, String(token[token.index(after: split)...]))
                lastKey = key
            }
        }
        closeRegion()
    }
}

/// One region of a sampled instrument: a file, and when it answers.
struct SFZRegion {
    var sample: String
    var lowKey: Int
    var highKey: Int
    var rootKey: Int
    var lowVelocity: Int
    var highVelocity: Int
    /// A correction in cents, for a recording that is not quite in tune.
    var tune: Double
    /// The region's own level, in decibels.
    var volume: Double
    var loops: Bool
    var loopStart: Int?
    var loopEnd: Int?

    init?(_ opcodes: [String: String]) {
        guard let sample = opcodes["sample"], !sample.isEmpty else { return nil }
        // SFZ is a Windows format by birth, so paths are written with
        // backslashes and have to be turned round to be opened here.
        self.sample = sample.replacingOccurrences(of: "\\", with: "/")
            .trimmingCharacters(in: .whitespaces)

        let key = opcodes["key"].flatMap(SFZRegion.note)
        lowKey = key ?? opcodes["lokey"].flatMap(SFZRegion.note) ?? 0
        highKey = key ?? opcodes["hikey"].flatMap(SFZRegion.note) ?? 127
        // With no center given, the file is taken to be recorded at the bottom
        // of its own range, which is what a one-file-per-note library means.
        rootKey = opcodes["pitch_keycenter"].flatMap(SFZRegion.note) ?? key ?? lowKey
        // Every number below is held to the range the format gives it: a key
        // or a velocity is a MIDI number, a correction is a few octaves at
        // most, and a level is in decibels. A value past its range (or not a
        // number) would reach the voice as a pitch step no playback can take.
        func velocity(_ text: String?) -> Int? { text.flatMap { Int($0) }.map { min(max($0, 0), 127) } }
        func number(_ text: String?, in range: ClosedRange<Double>) -> Double? {
            guard let value = text.flatMap({ Double($0) }), value.isFinite else { return nil }
            return min(max(value, range.lowerBound), range.upperBound)
        }
        lowVelocity = velocity(opcodes["lovel"]) ?? 0
        highVelocity = velocity(opcodes["hivel"]) ?? 127

        let cents = number(opcodes["tune"], in: -9600...9600) ?? 0
        let semitones = number(opcodes["transpose"], in: -127...127) ?? 0
        tune = cents + semitones * 100
        volume = number(opcodes["volume"], in: -144...48) ?? 0

        let mode = opcodes["loop_mode"] ?? ""
        loops = mode == "loop_continuous" || mode == "loop_sustain"
        func frame(_ text: String?) -> Int? { text.flatMap { Int($0) }.flatMap { $0 >= 0 ? $0 : nil } }
        loopStart = frame(opcodes["loop_start"]) ?? frame(opcodes["loopstart"])
        loopEnd = frame(opcodes["loop_end"]) ?? frame(opcodes["loopend"])
    }

    /// A note as a number, written either way round: `60` or `c4`.
    ///
    /// Libraries use both, and a reader that took only numbers would fail on
    /// half of them for no reason a user could see.
    static func note(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        // A key is a MIDI number; -1 is the format's way of saying none.
        if let number = Int(trimmed) { return (-1...127).contains(number) ? number : nil }

        var characters = Array(trimmed.lowercased())
        guard !characters.isEmpty else { return nil }
        let letters: [Character: Int] = ["c": 0, "d": 2, "e": 4, "f": 5,
                                         "g": 7, "a": 9, "b": 11]
        guard let base = letters[characters.removeFirst()] else { return nil }
        var semitone = base
        while let first = characters.first, first == "#" || first == "b" {
            semitone += first == "#" ? 1 : -1
            characters.removeFirst()
        }
        guard let octave = Int(String(characters)), (-1...9).contains(octave) else { return nil }
        // The convention SFZ uses puts middle C at 60, which is c4 here.
        let number = (octave + 1) * 12 + semitone
        return (-1...127).contains(number) ? number : nil
    }
}
