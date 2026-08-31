import Foundation
import ARKit
import Vision
import CoreImage
import simd

/// Runs ARKit world tracking on the rear camera and maps where each frame draws
/// the eye with the on-device attention model (Vision), turning each reading into
/// a `PhoneSaliencySample`: the coarse heat map, the bounding regions it peaks in
/// (each with the model's confidence), and the matching JPEG color frame. On a
/// LiDAR phone each region's center also lifts to a metric 3D position in ARKit
/// world space, through the scene-depth map and the camera pose, the same lift
/// the hands and the text ride. World tracking runs on any device, so the mode
/// always works; without LiDAR the regions simply stay 2D.
///
/// The model is the expensive part, so it runs on its own serial queue behind a
/// drop-if-busy gate: a frame that arrives while one is being mapped is skipped,
/// never queued, and the camera never backs up. Everything the lift needs is
/// copied out of the frame *inside* the delegate callback (the shared
/// `LiftContext`); only the capture pixel buffer rides to the queue by reference,
/// held for at most one pass.
///
/// The model is handed the device-hold orientation, so its heat map and boxes
/// come back in the upright frame and go onto the wire that way; the color frame
/// stays camera-native and carries the turn count that stands it up on the Mac.
/// `@unchecked Sendable` under the usual discipline: the handler is wired on the
/// main thread before `start()`, `busy` is touched only on the main thread, and
/// the mapping pass touches only its own copies.
final class SaliencyStreamer: NSObject, ARSessionDelegate, LightReporting, @unchecked Sendable {

    /// Fired (on the main thread) with each analyzed frame's reading. Every
    /// reading carries a heat map; `regions` is empty when nothing stands out.
    var onSaliency: ((PhoneSaliencySample) -> Void)?

    let lightSampler = LightSampler()

    /// Whether the regions lift to 3D here (scene depth needs LiDAR).
    var liftsTo3D: Bool { ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) }

    /// The longest color dimension sent over the wire (the backdrop's resolution).
    private let maxColorDimension = 960

    private let session = ARSession()
    private let queue = DispatchQueue(label: "dev.ollin.attention")
    private let ciContext = CIContext(options: [.cacheIntermediates: false])
    /// Main-thread-only: whether a mapping pass is in flight (the drop-if-busy gate).
    private var busy = false

    func start() {
        session.delegate = self
        let config = ARWorldTrackingConfiguration()
        // Smoothed depth is steadier frame-to-frame (kinder to a lifted center);
        // fall back to raw scene depth, and run without either on a non-LiDAR
        // phone (the regions then stay 2D).
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
        // mapping pass is in flight.
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
            let sample = self.mapAttention(in: pixelBuffer, timestamp: timestamp,
                                           isTracked: isTracked, turns: turns, lift: lift)
            DispatchQueue.main.async {
                self.busy = false
                if let sample { self.onSaliency?(sample) }
            }
        }
    }

    // MARK: The mapping pass (on the attention queue)

    /// Run the attention model over one frame and lift what it marks. Returns
    /// `nil` when the pass itself failed (the last good reading stays put on the
    /// Mac).
    private func mapAttention(in pixelBuffer: CVPixelBuffer, timestamp: Double,
                              isTracked: Bool, turns: UInt8,
                              lift: LiftContext?) -> PhoneSaliencySample? {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: visionOrientation(forQuarterTurnsCW: turns),
                                            options: [:])
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first,
              let (heatWidth, heatHeight, heatFloats) = floatPixels(observation.pixelBuffer)
        else { return nil }

        // The heat arrives as floats in 0...1 at the model's own coarse size;
        // one byte per pixel carries it whole.
        let heat = heatFloats.map { UInt8((min(max($0, 0), 1) * 255).rounded()) }

        let regions = (observation.salientObjects ?? []).map { object -> PhoneSalientRegionSample in
            let box = object.boundingBox
            var region = PhoneSalientRegionSample(
                x: Float(box.origin.x), y: Float(box.origin.y),
                width: Float(box.width), height: Float(box.height),
                confidence: Float(object.confidence))
            if let lift,
               let center = worldPosition(ofUpright: SIMD2<Float>(Float(box.midX), Float(box.midY)),
                                          turns: turns, lift: lift) {
                region.hasWorldCenter = true
                region.worldCenter = center
            }
            return region
        }

        let jpeg = cameraJPEG(from: pixelBuffer, context: ciContext,
                              maxDimension: maxColorDimension, quality: 0.6) ?? Data()

        return PhoneSaliencySample(isTracked: isTracked, timestamp: timestamp,
                                   heatWidth: heatWidth, heatHeight: heatHeight,
                                   orientation: turns, heat: heat,
                                   colorJPEG: jpeg, regions: regions)
    }
}
