import Foundation
import Ollin

/// A piece of music as a file, read from or written to the Standard MIDI File
/// format every sequencer and notation program speaks.
///
/// ```swift
/// let song = try MIDIFile(resource: "prelude", in: .module)
///
/// override func draw() {
///     let now = song.beats(at: time)
///     let ahead = song.beats(at: time + deltaTime)
///     synth.play(song.notes(from: now, to: ahead), tempo: song.tempo(at: now), from: now)
/// }
/// ```
///
/// The file arrives as notes rather than bytes: each ``Track`` holds
/// ``ScheduledNote`` values, the same thing a ``StepSequencer`` hands back, so
/// a piece written elsewhere plays through a ``Synth``, draws as a piano roll,
/// or drives anything else the sketch does, with no translation in between.
/// It goes out the same way, so a phrase a sketch worked out for itself opens
/// in a program made for editing music:
///
/// ```swift
/// try MIDIFile(phrase, tempo: 96, name: "Wander").write(to: "wander.mid")
/// ```
///
/// **Time is in beats.** Nothing in the composition tier knows what a second
/// is, and a file agrees: every position is a beat, a quarter note being one,
/// and the tempo map turns beats into seconds. ``seconds(at:)`` and
/// ``beats(at:)`` read the map from either side, so a file that changes speed
/// partway through still lines up with the sketch clock.
///
/// **What is read, and what is passed over.** Notes, control changes, pitch
/// bends, program changes, track names, tempo changes, time signatures, and
/// markers all come across. Aftertouch, system-exclusive blocks, key
/// signatures, and the meta events that describe the file rather than the
/// music are stepped over: their bytes are read and skipped, so a file that
/// carries them loads and plays without the parts this does not model. Only
/// what is listed here is written back.
///
/// **A track plays on one channel.** A track that uses several reads as one
/// track per channel, since the channel is what says which instrument a note
/// belongs to. That is also what makes a format 0 file useful: everything in
/// it is on one chunk, and it arrives here split into the instruments that
/// were playing.
public struct MIDIFile: Sendable, Hashable {

    /// How the file lays its music out, the number in its header.
    public enum Format: Int, Sendable, Hashable, CustomStringConvertible {
        /// Format 0: the whole piece on one track.
        case oneTrack = 0
        /// Format 1: several tracks that play together, the usual shape.
        case parallelTracks = 1
        /// Format 2: several patterns, each its own piece rather than a part
        /// of one. Read as tracks; joining them would invent music the file
        /// does not claim.
        case separatePatterns = 2

        public var description: String {
            switch self {
            case .oneTrack: return "one track"
            case .parallelTracks: return "parallel tracks"
            case .separatePatterns: return "separate patterns"
            }
        }
    }

    /// What a tick in the file is worth.
    public enum Division: Sendable, Hashable, CustomStringConvertible {
        /// Ticks in a quarter note, how nearly every file is timed. The
        /// resolution: 960 puts a tick a thousandth of a beat apart.
        case perQuarter(Int)
        /// Ticks counted against the clock rather than the music, which is how
        /// a file cut to picture is timed. `framesPerSecond` is one of 24, 25,
        /// 29.97, or 30.
        case perSecond(framesPerSecond: Double, ticksPerFrame: Int)

        /// How many ticks make a second, where that is a fixed number.
        var ticksPerSecond: Double? {
            switch self {
            case .perQuarter: return nil
            case .perSecond(let fps, let ticks): return fps * Double(ticks)
            }
        }

        public var description: String {
            switch self {
            case .perQuarter(let ticks): return "\(ticks) ticks per quarter note"
            case .perSecond(let fps, let ticks):
                let rate = fps == fps.rounded() ? String(Int(fps)) : String(format: "%g", fps)
                return "\(rate) frames a second, \(ticks) ticks a frame"
            }
        }
    }

    /// The tempo from one beat on.
    public struct TempoChange: Sendable, Hashable {
        /// Where it takes effect, in beats from the start.
        public var beat: Double
        /// How fast the music goes from there.
        public var tempo: Tempo

        public init(beat: Double, tempo: Tempo) {
            self.beat = beat
            self.tempo = tempo
        }
    }

