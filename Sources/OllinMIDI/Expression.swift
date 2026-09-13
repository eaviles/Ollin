import Foundation

/// One of the two zones MIDI Polyphonic Expression divides the sixteen
/// channels into.
///
/// A controller that bends, presses, and slides each note on its own puts
/// every note on a channel of its own, so the channel's pitch bend, pressure,
/// and controller 74 belong to that one note. One channel at the edge, the
/// master, carries what applies to the whole zone. The lower zone runs up from
/// channel 1, the upper down from 16, and most controllers use the lower one
/// alone.
///
/// ```swift
/// midi.mpeZones = [.lower()]          // channel 1 master, 2 to 16 for notes
/// ```
///
/// A controller that announces its layout (the configuration message on its
/// master channel) sets this for you; setting it by hand is for one that does
/// not.
public struct MPEZone: Sendable, Hashable {
    /// The channel the zone's shared messages arrive on: 1 for the lower zone,
    /// 16 for the upper.
    public var masterChannel: Int
    /// The channels the notes arrive on, one note to a channel: the lower zone
    /// counts up from 2, the upper down from 15.
    public var memberChannels: ClosedRange<Int>
    /// How far a full pitch bend on a note's own channel moves it, in
    /// semitones. The specification's default is 48, so a bend can slide a
    /// note across the whole surface.
    public var memberPitchBendRange: Double
    /// How far a full pitch bend on the master channel moves every note in the
    /// zone, in semitones. The specification's default is 2.
    public var masterPitchBendRange: Double

    public init(masterChannel: Int, memberChannels: ClosedRange<Int>,
                memberPitchBendRange: Double = 48, masterPitchBendRange: Double = 2) {
        self.masterChannel = min(max(1, masterChannel), 16)
        let low = min(max(1, memberChannels.lowerBound), 16)
        let high = min(max(low, memberChannels.upperBound), 16)
        self.memberChannels = low...high
        self.memberPitchBendRange = max(0, memberPitchBendRange)
        self.masterPitchBendRange = max(0, masterPitchBendRange)
    }

    /// The lower zone: channel 1 is the master and the notes take the next
    /// `members` channels, 2 up to 16.
    public static func lower(members: Int = 15) -> MPEZone {
        let count = min(max(1, members), 15)
        return MPEZone(masterChannel: 1, memberChannels: 2...(1 + count))
    }

    /// The upper zone: channel 16 is the master and the notes take the
    /// `members` channels below it, 15 down to 1.
    public static func upper(members: Int = 15) -> MPEZone {
        let count = min(max(1, members), 15)
        return MPEZone(masterChannel: 16, memberChannels: (16 - count)...15)
    }

    /// Whether this is the zone that runs up from channel 1.
    public var isLower: Bool { masterChannel == 1 }

    /// How many channels carry notes.
    public var memberCount: Int { memberChannels.count }

    /// Whether the channel is the zone's master or one of its members.
    public func contains(channel: Int) -> Bool {
        channel == masterChannel || memberChannels.contains(channel)
    }

    /// Whether the channel is one a note arrives on.
    public func isMember(channel: Int) -> Bool { memberChannels.contains(channel) }
}

/// A note a `MIDIInput` is holding, with everything the controller has said
/// about it since it started.
///
/// The bend, pressure, and slide are resolved for the note: on a member
/// channel of an [`MPEZone`](MPEZone) they are the channel's own, with the
/// master channel's added on top; on any other channel they are the channel's,
/// which is what a plain keyboard's wheel and aftertouch mean. A key's own
/// pressure (polyphonic aftertouch) counts as its pressure wherever it arrives.
///
/// ```swift
/// for note in midi.heldNotes {
///     drawCircle(x(note.pitch), y(note.slide), 20 + 60 * note.pressure)
/// }
/// ```
public struct HeldNote: Sendable, Hashable, Identifiable {
    /// The key, 0 to 127, as the controller numbers it.
    public let note: Int
    /// The channel the note arrived on, 1 to 16.
    public let channel: Int
    /// How hard it was struck, `0...1`.
    public let velocity: Double
    /// How far it has been bent, in semitones, the channel's range applied.
    public let pitchBend: Double
    /// How hard it is being pressed, `0...1`. Zero until the controller says.
    public let pressure: Double
    /// Where the finger sits along the key, `0...1` (controller 74). Half way
    /// until the controller says.
    public let slide: Double

