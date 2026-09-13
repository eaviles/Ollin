import Foundation
import Testing
@testable import OllinMIDI

/// The state behind `heldNotes`, driven with messages alone: which channel's
/// bend, pressure, and slide belong to which note, what a zone changes, and
/// how a controller lays a zone out over the wire.
@Suite struct MIDIExpressionTests {

    func message(_ kind: MIDIMessage.Kind, channel: Int) -> MIDIMessage {
        MIDIMessage(kind, channel: channel)
    }

    /// The five control changes a registered parameter takes.
    func registered(_ parameter: Int, value: Int, fine: Int = 0, channel: Int,
                    into engine: inout ExpressionEngine) {
        engine.apply(message(.controlChange(controller: 101, value: parameter >> 7), channel: channel))
        engine.apply(message(.controlChange(controller: 100, value: parameter & 0x7F), channel: channel))
        engine.apply(message(.controlChange(controller: 6, value: value), channel: channel))
        engine.apply(message(.controlChange(controller: 38, value: fine), channel: channel))
        engine.apply(message(.controlChange(controller: 101, value: 127), channel: channel))
        engine.apply(message(.controlChange(controller: 100, value: 127), channel: channel))
    }

    @Test func zonesLayOutTheirChannels() {
        let lower = MPEZone.lower()
        #expect(lower.masterChannel == 1)
        #expect(lower.memberChannels == 2...16)
        #expect(lower.memberCount == 15)
        #expect(lower.isLower)
        #expect(lower.contains(channel: 1) && lower.contains(channel: 16) && lower.isMember(channel: 9))
        #expect(!lower.isMember(channel: 1))

        let upper = MPEZone.upper(members: 3)
        #expect(upper.masterChannel == 16)
        #expect(upper.memberChannels == 13...15)
        #expect(!upper.isLower)
        #expect(!upper.contains(channel: 12))

        // A zone always has at least one member and never more than fifteen.
        #expect(MPEZone.lower(members: 0).memberChannels == 2...2)
        #expect(MPEZone.lower(members: 40).memberChannels == 2...16)
        #expect(MPEZone.lower().memberPitchBendRange == 48)
        #expect(MPEZone.lower().masterPitchBendRange == 2)
    }

    /// With no zone a channel's wheel, aftertouch, and controller 74 belong
    /// to every note on it, and a key's own pressure to that key alone.
    @Test func aPlainKeyboardSharesItsChannel() {
        var engine = ExpressionEngine()
        engine.apply(message(.noteOn(note: 60, velocity: 127), channel: 1))
        engine.apply(message(.noteOn(note: 64, velocity: 64), channel: 1))

        var notes = engine.heldNotes()
        #expect(notes.map(\.note) == [60, 64])
        #expect(notes[0].velocity == 1)
        #expect(abs(notes[1].velocity - 64.0 / 127) < 1e-9)
        #expect(notes.allSatisfy { $0.pitchBend == 0 && $0.pressure == 0 && $0.slide == 0.5 })

        engine.apply(message(.pitchBend(value: 8192 + 4096), channel: 1))   // half the range
        engine.apply(message(.channelPressure(pressure: 127), channel: 1))
        engine.apply(message(.controlChange(controller: 74, value: 127), channel: 1))
        notes = engine.heldNotes()
        #expect(notes.allSatisfy { abs($0.pitchBend - 1) < 1e-9 })   // half of two semitones
        #expect(notes.allSatisfy { $0.pressure == 1 && $0.slide == 1 })
        #expect(abs(notes[0].pitch - 61) < 1e-9)

        // A key's own pressure is its own.
        engine.apply(message(.channelPressure(pressure: 0), channel: 1))
        engine.apply(message(.polyPressure(note: 64, pressure: 127), channel: 1))
        notes = engine.heldNotes()
        #expect(notes[0].pressure == 0)
        #expect(notes[1].pressure == 1)

        // Another channel's wheel is not this channel's.
        engine.apply(message(.pitchBend(value: 0), channel: 2))
        #expect(engine.heldNotes().allSatisfy { abs($0.pitchBend - 1) < 1e-9 })
    }

