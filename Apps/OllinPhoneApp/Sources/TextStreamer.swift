import Foundation
import ARKit
import Vision
import simd

/// Runs ARKit world tracking on the rear camera and reads the text in each frame
/// with the on-device recognizer (Vision), turning each line into a
/// `PhoneTextSample`: what it says, the reader's confidence, and the line's four
/// corners as upright 2D image points, plus, on a LiDAR phone, a metric 3D
/// position per corner in ARKit world space, lifted through the scene-depth map
/// and the camera pose. World tracking runs on any device, so the mode always
/// works; without LiDAR the lines simply stay 2D.
///
/// The recognizer is the expensive part, so it runs on its own serial queue
/// behind a drop-if-busy gate: a frame that arrives while one is being read is
/// skipped, never queued, and the camera never backs up. It reads at the
/// accurate level, because text in a room is small in the frame and the fast
/// level misses it; a few finished readings a second is plenty for signs, which
/// mostly hold still. Everything the lift needs is copied out of the frame
/// *inside* the delegate callback (the shared `LiftContext`); only the capture
/// pixel buffer rides to the queue by reference, held for at most one pass.
///
/// The recognizer wants an upright picture, so the request is handed the
/// device-hold orientation; its corners come back in the upright frame and go
/// onto the wire that way, and the lift maps each back onto the camera-native
/// depth grid with the shared quarter-turn arithmetic. A line lifts all four
/// corners or none: three lifted corners are not a quad.
///
/// The finished set is handed to the main thread, where `onTexts` fires: the
/// same contract as every other streamer, with the empty set meaning no
/// readable text is in view. `@unchecked Sendable` under the usual discipline:
/// the handler is wired on the main thread before `start()`, `busy` is touched
/// only on the main thread, and the reading pass touches only its own copies.
final class TextStreamer: NSObject, ARSessionDelegate, LightReporting, @unchecked Sendable {

    /// Fired (on the main thread) with each analyzed frame's lines; empty when
    /// no readable text is in view, so a sign leaving clears itself.
    var onTexts: (([PhoneTextSample]) -> Void)?

    let lightSampler = LightSampler()

    /// Whether the lines lift to 3D here (scene depth needs LiDAR).
    var liftsTo3D: Bool { ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) }

    /// Lines below this confidence are dropped (a misread glint or texture).
    private let minimumLineConfidence: Float = 0.3

    private let session = ARSession()
    private let queue = DispatchQueue(label: "dev.ollin.text-reading")
    /// Main-thread-only: whether a reading pass is in flight (the drop-if-busy gate).
    private var busy = false

    func start() {
        session.delegate = self
        let config = ARWorldTrackingConfiguration()
        // Smoothed depth is steadier frame-to-frame (kinder to a lifted corner);
        // fall back to raw scene depth, and run without either on a non-LiDAR
        // phone (the lines then stay 2D).
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            config.frameSemantics.insert(.smoothedSceneDepth)
        } else if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() { session.pause() }

    // MARK: ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Before the busy gate, so the room's light keeps arriving while a
        // reading pass is in flight.
        lightSampler.report(frame)
        guard !busy else { return }
        busy = true

        // Copy everything the pass needs out of the frame now, on the callback:
        // the frame's buffers are the session's own, and only the capture pixel
        // buffer (which CoreVideo reference-counts) rides along.
        let pixelBuffer = frame.capturedImage
        let timestamp = frame.timestamp
        let turns = captureQuarterTurns()
        let isTracked: Bool = if case .normal = frame.camera.trackingState { true } else { false }
        let lift = liftContext(of: frame)

        queue.async { [weak self] in
            guard let self else { return }
            let texts = self.readTexts(in: pixelBuffer, timestamp: timestamp,
                                       isTracked: tracked, turns: turns, lift: lift)
            DispatchQueue.main.async {
                self.busy = false
                if let texts { self.onTexts?(texts) }
            }
        }
    }

    // MARK: The reading pass (on the text queue)

    /// Run the recognizer over one frame and lift what it reads. Returns `nil`
    /// when the pass itself failed (the last good set stays put on the Mac), and
    /// the empty list when it ran and read nothing.
    private func readTexts(in pixelBuffer: CVPixelBuffer, timestamp: Double,
                           isTracked: Bool, turns: UInt8, lift: LiftContext?) -> [PhoneTextSample]? {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: visionOrientation(forQuarterTurnsCW: turns),
                                            options: [:])
        guard (try? handler.perform([request])) != nil else { return nil }

        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first,
                  !candidate.string.isEmpty,
                  candidate.confidence >= minimumLineConfidence else { return nil }
            // The observation's corners are normalized to the upright picture
            // (lower-left origin), the convention the wire carries.
            let corners = [observation.topLeft, observation.topRight,
                           observation.bottomRight, observation.bottomLeft]
                .map { SIMD2<Float>(Float($0.x), Float($0.y)) }
            var sample = PhoneTextSample(isTracked: tracked, timestamp: timestamp,
                                         text: candidate.string,
                                         confidence: Float(candidate.confidence),
                                         corners: corners)
            // All four corners or none: three lifted corners are not a quad.
            if let lift {
                let lifted = corners.compactMap { worldPosition(ofUpright: $0, turns: turns, lift: lift) }
                if lifted.count == 4 {
                    sample.hasWorldCorners = true
                    sample.worldCorners = lifted
                }
            }
            return sample
        }
    }
}
