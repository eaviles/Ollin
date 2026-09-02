import Foundation

/// A single MIDI message: a `kind` (what happened) plus the `channel` it arrived
/// on. This is the unit a sketch reads from a `MIDIInput` and sends through a
/// `MIDIOutput`.
///
/// The everyday ones are notes and control changes: a key pressed, a parameter
/// turned:
///
/// ```swift
/// switch message.kind {
/// case .noteOn(let note, let velocity):     trigger(note, velocity)
/// case .controlChange(let cc, let value):   knobs[cc] = value
/// default: break
/// }
/// ```
///
/// The convenience accessors keep the common reads terse — `message.note`,
/// `message.velocity`, `message.controller`, `message.value` — so most sketches
/// never switch on `kind` directly.
///
/// Channels are numbered **1…16** the way a DAW or a controller labels them (the
/// wire uses 0…15; the conversion happens at the Core MIDI boundary). System
/// messages (`clock`/`start`/`stop`/`continue`/`songPosition`) carry no channel
/// and report `0`.
public struct MIDIMessage: Sendable, Equatable {

    /// What the message says. Channel-voice cases carry their data; the
    /// system-real-time cases are bare.
    public enum Kind: Sendable, Equatable {
        /// A key (or pad) pressed. `velocity` is the strike strength, 1…127.
        case noteOn(note: Int, velocity: Int)
        /// A key released. (A note-on with velocity 0 is normalized to this.)
        case noteOff(note: Int, velocity: Int)
        /// A continuous controller moved — a knob, fader, or pedal. `controller`
        /// is the CC number (0…127), `value` its position (0…127).
        case controlChange(controller: Int, value: Int)
        /// A patch/preset change. `program` is 0…127.
        case programChange(program: Int)
        /// Channel-wide pressure (mono aftertouch), 0…127.
        case channelPressure(pressure: Int)
        /// Per-note pressure (poly aftertouch) for `note`, 0…127.
        case polyPressure(note: Int, pressure: Int)
        /// The pitch wheel. `value` is 0…16383 with **8192** at center.
        case pitchBend(value: Int)

        /// Timing clock — 24 of these per quarter note. (No channel.)
        case clock
        /// Transport start. (No channel.)
        case start
        /// Transport stop. (No channel.)
        case stop
        /// Transport resume from the current position. (No channel.)
        case `continue`
        /// Where in the song the transport sits, counted in sixteenth notes
        /// (6 timing clocks each), 0…16383. Usually sent while stopped, so a
        /// following `continue` resumes from the right place. (No channel.)
        case songPosition(sixteenths: Int)
    }

    /// What the message says.
    public var kind: Kind
    /// The channel, 1…16 for channel-voice messages; `0` for system messages.
    public var channel: Int

    /// Builds a message. `channel` defaults to `0` for the system messages that
    /// carry none.
    public init(_ kind: Kind, channel: Int = 0) {
        self.kind = kind
        self.channel = channel
    }

    // MARK: Convenience reads

    /// The note number for a note or poly-pressure message, else `nil`.
    public var note: Int? {
        switch kind {
        case .noteOn(let note, _), .noteOff(let note, _), .polyPressure(let note, _): return note
        default: return nil
        }
    }

    /// The strike/release velocity for a note message, else `nil`.
    public var velocity: Int? {
        switch kind {
        case .noteOn(_, let velocity), .noteOff(_, let velocity): return velocity
        default: return nil
        }
    }

    /// The CC number for a control-change message, else `nil`.
    public var controller: Int? {
        if case .controlChange(let controller, _) = kind { return controller }
        return nil
    }

    /// The scalar payload of the message: the CC value, program number,
    /// pressure, or pitch-bend amount. `nil` for note and system messages (read
    /// `velocity`/`note` for those).
    public var value: Int? {
        switch kind {
        case .controlChange(_, let value): return value
        case .programChange(let program): return program
        case .channelPressure(let pressure): return pressure
        case .polyPressure(_, let pressure): return pressure
        case .pitchBend(let value): return value
        default: return nil
        }
    }

    /// Whether this is a key/pad press (a note-on with non-zero velocity).
    public var isNoteOn: Bool {
        if case .noteOn = kind { return true }
        return false
    }

    /// Whether this is a key/pad release (a note-off, or the note-on-velocity-0
    /// the parser already folded into one).
    public var isNoteOff: Bool {
        if case .noteOff = kind { return true }
        return false
    }
}

// MARK: - Parsing (MIDI 1.0 bytes → message)