    /// In a zone each member channel's bend, pressure, and slide are one
    /// note's, the master channel's ride on top of every note, and a member's
    /// bend spans the wide range.
    @Test func aZoneGivesEachNoteItsOwn() {
        var engine = ExpressionEngine()
        engine.setZones([.lower()])
        engine.apply(message(.noteOn(note: 60, velocity: 100), channel: 2))
        engine.apply(message(.noteOn(note: 64, velocity: 100), channel: 3))

        engine.apply(message(.pitchBend(value: 16383), channel: 2))
        engine.apply(message(.channelPressure(pressure: 127), channel: 3))
        engine.apply(message(.controlChange(controller: 74, value: 0), channel: 2))
        var notes = engine.heldNotes()
        #expect(abs(notes[0].pitchBend - 48 * 8191.0 / 8192) < 1e-9)
        #expect(notes[1].pitchBend == 0)
        #expect(notes[0].pressure == 0)
        #expect(notes[1].pressure == 1)
        #expect(notes[0].slide == 0)
        #expect(notes[1].slide == 0.5)

        // The master channel speaks to the whole zone.
        engine.apply(message(.pitchBend(value: 8192 + 4096), channel: 1))    // one semitone of two
        engine.apply(message(.channelPressure(pressure: 64), channel: 1))
        engine.apply(message(.controlChange(controller: 74, value: 64 + 32), channel: 1))
        notes = engine.heldNotes()
        #expect(abs(notes[0].pitchBend - (48 * 8191.0 / 8192 + 1)) < 1e-9)
        #expect(abs(notes[1].pitchBend - 1) < 1e-9)
        #expect(abs(notes[0].pressure - 64.0 / 127) < 1e-9)
        #expect(notes[1].pressure == 1)                                       // held at the top
        #expect(abs(notes[0].slide - 32.0 / 127) < 1e-9)
        #expect(abs(notes[1].slide - (0.5 + 32.0 / 127)) < 1e-9)

        // A note on a channel outside the zone reads its own channel plainly.
        engine.setZones([.lower(members: 4)])
        engine.apply(message(.noteOn(note: 70, velocity: 100), channel: 9))
        engine.apply(message(.pitchBend(value: 16383), channel: 9))
        let outside = engine.heldNotes().first { $0.channel == 9 }
        #expect(abs((outside?.pitchBend ?? 0) - 2 * 8191.0 / 8192) < 1e-9)
    }

    /// The configuration message lays a zone out, takes it away, and the
    /// other zone gives up the channels it takes.
    @Test func theConfigurationMessageLaysOutTheZone() {
        var engine = ExpressionEngine()
        registered(6, value: 7, channel: 1, into: &engine)
        #expect(engine.zones == [.lower(members: 7)])

        registered(6, value: 4, channel: 16, into: &engine)
        #expect(engine.zones == [.lower(members: 7), .upper(members: 4)])

        // The lower zone grows into the upper's channels, and the upper keeps
        // what is left on its side.
        registered(6, value: 13, channel: 1, into: &engine)
        #expect(engine.zones.count == 2)
        #expect(engine.zones[0] == .lower(members: 13))
        #expect(engine.zones[1].masterChannel == 16)
        #expect(engine.zones[1].memberChannels == 15...15)

        // All fifteen on one side leaves nothing for the other.
        registered(6, value: 15, channel: 16, into: &engine)
        #expect(engine.zones == [.upper(members: 15)])

        // Zero members is the zone off.
        registered(6, value: 0, channel: 16, into: &engine)
        #expect(engine.zones.isEmpty)

        // The message means nothing on a channel that cannot be a master.
        registered(6, value: 5, channel: 4, into: &engine)
        #expect(engine.zones.isEmpty)
    }

