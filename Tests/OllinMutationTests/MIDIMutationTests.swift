import Foundation
import Testing
import OllinMutation
@testable import OllinMIDI

/// MIDI 1.0 bytes, Universal MIDI Packet words, and the timecode walk (the
/// quarter-frame pieces an engine assembles into a position, and the
/// full-frame exclusive that sets one outright), under the mutation harness.
@Suite struct MIDIMutationTests {

    @Test func messagesAndWords() {
        let seeds: [[UInt8]] = [
            [0x90, 60, 100], [0x80, 60, 0], [0xB0, 74, 12], [0xE0, 0x00, 0x40],
            [0xF1, 0x23, 0], [0xF2, 0x10, 0x02], [0xF8, 0, 0], [0xC5, 7, 0], [0xD1, 5, 0], [0xA3, 60, 9],
        ]
        let report = MutationRun.run("midi-message", seeds: seeds, count: 400) { bytes in
            guard let status = bytes.first else { return false }
            let message = MIDIMessage(status: status,
                                      data1: bytes.count > 1 ? bytes[1] : 0,
                                      data2: bytes.count > 2 ? bytes[2] : 0)
            if let message {
                _ = message.bytes
                _ = message.umpWord
                _ = message.description
            }
            var word: UInt32 = 0
            for byte in bytes.prefix(4) { word = word << 8 | UInt32(byte) }
            _ = MIDIMessage(umpWord: word)
            return message != nil
        }
        #expect(report.seedsRefused.isEmpty, "\(report)")
    }

    /// The pieces of a timecode in the order a running deck sends them, in
    /// reverse as a deck shuttling backward sends them, and the full-frame
    /// message that locates. The engine is one for the whole run, so a mutated
    /// walk lands on whatever state the last one left.
    @Test func theTimecodeWalk() {
        let code = Timecode(hours: 1, minutes: 2, seconds: 3, frames: 4, frameRate: .fps25)
        let walk: [UInt8] = (0..<8).map { UInt8($0 << 4 | code.quarterFrameValue(piece: $0)) }
        let seeds: [[UInt8]] = [walk, Array(walk.reversed()), code.fullFrameSysEx, walk + walk,
                                Timecode(hours: 23, minutes: 59, seconds: 59, frames: 29, frameRate: .fps30Drop).fullFrameSysEx]
        var engine = TimecodeEngine()
        var time = 0.0
        let report = MutationRun.run("midi-timecode", seeds: seeds, count: 500) { bytes in
            if let located = Timecode(fullFrameSysEx: bytes) {
                engine.locate(to: located, at: time)
                _ = located.totalSeconds
                _ = located.frameNumber
                _ = located.description
                _ = located.advanced(byFrames: 1_000_000)
            }
            for byte in bytes {
                guard let message = MIDIMessage(status: 0xF1, data1: byte),
                      case .timecodeQuarterFrame(let piece, let value) = message.kind else { continue }
                time += 0.01
                engine.handle(piece: piece, value: value, at: time)
            }
            _ = engine.timecode(at: time)
            _ = engine.seconds(at: time)
            _ = engine.isPlaying(at: time)
            _ = engine.isReceiving(at: time + 2)
            _ = engine.frameRate
            return true
        }
        #expect(report.cases > 0, "\(report)")
    }
}
