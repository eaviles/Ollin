import Foundation
import AVFoundation
import SoundAnalysis

/// Runs the on-device sound classifier over the phone's microphone and turns
/// each judged window into a `PhoneSoundSample`: every label the classifier
/// knows, with how sure it is of each, strongest first, on the audio clock.
///
/// The phone sends the whole judgment and the Mac decides what counts as a
/// sound starting, because the wire runs one way and the sketch is where a
/// threshold belongs. The built-in classifier (three hundred-odd everyday
/// sounds) judges a second and a half of audio at a time, half overlapped, so a
/// reading goes out about every three quarters of a second: a few kilobytes,
/// nothing beside a depth frame.
///
/// This is the app's one sensor that needs no camera, so it runs beside
/// whichever mode is on and survives a mode switch; the screen's **Hear**
/// switch is what starts and stops it, since the microphone asks its own
/// permission and a person may not want it open. The microphone's samples
/// never leave the phone: only the labels do.
///
/// The classifier runs on its own serial queue, fed from the audio engine's
/// tap; results come back on that queue and are handed to the main thread,
/// where `onSound` fires. `@unchecked Sendable` under the usual discipline: the
/// handler is wired on the main thread before `start()`, the engine and the
/// session are touched only on the main thread, and the analyzer only on its
/// queue.
final class SoundStreamer: NSObject, SNResultsObserving, @unchecked Sendable {

    /// Fired (on the main thread) with each judged window.
    var onSound: ((PhoneSoundSample) -> Void)?

    /// Fired (on the main thread) when listening cannot start or stops on its
    /// own, with the reason for the screen; `nil` once it is running again.
    var onStatus: ((String?) -> Void)?

    /// How much audio each judgment is made from, in seconds. The Mac's own
    /// classifier settled on this length by measurement (a shorter window reads
    /// a click train as a synthesizer), so the phone judges the same way.
    private let windowDuration = 1.5

    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "dev.ollin.sound-classifying", qos: .userInitiated)
    /// Touched only on `queue`.
    private var analyzer: SNAudioStreamAnalyzer?
    private var firstSampleTime: AVAudioFramePosition?
    /// Main-thread-only: whether the engine has been asked to run.
    private(set) var isRunning = false

    /// Start listening: ask for the microphone if it has not been asked for,
    /// open the audio session, and feed the engine's input into the classifier.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self, self.isRunning else { return }
                guard granted else {
                    self.isRunning = false
                    self.onStatus?("microphone not allowed (Settings ▸ Ollin Capture)")
                    return
                }
                self.run()
            }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted(_:)),
                                               name: AVAudioSession.interruptionNotification,
                                               object: AVAudioSession.sharedInstance())
    }

    /// Stop listening and release the microphone.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification,
                                                  object: AVAudioSession.sharedInstance())
        tearDown()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: The engine

    /// On the main thread, with permission granted.
    private func run() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
        } catch {
            onStatus?("the microphone could not be opened: \(error.localizedDescription)")
            return
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            onStatus?("the microphone reports no audio format")
            return
        }
        guard let request = try? SNClassifySoundRequest(classifierIdentifier: .version1) else {
            onStatus?("the sound classifier could not be loaded on this phone")
            return
        }
        request.windowDuration = CMTime(seconds: windowDuration, preferredTimescale: 48_000)

        let analyzer = SNAudioStreamAnalyzer(format: format)
        do { try analyzer.add(request, withObserver: self) } catch {
            onStatus?("the sound classifier rejected the microphone: \(error.localizedDescription)")
            return
        }
        queue.sync {
            self.analyzer = analyzer
            self.firstSampleTime = nil
        }

        // The tap runs on the audio thread; the analysis runs on its own queue so
        // the audio thread never waits on the model. Positions are made relative
        // to the first buffer, so times on the wire count from when listening
        // began rather than from the device's clock.
        input.installTap(onBus: 0, bufferSize: 8192, format: format) { [weak self] buffer, when in
            guard let self else { return }
            self.queue.async {
                guard let analyzer = self.analyzer else { return }
                let first = self.firstSampleTime ?? when.sampleTime
                self.firstSampleTime = first
                analyzer.analyze(buffer, atAudioFramePosition: when.sampleTime - first)
            }
        }
        do {
            try engine.start()
            onStatus?(nil)
        } catch {
            input.removeTap(onBus: 0)
            onStatus?("the audio engine would not start: \(error.localizedDescription)")
        }
    }

    /// On the main thread.
    private func tearDown() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        queue.sync {
            analyzer?.completeAnalysis()
            analyzer = nil
        }
    }

    /// A phone call or another app taking the microphone pauses the engine; when
    /// the interruption ends, start again so the Mac's readings resume.
    @objc private func interrupted(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            onStatus?("paused: something else has the microphone")
        case .ended:
            guard isRunning else { return }
            tearDown()
            run()
        @unknown default:
            break
        }
    }

    // MARK: SNResultsObserving (on `queue`)

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let result = result as? SNClassificationResult else { return }
        let labels = result.classifications.map {
            PhoneSoundClassification(label: $0.identifier, confidence: Float($0.confidence))
        }
        let sample = PhoneSoundSample(timestamp: result.timeRange.start.seconds,
                                      duration: result.timeRange.duration.seconds,
                                      classifications: labels)
        DispatchQueue.main.async { [weak self] in self?.onSound?(sample) }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        let reason = "sound classification stopped: \(error.localizedDescription)"
        DispatchQueue.main.async { [weak self] in self?.onStatus?(reason) }
    }

    func requestDidComplete(_ request: SNRequest) {}
}