    /// The bend range arrives as a registered parameter: a channel's own
    /// outside a zone, the whole zone's members' from any member, and the
    /// master's from the master.
    @Test func theBendRangeArrives() {
        var engine = ExpressionEngine()
        registered(0, value: 12, fine: 50, channel: 1, into: &engine)
        #expect(abs(engine.bendRange(channel: 1) - 12.5) < 1e-9)
        #expect(engine.bendRange(channel: 2) == 2)

        engine.apply(message(.noteOn(note: 60, velocity: 100), channel: 1))
        engine.apply(message(.pitchBend(value: 16383), channel: 1))
        #expect(abs(engine.heldNotes()[0].pitchBend - 12.5 * 8191.0 / 8192) < 1e-9)

        engine.setZones([.lower()])
        registered(0, value: 24, channel: 5, into: &engine)
        #expect(engine.zones[0].memberPitchBendRange == 24)
        #expect(engine.bendRange(channel: 2) == 24)
        registered(0, value: 4, channel: 1, into: &engine)
        #expect(engine.zones[0].masterPitchBendRange == 4)
        #expect(engine.zones[0].memberPitchBendRange == 24)
    }

    /// A data entry for a parameter that was not selected, or that was
    /// selected as a non-registered one, sets nothing.
    @Test func onlyASelectedRegisteredParameterIsRead() {
        var engine = ExpressionEngine()
        engine.apply(message(.controlChange(controller: 6, value: 5), channel: 1))
        #expect(engine.zones.isEmpty)
        #expect(engine.bendRange(channel: 1) == 2)

        engine.apply(message(.controlChange(controller: 99, value: 0), channel: 1))
        engine.apply(message(.controlChange(controller: 98, value: 6), channel: 1))
        engine.apply(message(.controlChange(controller: 6, value: 5), channel: 1))
        #expect(engine.zones.isEmpty)

        // Selecting the registered one again after that reads it.
        engine.apply(message(.controlChange(controller: 101, value: 0), channel: 1))
        engine.apply(message(.controlChange(controller: 100, value: 6), channel: 1))
        engine.apply(message(.controlChange(controller: 6, value: 5), channel: 1))
        #expect(engine.zones == [.lower(members: 5)])
    }

    /// The channel-mode messages a controller sends when everything lets go.
    @Test func aChannelCanBeClearedAndReset() {
        var engine = ExpressionEngine()
        engine.apply(message(.noteOn(note: 60, velocity: 100), channel: 1))
        engine.apply(message(.noteOn(note: 62, velocity: 100), channel: 2))
        engine.apply(message(.controlChange(controller: 123, value: 0), channel: 1))
        #expect(engine.heldNotes().map(\.note) == [62])
        #expect(!engine.isNoteOn(60, channel: nil))
        #expect(engine.isNoteOn(62, channel: 2))
        #expect(!engine.isNoteOn(62, channel: 1))

        engine.apply(message(.pitchBend(value: 0), channel: 2))
        engine.apply(message(.channelPressure(pressure: 90), channel: 2))
        engine.apply(message(.controlChange(controller: 74, value: 10), channel: 2))
        engine.apply(message(.controlChange(controller: 121, value: 0), channel: 2))
        let note = engine.heldNotes()[0]
        #expect(note.pitchBend == 0 && note.pressure == 0 && note.slide == 0.5)
    }

    /// Notes come oldest first, a note struck again keeps its place at the
    /// back, and the note and its channel together are its identity.
    @Test func heldNotesComeOldestFirst() {
        var engine = ExpressionEngine()
        engine.apply(message(.noteOn(note: 64, velocity: 100), channel: 3))
        engine.apply(message(.noteOn(note: 60, velocity: 100), channel: 2))
        engine.apply(message(.noteOn(note: 60, velocity: 100), channel: 5))
        #expect(engine.heldNotes().map(\.channel) == [3, 2, 5])
        engine.apply(message(.noteOff(note: 64, velocity: 0), channel: 3))
        engine.apply(message(.noteOn(note: 64, velocity: 100), channel: 3))
        let notes = engine.heldNotes()
        #expect(notes.map(\.channel) == [2, 5, 3])
        #expect(Set(notes.map(\.id)).count == 3)
        #expect(notes[0].id != notes[1].id)
    }
}
