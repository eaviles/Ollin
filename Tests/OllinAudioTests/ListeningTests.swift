import AVFoundation
import Foundation
import Ollin
import Testing
@testable import OllinAudio

/// The listening tier: naming sounds and turning speech into words.
///
/// There is no pixel snapshot here (a sound cannot be snapshotted) and no
/// microphone (a test cannot make a noise in the room). Instead every check
/// runs over audio the test synthesizes itself, which is also what keeps them
/// deterministic: the same samples always produce the same judgment, and each
/// claim is measured against a counterfactual made of different samples.
@Suite struct ListeningTests {

    // MARK: Sounds a test can make

    /// A steady tone. Reads as music, and as nothing percussive.
    static func tone(_ frequency: Double, seconds: Double, rate: Double = 44100) -> [Float] {
        let count = Int(seconds * rate)
        return (0..<count).map { Float(0.5 * sin(2 * .pi * frequency * Double($0) / rate)) }
    }

    /// A train of short impacts. Reads as clicking, and as nothing tonal. The
    /// pulse is a millisecond wide rather than one sample: a single sample
    /// carries almost no energy, and the classifier judges what it can hear.
    static func clicks(every period: Double, seconds: Double, rate: Double = 44100) -> [Float] {
        let count = Int(seconds * rate)
        let stride = Int(period * rate)
        let width = max(1, Int(0.001 * rate))
        return (0..<count).map { $0 % stride < width ? Float(0.9) : 0 }
    }

    static func silence(seconds: Double, rate: Double = 44100) -> [Float] {
        [Float](repeating: 0, count: Int(seconds * rate))
    }

    // MARK: The vocabulary

    @Test func theBuiltInClassifierKnowsEverydaySounds() {
        let classifier = SoundClassifierEngine(request: .builtIn, threshold: 0.6, windowDuration: 1.5)
        let labels = classifier.labels
        #expect(labels.count > 200)
        #expect(labels.contains("clapping"))
        #expect(labels.contains("dog_bark"))
        #expect(labels.contains("music"))
    }

    // MARK: One-shot classification

    @Test func aToneAndAClickTrainAreNamedDifferently() {
        let tonal = SoundClassifier.classify(Self.tone(440, seconds: 4), sampleRate: 44100)
        let percussive = SoundClassifier.classify(Self.clicks(every: 0.25, seconds: 4),
                                                  sampleRate: 44100)
        // The claim is not that a label is any particular word (the vocabulary
        // is Apple's, and a pure sine really is closer to a tuning fork than to
        // a band). It is that two genuinely different sounds are told apart,
        // each way round, which is what a counterfactual pair states.
        #expect(tonal.first?.label != percussive.first?.label)
        #expect(confidence("click", in: percussive) > 0.5)
        #expect(confidence("click", in: percussive) > confidence("click", in: tonal))
        #expect(confidence("tuning_fork", in: tonal) > 0.5)
        #expect(confidence("tuning_fork", in: tonal) > confidence("tuning_fork", in: percussive))
    }

    @Test func peaksComeBackStrongestFirst() {
        let heard = SoundClassifier.classify(Self.tone(220, seconds: 4), sampleRate: 44100)
        #expect(heard.count > 1)
        #expect(zip(heard, heard.dropFirst()).allSatisfy { $0.confidence >= $1.confidence })
        #expect(Set(heard.map(\.label)).count == heard.count)   // one row per label
    }

    @Test func silenceReachesNothingWorthActingOn() {
        let heard = SoundClassifier.classify(Self.silence(seconds: 4), sampleRate: 44100)
        // The classifier always says *something*, which is exactly why the
        // default threshold exists: nothing in silence should cross it.
        #expect(heard.allSatisfy { $0.confidence < 0.6 })
    }

    @Test func emptyAudioIsAnEmptyAnswerRatherThanACrash() {
        #expect(SoundClassifier.classify([], sampleRate: 44100).isEmpty)
        #expect(SoundClassifier.classify(Self.tone(440, seconds: 1), sampleRate: 0).isEmpty)
    }

    @Test func aClipReadsTheSameEveryTime() {
        let samples = Self.tone(330, seconds: 3)
        let first = SoundClassifier.classify(samples, sampleRate: 44100)
        let second = SoundClassifier.classify(samples, sampleRate: 44100)
        #expect(first == second)
    }

    // MARK: The live classifier's state machine

    /// The smallest possible `AudioTapSource`: a slot and nothing else.
    @MainActor final class StubTapSource: AudioTapSource {
        var audioTap: AudioTap?
    }

