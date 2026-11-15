import Foundation
import ARKit
import AVFoundation
import CoreMedia
import UIKit

/// Writes what the phone senses to a recording in the app's own Documents
/// folder, with no cable: the camera's video, the microphone's sound, and
/// every message the cable would have carried, frame for frame.
///
/// The files are written by `PhoneRecordingWriter`, in the file this app shares
/// with the Mac, so the format has one writer and the Mac's tests run it. This
/// class is the phone's half: where the folder goes, the microphone, and the
/// clock a message is stamped with.
///
/// A message is stamped with the time of the newest camera frame at the moment
/// it is handed over. That is the frame a sketch on the cable would first have
/// seen it on, so a recording plays back with the delays the phone really had.
///
/// Main-actor bound, like the ARKit callbacks that feed it. The microphone
/// delivers on a queue of its own, and what it delivers goes straight to the
/// writer, which is safe to call from any thread.
@MainActor
final class Recorder {

    /// Whether a recording is being written.
    private(set) var isRecording = false

    /// What the screen shows about the recording, or about the last one.
    private(set) var info = ""

    /// Fired (on the main thread) when `info` or `isRecording` changes.
    var onChange: (() -> Void)?

    private var writer: PhoneRecordingWriter?
    private var sound: SoundCapture?
    private var name = ""
    private var startedAt: TimeInterval = 0
    /// The newest camera frame's time, which stamps every other message. Zero
    /// until the first frame of this recording has been taken.
    private var frameTime: TimeInterval = 0
    private var lastReport: TimeInterval = 0

    /// Start a recording of `mode`, held the way the phone is held now.
    func start(mode: PhoneCaptureMode, quarterTurnsCW: UInt8) {
        guard !isRecording else { return }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        name = "\(mode.title) \(formatter.string(from: Date()))"
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let folder = documents.appendingPathComponent(name)
            .appendingPathExtension(PhoneRecordingFile.folderExtension)

        // The microphone is asked for once; a recording made without it is a
        // recording without sound, said on the screen.
        let granted = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        do {
            let writer = try PhoneRecordingWriter(
                folder: folder, mode: mode, quarterTurnsCW: quarterTurnsCW,
                device: UIDevice.current.model, framesPerSecond: 60, wantsSound: granted)
            self.writer = writer
            if granted {
                let capture = SoundCapture { [writer] buffer in writer.append(sound: buffer) }
                capture.start()
                sound = capture
            } else {
                AVCaptureDevice.requestAccess(for: .audio) { _ in }
            }
            isRecording = true
            frameTime = 0
            lastReport = 0
            startedAt = ProcessInfo.processInfo.systemUptime
            info = granted ? "starting…" : "starting… (no microphone: recording without sound)"
        } catch {
            info = "\(error)"
        }
        onChange?()
    }

    /// One frame of the camera: its picture and where the camera stood.
    func record(picture: CVPixelBuffer, camera: PhoneCameraSample) {
        guard isRecording, let writer else { return }
        frameTime = camera.timestamp
        writer.append(picture: picture, camera: camera)
        // The screen is told a few times a second, not sixty.
        if camera.timestamp - lastReport >= 0.25 {
            lastReport = camera.timestamp
            let seconds = Int(ProcessInfo.processInfo.systemUptime - startedAt)
            let dropped = writer.droppedFrames
            info = String(format: "%d:%02d · %d frames", seconds / 60, seconds % 60, writer.frameCount)
                + (dropped > 0 ? " · \(dropped) dropped" : "")
            onChange?()
        }
    }

    /// Any other message the cable would have carried.
    func record(_ message: PhoneMessage) {
        guard isRecording, let writer, frameTime > 0 else { return }
        writer.append(message, at: frameTime)
    }

    /// Close the recording. The files are finished off the main thread and the
    /// screen says so when they are.
    func stop() {
        guard isRecording, let writer else { return }
        isRecording = false
        sound?.stop()
        sound = nil
        self.writer = nil
        info = "saving…"
        onChange?()
        let name = name
        Task { @MainActor [weak self] in
            do {
                let saved = try await writer.finish()
                self?.info = "saved \(name) · \(saved.frameCount) frames"
                    + (saved.droppedFrames > 0 ? " · \(saved.droppedFrames) dropped" : "")
            } catch {
                self?.info = "\(error)"
            }
            self?.onChange?()
        }
    }
}

/// The microphone, for a recording: an audio-only capture session whose
/// buffers are restamped onto the clock the camera's frames are stamped on.
///
/// The session's own clock is the microphone's, and a camera frame is stamped
/// with the time since the phone started, so each buffer's time is converted
/// from the one to the other before the writer sees it. Without that the sound
/// would sit wherever the two clocks happened to disagree.
///
/// `@unchecked Sendable`: the session is started and stopped on its own queue,
/// and the delegate method runs on the output's queue and touches only what was
/// set at `init`.
private final class SoundCapture: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate,
                                  @unchecked Sendable {

    private let session = AVCaptureSession()
    private let output = AVCaptureAudioDataOutput()
    private let queue = DispatchQueue(label: "dev.ollin.recording.sound")
    private let onBuffer: @Sendable (CMSampleBuffer) -> Void

    init(onBuffer: @escaping @Sendable (CMSampleBuffer) -> Void) {
        self.onBuffer = onBuffer
    }

    func start() {
        queue.async { [self] in
            guard let microphone = AVCaptureDevice.default(for: .audio),
                  let input = try? AVCaptureDeviceInput(device: microphone),
                  session.canAddInput(input), session.canAddOutput(output) else { return }
            session.addInput(input)
            session.addOutput(output)
            output.setSampleBufferDelegate(self, queue: queue)
            session.startRunning()
        }
    }

    func stop() {
        queue.async { [self] in
            output.setSampleBufferDelegate(nil, queue: nil)
            session.stopRunning()
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let clock = session.synchronizationClock ?? CMClockGetHostTimeClock()
        guard let restamped = PhoneRecordingWriter.restamped(
            sampleBuffer, from: clock, to: CMClockGetHostTimeClock()) else { return }
        onBuffer(restamped)
    }
}