    /// How the bars are counted from one beat on: `3/4`, `6/8`, `7/8`.
    public struct TimeSignature: Sendable, Hashable, CustomStringConvertible {
        /// Where it takes effect, in beats from the start.
        public var beat: Double
        /// How many of the unit make a bar: the 3 in `3/4`.
        public var count: Int
        /// What is being counted: the 4 in `3/4`, as a length.
        public var unit: NoteLength

        public init(beat: Double = 0, count: Int = 4, unit: NoteLength = .quarter) {
            self.beat = beat
            self.count = count
            self.unit = unit
        }

        /// How long a bar lasts, in beats. `6/8` is three beats, not six.
        public var barLength: NoteLength { unit * Double(count) }

        /// The signature as it is written: `"3/4"`.
        public var description: String {
            let denominator = unit.beats > 0 ? Int((4 / unit.beats).rounded()) : 4
            return "\(count)/\(denominator)"
        }
    }

    /// A place in the music somebody named, which is what a sketch can cue a
    /// scene from.
    public struct Marker: Sendable, Hashable {
        /// Where it sits, in beats from the start.
        public var beat: Double
        /// What it says.
        public var text: String

        public init(beat: Double, text: String) {
            self.beat = beat
            self.text = text
        }
    }

    /// A controller moved: a mod wheel, a pedal, a fader.
    public struct ControlChange: Sendable, Hashable {
        /// Where it happens, in beats from the start.
        public var beat: Double
        /// Which controller, 0 to 127. 1 is the mod wheel, 64 the sustain
        /// pedal, 7 the volume.
        public var controller: Int
        /// Where it was moved to, 0 to 1.
        public var value: Double

        public init(beat: Double, controller: Int, value: Double) {
            self.beat = beat
            self.controller = controller
            self.value = value
        }
    }

    /// The pitch wheel moved.
    public struct PitchBend: Sendable, Hashable {
        /// Where it happens, in beats from the start.
        public var beat: Double
        /// Where the wheel sits, -1 to 1, with 0 at rest. How far that bends a
        /// note is the instrument's business, two semitones unless it was told
        /// otherwise.
        public var position: Double

        public init(beat: Double, position: Double) {
            self.beat = beat
            self.position = position
        }
    }

    /// One part: its notes, and what else happened on its channel.
    public struct Track: Sendable, Hashable {
        /// What the file calls it, or an empty string.
        public var name: String
        /// The channel it plays on, 1 to 16 the way a sequencer labels them.
        /// Channel 10 is where drums go by convention.
        public var channel: Int
        /// The sound the file asks for, 0 to 127, if it asks for one.
        public var program: Int?
        /// The notes, each with its pitch, loudness, length in beats, and the
        /// beat it lands on.
        public var notes: [ScheduledNote]
        /// Controllers moved while it played.
        public var controls: [ControlChange]
        /// The pitch wheel while it played.
        public var bends: [PitchBend]

        public init(
            _ notes: [ScheduledNote], name: String = "", channel: Int = 1,
            program: Int? = nil, controls: [ControlChange] = [], bends: [PitchBend] = []
        ) {
            self.name = name
            self.channel = channel
            self.program = program
            self.notes = notes
            self.controls = controls
            self.bends = bends
        }

        /// Whether anything happens on it.
        public var isEmpty: Bool { notes.isEmpty && controls.isEmpty && bends.isEmpty }

        /// Where its last note lets go, in beats.
        public var lastBeat: Double {
            notes.reduce(0) { max($0, $1.beat + $1.length.beats) }
        }
    }

    /// How the file lays its music out.
    public var format: Format
    /// What a tick in the file is worth.
    public var division: Division
    /// What the file calls the piece, or an empty string.
    public var name: String
    /// The parts, each on its own channel.
    public var tracks: [Track]
    /// Where the music changes speed. Empty means it never does, and the
    /// format says 120 beats a minute until told otherwise.
    public var tempoChanges: [TempoChange]
    /// Where the bars change shape.
    public var timeSignatures: [TimeSignature]
    /// The places somebody named.
    public var markers: [Marker]

    public init(
        format: Format = .parallelTracks,
        division: Division = .perQuarter(960),
        name: String = "",
        tracks: [Track] = [],
        tempoChanges: [TempoChange] = [],
        timeSignatures: [TimeSignature] = [],
        markers: [Marker] = []
    ) {
        self.format = format
        self.division = division
        self.name = name
        self.tracks = tracks
        self.tempoChanges = tempoChanges
        self.timeSignatures = timeSignatures
        self.markers = markers
    }

