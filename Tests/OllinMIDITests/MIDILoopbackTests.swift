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

        let knob = Param(wrappedValue: 0.0, 0...100)   // no smoothing → instant
        input.bind(controlChange: 20, to: knob.projectedValue)   // 0…127 → 0…100

        output.controlChange(20, value: 127)
        let value = await waitFor { knob.wrappedValue >= 99.9 ? knob.wrappedValue : nil }
        #expect((value ?? 0) > 99)
    }
}
