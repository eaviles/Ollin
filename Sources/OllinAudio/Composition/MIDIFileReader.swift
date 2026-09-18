import Foundation
import Ollin

// Reading a Standard MIDI File. The format is chunks: one header saying how
// many tracks there are and what a tick is worth, then a chunk per track of
// events, each preceded by how long to wait since the one before it. The
// waits are counted in ticks and written seven bits at a time; turning them
// into beats needs the header's division and, for a file timed to film, the
// tempo map as well, which is why the whole file is read into ticks first and
// converted afterwards.
extension MIDIFile {

    /// What stopped a file being read, and where.
    public struct ReadError: Error, Equatable, Sendable, CustomStringConvertible {
        /// How far into the file the trouble was, in bytes, where that is
        /// known.
        public let offset: Int?
        /// What went wrong, in a sentence.
        public let problem: String

        init(offset: Int?, problem: String) {
            self.offset = offset
            self.problem = problem
        }

        public var description: String {
            guard let offset else { return problem }
            return "byte \(offset): \(problem)"
        }
    }

    /// The music in a `.mid` file on disk. Throws a ``ReadError`` naming the
    /// byte that stopped it.
    public init(contentsOf path: String) throws {
        guard let data = FileManager.default.contents(atPath: path) else {
            throw ReadError(offset: nil, problem: "no file at \(path)")
        }
        try self.init(data: data)
    }

    /// The music in a bundled `.mid` file.
    ///
    /// `in:` has no default on purpose: a default would resolve to Ollin's own
    /// bundle rather than the caller's. Pass `.module` from your sketch.
    public init(resource: String, withExtension ext: String? = "mid", in bundle: Bundle) throws {
        guard let url = bundle.url(forResource: resource, withExtension: ext) else {
            throw ReadError(offset: nil, problem: "no resource named \(resource) in the bundle")
        }
        try self.init(contentsOf: url.path)
    }

    /// The music in the bytes of a `.mid` file.
    public init(data: Data) throws {
        var reader = MIDIByteReader(bytes: [UInt8](data))

        guard try reader.text(4) == "MThd" else {
            throw ReadError(offset: 0, problem: "not a MIDI file (it does not open with MThd)")
        }
        let headerLength = try reader.uint32()
        guard headerLength >= 6 else {
            throw ReadError(offset: 4, problem: "the header says it holds \(headerLength) bytes, and it needs 6")
        }
        let formatNumber = try reader.uint16()
        _ = try reader.uint16()   // The track count; the chunks that follow are what is read.
        let divisionWord = try reader.uint16()
        // A header may be longer than the three fields this format defines.
        try reader.skip(headerLength - 6)

        guard let format = Format(rawValue: formatNumber) else {
            throw ReadError(offset: 8, problem: "format \(formatNumber) is not one this reads (0, 1, or 2)")
        }
        let division = try MIDIFile.division(fromWord: divisionWord, at: 12)

        // Every chunk is read into ticks first: a tempo change anywhere in the
        // file moves the beats of every track, so nothing can be converted
        // until all of them are in.
        var chunks: [RawTrack] = []
        while !reader.isAtEnd {
            let mark = reader.index
            let identifier = try reader.text(4)
            let length = try reader.uint32()
            guard identifier == "MTrk" else {
                // A chunk this does not know is stepped over by its own length,
                // which is what the format says to do with one.
                try reader.skip(length)
                continue
            }
            guard reader.index + length <= reader.bytes.count else {
                throw ReadError(offset: mark, problem: "the track says it holds \(length) bytes and the file ends first")
            }
            let end = reader.index + length
            chunks.append(try MIDIFile.readTrack(&reader, until: end))
            reader.index = end
        }

        let clock = TickClock(division: division, tempos: chunks.flatMap(\.tempos).sorted { $0.tick < $1.tick })

        self.init(format: format, division: division)
        self.name = chunks.first?.name ?? ""
        self.tempoChanges = clock.tempos.map {
            TempoChange(beat: clock.beat(at: $0.tick), tempo: Tempo(60_000_000 / Double(max(1, $0.microseconds))))
        }
        self.timeSignatures = chunks.flatMap(\.signatures).map {
            TimeSignature(beat: clock.beat(at: $0.tick), count: $0.count,
                          unit: NoteLength(beats: 4 / pow(2, Double($0.power))))
        }.sorted { $0.beat < $1.beat }
        self.markers = chunks.flatMap(\.markers).map {
            Marker(beat: clock.beat(at: $0.tick), text: $0.text)
        }.sorted { $0.beat < $1.beat }

        var tracks: [Track] = []
        for (index, chunk) in chunks.enumerated() {
            // The first chunk of a file laid out in parallel tracks carries the
            // timing rather than a part, by convention, and is empty of notes.
            // It has been read for its tempo map already; keeping it would add
            // a part that plays nothing.
            if index == 0, format != .oneTrack, chunk.isEmptyOfMusic { continue }
            tracks += chunk.tracks(clock: clock)
        }
        self.tracks = tracks
    }

