import Foundation
import AVFoundation
import Vision
import CoreImage

/// Runs the **front camera** through a plain capture session and computes a person
/// matte per frame with Vision's on-device person segmentation, streaming the same
/// `PhoneSegmentationSample` the rear-camera Segment mode sends, so the Mac side
/// needs nothing new. ARKit's person segmentation is rear-only, which is why this
/// path exists: it is the one sensor that runs without an ARKit session (and
/// therefore the one mode with no light estimate to report).
///
/// Two properties are set on the capture connection before any frame flows, and
/// they are what keep the payload simple:
///
/// - **Rotation.** The connection rotates each buffer upright for how the phone is
///   held (`AVCaptureDevice.RotationCoordinator`, hardware-assisted), so the model
///   sees an upright person, the wire's `orientation` turn count is always 0, and
///   the Mac rotates nothing.
/// - **Mirroring.** The buffer is mirrored like the front-camera preview, so the
///   feed reads as a mirror on the canvas (the selfie convention). The matte is
///   computed *from the mirrored buffer*, so matte and color stay aligned by
///   construction. A sketch that wants the unmirrored view flips it back when
///   drawing.
///
/// Threading: frames arrive on a private capture queue and the Vision pass, the
/// matte copy/downscale, and the JPEG encode all run there (off the main thread,
/// unlike the ARKit streamers, whose callbacks land on main). The finished sample
/// is handed to the main thread, where `onSegmentation` fires: the same contract
/// as every other streamer. `@unchecked Sendable` under that discipline: the
/// handler is wired on the main thread before `start()`, and the session state is
/// touched only on the capture queue.
final class SelfieStreamer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {

    /// Fired (on the main thread) for each frame with its matte. `isTracked` means
    /// someone is actually in view (the matte has ink), since a capture session has
    /// no tracking state to report.
    var onSegmentation: ((PhoneSegmentationSample) -> Void)?

    /// Whether this device has a front camera to run.
    static var hasFrontCamera: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) != nil
    }

    /// The longest matte dimension sent over the wire: the same bound as the
    /// rear-camera path, for the same reason. It's a soft mask the Mac rescales
    /// onto the color.
    private let maxMatteDimension = 512
    /// The longest color dimension sent over the wire (the cutout's resolution).
    private let maxColorDimension = 960

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "dev.ollin.selfie-capture")
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    private var configured = false
    private weak var videoConnection: AVCaptureConnection?
    private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?

    func start() {
        guard Self.hasFrontCamera else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            queue.async { [weak self] in self?.run() }
        case .notDetermined:
            // The ARKit modes normally trigger the camera prompt first, but Selfie
            // must also work as the very first thing ever tapped.
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard granted, let self else { return }
                self.queue.async { self.run() }
            }
        default:
            break
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    /// On the capture queue: configure once, then run. `startRunning` blocks, which
    /// is why none of this happens on the main thread.
    private func run() {
        if !configured { configured = configure() }
        guard configured, !session.isRunning else { return }
        session.startRunning()
    }

    /// Build the session: front camera in, BGRA frames out at up to 30 fps, the
    /// connection rotating buffers upright and mirroring them. Returns whether the
    /// session is usable.
    private func configure() -> Bool {
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: camera) else { return false }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .hd1280x720
        guard session.canAddInput(input) else { return false }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        // The segmentation pass paces the stream: a frame that arrives while one is
        // still being worked on is dropped, never queued up.
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { return false }
        session.addOutput(output)

        // 30 fps is plenty for a matte and halves the segmentation + JPEG work.
        if let range = camera.activeFormat.videoSupportedFrameRateRanges.first,
           range.minFrameRate <= 30, 30 <= range.maxFrameRate,
           (try? camera.lockForConfiguration()) != nil {
            camera.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
            camera.unlockForConfiguration()
        }

        if let connection = output.connection(with: .video) {
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
            // Rotate the delivered buffers upright for the current device hold, and
            // keep them upright when the phone turns. (If a hold ever reads rotated
            // on-device, this is the one knob; the matte can't misalign with the
            // color, since Vision runs on the delivered buffer.)
            videoConnection = connection
            let coordinator = AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: nil)
            rotationCoordinator = coordinator
            let angle = coordinator.videoRotationAngleForHorizonLevelCapture
            if connection.isVideoRotationAngleSupported(angle) {
                connection.videoRotationAngle = angle
            }
            rotationObservation = coordinator.observe(
                \.videoRotationAngleForHorizonLevelCapture, options: [.new]
            ) { [weak self] _, change in
                guard let connection = self?.videoConnection, let angle = change.newValue,
                      connection.isVideoRotationAngleSupported(angle) else { return }
                connection.videoRotationAngle = angle
            }
        }
        return true
    }

    // MARK: AVCaptureVideoDataOutputSampleBufferDelegate

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds

        // The matte, from the (already upright, already mirrored) frame. Byte output
        // is requested explicitly so the shared plane helpers apply.
        let request = VNGeneratePersonSegmentationRequest()
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
        guard (try? handler.perform([request])) != nil,
              let matteBuffer = request.results?.first?.pixelBuffer,
              let (w, h, native) = bytePixels(matteBuffer) else { return }
        let (mw, mh, matte) = downscalePlane(native, width: w, height: h, maxDimension: maxMatteDimension)

        guard let jpeg = cameraJPEG(from: pixelBuffer, context: ciContext,
                                    maxDimension: maxColorDimension, quality: 0.6) else { return }

        // "Tracked" here means a person is in view: the matte carries some ink
        // (early-exits on the first lit pixel; a full scan of an empty matte is
        // a fraction of a millisecond).
        let someoneInView = matte.contains { $0 > 32 }

        // Orientation 0: the buffers already arrive upright, so the Mac rotates
        // nothing and matte/color alignment is by construction.
        let sample = PhoneSegmentationSample(
            isTracked: someoneInView, timestamp: timestamp,
            matteWidth: mw, matteHeight: mh, orientation: 0,
            matte: matte, colorJPEG: jpeg)
        DispatchQueue.main.async { [weak self] in self?.onSegmentation?(sample) }
    }
}
