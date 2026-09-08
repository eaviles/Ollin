import Foundation
import Ollin
import OllinMIDI
import OllinOSC

/// `swift run OllinLiveCoding --controltest`: headless checks of the host's
/// own controls on MIDI and OSC, against counters rather than the window:
///
/// - Learn takes the next control for the lit action, once, and a control
///   learned elsewhere moves rather than doubling.
/// - A note fires a press action on its channel and no other; a controller
///   button fires once on the way up; a fader rides a continuous action.
/// - The fixed OSC addresses answer with nothing learned: a bare message
///   turns a toggle over, a value sets it, a button's release is ignored.
/// - The map survives a restart through the defaults.
/// - A note from a virtual MIDI source and a message over a UDP socket both
///   reach the host through the same poll the window runs (the MIDI half is
///   passed over, and says so, where Core MIDI is not available).
enum ControlTest {
    @MainActor
    static func run() -> Never {
        Task { @MainActor in
            await check()
        }
        RunLoop.main.run()   // pumped until a check calls exit()
        exit(1)
    }

    /// What the actions did, counted.
    @MainActor
    final class Tally {
        var evaluations = 0
        var freshEvaluations = 0
        var codeHidden = false
        var hiddenSets = 0
        var backdrop = 0.55
        var codeSize = 15.0
        var recording = false
        var cueCalls: [CueRequest] = []
        var cueFades: [Double] = []

        var handlers: PerformanceControls.Handlers {
            PerformanceControls.Handlers(
                evaluate: { [self] fresh in
                    if fresh { freshEvaluations += 1 } else { evaluations += 1 }
                },
                setCodeHidden: { [self] wanted in
                    codeHidden = wanted ?? !codeHidden
                    hiddenSets += 1
                },
                setBackdrop: { [self] in backdrop = $0 },
                setCodeSize: { [self] in codeSize = $0 },
                setRecording: { [self] wanted in recording = wanted ?? !recording },
                cue: { [self] request in cueCalls.append(request) },
                cueOver: { [self] request, fade in
                    cueCalls.append(request)
                    cueFades.append(fade)
                }
            )
        }
    }

