import Foundation
import Testing
@testable import OllinMIDI

/// Pure checks on `Timecode` and the engine behind `TimecodeClock`: the
/// drop-frame arithmetic, the wire forms both ways, and the position a set
/// of quarter frames lands on. No Core MIDI; the loopback suite covers the pipe.
@Suite
struct TimecodeTests {

    // MARK: The value

    @Test func fieldsRoundTripThroughTheFrameNumberAtEveryRate() {
        for rate in Timecode.FrameRate.allCases {
            for frame in stride(from: 0, to: 30 * 3600 * 2, by: 97) {
                let code = Timecode(frameNumber: frame, frameRate: rate)
                #expect(code.frameNumber == frame)
                #expect(code.frames < rate.framesPerSecond)
                #expect(code.seconds < 60 && code.minutes < 60)
            }
        }
    }

    /// Drop frame skips numbers 0 and 1 at the top of every minute except
    /// each tenth, so the labels never show them there.
    @Test func dropFrameSkipsTwoNumbersAtMostMinutes() {
        var skipped = 0, kept = 0
        // Thirty minutes of drop frame: 1,798 frames a minute plus the two the
        // tenth minutes keep.
        for frame in 0 ..< 30 * 1798 + 3 * 2 {
            let code = Timecode(frameNumber: frame, frameRate: .fps30Drop)
            if code.seconds == 0, code.frames < 2 {
                #expect(code.minutes % 10 == 0)
                kept += 1
            }
            if code.seconds == 0, code.frames == 2 { skipped += 1 }
        }
        #expect(kept == 2 * 3)      // minutes 0, 10, 20 of the half hour
        #expect(skipped == 30)      // every minute has a frame 2 at its top
        let oneMinute = Timecode(hours: 0, minutes: 1, seconds: 0, frames: 2, frameRate: .fps30Drop)
        #expect(oneMinute.frameNumber == 1800)
    }

    /// A minute of drop frame is 1,798 counted frames and lasts within a
    /// hundredth of a second of a wall-clock minute; a minute of 30 non-drop
    /// is 1,800 frames and lasts a minute and a bit at 30 per 1.001 seconds
    /// only if the rate were 29.97, which non-drop is not.
    @Test func totalSecondsHonorsTheRate() {
        let drop = Timecode(hours: 0, minutes: 1, seconds: 0, frames: 2, frameRate: .fps30Drop)
        #expect(abs(drop.totalSeconds - 60.06) < 0.01)
        let plain = Timecode(hours: 0, minutes: 1, seconds: 0, frames: 0, frameRate: .fps30)
        #expect(plain.totalSeconds == 60)
        let film = Timecode(hours: 1, minutes: 0, seconds: 0, frames: 12, frameRate: .fps24)
        #expect(film.totalSeconds == 3600.5)
        let back = Timecode(seconds: 3600.5, frameRate: .fps24)
        #expect(back == film)
    }

    @Test func describesLikeABroadcastDisplay() {
        #expect("\(Timecode(hours: 1, minutes: 2, seconds: 3, frames: 4, frameRate: .fps25))" == "01:02:03:04")
        #expect("\(Timecode(hours: 0, minutes: 10, seconds: 0, frames: 0, frameRate: .fps30Drop))" == "00:10:00;00")
    }

    // MARK: The wire forms

    @Test func quarterFramesSpellTheTimeAndTheRate() {
        let code = Timecode(hours: 23, minutes: 59, seconds: 58, frames: 29, frameRate: .fps30Drop)
        let nibbles = (0 ..< 8).map { code.quarterFrameValue(piece: $0) }
        #expect(nibbles.allSatisfy { (0 ... 15).contains($0) })
        #expect(Timecode(quarterFrameValues: nibbles) == code)
        let film = Timecode(hours: 17, minutes: 0, seconds: 0, frames: 23, frameRate: .fps24)
        #expect(Timecode(quarterFrameValues: (0 ..< 8).map { film.quarterFrameValue(piece: $0) }) == film)
    }