    /// The note and the channel together, which is what makes a note on a
    /// polyphonic-expression surface one of a kind.
    public var id: Int { channel << 7 | note }

    /// The pitch sounding now, as a MIDI number with the bend folded in.
    public var pitch: Double { Double(note) + pitchBend }
}

/// The state behind `heldNotes`: which keys are down, what each channel's
/// bend, pressure, and controller 74 are, the zones, and the registered
/// parameter the last few control changes have been selecting.
///
/// Pure, so it can be tested with messages alone; the input feeds it under its
/// lock and reads it back on the main thread.
struct ExpressionEngine: Sendable {

    struct Key: Hashable, Sendable {
        let channel: Int
        let note: Int
    }

    private struct Channel: Sendable {
        var bend = 8192
        var pressure = 0
        /// Nil until controller 74 arrives, so a note reads half way rather
        /// than the 64 out of 127 a rounded center would give.
        var slide: Int?
        /// The bend range outside any zone, in semitones.
        var bendRange = 2.0
        /// The registered parameter the data entry that follows will set,
        /// assembled from controllers 101 and 100; nil once a non-registered
        /// one is selected, or after the null parameter.
        var parameter: Int?
        var parameterLow = 0
        var parameterHigh = 0
    }

    private struct Held: Sendable {
        var velocity: Int
        var polyPressure = 0
        var order: Int
    }

    private(set) var zones: [MPEZone] = []
    private var channels = [Channel](repeating: Channel(), count: 17)
    private var held: [Key: Held] = [:]
    private var counter = 0

    /// The registered parameter numbers this reads.
    private static let bendRangeParameter = 0
    private static let configurationParameter = 6

    // MARK: Zones

    /// Replaces the zones, the way a sketch does by hand.
    mutating func setZones(_ zones: [MPEZone]) {
        self.zones = zones
    }

    /// Lays out one zone from its configuration message: `members` channels
    /// beside `master`, or none to take the zone away. The other zone gives
    /// up the channels this one takes.
    private mutating func configure(master: Int, members: Int) {
        zones.removeAll { $0.masterChannel == master }
        guard members > 0 else { return }
        let zone = master == 1 ? MPEZone.lower(members: members) : MPEZone.upper(members: members)
        zones = zones.compactMap { other in
            guard other.masterChannel != master else { return nil }
            // The two zones cannot share a channel: the one being set wins,
            // and the other keeps whatever is left on its own side.
            let taken = zone.memberChannels
            var kept = other
            if other.isLower {
                let high = min(other.memberChannels.upperBound, taken.lowerBound - 1)
                guard high >= other.memberChannels.lowerBound, high < zone.masterChannel else { return nil }
                kept.memberChannels = other.memberChannels.lowerBound...high
            } else {
                let low = max(other.memberChannels.lowerBound, taken.upperBound + 1)
                guard low <= other.memberChannels.upperBound, low > zone.masterChannel else { return nil }
                kept.memberChannels = low...other.memberChannels.upperBound
            }
            return kept
        }
        zones.append(zone)
        zones.sort { $0.masterChannel < $1.masterChannel }
    }

    private func zone(of channel: Int) -> Int? {
        zones.firstIndex { $0.contains(channel: channel) }
    }

    // MARK: Messages

    mutating func apply(_ message: MIDIMessage) {
        let channel = message.channel
        guard (1...16).contains(channel) else { return }
        switch message.kind {
        case .noteOn(let note, let velocity):
            counter += 1
            held[Key(channel: channel, note: note)] = Held(velocity: velocity, order: counter)
        case .noteOff(let note, _):
            held[Key(channel: channel, note: note)] = nil
        case .polyPressure(let note, let pressure):
            held[Key(channel: channel, note: note)]?.polyPressure = pressure
        case .channelPressure(let pressure):
            channels[channel].pressure = pressure
        case .pitchBend(let value):
            channels[channel].bend = value
        case .controlChange(let controller, let value):
            control(controller, value: value, channel: channel)
        default:
            break
        }
    }

