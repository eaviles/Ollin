import Foundation
import Testing
import Ollin
@testable import OllinMIDI

/// End-to-end over Core MIDI in-process: a `MIDIOutput` virtual source feeding a
/// `MIDIInput`, exercising the polling cache, the event drain, and `@Param`
/// binding. It needs the Core MIDI server (and virtual-source routing), which
/// isn't guaranteed in every sandbox, so it soft-skips when the link can't be
/// brought up — the parser tests are the always-on CI guard. Run on a real Mac it
/// verifies the whole pipe.
@Suite
struct MIDILoopbackTests {

    /// Polls `probe` until non-nil or the timeout elapses.
    ///
    /// The probe comes before the clock is read: a starved task can wake past
    /// its own deadline having never looked, and giving up then reports nothing
    /// arrived over a message that already did.
    func waitFor<T>(timeout: Double = 3.0, _ probe: () -> T?) async -> T? {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let value = probe() { return value }
            if Date() >= deadline { return nil }
            try? await Task.sleep(nanoseconds: 5_000_000)   // 5 ms
        }
    }

    /// Brings up a virtual-source output and an input connected to it, with the
    /// link confirmed live (a warmup CC has made it across). Returns `nil` to
    /// signal a soft-skip when Core MIDI isn't available.
    func makePair() async -> (output: MIDIOutput, input: MIDIInput)? {
        let output = MIDIOutput(name: "OllinMIDITest")
        let input = MIDIInput(name: "OllinMIDITestIn")
        do {
            try output.openVirtual(named: "OllinMIDITest Loopback")
            try input.start()
        } catch {
            return nil
        }
        // The input connects to the new virtual source on a setup-change
        // notification, which is async — resend the warmup until it lands.
        let connected = await waitFor { () -> Bool? in
            output.controlChange(1, value: 1)
            return input.controlValue(1) != nil ? true : nil
        }
        guard connected == true else {
            output.close(); input.stop()
            return nil
        }
        _ = input.messages()   // clear the warmups
        return (output, input)
    }

    @Test func controlChangeReachesTheCache() async {
        guard let (output, input) = await makePair() else { return }   // soft-skip
        defer { output.close(); input.stop() }

        output.controlChange(7, value: 99)
        let value = await waitFor { input.controlValue(7) == 99 ? 99 : nil }
        #expect(value == 99)
    }

    @Test func notesDrainInOrderAndTrackHeldState() async {
        guard let (output, input) = await makePair() else { return }   // soft-skip
        defer { output.close(); input.stop() }

        output.noteOn(60, velocity: 100)
        _ = await waitFor { input.isNoteOn(60) ? true : nil }
        #expect(input.isNoteOn(60))

        output.noteOff(60)
        _ = await waitFor { input.isNoteOn(60) ? nil : true }
        #expect(!input.isNoteOn(60))

        let notes = input.messages().compactMap { $0.note }
        #expect(notes.contains(60))
    }

    @Test func bindingDrivesAParam() async {
        guard let (output, input) = await makePair() else { return }   // soft-skip
        defer { output.close(); input.stop() }

        let parameter = Param(wrappedValue: 0.0, 0...100)   // no smoothing → instant
        input.bind(controlChange: 20, to: parameter.projectedValue)   // 0…127 → 0…100

        output.controlChange(20, value: 127)
        let value = await waitFor { parameter.wrappedValue >= 99.9 ? parameter.wrappedValue : nil }
        #expect((value ?? 0) > 99)
    }

    /// A tempo binds the way a number does, into its range in beats per
    /// minute, and the knob never touches the beats per bar.
    @Test func bindingDrivesATempoParam() async {
        guard let (output, input) = await makePair() else { return }   // soft-skip
        defer { output.close(); input.stop() }

        let tempo = Param(wrappedValue: Tempo(90, beatsPerBar: 3), 60...160)
        input.bind(controlChange: 21, to: tempo.projectedValue)   // 0…127 → 60…160 bpm

        output.controlChange(21, value: 127)
        let value = await waitFor { tempo.wrappedValue.beatsPerMinute >= 159.9 ? tempo.wrappedValue : nil }
        #expect((value?.beatsPerMinute ?? 0) > 159)
        #expect(value?.beatsPerBar == 3)
    }

    /// Timecode crosses the link both ways it travels: eight quarter frames
    /// land a `TimecodeClock` on the frame they spell plus the frame the set
    /// took, and a full-frame exclusive (the two-packet path through the
    /// event list) locates it outright.
    @Test func timecodeCrossesTheLink() async {
        guard let (output, input) = await makePair() else { return }   // soft-skip
        defer { output.close(); input.stop() }

        let clock = TimecodeClock(from: input)
        let code = Timecode(hours: 1, minutes: 2, seconds: 3, frames: 4, frameRate: .fps25)
        for piece in 0 ..< 8 {
            output.send(MIDIMessage(.timecodeQuarterFrame(piece: piece, value: code.quarterFrameValue(piece: piece))))
        }
        let landed = await waitFor { clock.timecode }
        #expect(landed?.frameRate == .fps25)
        #expect(landed == code.advanced(by: 1))
        #expect(clock.isReceiving)

        let parked = Timecode(hours: 9, minutes: 0, seconds: 0, frames: 0, frameRate: .fps30)
        output.send(timecode: parked)
        let located = await waitFor { clock.timecode == parked ? parked : nil }
        #expect(located == parked)
        #expect(clock.frameRate == .fps30)
    }
}