    /// A file of one part, from notes a sketch worked out.
    ///
    /// What a ``StepSequencer`` run, an ``Arpeggiator``, a ``MarkovChain``
    /// wander, or anything else that answers in ``ScheduledNote`` values hands
    /// back goes straight in.
    ///
    /// ```swift
    /// var bar = 0.0
    /// var phrase: [ScheduledNote] = []
    /// while bar < 32 {
    ///     phrase += sequencer.events(upTo: bar)
    ///     bar += 4
    /// }
    /// try MIDIFile(phrase, tempo: 112, name: "Pattern").write(to: "pattern.mid")
    /// ```
    ///
    /// - Parameters:
    ///   - notes: the notes, each with the beat it lands on.
    ///   - tempo: how fast the piece goes, written into the file so whatever
    ///     opens it agrees.
    ///   - name: what to call the piece.
    ///   - channel: which channel the notes play on, 1 to 16.
    public init(_ notes: [ScheduledNote], tempo: Tempo = 120, name: String = "", channel: Int = 1) {
        self.init(
            format: .parallelTracks,
            name: name,
            tracks: [Track(notes, name: name, channel: channel)],
            tempoChanges: [TempoChange(beat: 0, tempo: tempo)],
            timeSignatures: [TimeSignature(count: tempo.beatsPerBar)]
        )
    }

    // MARK: Reading the music

    /// Every track's notes, in the order they are played.
    public var notes: [ScheduledNote] {
        tracks.flatMap(\.notes).sorted { $0.beat < $1.beat }
    }

    /// The notes that start in a stretch of beats, `from` up to but not
    /// including `to`.
    ///
    /// What a sketch asks for once a frame, against where the music will be at
    /// the end of it, so the synth can wait out the rest of each note's lead.
    public func notes(from: Double, to: Double) -> [ScheduledNote] {
        notes.filter { $0.beat >= from && $0.beat < to }
    }

    /// Where the last note lets go, in beats.
    public var lastBeat: Double {
        tracks.reduce(0) { max($0, $1.lastBeat) }
    }

    /// How long the piece lasts in seconds, reading the tempo map.
    public var duration: Double { seconds(at: lastBeat) }

    /// How fast the music goes at a beat.
    ///
    /// The bars come from the time signature in force there, where it divides
    /// into whole beats, so `tempo.beatsPerBar` is 3 in `3/4` and in `6/8`.
    public func tempo(at beat: Double) -> Tempo {
        var beatsPerMinute = 120.0
        for change in tempoChanges.sorted(by: { $0.beat < $1.beat }) where change.beat <= beat {
            beatsPerMinute = change.tempo.beatsPerMinute
        }
        var beatsPerBar = 4
        for signature in timeSignatures.sorted(by: { $0.beat < $1.beat }) where signature.beat <= beat {
            let bar = signature.barLength.beats
            beatsPerBar = bar > 0 && bar == bar.rounded() ? Int(bar) : 4
        }
        return Tempo(beatsPerMinute, beatsPerBar: max(1, beatsPerBar))
    }

    /// How fast the music goes where it starts.
    public var tempo: Tempo { tempo(at: 0) }

    /// How the bars are counted at a beat.
    public func timeSignature(at beat: Double) -> TimeSignature {
        var found = TimeSignature()
        for signature in timeSignatures.sorted(by: { $0.beat < $1.beat }) where signature.beat <= beat {
            found = signature
        }
        return found
    }

    /// Where a beat falls on the clock, in seconds, reading the tempo map.
    public func seconds(at beat: Double) -> Double {
        var seconds = 0.0
        var cursor = 0.0
        var beatsPerMinute = 120.0
        for change in tempoChanges.sorted(by: { $0.beat < $1.beat }) where change.beat < beat {
            if change.beat > cursor {
                seconds += (change.beat - cursor) * 60 / max(1e-6, beatsPerMinute)
                cursor = change.beat
            }
            beatsPerMinute = change.tempo.beatsPerMinute
        }
        return seconds + (beat - cursor) * 60 / max(1e-6, beatsPerMinute)
    }