    private mutating func control(_ controller: Int, value: Int, channel: Int) {
        switch controller {
        case 74:
            channels[channel].slide = value
        case 101:
            // The registered parameter's high seven bits; selecting one
            // again after a non-registered one.
            channels[channel].parameterHigh = value
            channels[channel].parameter = value == 127 && channels[channel].parameterLow == 127
                ? nil : value << 7 | channels[channel].parameterLow
        case 100:
            channels[channel].parameterLow = value
            channels[channel].parameter = value == 127 && channels[channel].parameterHigh == 127
                ? nil : channels[channel].parameterHigh << 7 | value
        case 99, 98:
            // A non-registered parameter is being selected; the data entry
            // that follows is not ours to read.
            channels[channel].parameter = nil
        case 6:
            dataEntry(value, fine: false, channel: channel)
        case 38:
            dataEntry(value, fine: true, channel: channel)
        case 120, 123:
            // All sound off, all notes off: every key on the channel is up.
            held = held.filter { $0.key.channel != channel }
        case 121:
            // Reset all controllers: the channel's expression, not its layout.
            channels[channel].bend = 8192
            channels[channel].pressure = 0
            channels[channel].slide = nil
        default:
            break
        }
    }

    /// A data entry for whichever registered parameter the channel selected.
    private mutating func dataEntry(_ value: Int, fine: Bool, channel: Int) {
        guard let parameter = channels[channel].parameter else { return }
        switch parameter {
        case Self.configurationParameter:
            // The configuration message means something only on the two
            // channels a master can be, and its fine byte is nothing.
            guard !fine, channel == 1 || channel == 16 else { return }
            configure(master: channel, members: value)
        case Self.bendRangeParameter:
            // Semitones in the coarse byte, cents in the fine one.
            let current = bendRange(channel: channel)
            let semitones = fine ? current.rounded(.down) + Double(value) / 100
                                 : Double(value) + current.truncatingRemainder(dividingBy: 1)
            setBendRange(semitones, channel: channel)
        default:
            break
        }
    }

    /// The range a full bend on the channel spans, in semitones.
    func bendRange(channel: Int) -> Double {
        if let index = zone(of: channel) {
            let zone = zones[index]
            return zone.isMember(channel: channel) ? zone.memberPitchBendRange : zone.masterPitchBendRange
        }
        return channels[channel].bendRange
    }

    /// A bend range set on a member channel is the zone's, for every member;
    /// set on the master it is the master's; elsewhere it is the channel's.
    private mutating func setBendRange(_ semitones: Double, channel: Int) {
        if let index = zone(of: channel) {
            if zones[index].isMember(channel: channel) {
                zones[index].memberPitchBendRange = semitones
            } else {
                zones[index].masterPitchBendRange = semitones
            }
        } else {
            channels[channel].bendRange = semitones
        }
    }

    // MARK: Reading

    func isNoteOn(_ note: Int, channel: Int?) -> Bool {
        if let channel { return held[Key(channel: channel, note: note)] != nil }
        return held.keys.contains { $0.note == note }
    }

    /// Every held note with its expression resolved, oldest first.
    func heldNotes() -> [HeldNote] {
        held.sorted { $0.value.order < $1.value.order }.map { key, state in
            let channel = channels[key.channel]
            var bend = Self.normalized(channel.bend) * bendRange(channel: key.channel)
            var pressure = Double(max(channel.pressure, state.polyPressure)) / 127
            var slide = channel.slide.map { Double($0) / 127 } ?? 0.5
            if let index = zone(of: key.channel), zones[index].isMember(channel: key.channel) {
                // What the master channel says applies to every note in the
                // zone, on top of the note's own.
                let zone = zones[index]
                let master = channels[zone.masterChannel]
                bend += Self.normalized(master.bend) * zone.masterPitchBendRange
                pressure = min(1, pressure + Double(master.pressure) / 127)
                if let masterSlide = master.slide {
                    slide = min(max(0, slide + Double(masterSlide - 64) / 127), 1)
                }
            }
            return HeldNote(note: key.note, channel: key.channel,
                            velocity: Double(state.velocity) / 127,
                            pitchBend: bend, pressure: pressure, slide: slide)
        }
    }

    /// A fourteen-bit bend as a fraction of the range, `-1...1` about 8192.
    private static func normalized(_ bend: Int) -> Double {
        Double(bend - 8192) / 8192
    }
}
