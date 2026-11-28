import AVFoundation
import Foundation
import Testing
import Ollin
@testable import OllinAudio

/// The life of a sound source around the calls that start and stop it: a
/// microphone whose start waits on the system's prompt, a file that is paused
/// and played again, a full instrument deciding which note to give up, and
/// an arpeggiator holding a chord after the fingers leave.
@Suite(.serialized) @MainActor
struct SoundLifecycleTests {

    // MARK: The microphone, with nothing real behind it

    /// Counts what the lifecycle asks of the engine, and can refuse a start.
    final class FakeDevice {
        var installs = 0, removals = 0, starts = 0, stops = 0
        var refusesNextStart = false
        /// Taps installed and not removed. The engine allows one: a second
        /// raises an exception that takes the process down.
        var taps: Int { installs - removals }
    }
    struct Refused: Error {}

    private func makeInput(_ fake: FakeDevice) -> AudioInput {
        let input = AudioInput()
        input.device = AudioInput.Device(
            installTap: { fake.installs += 1 },
            removeTap: { fake.removals += 1 },
            start: {
                if fake.refusesNextStart {
                    fake.refusesNextStart = false
                    throw Refused()
                }
                fake.starts += 1
            },
            stop: { fake.stops += 1 })
        return input
    }

    /// The answers the system's prompt has been asked for and has not given.
    final class Prompt: @unchecked Sendable {
        var pending: [@Sendable (Bool) -> Void] = []
        var asked: Int { pending.count }
        func answer(_ granted: Bool) {
            let all = pending
            for answer in all { answer(granted) }
        }
    }

    /// Run `body` with the permission standing at `status` and the prompt
    /// replaced by `prompt`. The seams are back in place before this returns,
    /// and nothing in it suspends, so no other test sees them.
    private func withPermission(_ status: AVAuthorizationStatus, _ prompt: Prompt = Prompt(),
                                _ body: () throws -> Void) rethrows {
        let kept = (AudioInput.authorizationStatus, AudioInput.requestAccess)
        defer { (AudioInput.authorizationStatus, AudioInput.requestAccess) = kept }
        AudioInput.authorizationStatus = { status }
        AudioInput.requestAccess = { prompt.pending.append($0) }
        try body()
    }

    /// Let the main actor run what an answer queued on it.
    private func settle() async {
        for _ in 0..<8 { await Task { @MainActor in }.value }
    }

    /// An engine that will not start leaves nothing installed, so the next
    /// `start()` is a clean one. The tap is the node's only one.
    @Test func aStartTheEngineRefusesLeavesNoTapBehind() throws {
        let fake = FakeDevice()
        let input = makeInput(fake)
        fake.refusesNextStart = true
        withPermission(.authorized) {
            #expect(throws: Refused.self) { try input.start() }
        }
        #expect(!input.isRunning)
        #expect(fake.taps == 0, "a start that failed left \(fake.taps) tap on the input")

        try withPermission(.authorized) { try input.start() }
        #expect(input.isRunning)
        #expect(fake.taps == 1, "the second start left \(fake.taps) taps on a node that allows one")

        input.stop()
        #expect(!input.isRunning && fake.taps == 0 && fake.stops == 1)
    }

    /// `stop()` while the system's prompt is still up calls the start off:
    /// the answer, when it comes, opens nothing.
    @Test func stoppingWhileThePromptIsUpCallsTheStartOff() async throws {
        let fake = FakeDevice(), prompt = Prompt()
        let input = makeInput(fake)
        try withPermission(.notDetermined, prompt) { try input.start() }
        #expect(prompt.asked == 1 && !input.isRunning)

        input.stop()
        prompt.answer(true)
        await settle()
        #expect(fake.starts == 0, "the microphone opened after stop() was called")
        #expect(!input.isRunning)
        #expect(fake.taps == 0)
        #expect(input.unavailableReason == nil)
    }

    /// A sketch that calls `start()` again while the prompt is up (from a
    /// retry, or every frame) asks once and starts once.
    @Test func aSecondStartWhileThePromptIsUpStartsOnce() async throws {
        let fake = FakeDevice(), prompt = Prompt()
        let input = makeInput(fake)
        try withPermission(.notDetermined, prompt) {
            try input.start()
            try input.start()
            try input.start()
        }
        #expect(prompt.asked == 1, "the prompt was asked for \(prompt.asked) times")
        prompt.answer(true)
        await settle()
        #expect(input.isRunning)
        #expect(fake.taps == 1, "\(fake.taps) taps on a node that allows one")
        #expect(fake.starts == 1)
    }