    /// What the header's last two bytes say a tick is worth.
    private static func division(fromWord word: Int, at offset: Int) throws -> Division {
        guard word & 0x8000 != 0 else {
            guard word > 0 else {
                throw ReadError(offset: offset, problem: "the header puts no ticks in a quarter note")
            }
            return .perQuarter(word)
        }
        // A film-timed file writes a negative frame rate in the high byte.
        let frames = 256 - ((word >> 8) & 0xFF)
        let ticksPerFrame = word & 0xFF
        guard ticksPerFrame > 0 else {
            throw ReadError(offset: offset, problem: "the header puts no ticks in a frame")
        }
        // 29 names the 29.97 of broadcast, the one rate that is not its number.
        let rate: Double = frames == 29 ? 30_000.0 / 1001.0 : Double(frames)
        guard rate > 0 else {
            throw ReadError(offset: offset, problem: "the header names no frame rate")
        }
        return .perSecond(framesPerSecond: rate, ticksPerFrame: ticksPerFrame)
    }

    // MARK: One chunk, in ticks

    /// A tempo change where the file puts it.
    struct RawTempo { var tick: Int; var microseconds: Int }
    struct RawSignature { var tick: Int; var count: Int; var power: Int }
    struct RawMarker { var tick: Int; var text: String }
    /// A note whose ending has been found.
    struct RawNote { var tick: Int; var end: Int; var channel: Int; var note: Int; var velocity: Int }
    struct RawControl { var tick: Int; var channel: Int; var controller: Int; var value: Int }
    struct RawBend { var tick: Int; var channel: Int; var value: Int }

    /// One track chunk as the file wrote it, before any of it is in beats.
    struct RawTrack {
        var name = ""
        var notes: [RawNote] = []
        var controls: [RawControl] = []
        var bends: [RawBend] = []
        var programs: [Int: Int] = [:]
        var tempos: [RawTempo] = []
        var signatures: [RawSignature] = []
        var markers: [RawMarker] = []
        /// The order the channels first played, so the parts come out in the
        /// order the file introduced them rather than by number.
        var channelOrder: [Int] = []

        var isEmptyOfMusic: Bool { notes.isEmpty && controls.isEmpty && bends.isEmpty && programs.isEmpty }

        mutating func sawChannel(_ channel: Int) {
            if !channelOrder.contains(channel) { channelOrder.append(channel) }
        }

        /// The chunk as one part per channel, in beats.
        func tracks(clock: TickClock) -> [Track] {
            channelOrder.map { channel in
                var index = 0
                let notes: [ScheduledNote] = self.notes.filter { $0.channel == channel }.map { raw in
                    let beat = clock.beat(at: raw.tick)
                    let note = Note(Pitch(Double(raw.note)),
                                    velocity: Double(raw.velocity) / 127,
                                    length: NoteLength(beats: max(0, clock.beat(at: raw.end) - beat)))
                    defer { index += 1 }
                    return ScheduledNote(note, beat: beat, step: index)
                }
                let controls = self.controls.filter { $0.channel == channel }.map {
                    ControlChange(beat: clock.beat(at: $0.tick), controller: $0.controller,
                                  value: Double($0.value) / 127)
                }
                let bends = self.bends.filter { $0.channel == channel }.map {
                    PitchBend(beat: clock.beat(at: $0.tick), position: Double($0.value - 8192) / 8192)
                }
                return Track(notes, name: name, channel: channel + 1,
                             program: programs[channel], controls: controls, bends: bends)
            }
        }
    }