public extension MIDIMessage {
    /// Builds a message from a MIDI 1.0 status byte and up to two data bytes.
    ///
    /// Returns `nil` for status bytes Ollin doesn't model (System Exclusive, MIDI
    /// Time Code, song select, tune request, active sensing, reset) and for a
    /// bare data byte (`status < 0x80`), so a caller can skip what it doesn't
    /// understand without trapping. A note-on with velocity `0` is normalized to
    /// a note-off, the convention most gear uses.
    init?(status: UInt8, data1: UInt8 = 0, data2: UInt8 = 0) {
        guard status >= 0x80 else { return nil }   // a data byte alone isn't a message

        // System real-time / common: 0xF0…0xFF, no channel. Only the transport,
        // clock, and song-position messages are modeled; the rest are skipped.
        if status >= 0xF0 {
            switch status {
            case 0xF2: self.init(.songPosition(sixteenths: Int(data1 & 0x7F) | (Int(data2 & 0x7F) << 7)))
            case 0xF8: self.init(.clock)
            case 0xFA: self.init(.start)
            case 0xFB: self.init(.continue)
            case 0xFC: self.init(.stop)
            default: return nil
            }
            return
        }

        // Channel voice: high nibble selects the kind, low nibble the channel.
        let kind = status & 0xF0
        let channel = Int(status & 0x0F) + 1
        let d1 = Int(data1 & 0x7F)
        let d2 = Int(data2 & 0x7F)
        switch kind {
        case 0x80: self.init(.noteOff(note: d1, velocity: d2), channel: channel)
        case 0x90: self.init(d2 == 0 ? .noteOff(note: d1, velocity: 0)
                                     : .noteOn(note: d1, velocity: d2), channel: channel)
        case 0xA0: self.init(.polyPressure(note: d1, pressure: d2), channel: channel)
        case 0xB0: self.init(.controlChange(controller: d1, value: d2), channel: channel)
        case 0xC0: self.init(.programChange(program: d1), channel: channel)
        case 0xD0: self.init(.channelPressure(pressure: d1), channel: channel)
        case 0xE0: self.init(.pitchBend(value: d1 | (d2 << 7)), channel: channel)
        default: return nil
        }
    }

    /// Builds a message from a single MIDI 1.0 Universal MIDI Packet word — the
    /// form Core MIDI's modern API delivers. Returns `nil` for word types Ollin
    /// doesn't model (MIDI 2.0 channel voice, SysEx/data, utility), so an event
    /// list can be walked and the unhandled words skipped.
    init?(umpWord word: UInt32) {
        // The high nibble is the UMP message type. Only 0x2 (MIDI 1.0 channel
        // voice) and 0x1 (system real-time/common) carry the legacy
        // status+two-data-byte layout in the low 24 bits.
        let messageType = (word >> 28) & 0xF
        guard messageType == 0x1 || messageType == 0x2 else { return nil }
        self.init(status: UInt8((word >> 16) & 0xFF),
                  data1: UInt8((word >> 8) & 0xFF),
                  data2: UInt8(word & 0xFF))
    }
}

// MARK: - Encoding (message → MIDI 1.0 bytes / UMP)

public extension MIDIMessage {
    /// The status byte (channel folded in) and the two data bytes for this
    /// message. Out-of-range channels and data are clamped to the legal 7-bit /
    /// 1…16 ranges.
    var bytes: (status: UInt8, data1: UInt8, data2: UInt8) {
        let nibble = UInt8((Swift.max(1, Swift.min(16, channel)) - 1) & 0x0F)
        func clamp7(_ v: Int) -> UInt8 { UInt8(Swift.max(0, Swift.min(127, v))) }
        switch kind {
        case .noteOff(let note, let velocity):       return (0x80 | nibble, clamp7(note), clamp7(velocity))
        case .noteOn(let note, let velocity):        return (0x90 | nibble, clamp7(note), clamp7(velocity))
        case .polyPressure(let note, let pressure):  return (0xA0 | nibble, clamp7(note), clamp7(pressure))
        case .controlChange(let cc, let value):      return (0xB0 | nibble, clamp7(cc), clamp7(value))
        case .programChange(let program):            return (0xC0 | nibble, clamp7(program), 0)
        case .channelPressure(let pressure):         return (0xD0 | nibble, clamp7(pressure), 0)
        case .pitchBend(let value):
            let v = Swift.max(0, Swift.min(16383, value))
            return (0xE0 | nibble, UInt8(v & 0x7F), UInt8((v >> 7) & 0x7F))
        case .clock:    return (0xF8, 0, 0)
        case .start:    return (0xFA, 0, 0)
        case .continue: return (0xFB, 0, 0)
        case .stop:     return (0xFC, 0, 0)
        case .songPosition(let sixteenths):
            let s = Swift.max(0, Swift.min(16383, sixteenths))
            return (0xF2, UInt8(s & 0x7F), UInt8((s >> 7) & 0x7F))
        }
    }

    /// This message as a single MIDI 1.0 Universal MIDI Packet word (group 0),
    /// the form Core MIDI's modern send API takes.
    var umpWord: UInt32 {
        let (status, data1, data2) = bytes
        let messageType: UInt32 = status >= 0xF0 ? 0x1 : 0x2
        return (messageType << 28) | (UInt32(status) << 16) | (UInt32(data1) << 8) | UInt32(data2)
    }
}

// MARK: - Description

extension MIDIMessage: CustomStringConvertible {
    public var description: String {
        let body: String
        switch kind {
        case .noteOn(let n, let v):        body = "noteOn \(n) vel \(v)"
        case .noteOff(let n, let v):       body = "noteOff \(n) vel \(v)"
        case .controlChange(let c, let v): body = "cc \(c) = \(v)"
        case .programChange(let p):        body = "program \(p)"
        case .channelPressure(let p):      body = "pressure \(p)"
        case .polyPressure(let n, let p):  body = "polyPressure \(n) = \(p)"
        case .pitchBend(let v):            body = "pitchBend \(v)"
        case .clock:                       return "clock"
        case .start:                       return "start"
        case .stop:                        return "stop"
        case .continue:                    return "continue"
        case .songPosition(let s):         return "songPosition \(s)"
        }
        return "ch\(channel) \(body)"
    }
}