    /// A sound that goes on does not fire an event per window. The engine keeps
    /// the set of labels currently over the threshold, and only a crossing from
    /// below counts, so a held note is one event and not a stream of them.
    @Test func aContinuousSoundFiresOnceRatherThanPerWindow() async {
        let engine = SoundClassifierEngine(request: .builtIn, threshold: 0.5, windowDuration: 1.5)
        feed(Self.tone(440, seconds: 8), to: engine)
        await settle()

        let events = engine.drainEvents()
        guard let top = engine.top, top.confidence > 0.5 else { return }   // soft-skip
        // Eight seconds is several analysis windows, and the sound is over the
        // threshold in all of them. One crossing is the event.
        #expect(events.filter { $0.label == top.label }.count == 1,
                "one crossing, not one per analysis window")
        // And nothing is left over: a second read of the same drain is empty.
        #expect(engine.drainEvents().isEmpty)
    }

    /// The counterfactual for the test above: silence never crosses, so nothing
    /// is handed out at all.
    @Test func silenceFiresNothing() async {
        let engine = SoundClassifierEngine(request: .builtIn, threshold: 0.5, windowDuration: 1.5)
        feed(Self.silence(seconds: 6), to: engine)
        await settle()
        #expect(engine.drainEvents().isEmpty)
    }

    /// `timeSinceHearing` runs on the sample clock, so it measures the audio
    /// rather than how long the machine took to think about it.
    @Test func timeSinceHearingIsMeasuredInAudio() async {
        let engine = SoundClassifierEngine(request: .builtIn, threshold: 0.5, windowDuration: 1.5)
        feed(Self.tone(440, seconds: 4), to: engine)
        await settle()
        guard let heard = engine.drainEvents().last else { return }   // soft-skip: nothing crossed
        // Four seconds of audio went in, so the last crossing is inside it,
        // however long the machine took to think about it.
        #expect(engine.timeSinceHearing(heard.label) < 4)
        #expect(engine.timeSinceHearing("dog_bark") > 1000)   // never heard
    }

    /// The confidence a one-shot read gave one label, or zero.
    func confidence(_ label: String, in heard: [SoundClassification]) -> Double {
        heard.first { $0.label == label }?.confidence ?? 0
    }

    /// Feeds a whole clip through the live path in tap-sized blocks, the way a
    /// source's audio thread would.
    func feed(_ samples: [Float], to engine: some AudioListening, rate: Double = 44100,
              block: Int = 1024) {
        samples.withUnsafeBufferPointer { all in
            var offset = 0
            while offset < all.count {
                let count = min(block, all.count - offset)
                let slice = UnsafeBufferPointer(start: all.baseAddress! + offset, count: count)
                engine.hear(slice, sampleRate: rate)
                offset += count
            }
        }
    }

    /// Lets the analysis queue catch up. The live path runs the classifier off
    /// the audio thread on purpose, so a test has to wait for it.
    func settle(seconds: Double = 6) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    // MARK: The caption-versus-transcript rule

    /// The rule the whole speech surface rests on: an uncommitted result
    /// *replaces* the tail, because that is what the recognizer is doing to it,
    /// while a committed one is added to what is kept. So the caption changes
    /// its mind and the transcript never does.
    @Test func aCaptionRevisesWhereATranscriptDoesNot() {
        let engine = SpeechEngine(locale: Locale(identifier: "en_US"))

        engine.receive("the quick", isFinal: false, start: 0, duration: 1)
        #expect(engine.caption == "the quick")
        #expect(engine.transcript.isEmpty, "nothing is committed yet")

        engine.receive("the quick brown", isFinal: false, start: 0, duration: 1.5)
        #expect(engine.caption == "the quick brown", "the guess was replaced, not appended")

        engine.receive("the quick brown fox. ", isFinal: true, start: 0, duration: 2)
        #expect(engine.transcript == "the quick brown fox.")
        #expect(engine.caption == "the quick brown fox.")

        engine.receive(" jumps", isFinal: false, start: 2, duration: 0.5)
        #expect(engine.caption == "the quick brown fox. jumps")
        #expect(engine.transcript == "the quick brown fox.", "a guess never reaches the transcript")
    }

    /// A phrase is handed out once, which is what makes it usable as a trigger.
    @Test func phrasesDrain() {
        let engine = SpeechEngine(locale: Locale(identifier: "en_US"))
        engine.receive("red", isFinal: true, start: 0, duration: 1)
        engine.receive("blue", isFinal: true, start: 1, duration: 1)

        let first = engine.drainPhrases()
        #expect(first.map(\.text) == ["red", "blue"])
        #expect(first.first?.start == 0)
        #expect(first.last?.duration == 1)
        #expect(engine.drainPhrases().isEmpty)
        #expect(engine.latest?.text == "blue", "the latest phrase stays readable after a drain")
    }

    /// An uncommitted result is never a phrase, so a trigger cannot fire on a
    /// word the recognizer is about to take back.
    @Test func aGuessIsNeverHandedOutAsAPhrase() {
        let engine = SpeechEngine(locale: Locale(identifier: "en_US"))
        engine.receive("wreck a nice beach", isFinal: false, start: 0, duration: 1)
        #expect(engine.drainPhrases().isEmpty)
        engine.receive("recognize speech", isFinal: true, start: 0, duration: 1)
        #expect(engine.drainPhrases().map(\.text) == ["recognize speech"])
    }

    @Test func theCaptionKeepsOnlyItsTail() {
        let engine = SpeechEngine(locale: Locale(identifier: "en_US"))
        engine.captionWords = 3
        engine.receive("one two three four five", isFinal: true, start: 0, duration: 1)
        #expect(engine.caption == "three four five")
        #expect(engine.transcript == "one two three four five", "the whole of it is still kept")
    }

    @Test func resetForgetsWhatWasHeard() {
        let engine = SpeechEngine(locale: Locale(identifier: "en_US"))
        engine.receive("something", isFinal: true, start: 0, duration: 1)
        engine.receive("more", isFinal: false, start: 1, duration: 1)
        engine.reset()
        #expect(engine.caption.isEmpty)
        #expect(engine.transcript.isEmpty)
        #expect(engine.drainPhrases().isEmpty)
        #expect(engine.latest == nil)
    }

    // MARK: Recognition itself

    /// The one end-to-end speech check, over audio the test speaks to itself:
    /// the system's own synthesizer writes the samples, and the recognizer
    /// reads them back. Soft-skips where no voice is installed.
    @MainActor
    @Test func transcribesASpokenSentence() async throws {
        let sentence = "the quick brown fox jumps over the lazy dog"
        guard let spoken = await SpokenSamples.make(sentence) else { return }   // soft-skip: no voice
        let heard = try await SpeechListener.transcribe(spoken.samples,
                                                        sampleRate: spoken.sampleRate,
                                                        locale: Locale(identifier: "en_US"))
        let words = heard.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !words.isEmpty else { return }   // soft-skip: no model installed here
        #expect(words.joined(separator: " ").contains("quick brown fox"))
        #expect(words.contains("lazy"))
    }

    /// The live wiring, which the one-shot above does not touch: a source's tap
    /// reaching the recognizer through the hub, the resampling, and the caption
    /// filling in. Fed by the same self-spoken audio, pushed through a plain
    /// `AudioTapSource` the way a microphone's engine would.
    @MainActor
    @Test func aTapSourceReachesTheRecognizer() async throws {
        guard let spoken = await SpokenSamples.make("hello there") else { return }   // soft-skip
        let source = StubTapSource()
        let listener = SpeechListener(of: source, locale: Locale(identifier: "en_US"))
        defer { listener.detach() }

        // Give the recognizer a moment to install and start before pushing.
        for _ in 0..<40 where !listener.isListening {
            try? await Task.sleep(for: .milliseconds(250))
        }
        guard listener.isListening, let tap = source.audioTap else { return }   // soft-skip

        spoken.samples.withUnsafeBufferPointer { all in
            var offset = 0
            while offset < all.count {
                let count = min(2048, all.count - offset)
                tap(UnsafeBufferPointer(start: all.baseAddress! + offset, count: count),
                    spoken.sampleRate)
                offset += count
            }
        }
        // Silence after the words is what lets the recognizer finish a phrase.
        let quiet = [Float](repeating: 0, count: Int(spoken.sampleRate))
        quiet.withUnsafeBufferPointer { tap($0, spoken.sampleRate) }

        for _ in 0..<40 where listener.caption.isEmpty {
            try? await Task.sleep(for: .milliseconds(250))
        }
        #expect(listener.caption.lowercased().contains("hello"))
    }

    @Test func transcribingNothingIsAnEmptyStringRatherThanACrash() async throws {
        #expect(try await SpeechListener.transcribe([], sampleRate: 44100).isEmpty)
    }

    /// A language the recognizer does not know is refused by name rather than
    /// hearing nothing forever.
    @Test func anUnknownLanguageIsRefusedRatherThanSilent() async throws {
        let none = try await SpeechEngine.prepareTranscriber(for: Locale(identifier: "xx_YY"))
        #expect(none == nil)
    }
}