    /// Walks one track chunk, pairing every note that starts with the one that
    /// lets it go.
    private static func readTrack(_ reader: inout MIDIByteReader, until end: Int) throws -> RawTrack {
        var track = RawTrack()
        var tick = 0
        var status: UInt8 = 0
        // A note may be struck again before the first is released, so each
        // pitch holds a queue and a release takes the oldest, which is the one
        // that has been sounding longest.
        var sounding: [Int: [(tick: Int, velocity: Int)]] = [:]

        func release(channel: Int, note: Int, at tick: Int) {
            let key = channel << 8 | note
            guard var queue = sounding[key], !queue.isEmpty else { return }
            let started = queue.removeFirst()
            sounding[key] = queue.isEmpty ? nil : queue
            track.notes.append(RawNote(tick: started.tick, end: tick, channel: channel,
                                       note: note, velocity: started.velocity))
        }

        while reader.index < end {
            tick += try reader.variableLength()
            var byte = try reader.byte()

            if byte == 0xFF {
                let type = try reader.byte()
                let length = try reader.variableLength()
                // Taken as its own array: a slice of the file keeps the
                // file's own indices, and this reads the payload from 0.
                let payload = Array(try reader.take(length))
                switch type {
                case 0x03 where track.name.isEmpty:
                    track.name = String(decoding: payload, as: UTF8.self)
                case 0x06:
                    track.markers.append(RawMarker(tick: tick, text: String(decoding: payload, as: UTF8.self)))
                case 0x51 where payload.count >= 3:
                    let value = Int(payload[0]) << 16 | Int(payload[1]) << 8 | Int(payload[2])
                    track.tempos.append(RawTempo(tick: tick, microseconds: value))
                case 0x58 where payload.count >= 2:
                    track.signatures.append(RawSignature(tick: tick, count: Int(payload[0]),
                                                         power: Int(payload[1])))
                case 0x2F:
                    // End of track. Anything still sounding is let go here.
                    reader.index = end
                    for (key, queue) in sounding {
                        for started in queue {
                            track.notes.append(RawNote(tick: started.tick, end: tick,
                                                       channel: key >> 8, note: key & 0xFF,
                                                       velocity: started.velocity))
                        }
                        sounding[key] = nil
                    }
                default:
                    break   // A meta event this does not model, read and stepped over.
                }
                // Anything but a channel message ends the run a status byte was
                // standing in for.
                status = 0
                continue
            }

            if byte == 0xF0 || byte == 0xF7 {
                // A system-exclusive block: read by its own length and skipped.
                let length = try reader.variableLength()
                try reader.skip(length)
                status = 0
                continue
            }

            if byte < 0x80 {
                // Running status: the message repeats the last one's kind, and
                // this byte is already its first piece of data.
                guard status >= 0x80 else {
                    throw ReadError(offset: reader.index - 1,
                                    problem: "a message with no kind, and none before it to borrow")
                }
                reader.index -= 1
                byte = status
            } else {
                status = byte
            }

            let channel = Int(byte & 0x0F)
            switch byte & 0xF0 {
            case 0x80:
                let note = Int(try reader.byte())
                _ = try reader.byte()
                release(channel: channel, note: note, at: tick)
                track.sawChannel(channel)
            case 0x90:
                let note = Int(try reader.byte())
                let velocity = Int(try reader.byte())
                track.sawChannel(channel)
                if velocity == 0 {
                    // The format's other spelling of a note let go.
                    release(channel: channel, note: note, at: tick)
                } else {
                    sounding[channel << 8 | note, default: []].append((tick: tick, velocity: velocity))
                }
            case 0xB0:
                let controller = Int(try reader.byte())
                let value = Int(try reader.byte())
                track.controls.append(RawControl(tick: tick, channel: channel,
                                                 controller: controller, value: value))
                track.sawChannel(channel)
            case 0xC0:
                let program = Int(try reader.byte())
                if track.programs[channel] == nil { track.programs[channel] = program }
                track.sawChannel(channel)
            case 0xE0:
                let low = Int(try reader.byte())
                let high = Int(try reader.byte())
                track.bends.append(RawBend(tick: tick, channel: channel, value: high << 7 | low))
                track.sawChannel(channel)
            case 0xA0, 0xD0:
                // Aftertouch, read and stepped over.
                try reader.skip((byte & 0xF0) == 0xA0 ? 2 : 1)
            default:
                throw ReadError(offset: reader.index - 1,
                                problem: "a message kind this does not read (0x\(String(byte, radix: 16)))")
            }
        }

        // A chunk that ends without saying so still lets its notes go.
        for (key, queue) in sounding {
            for started in queue {
                track.notes.append(RawNote(tick: started.tick, end: tick,
                                           channel: key >> 8, note: key & 0xFF,
                                           velocity: started.velocity))
            }
        }
        track.notes.sort { ($0.tick, $0.note) < ($1.tick, $1.note) }
        return track
    }

