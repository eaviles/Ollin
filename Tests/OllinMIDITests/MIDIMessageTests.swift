import Foundation
import Testing
@testable import OllinMIDI

/// Format correctness for the MIDI 1.0 message parser/encoder: every message kind
/// parses from its status+data bytes and from a Universal MIDI Packet word, the
/// encoders round-trip, and malformed or unmodeled input returns `nil` rather than
/// trapping. No Core MIDI, no GPU, so these run everywhere including CI.
@Suite
struct MIDIMessageTests {

    // MARK: Parsing channel-voice messages from bytes

    @Test func parsesNoteOn() {
        let message = MIDIMessage(status: 0x90, data1: 60, data2: 100)
        #expect(message == MIDIMessage(.noteOn(note: 60, velocity: 100), channel: 1))
        #expect(message?.note == 60)
        #expect(message?.velocity == 100)
        #expect(message?.isNoteOn == true)
    }

    @Test func parsesNoteOff() {
        #expect(MIDIMessage(status: 0x80, data1: 60, data2: 0)
            == MIDIMessage(.noteOff(note: 60, velocity: 0), channel: 1))
    }

    /// A note-on with velocity 0 is the common "note-off" — normalized to one.
    @Test func noteOnVelocityZeroBecomesNoteOff() {
        let message = MIDIMessage(status: 0x90, data1: 64, data2: 0)
        #expect(message == MIDIMessage(.noteOff(note: 64, velocity: 0), channel: 1))
        #expect(message?.isNoteOff == true)
    }

    @Test func parsesControlChange() {
        let message = MIDIMessage(status: 0xB0, data1: 7, data2: 64)
        #expect(message == MIDIMessage(.controlChange(controller: 7, value: 64), channel: 1))
        #expect(message?.controller == 7)
        #expect(message?.value == 64)
    }

    @Test func parsesProgramAndPressure() {
        #expect(MIDIMessage(status: 0xC0, data1: 5)
            == MIDIMessage(.programChange(program: 5), channel: 1))
        #expect(MIDIMessage(status: 0xD0, data1: 90)
            == MIDIMessage(.channelPressure(pressure: 90), channel: 1))
        #expect(MIDIMessage(status: 0xA0, data1: 60, data2: 80)
            == MIDIMessage(.polyPressure(note: 60, pressure: 80), channel: 1))
    }

    /// Pitch bend packs its 14-bit value as LSB-then-MSB; 0/64 is dead center.
    @Test func parsesPitchBendCenter() {
        let message = MIDIMessage(status: 0xE0, data1: 0, data2: 64)
        #expect(message == MIDIMessage(.pitchBend(value: 8192), channel: 1))
    }

    /// The low status nibble is the channel, surfaced as 1…16.
    @Test func decodesChannel() {
        #expect(MIDIMessage(status: 0x95, data1: 60, data2: 100)?.channel == 6)
        #expect(MIDIMessage(status: 0xBF, data1: 1, data2: 1)?.channel == 16)
    }

    // MARK: System real-time

    @Test func parsesTransportAndClock() {
        #expect(MIDIMessage(status: 0xF8) == MIDIMessage(.clock))
        #expect(MIDIMessage(status: 0xFA) == MIDIMessage(.start))
        #expect(MIDIMessage(status: 0xFB) == MIDIMessage(.continue))
        #expect(MIDIMessage(status: 0xFC) == MIDIMessage(.stop))
        #expect(MIDIMessage(status: 0xF8)?.channel == 0)   // system: no channel
    }

    /// Song position packs its 14-bit sixteenth-note count LSB-first.
    @Test func parsesSongPosition() {
        #expect(MIDIMessage(status: 0xF2, data1: 0x02, data2: 0x01)
            == MIDIMessage(.songPosition(sixteenths: 130)))
        #expect(MIDIMessage(status: 0xF2)?.kind == .songPosition(sixteenths: 0))
    }

    // MARK: Rejecting what isn't modeled

    @Test func rejectsBareDataByteAndUnmodeledSystem() {
        #expect(MIDIMessage(status: 0x40, data1: 0, data2: 0) == nil)   // a data byte, not a status
        #expect(MIDIMessage(status: 0xF0) == nil)   // SysEx start
        #expect(MIDIMessage(status: 0xF1, data1: 1) == nil)   // MIDI time code
        #expect(MIDIMessage(status: 0xF6) == nil)   // tune request
        #expect(MIDIMessage(status: 0xFE) == nil)   // active sensing
    }

    // MARK: Universal MIDI Packet words

    @Test func parsesUMPChannelVoiceWord() {
        // mt 0x2, group 0, status 0x90, note 60, velocity 100.
        let word: UInt32 = (0x2 << 28) | (0x90 << 16) | (60 << 8) | 100
        #expect(MIDIMessage(umpWord: word) == MIDIMessage(.noteOn(note: 60, velocity: 100), channel: 1))
    }

    @Test func parsesUMPSystemWord() {
        let word: UInt32 = (0x1 << 28) | (0xF8 << 16)   // mt 0x1, clock
        #expect(MIDIMessage(umpWord: word) == MIDIMessage(.clock))
    }

    @Test func rejectsNonMIDI1WordTypes() {
        #expect(MIDIMessage(umpWord: 0x0 << 28) == nil)   // utility
        #expect(MIDIMessage(umpWord: 0x3 << 28) == nil)   // data / SysEx
        #expect(MIDIMessage(umpWord: 0x4 << 28) == nil)   // MIDI 2.0 channel voice
    }

    // MARK: Encoding round-trips

    /// Every channel-voice and system message survives bytes → parse and
    /// UMP-word → parse unchanged.
    @Test func encodeRoundTrips() {
        let messages: [MIDIMessage] = [
            MIDIMessage(.noteOn(note: 60, velocity: 100), channel: 1),
            MIDIMessage(.noteOff(note: 48, velocity: 20), channel: 10),
            MIDIMessage(.controlChange(controller: 74, value: 96), channel: 3),
            MIDIMessage(.programChange(program: 12), channel: 16),
            MIDIMessage(.channelPressure(pressure: 55), channel: 2),
            MIDIMessage(.polyPressure(note: 64, pressure: 33), channel: 4),
            MIDIMessage(.pitchBend(value: 8192), channel: 5),
            MIDIMessage(.pitchBend(value: 0), channel: 5),
            MIDIMessage(.pitchBend(value: 16383), channel: 5),
            MIDIMessage(.clock), MIDIMessage(.start), MIDIMessage(.stop), MIDIMessage(.continue),
            MIDIMessage(.songPosition(sixteenths: 0)),
            MIDIMessage(.songPosition(sixteenths: 130)),
            MIDIMessage(.songPosition(sixteenths: 16383)),
        ]
        for message in messages {
            let (status, data1, data2) = message.bytes
            #expect(MIDIMessage(status: status, data1: data1, data2: data2) == message)
            #expect(MIDIMessage(umpWord: message.umpWord) == message)
        }
    }

    /// Out-of-range channel and data clamp into the legal MIDI ranges.
    @Test func encodingClamps() {
        let (status, data1, data2) = MIDIMessage(.controlChange(controller: 200, value: 999), channel: 99).bytes
        #expect(status == 0xBF)   // channel clamped to 16 → nibble 0x0F
        #expect(data1 == 127)
        #expect(data2 == 127)

        let (_, lsb, msb) = MIDIMessage(.songPosition(sixteenths: 99_999)).bytes
        #expect(Int(lsb) | (Int(msb) << 7) == 16383)   // clamped to the 14-bit ceiling
    }
}