    @Test func aQuarterFrameMessageParsesAndEncodes() {
        let message = MIDIMessage(status: 0xF1, data1: 0x23)
        #expect(message?.kind == .timecodeQuarterFrame(piece: 2, value: 3))
        let bytes = MIDIMessage(.timecodeQuarterFrame(piece: 7, value: 9)).bytes
        #expect(bytes.status == 0xF1 && bytes.data1 == 0x79 && bytes.data2 == 0)
        #expect(MIDIMessage(umpWord: MIDIMessage(.timecodeQuarterFrame(piece: 5, value: 1)).umpWord)?.kind
                == .timecodeQuarterFrame(piece: 5, value: 1))
    }

    @Test func aFullFrameExclusiveRoundTrips() {
        let code = Timecode(hours: 5, minutes: 42, seconds: 7, frames: 18, frameRate: .fps25)
        let body = code.fullFrameSysEx
        #expect(body == [0x7F, 0x7F, 0x01, 0x01, 0x25, 42, 7, 18])
        #expect(Timecode(fullFrameSysEx: body) == code)
        #expect(Timecode(fullFrameSysEx: [0x7F, 0x7F, 0x06, 0x01, 0, 0, 0, 0]) == nil)
    }

    // MARK: The engine

    /// Sends the eight pieces of `code` forward at `rate`, four a frame,
    /// starting at `t0`, and returns the time the last landed.
    @discardableResult
    private func spell(_ code: Timecode, into engine: inout TimecodeEngine,
                       from t0: Double, reversed: Bool = false) -> Double {
        let quarter = code.frameRate.secondsPerFrame / 4
        let order = reversed ? Array((0 ..< 8).reversed()) : Array(0 ..< 8)
        var time = t0
        for (step, piece) in order.enumerated() {
            time = t0 + Double(step) * quarter
            engine.handle(piece: piece, value: code.quarterFrameValue(piece: piece), at: time)
        }
        return time
    }

    /// A set completes two frames after it began, so the position it lands on
    /// is the spelled time plus a frame and three quarters, and the next
    /// piece takes it to the spelled time plus two.
    @Test func aCompletedSetLandsOnTheTimeItSpellsPlusTheTimeItTook() {
        var engine = TimecodeEngine()
        let code = Timecode(hours: 1, minutes: 0, seconds: 10, frames: 0, frameRate: .fps25)
        let landed = spell(code, into: &engine, from: 10)
        #expect(engine.frameRate == .fps25)
        #expect(engine.frames(at: landed) == Double(code.frameNumber) + 1.75)
        #expect(engine.timecode(at: landed) == code.advanced(by: 1))
        engine.handle(piece: 0, value: code.advanced(by: 2).quarterFrameValue(piece: 0), at: landed + 0.01)
        #expect(engine.frames(at: landed + 0.01) == Double(code.frameNumber) + 2)
        #expect(engine.timecode(at: landed + 0.01) == code.advanced(by: 2))
    }

    @Test func thePositionGlidesBetweenPiecesAndNeverRunsBack() {
        var engine = TimecodeEngine()
        let code = Timecode(hours: 0, minutes: 0, seconds: 5, frames: 0, frameRate: .fps30)
        let landed = spell(code, into: &engine, from: 1)
        let base = engine.seconds(at: landed)
        let later = engine.seconds(at: landed + 0.004)   // under a quarter frame later
        #expect(later > base)
        #expect(later - base < 1 / 30.0 / 4)
        // A late next piece: the glide stopped just short, so the exact step still lands ahead.
        let farther = engine.seconds(at: landed + 0.02)
        engine.handle(piece: 0, value: 0, at: landed + 0.02)
        #expect(engine.seconds(at: landed + 0.02) >= farther)
    }

    @Test func silenceStopsTheClockWhereItWas() {
        var engine = TimecodeEngine()
        let code = Timecode(hours: 0, minutes: 2, seconds: 0, frames: 0, frameRate: .fps24)
        let landed = spell(code, into: &engine, from: 0)
        #expect(engine.isPlaying(at: landed + 0.1))
        #expect(!engine.isPlaying(at: landed + 0.7))
        #expect(!engine.isReceiving(at: landed + 1.5))
        #expect(engine.frames(at: landed + 3) == Double(code.frameNumber) + 1.75)
    }

    @Test func aFullFrameLocatesAndHolds() {
        var engine = TimecodeEngine()
        let code = Timecode(hours: 2, minutes: 30, seconds: 0, frames: 0, frameRate: .fps30Drop)
        engine.locate(to: code, at: 5)
        #expect(engine.timecode(at: 5.2) == code)
        #expect(engine.seconds(at: 9) == code.totalSeconds)
        #expect(!engine.isPlaying(at: 5.2))
        #expect(engine.isReceiving(at: 5.2))
        #expect(engine.frameRate == .fps30Drop)
        // Rolling from there: the first complete set re-anchors.
        let landed = spell(code.advanced(by: 10), into: &engine, from: 6)
        #expect(engine.timecode(at: landed) == code.advanced(by: 11))
    }

    @Test func piecesInReverseRunThePositionBackward() {
        var engine = TimecodeEngine()
        let code = Timecode(hours: 0, minutes: 1, seconds: 0, frames: 10, frameRate: .fps25)
        let landed = spell(code, into: &engine, from: 0, reversed: true)
        #expect(engine.direction < 0)
        let at = engine.frames(at: landed)
        #expect(at == Double(code.frameNumber) - 1.75)
        engine.handle(piece: 7, value: 0, at: landed + 0.01)
        #expect(engine.frames(at: landed + 0.01) == Double(code.frameNumber) - 2)
    }

    @Test func aSkippedPieceStartsTheSetOver() {
        var engine = TimecodeEngine()
        let code = Timecode(hours: 0, minutes: 0, seconds: 1, frames: 0, frameRate: .fps25)
        for piece in 0 ..< 6 {
            engine.handle(piece: piece, value: code.quarterFrameValue(piece: piece), at: Double(piece) * 0.01)
        }
        engine.handle(piece: 2, value: 0, at: 0.07)   // the sender jumped mid-set
        engine.handle(piece: 3, value: 0, at: 0.08)
        for piece in 4 ..< 8 {
            engine.handle(piece: piece, value: code.quarterFrameValue(piece: piece), at: 0.09 + Double(piece) * 0.01)
        }
        // Pieces 0 and 1 were never re-heard after the restart, so no set completed.
        #expect(engine.frames(at: 0.2) == nil)
    }
}