    @MainActor
    private static func check() async {
        let suite = "ollin.livecoding.controltest"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let tally = Tally()
        let controls = PerformanceControls(handlers: tally.handlers, defaults: defaults)
        typealias Action = PerformanceControls.Action

        print("OllinLiveCoding controltest: learning …")
        controls.handle(MIDIMessage(.noteOn(note: 36, velocity: 100), channel: 10))
        guard tally.evaluations == 0, controls.map.isEmpty else {
            fail("an unlearned note did something")
        }
        controls.learn(.evaluate)
        guard controls.learning == .evaluate else { fail("Learn did not light") }
        controls.handle(MIDIMessage(.noteOn(note: 36, velocity: 100), channel: 10))
        guard controls.map[.evaluate] == .note(36, channel: 10), controls.learning == nil else {
            fail("the note was not learned: \(String(describing: controls.map[.evaluate]))")
        }
        guard tally.evaluations == 0 else { fail("learning a note also fired it") }
        // Learn lit twice goes out.
        controls.learn(.record)
        controls.learn(.record)
        guard controls.learning == nil else { fail("Learn did not go out on the second press") }
        // A fader's action refuses a note and takes a controller.
        controls.learn(.backdrop)
        controls.handle(MIDIMessage(.noteOn(note: 40, velocity: 100), channel: 10))
        guard controls.learning == .backdrop, controls.map[.backdrop] == nil else {
            fail("a note was learned for a fader's action")
        }
        controls.handle(MIDIMessage(.controlChange(controller: 7, value: 3), channel: 1))
        guard controls.map[.backdrop] == .control(7, channel: 1) else { fail("the fader was not learned") }
        // One control, one action: the same note learned for record leaves evaluate.
        controls.learn(.record)
        controls.handle(MIDIMessage(.noteOn(note: 36, velocity: 100), channel: 10))
        guard controls.map[.record] == .note(36, channel: 10), controls.map[.evaluate] == nil else {
            fail("a control learned twice did not move")
        }
        controls.clear(.record)
        guard controls.map[.record] == nil else { fail("clear left the binding") }

        print("OllinLiveCoding controltest: MIDI matching …")
        controls.learn(.evaluate)
        controls.handle(MIDIMessage(.noteOn(note: 36, velocity: 100), channel: 10))
        controls.handle(MIDIMessage(.noteOn(note: 36, velocity: 100), channel: 10))
        controls.handle(MIDIMessage(.noteOn(note: 36, velocity: 100), channel: 9))
        controls.handle(MIDIMessage(.noteOff(note: 36, velocity: 0), channel: 10))
        guard tally.evaluations == 1 else {
            fail("a learned note fired \(tally.evaluations) times (wanted 1: once on its channel, never off it)")
        }
        controls.learn(.evaluateFresh)
        controls.handle(MIDIMessage(.controlChange(controller: 20, value: 127), channel: 1))
        controls.handle(MIDIMessage(.controlChange(controller: 20, value: 127), channel: 1))
        controls.handle(MIDIMessage(.controlChange(controller: 20, value: 0), channel: 1))
        controls.handle(MIDIMessage(.controlChange(controller: 20, value: 127), channel: 1))
        guard tally.freshEvaluations == 2 else {
            fail("a controller button fired \(tally.freshEvaluations) times (wanted 2: once per rise)")
        }
        controls.handle(MIDIMessage(.controlChange(controller: 7, value: 64), channel: 1))
        guard abs(tally.backdrop - 64.0 / 127) < 1e-9 else { fail("the fader did not ride the backdrop") }
        controls.learn(.codeSize)
        controls.handle(MIDIMessage(.controlChange(controller: 8, value: 127), channel: 1))
        controls.handle(MIDIMessage(.controlChange(controller: 8, value: 127), channel: 1))
        guard tally.codeSize == PerformanceControls.largestCodeSize else {
            fail("the size fader at the top read \(tally.codeSize)")
        }
        controls.handle(MIDIMessage(.controlChange(controller: 8, value: 0), channel: 1))
        guard tally.codeSize == PerformanceControls.smallestCodeSize else {
            fail("the size fader at the bottom read \(tally.codeSize)")
        }

        print("OllinLiveCoding controltest: the fixed OSC addresses …")
        let before = tally.evaluations
        controls.handle(OSCMessage(Action.evaluate.address))
        controls.handle(OSCMessage(Action.evaluate.address, .float(1)))
        controls.handle(OSCMessage(Action.evaluate.address, .float(0)))   // a button's release
        guard tally.evaluations == before + 2 else {
            fail("the fixed evaluate address fired \(tally.evaluations - before) times (wanted 2)")
        }
        controls.handle(OSCMessage(Action.hideCode.address))
        guard tally.codeHidden else { fail("a bare message did not turn the code over") }
        controls.handle(OSCMessage(Action.hideCode.address, .float(0)))
        guard !tally.codeHidden else { fail("a zero did not show the code") }
        controls.handle(OSCMessage(Action.hideCode.address, .bool(true)))
        guard tally.codeHidden else { fail("a true did not hide the code") }
        controls.handle(OSCMessage(Action.backdrop.address, .float(0.8)))
        guard abs(tally.backdrop - 0.8) < 1e-6 else { fail("the backdrop address read \(tally.backdrop)") }
        controls.handle(OSCMessage(Action.codeSize.address, .float(0.5)))
        guard abs(tally.codeSize - 20.5) < 1e-6 else { fail("the size address read \(tally.codeSize)") }
        controls.handle(OSCMessage(Action.record.address))
        guard tally.recording else { fail("the record address did not start a take") }
        controls.handle(OSCMessage("/somewhere/else"))
        guard tally.evaluations == before + 2 else { fail("an unknown address did something") }
        // A learned address answers beside the fixed ones.
        controls.learn(.evaluate)
        controls.handle(OSCMessage("/pad/1", .float(1)))
        guard controls.map[.evaluate] == .osc("/pad/1") else { fail("the address was not learned") }
        controls.handle(OSCMessage("/pad/1", .float(1)))
        guard tally.evaluations == before + 3 else { fail("the learned address did not fire") }

        print("OllinLiveCoding controltest: the map survives a restart …")
        let again = PerformanceControls(handlers: tally.handlers, defaults: defaults)
        guard again.map == controls.map, !again.map.isEmpty else {
            fail("the map read back as \(again.map)")
        }

        print("OllinLiveCoding controltest: OSC over a socket …")
        let port = 47_811
        controls.oscPort = port
        controls.start()
        let sender = OSCSender(host: "127.0.0.1", port: port)
        let arrived = await waitFor(seconds: 4) {
            sender.send(Action.evaluateFresh.address)
            controls.poll()
            return tally.freshEvaluations > 2
        }
        guard arrived else { fail("a message over the socket never reached the host (\(controls.oscStatus))") }
        sender.close()

        print("OllinLiveCoding controltest: MIDI from a virtual source …")
        // The OSC phase learned evaluate onto an address; put the pad back.
        controls.learn(.evaluate)
        controls.handle(MIDIMessage(.noteOn(note: 36, velocity: 100), channel: 10))
        guard controls.map[.evaluate] == .note(36, channel: 10) else { fail("the pad was not learned back") }
        let output = MIDIOutput(name: "OllinLiveCodingControlTest")
        if controls.isListeningToMIDI, (try? output.openVirtual(named: "OllinLiveCoding controltest")) != nil {
            let fired = tally.evaluations
            let landed = await waitFor(seconds: 4) {
                output.noteOn(36, velocity: 100, channel: 10)
                output.noteOff(36, channel: 10)
                controls.poll()
                return tally.evaluations > fired
            }
            output.close()
            guard landed else { fail("a note from a virtual source never reached the host") }
        } else {
            print("OllinLiveCoding controltest: Core MIDI is not available here, the virtual source is passed over.")
        }
        controls.stop()
        defaults.removePersistentDomain(forName: suite)

        print("OllinLiveCoding controltest: cues …")
        // A program change is a cue number, on any channel, with nothing learned.
        controls.handle(MIDIMessage(.programChange(program: 3), channel: 5))
        guard tally.cueCalls == [.number(3)] else { fail("a program change did not call cue 3: \(tally.cueCalls)") }
        // The fixed address takes a name or a number, and a fade of its own.
        controls.handle(OSCMessage(Action.cueAddress, .string("finale")))
        controls.handle(OSCMessage(Action.cueAddress, .int(1)))
        controls.handle(OSCMessage(Action.cueAddress, .string("intro"), .float(2.5)))
        guard tally.cueCalls == [.number(3), .named("finale"), .number(1), .named("intro")],
              tally.cueFades == [2.5] else {
            fail("/ollin/cue did not call as asked: \(tally.cueCalls) fades \(tally.cueFades)")
        }
        // Next and previous are press actions: fixed addresses, and learnable.
        controls.handle(OSCMessage(Action.cueNext.address))
        controls.learn(.cuePrevious)
        controls.handle(MIDIMessage(.noteOn(note: 40, velocity: 100), channel: 1))
        guard controls.map[.cuePrevious] == .note(40, channel: 1) else { fail("previous cue did not learn the note") }
        controls.handle(MIDIMessage(.noteOn(note: 40, velocity: 100), channel: 1))
        guard tally.cueCalls.suffix(2) == [.next, .previous] else {
            fail("next and previous did not press: \(tally.cueCalls.suffix(2))")
        }
        // A bare message at the cue address with nothing to name calls nothing.
        controls.handle(OSCMessage(Action.cueAddress))
        guard tally.cueCalls.count == 6 else { fail("an empty cue message called something") }

        print("OllinLiveCoding controltest passed: cues on a program change, the cue address, next and previous; learning, MIDI matching, the fixed OSC addresses, the map, and both wires hold.")
        exit(0)
    }

    /// Probes until it answers or the time is up; the probe runs before the
    /// clock is read, so a late wake-up still gets its look.
    @MainActor
    private static func waitFor(seconds: Double, _ probe: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while true {
            if probe() { return true }
            if Date() >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("OllinLiveCoding controltest FAILED: \(message)\n".utf8))
        exit(1)
    }
}