    /// Where the music has got to after a number of seconds, in beats. The
    /// other way round from ``seconds(at:)``, and its exact inverse.
    public func beats(at seconds: Double) -> Double {
        var elapsed = 0.0
        var cursor = 0.0
        var beatsPerMinute = 120.0
        for change in tempoChanges.sorted(by: { $0.beat < $1.beat }) {
            guard change.beat > cursor else {
                beatsPerMinute = change.tempo.beatsPerMinute
                continue
            }
            let span = (change.beat - cursor) * 60 / max(1e-6, beatsPerMinute)
            if elapsed + span > seconds { break }
            elapsed += span
            cursor = change.beat
            beatsPerMinute = change.tempo.beatsPerMinute
        }
        return cursor + (seconds - elapsed) * max(1e-6, beatsPerMinute) / 60
    }

    // MARK: Writing it out

    /// Writes the file. `path` is where it goes, `.mid` by convention.
    public func write(to path: String) throws {
        try data().write(to: URL(fileURLWithPath: path))
    }

    /// The file as bytes, which is what ``write(to:)`` puts down.
    public func data() -> Data {
        var out = Data()
        let chunks = trackChunks()
        out.append(contentsOf: Array("MThd".utf8))
        out.append(uint32: 6)
        out.append(uint16: format.rawValue)
        out.append(uint16: chunks.count)
        out.append(uint16: divisionWord())
        for chunk in chunks {
            out.append(contentsOf: Array("MTrk".utf8))
            out.append(uint32: chunk.count)
            out.append(chunk)
        }
        return out
    }

    /// The division as the two bytes the header carries. A count of ticks in a
    /// quarter note is the number itself; a film rate is a negative frame rate
    /// in the high byte and the ticks in a frame in the low one.
    private func divisionWord() -> Int {
        switch division {
        case .perQuarter(let ticks):
            return min(max(ticks, 1), 0x7FFF)
        case .perSecond(let fps, let ticksPerFrame):
            // 29.97 is written as 29, the one rate whose name is not its number.
            let frames = Int(fps.rounded())
            let high = (256 - min(max(frames, 1), 127)) & 0xFF
            return high << 8 | (min(max(ticksPerFrame, 1), 255) & 0xFF)
        }
    }

    /// How many ticks a beat is worth on the way out. A film-timed file is
    /// written at its own rate, so a beat depends on the tempo where it sits.
    private func ticks(atBeat beat: Double) -> Int {
        switch division {
        case .perQuarter(let ticks):
            return Int((beat * Double(ticks)).rounded())
        case .perSecond:
            guard let perSecond = division.ticksPerSecond else { return 0 }
            return Int((seconds(at: beat) * perSecond).rounded())
        }
    }

    /// The bytes of each track chunk, the meta events on the first.
    private func trackChunks() -> [Data] {
        var chunks: [Data] = []
        var meta = metaEvents()

        switch format {
        case .oneTrack:
            // One chunk holds everything, each part on its own channel. There
            // is one name to be had, so the piece's takes it.
            var events = meta
            let title = name.isEmpty ? (tracks.first?.name ?? "") : name
            if !title.isEmpty { events.append(WritableEvent(tick: 0, order: 0, bytes: metaBytes(3, title))) }
            for track in tracks { events += channelEvents(of: track) }
            chunks.append(chunk(of: events))
        case .parallelTracks, .separatePatterns:
            // The first chunk carries the piece's timing, which is where a
            // sequencer looks for it. It takes the piece's name too.
            if !name.isEmpty { meta.append(WritableEvent(tick: 0, order: 0, bytes: metaBytes(3, name))) }
            chunks.append(chunk(of: meta))
            for track in tracks {
                var events = channelEvents(of: track)
                if !track.name.isEmpty {
                    events.append(WritableEvent(tick: 0, order: 0, bytes: metaBytes(3, track.name)))
                }
                chunks.append(chunk(of: events))
            }
        }
        return chunks
    }

    /// One event on its way into a chunk. `order` settles a tie: at one tick
    /// the meta comes first, then the note that lets go, then anything moved,
    /// then the note that starts, so a note repeated on its own tail is not
    /// cut off by its own ending.
    private struct WritableEvent {
        var tick: Int
        var order: Int
        var bytes: [UInt8]
    }

