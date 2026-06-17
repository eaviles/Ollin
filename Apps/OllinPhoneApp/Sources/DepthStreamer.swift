import Foundation
import ARKit
import simd
import CoreImage
import ImageIO
import UniformTypeIdentifiers

/// Runs ARKit world tracking with scene depth (the rear **LiDAR** camera) and turns
/// each frame into a `PhoneDepthSample` — a metric depth map, the matching JPEG
/// color image, the depth-grid camera intrinsics, per-pixel confidence, and the
/// 6DoF camera pose, which the Mac unprojects into a point cloud.
///
/// Scene depth needs a LiDAR sensor (Pro-tier iPhones), so this is gated on
/// `ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth)`. World
/// tracking uses the rear camera, so it's mutually exclusive with face tracking;
/// it shares the rear camera with body tracking but runs its own session.
///
/// ARKit delivers its delegate callbacks on the main thread, so `onDepth` fires on
/// main; the depth-map copy, intrinsics scaling, and JPEG encode all run there.
final class DepthStreamer: NSObject, ARSessionDelegate {

    /// Fired (on the main thread) for each frame that carries scene depth.
    var onDepth: ((PhoneDepthSample) -> Void)?

    /// Whether this device has a LiDAR sensor for scene depth.
    var isSupported: Bool { ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) }

    /// The longest color dimension sent over the wire — the captured image is
    /// downscaled to this so the JPEG stays small (the cloud's color resolution
    /// only feeds a 256×192 depth grid, so full capture resolution is wasted bytes).
    private let maxColorDimension = 960

    private let session = ARSession()
    private let ciContext = CIContext(options: [.cacheIntermediates: false])

    func start() {
        guard isSupported else { return }
        session.delegate = self
        let config = ARWorldTrackingConfiguration()
        // Smoothed depth is steadier frame-to-frame (kinder to a cloud); fall back to
        // raw scene depth if the device only offers that.
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            config.frameSemantics.insert(.smoothedSceneDepth)
        } else {
            config.frameSemantics.insert(.sceneDepth)
        }
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() { session.pause() }

    // MARK: ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard let sceneDepth = frame.smoothedSceneDepth ?? frame.sceneDepth else { return }

        guard let (depthW, depthH, depth) = floatPixels(sceneDepth.depthMap) else { return }
        let confidence = sceneDepth.confidenceMap.flatMap { bytePixels($0) }?.data

        guard let jpeg = cameraJPEG(from: frame.capturedImage, context: ciContext,
                                    maxDimension: maxColorDimension, quality: 0.6) else { return }

        // Intrinsics arrive at the captured-image resolution; bring them onto the
        // depth grid so the Mac builds a `CameraIntrinsics` against depthW×depthH.
        let res = frame.camera.imageResolution
        let k = frame.camera.intrinsics
        let sx = Float(depthW) / Float(res.width)
        let sy = Float(depthH) / Float(res.height)

        let normal: Bool = if case .normal = frame.camera.trackingState { true } else { false }
        onDepth?(PhoneDepthSample(
            tracked: normal,
            timestamp: frame.timestamp,
            depthWidth: depthW, depthHeight: depthH,
            fx: k.columns.0.x * sx, fy: k.columns.1.y * sy,
            cx: k.columns.2.x * sx, cy: k.columns.2.y * sy,
            cameraTransform: frame.camera.transform,
            colorJPEG: jpeg, depth: depth,
            confidence: (confidence?.count == depth.count) ? confidence : nil))
    }
}