    /// Stopped and started again under the same prompt, the one answer
    /// starts the capture once.
    @Test func stoppedAndStartedAgainUnderOnePromptStartsOnce() async throws {
        let fake = FakeDevice(), prompt = Prompt()
        let input = makeInput(fake)
        try withPermission(.notDetermined, prompt) {
            try input.start()
            input.stop()
            try input.start()
        }
        prompt.answer(true)
        await settle()
        #expect(input.isRunning)
        #expect(fake.taps == 1 && fake.starts == 1)
    }

    /// A refusal says so and starts nothing, and an engine that fails after
    /// the prompt says that instead, with nothing left installed.
    @Test func whatGoesWrongAfterThePromptIsWrittenDown() async throws {
        let fake = FakeDevice(), prompt = Prompt()
        let input = makeInput(fake)
        try withPermission(.notDetermined, prompt) { try input.start() }
        prompt.answer(false)
        await settle()
        #expect(input.unavailableReason?.contains("refused") == true)
        #expect(!input.isRunning && fake.installs == 0)

        let second = Prompt()
        fake.refusesNextStart = true
        try withPermission(.notDetermined, second) { try input.start() }
        #expect(input.unavailableReason == nil, "a new start clears the old sentence")
        second.answer(true)
        await settle()
        #expect(input.unavailableReason?.contains("could not start") == true)
        #expect(!input.isRunning)
        #expect(fake.taps == 0, "the failed start left \(fake.taps) tap behind")
    }

    // MARK: A listener stopped while it is still getting ready

    /// A listener that is stopped before its recognizer is ready says nothing
    /// afterwards: not the notice that a model is installing (the timer
    /// behind it was not stopped with the rest), and not whatever the
    /// called-off preparation ran into.
    @Test func aListenerStoppedWhileGettingReadySaysNothingAfterwards() async throws {
        let engine = SpeechEngine(locale: Locale(identifier: "en_US"))
        // A preparation that takes its time, and ends when it is called off.
        engine.prepare = { _ in
            try await Task.sleep(for: .seconds(30))
            return nil
        }
        engine.start()
        engine.stop()
        try await Task.sleep(nanoseconds: 700_000_000)
        #expect(engine.status.isAvailable,
                "a stopped listener went on to say: \(engine.status.reason ?? "")")