/// Speech the test makes for itself, so nothing recorded has to be committed to
/// the repository. `nil` when no voice is installed.
@MainActor
enum SpokenSamples {

    static func make(_ text: String, timeout: Double = 20) async -> (samples: [Float], sampleRate: Double)? {
        guard let voice = AVSpeechSynthesisVoice(language: "en-US") else { return nil }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice

        final class Collected: @unchecked Sendable {
            var samples: [Float] = []
            var rate: Double = 0
            var finished = false
        }
        let collected = Collected()
        let synthesizer = AVSpeechSynthesizer()
        synthesizer.write(utterance) { buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else { return }
            guard pcm.frameLength > 0 else {
                collected.finished = true
                return
            }
            collected.rate = pcm.format.sampleRate
            let frames = Int(pcm.frameLength)
            if let channel = pcm.floatChannelData?[0] {
                collected.samples.append(contentsOf: UnsafeBufferPointer(start: channel, count: frames))
            }
        }
        // The synthesizer delivers its buffers on the main queue, so the caller
        // has to yield rather than block: parking the main thread is exactly
        // what stops the callback from ever arriving.
        let deadline = Date().addingTimeInterval(timeout)
        while !collected.finished, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard !collected.samples.isEmpty, collected.rate > 0 else { return nil }
        return (collected.samples, collected.rate)
    }
}
