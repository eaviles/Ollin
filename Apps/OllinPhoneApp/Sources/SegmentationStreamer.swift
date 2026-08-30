import Foundation
import ARKit
import CoreImage
import UIKit

/// Runs ARKit world tracking with **person segmentation** (the rear camera) and
/// turns each frame into a `PhoneSegmentationSample` — a grayscale person matte
/// computed on the Neural Engine plus the matching JPEG color frame, which the Mac
/// turns into a tintable silhouette and a person cutout.
///
/// Person segmentation needs an A12+ device, so this is gated on
/// `ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentation)`. It
/// uses the rear camera (its own session), so it's mutually exclusive with face
/// tracking and shares the camera with body/depth.
///
/// ARKit delivers its delegate callbacks on the main thread, so `onSegmentation`
/// fires on main; the matte copy/downscale and the JPEG encode all run there.
final class SegmentationStreamer: NSObject, ARSessionDelegate, LightReporting {

    /// Fired (on the main thread) for each frame that carries a segmentation matte.
    var onSegmentation: ((PhoneSegmentationSample) -> Void)?

    let lightSampler = LightSampler()

    /// Whether this device supports ARKit person segmentation.
    var isSupported: Bool { ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentation) }

    /// The longest matte dimension sent over the wire — the buffer is downscaled to
    /// this. A soft mask the Mac rescales onto the color, so a bounded size keeps the
    /// payload small while staying crisp enough for a cutout edge.
    private let maxMatteDimension = 512
    /// The longest color dimension sent over the wire (the cutout's resolution).
    private let maxColorDimension = 960

    private let session = ARSession()
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    func start() {
        guard isSupported else { return }
        session.delegate = self
        let config = ARWorldTrackingConfiguration()
        config.frameSemantics.insert(.personSegmentation)
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() { session.pause() }

    // MARK: ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Before the matte guard, so the room's light keeps arriving on a frame with
        // nobody in it.
        lightSampler.report(frame)
        guard let buffer = frame.segmentationBuffer,
              let (w, h, native) = bytePixels(buffer) else { return }
        // The matte and the color come from the same frame, so they're in the same
        // (camera-native) orientation and line up; bound the matte's resolution.
        let (mw, mh, matte) = downscalePlane(native, width: w, height: h, maxDimension: maxMatteDimension)

        guard let jpeg = cameraJPEG(from: frame.capturedImage, context: ciContext,
                                    maxDimension: maxColorDimension, quality: 0.6) else { return }

        let normal: Bool = if case .normal = frame.camera.trackingState { true } else { false }
        // The shared device-hold mapping supplies the turn count; a wrong direction
        // there can't break matte/color alignment, since the Mac turns both by the
        // same N.
        onSegmentation?(PhoneSegmentationSample(
            isTracked: normal, timestamp: frame.timestamp,
            matteWidth: mw, matteHeight: mh, orientation: captureQuarterTurns(),
            matte: matte, colorJPEG: jpeg))
    }
}