    private func metaEvents() -> [WritableEvent] {
        var events: [WritableEvent] = []
        for change in tempoChanges {
            let microseconds = Int((60_000_000 / max(1e-6, change.tempo.beatsPerMinute)).rounded())
            let value = min(max(microseconds, 1), 0xFF_FFFF)
            events.append(WritableEvent(
                tick: ticks(atBeat: change.beat), order: 0,
                bytes: [0xFF, 0x51, 0x03,
                        UInt8((value >> 16) & 0xFF), UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)]))
        }
        for signature in timeSignatures {
            let denominator = signature.unit.beats > 0 ? (4 / signature.unit.beats) : 4
            let power = max(0, min(7, Int(log2(max(1, denominator)).rounded())))
            events.append(WritableEvent(
                tick: ticks(atBeat: signature.beat), order: 0,
                bytes: [0xFF, 0x58, 0x04, UInt8(min(max(signature.count, 1), 255)),
                        UInt8(power), 24, 8]))
        }
        for marker in markers {
            events.append(WritableEvent(tick: ticks(atBeat: marker.beat), order: 0,
                                        bytes: metaBytes(6, marker.text)))
        }
        return events
    }

    private func metaBytes(_ type: UInt8, _ text: String) -> [UInt8] {
        let bytes = Array(text.utf8.prefix(0xFF))
        return [0xFF, type] + Data.variableLength(bytes.count) + bytes
    }

    private func channelEvents(of track: Track) -> [WritableEvent] {
        let channel = UInt8(min(max(track.channel, 1), 16) - 1)
        var events: [WritableEvent] = []

        if let program = track.program {
            events.append(WritableEvent(tick: 0, order: 2,
                                        bytes: [0xC0 | channel, UInt8(min(max(program, 0), 127))]))
        }
        for control in track.controls {
            let value = UInt8(min(max((control.value * 127).rounded(), 0), 127))
            events.append(WritableEvent(
                tick: ticks(atBeat: control.beat), order: 2,
                bytes: [0xB0 | channel, UInt8(min(max(control.controller, 0), 127)), value]))
        }
        for bend in track.bends {
            let raw = Int((min(max(bend.position, -1), 1) * 8192).rounded()) + 8192
            let value = min(max(raw, 0), 16383)
            events.append(WritableEvent(
                tick: ticks(atBeat: bend.beat), order: 2,
                bytes: [0xE0 | channel, UInt8(value & 0x7F), UInt8((value >> 7) & 0x7F)]))
        }
        for scheduled in track.notes {
            let note = UInt8(min(max(scheduled.pitch.midi.rounded(), 0), 127))
            // A note-on of zero loudness is how the format spells a note-off,
            // so the quietest note a file can carry is 1.
            let velocity = UInt8(min(max((scheduled.velocity * 127).rounded(), 1), 127))
            let start = ticks(atBeat: scheduled.beat)
            let end = ticks(atBeat: scheduled.beat + scheduled.length.beats)
            events.append(WritableEvent(tick: start, order: 3,
                                        bytes: [0x90 | channel, note, velocity]))
            events.append(WritableEvent(tick: max(start, end), order: 1,
                                        bytes: [0x80 | channel, note, 0]))
        }
        return events
    }

    /// Lays events out in time, writes each one after the wait since the last,
    /// and closes the chunk.
    private func chunk(of events: [WritableEvent]) -> Data {
        var out = Data()
        var previous = 0
        for event in events.sorted(by: { ($0.tick, $0.order) < ($1.tick, $1.order) }) {
            out.append(Data.variableLength(max(0, event.tick - previous)))
            out.append(contentsOf: event.bytes)
            previous = max(previous, event.tick)
        }
        out.append(Data.variableLength(0))
        out.append(contentsOf: [0xFF, 0x2F, 0x00] as [UInt8])
        return out
    }
}

extension Data {

    /// A number as the format writes one: seven bits at a time, most
    /// significant first, every byte but the last carrying its top bit set.
    static func variableLength(_ value: Int) -> Data {
        var remaining = Swift.max(0, value)
        var bytes: [UInt8] = [UInt8(remaining & 0x7F)]
        remaining >>= 7
        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0x7F) | 0x80, at: 0)
            remaining >>= 7
        }
        return Data(bytes)
    }

    mutating func append(uint16 value: Int) {
        append(contentsOf: [UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)] as [UInt8])
    }

    mutating func append(uint32 value: Int) {
        append(contentsOf: [UInt8((value >> 24) & 0xFF), UInt8((value >> 16) & 0xFF),
                            UInt8((value >> 8) & 0xFF), UInt8(value & 0xFF)] as [UInt8])
    }
}