        // The control: left running, the same slow preparation does say that
        // a model is installing.
        let waiting = SpeechEngine(locale: Locale(identifier: "en_US"))
        waiting.prepare = { _ in
            try await Task.sleep(for: .seconds(30))
            return nil
        }
        waiting.start()
        defer { waiting.stop() }
        #expect(await wait(upTo: 5) { waiting.status.reason?.contains("installing") == true })
    }

    // MARK: A file paused and played again

    private func advance(_ player: AudioPlayer, frames: Int) {
        for _ in 0..<frames { player.advance(by: 1.0 / 60) }
    }

    /// `pause()` keeps the place and `play()` carries on from it. `play()`
    /// on a file that is playing, was stopped, or played out starts it from
    /// the top, so a sound can still be struck again.
    @Test func playAfterPauseCarriesOnFromWhereItPaused() throws {
        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }
        let url = try AudioPlayerTests.writeClickTrack(seconds: 1.5)
        defer { try? FileManager.default.removeItem(at: url) }
        let player = try AudioPlayer(url: url)

        player.play()
        advance(player, frames: 31)        // the first advance only arms the clock
        let place = player.headlessPosition
        #expect(place > 0)

        player.pause()
        #expect(!player.isPlaying)
        advance(player, frames: 10)
        #expect(player.headlessPosition == place, "a paused file holds its place")

        player.play()
        #expect(player.isPlaying)
        #expect(player.headlessPosition == place,
                "play() after pause() went to \(player.headlessPosition), not back to \(place)")
        advance(player, frames: 3)
        #expect(player.headlessPosition > place)

        // Playing: play() strikes it again from the top.
        player.play()
        #expect(player.headlessPosition == 0)

        // Stopped: from the top.
        advance(player, frames: 12)
        player.stop()
        player.play()
        #expect(player.headlessPosition == 0 && player.isPlaying)

        // Paused and then stopped: the place is gone with the stop.
        advance(player, frames: 12)
        player.pause()
        player.stop()
        player.play()
        #expect(player.headlessPosition == 0)

        // Played out: from the top.
        advance(player, frames: 200)
        #expect(!player.isPlaying, "a 1.5 s file has ended after 200 frames")
        player.play()
        #expect(player.headlessPosition == 0 && player.isPlaying)

        // Played out while paused is not a thing: a pause at the very end
        // still resumes into the end, and the next play() starts over.
    }

    /// Writes a silent mono file, so the live engine can be run without a
    /// sound leaving the machine.
    private func writeSilence(seconds: Double) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-silence-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        let count = AVAudioFrameCount(44100 * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count)!
        buffer.frameLength = count          // a fresh buffer is zeros
        try file.write(from: buffer)
        return url
    }

    /// Wait on the main actor until `probe` holds, the probe before the clock.
    private func wait(upTo seconds: Double, _ probe: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while true {
            if probe() { return true }
            if Date() >= deadline { return false }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    /// The same rule on the live engine, which is the one a person hears: a
    /// pause holds the place, `play()` carries on from it, and a file that
    /// played out starts from the top. The file is silent, and a machine
    /// with no way to play sound skips the test.
    @Test func playAfterPauseCarriesOnThroughTheLiveEngine() async throws {
        let url = try writeSilence(seconds: 0.9)
        defer { try? FileManager.default.removeItem(at: url) }
        let player = try AudioPlayer(url: url)
        defer { player.stop() }
        player.play()
        guard player.unavailableReason == nil else { return }       // no output device here

        guard await wait(upTo: 5, { (player.livePosition ?? 0) >= 0.3 }) else {
            // An engine that started and never rendered a sample is a machine
            // with nothing pulling sound out of it (a build runner): nothing
            // to hold here. One that rendered and then stood still is a fault.
            if let stuck = player.livePosition {
                Issue.record("the live engine started and stopped moving at \(stuck) s")
            }
            return
        }
        player.pause()
        let place = try #require(player.pausedAt)
        #expect(!player.isPlaying)
        try await Task.sleep(nanoseconds: 80_000_000)

        player.play()
        // Carried on, the node's count picks up at the place it paused at;
        // started over, the first reading would be near zero. The place was
        // read a render block ahead of where the node really stopped (about
        // 23 ms, measured), hence the slack.
        #expect(await wait(upTo: 5) { player.livePosition != nil })
        let resumed = player.livePosition ?? 0
        #expect(resumed >= place - 0.06, "play() after pause() read \(resumed) s, behind the pause at \(place) s")
        #expect(resumed < place + 0.3, "the pause itself was counted as playing")

        // Played out, then paused: there is nothing to carry on with, so
        // `play()` starts the file from the top.
        #expect(await wait(upTo: 5) { (player.livePosition ?? 0) >= 0.9 })
        player.pause()
        player.play()
        #expect(await wait(upTo: 5) { (player.livePosition ?? 1) < 0.3 },
                "a file that had played out did not start over: \(String(describing: player.livePosition))")
    }

    // MARK: Which note a full instrument gives up

    private func render(_ renderer: SynthRenderer, seconds: Double) {
        var left = Int(seconds * 44100)
        var chunk = [Float](repeating: 0, count: 512)
        while left > 0 {
            let count = min(512, left)
            chunk.withUnsafeMutableBufferPointer { renderer.render(into: $0, frameCount: count) }
            left -= count
        }
    }

    /// A note given a length is still being played until that length runs
    /// out. A full instrument gives up a note that has been let go before
    /// one that is still sounding, and among those the oldest: never the
    /// note that only just started, which is the quietest one there is while
    /// its attack is rising.
    @Test func aFullInstrumentKeepsTheNoteThatJustStarted() {
        let events = EventRing()
        let voice = Voice(waveform: .sine, envelope: Envelope(attack: 0.2, decay: 0.1, sustain: 0.8, release: 0.3))
        let renderer = SynthRenderer(voice: voice, polyphony: 2, sampleRate: 44100, events: events)
        let long = Int(5 * 44100.0)

        events.push(SynthEvent(kind: .noteOn, pitch: 60, velocity: 0.9, durationSamples: long))
        render(renderer, seconds: 0.5)          // the first note is up at its sustain
        events.push(SynthEvent(kind: .noteOn, pitch: 64, velocity: 0.9, durationSamples: long))
        render(renderer, seconds: 0.01)         // the second has barely begun to rise
        #expect(Set(renderer.soundingPitches) == [60, 64])

        events.push(SynthEvent(kind: .noteOn, pitch: 67, velocity: 0.9, durationSamples: long))
        render(renderer, seconds: 0.01)
        #expect(Set(renderer.soundingPitches) == [64, 67],
                "the instrument kept \(renderer.soundingPitches.sorted()): it gave up the newest note for the oldest")
    }

    /// A note that has been let go still goes before any note being played,
    /// timed or held.
    @Test func aNoteLetGoIsGivenUpBeforeOneStillPlayed() {
        let events = EventRing()
        let voice = Voice(waveform: .sine, envelope: Envelope(attack: 0.01, decay: 0.1, sustain: 0.8, release: 2))
        let renderer = SynthRenderer(voice: voice, polyphony: 2, sampleRate: 44100, events: events)

        events.push(SynthEvent(kind: .noteOn, pitch: 60, velocity: 0.9, durationSamples: Int(5 * 44100.0)))
        render(renderer, seconds: 0.2)
        // A short note that runs out and is left ringing in its release.
        events.push(SynthEvent(kind: .noteOn, pitch: 64, velocity: 0.9, durationSamples: Int(0.05 * 44100.0)))
        render(renderer, seconds: 0.2)
        #expect(Set(renderer.soundingPitches) == [60, 64])

        events.push(SynthEvent(kind: .noteOn, pitch: 67, velocity: 0.9, durationSamples: Int(5 * 44100.0)))
        render(renderer, seconds: 0.01)
        #expect(Set(renderer.soundingPitches) == [60, 67])
    }

    // MARK: The arpeggiator's hold

    /// Fingers never leave a chord in the same instant. With the hold on,
    /// the chord that plays on is the whole chord, not the last key to come
    /// up, and it stays whole while the fingers are leaving.
    @Test func theLatchKeepsTheWholeChordWhenTheKeysComeUpOneByOne() {
        let chord = [Pitch(60), Pitch(64), Pitch(67)]
        var arp = Arpeggiator(latches: true)
        for pitch in chord { arp.hold(pitch) }
        #expect(arp.playing == chord)

        arp.release(Pitch(67))
        #expect(arp.playing == chord, "one finger up, and the chord shrank to \(arp.playing)")
        arp.release(Pitch(64))
        arp.release(Pitch(60))
        #expect(arp.notes.isEmpty)
        #expect(arp.playing == chord, "every finger up, and the hold kept \(arp.playing)")

        // The same through the frame-by-frame form a controller reports.
        var framed = Arpeggiator(latches: true)
        framed.notes = chord
        framed.notes = [Pitch(60), Pitch(64)]
        framed.notes = [Pitch(60)]
        framed.notes = []
        #expect(framed.playing == chord)

        // A key added while one is still down joins the chord.
        var grown = Arpeggiator(latches: true)
        grown.hold(Pitch(60))
        grown.hold(Pitch(64))
        grown.release(Pitch(64))
        grown.hold(Pitch(67))
        grown.release(Pitch(60))
        grown.release(Pitch(67))
        #expect(grown.playing == chord)

        // The next key down after every key came up is a new chord.
        arp.hold(Pitch(62))
        #expect(arp.playing == [Pitch(62)])

        // Without the hold, what plays is what is held, as before.
        var plain = Arpeggiator()
        for pitch in chord { plain.hold(pitch) }
        plain.release(Pitch(67))
        #expect(plain.playing == [Pitch(60), Pitch(64)])
        plain.notes = []
        #expect(plain.playing.isEmpty)

        // The hold switched on takes the keys that are down now, and none
        // that came up before it.
        plain.hold(Pitch(72))
        plain.hold(Pitch(76))
        plain.release(Pitch(76))
        plain.latches = true
        plain.release(Pitch(72))
        #expect(plain.playing == [Pitch(72)])
    }
}