    /// Turns a tick into a beat.
    ///
    /// Where a tick is a fraction of a quarter note that is all it takes. A
    /// file timed to film counts ticks against the clock instead, so a tick is
    /// a fixed number of seconds and the beat it lands on depends on every
    /// tempo change before it: the map is walked once here and each change
    /// remembers the beat it starts at.
    struct TickClock {
        let division: Division
        let tempos: [RawTempo]
        private var marks: [(tick: Int, beat: Double, seconds: Double, beatsPerMinute: Double)] = []

        init(division: Division, tempos: [RawTempo]) {
            self.division = division
            self.tempos = tempos
            guard let ticksPerSecond = division.ticksPerSecond else { return }
            var mark = (tick: 0, beat: 0.0, seconds: 0.0, beatsPerMinute: 120.0)
            marks.append(mark)
            for tempo in tempos {
                let seconds = Double(tempo.tick) / ticksPerSecond
                let beat = mark.beat + (seconds - mark.seconds) * mark.beatsPerMinute / 60
                mark = (tick: tempo.tick, beat: beat, seconds: seconds,
                        beatsPerMinute: 60_000_000 / Double(max(1, tempo.microseconds)))
                marks.append(mark)
            }
        }

        func beat(at tick: Int) -> Double {
            switch division {
            case .perQuarter(let ticksPerQuarter):
                return Double(tick) / Double(max(1, ticksPerQuarter))
            case .perSecond:
                guard let ticksPerSecond = division.ticksPerSecond else { return 0 }
                let seconds = Double(tick) / ticksPerSecond
                var mark = marks[0]
                for candidate in marks where candidate.tick <= tick { mark = candidate }
                return mark.beat + (seconds - mark.seconds) * mark.beatsPerMinute / 60
            }
        }
    }
}

/// Walks the bytes of a file, refusing to read past its end.
struct MIDIByteReader {
    let bytes: [UInt8]
    var index = 0

    var isAtEnd: Bool { index >= bytes.count }

    mutating func byte() throws -> UInt8 {
        guard index < bytes.count else {
            throw MIDIFile.ReadError(offset: index, problem: "the file ends in the middle of a message")
        }
        defer { index += 1 }
        return bytes[index]
    }

    mutating func take(_ count: Int) throws -> ArraySlice<UInt8> {
        guard count >= 0, index + count <= bytes.count else {
            throw MIDIFile.ReadError(offset: index, problem: "the file ends before \(count) bytes it promised")
        }
        defer { index += count }
        return bytes[index ..< index + count]
    }

    mutating func skip(_ count: Int) throws {
        _ = try take(count)
    }

    mutating func text(_ count: Int) throws -> String {
        String(decoding: try take(count), as: UTF8.self)
    }

    mutating func uint16() throws -> Int {
        Int(try byte()) << 8 | Int(try byte())
    }

    mutating func uint32() throws -> Int {
        var value = 0
        for _ in 0 ..< 4 { value = value << 8 | Int(try byte()) }
        return value
    }

    /// A number written seven bits at a time, every byte but the last carrying
    /// its top bit set. Four bytes is the format's limit.
    mutating func variableLength() throws -> Int {
        var value = 0
        for _ in 0 ..< 4 {
            let byte = try self.byte()
            value = value << 7 | Int(byte & 0x7F)
            if byte & 0x80 == 0 { return value }
        }
        throw MIDIFile.ReadError(offset: index, problem: "a number running past the four bytes the format allows")
    }
}
