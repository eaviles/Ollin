import Foundation
import ARKit
import Vision
import simd

/// Runs ARKit world tracking on the rear camera and finds the hands in each frame
/// with the on-device hand-pose model (Vision, up to 4 hands), turning each into a
/// `PhoneHandSample`: a 21-joint skeleton of upright 2D image points, plus, on a
/// LiDAR phone, a metric 3D position per joint in ARKit world space, lifted through
/// the scene-depth map and the camera pose. World tracking runs on any device, so
/// the mode always works; without LiDAR the hands simply stay 2D.
///
/// The pose model is the expensive part, so it runs on its own serial queue behind
/// a drop-if-busy gate: a frame that arrives while one is being worked on is
/// skipped, never queued, and the camera never backs up. Everything the lift needs
/// (the depth floats, the depth-grid intrinsics, the camera pose, the device-hold
/// turn count) is copied out of the frame *inside* the delegate callback; only the
/// capture pixel buffer rides to the queue by reference, held for at most one pass.
///
/// The model wants an upright picture, so the request is handed the device-hold
/// orientation; its points come back in the upright frame and go onto the wire
/// as-is, and the lift maps each back onto the camera-native depth grid with the
/// shared quarter-turn arithmetic.
///
/// The finished set is handed to the main thread, where `onHands` fires: the same
/// contract as every other streamer, with the empty set meaning no hand is in view.
/// `@unchecked Sendable` under the usual discipline: the handler is wired on the
/// main thread before `start()`, `busy` is touched only on the main thread, and
/// the pose pass touches only its own copies.
final class HandStreamer: NSObject, ARSessionDelegate, LightReporting, @unchecked Sendable {

    /// Fired (on the main thread) with each analyzed frame's hands; empty when no
    /// hand is in view, so a hand leaving clears itself.
    var onHands: (([PhoneHandSample]) -> Void)?

    let lightSampler = LightSampler()

    /// Whether the hands lift to 3D here (scene depth needs LiDAR).
    var liftsTo3D: Bool { ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) }

    /// How many hands the model looks for. Two people's worth: the pass costs more
    /// per hand, and four is where a stage duet still tracks.
    private let maximumHandCount = 4

    /// Joints below this confidence are dropped (occluded or guessed).
    private let minimumJointConfidence: Float = 0.3

    /// How far around a joint's depth pixel to look for the median, in pixels. A
    /// single sample at a silhouette edge is often a hole.
    private let depthWindowRadius = 2

    private let session = ARSession()
    private let queue = DispatchQueue(label: "dev.ollin.hand-pose")
    /// Main-thread-only: whether a pose pass is in flight (the drop-if-busy gate).
    private var busy = false

    /// The copied pieces a 3D lift needs, all camera-native: the depth grid, the
    /// intrinsics already scaled onto it, and the camera→world pose.
    private struct LiftContext {
        var width: Int
        var height: Int
        var depth: [Float]
        var fx: Float
        var fy: Float
        var cx: Float
        var cy: Float
        var transform: simd_float4x4
    }

    func start() {
        session.delegate = self
        let config = ARWorldTrackingConfiguration()
        // Smoothed depth is steadier frame-to-frame (kinder to a lifted joint);
        // fall back to raw scene depth, and run without either on a non-LiDAR
        // phone (the hands then stay 2D).
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
        // Before the busy gate, so the room's light keeps arriving while a pose
        // pass is in flight.
        lightSampler.report(frame)
        guard !busy else { return }
        busy = true

        // Copy everything the pass needs out of the frame now, on the callback:
        // the frame's buffers are the session's own, and only the capture pixel
        // buffer (which CoreVideo reference-counts) rides along.
        let pixelBuffer = frame.capturedImage
        let timestamp = frame.timestamp
        let turns = captureQuarterTurns()
        let tracked: Bool = if case .normal = frame.camera.trackingState { true } else { false }

        var lift: LiftContext?
        if let sceneDepth = frame.smoothedSceneDepth ?? frame.sceneDepth,
           let (depthW, depthH, depth) = floatPixels(sceneDepth.depthMap) {
            // Intrinsics arrive at the captured-image resolution; bring them onto
            // the depth grid so a joint's pixel unprojects directly.
            let res = frame.camera.imageResolution
            let k = frame.camera.intrinsics
            let sx = Float(depthW) / Float(res.width)
            let sy = Float(depthH) / Float(res.height)
            lift = LiftContext(width: depthW, height: depthH, depth: depth,
                               fx: k.columns.0.x * sx, fy: k.columns.1.y * sy,
                               cx: k.columns.2.x * sx, cy: k.columns.2.y * sy,
                               transform: frame.camera.transform)
        }

        queue.async { [weak self] in
            guard let self else { return }
            let hands = self.findHands(in: pixelBuffer, timestamp: timestamp,
                                       tracked: tracked, turns: turns, lift: lift)
            DispatchQueue.main.async {
                self.busy = false
                if let hands { self.onHands?(hands) }
            }
        }
    }

    // MARK: The pose pass (on the hand queue)

    /// Run the hand-pose model over one frame and lift what it finds. Returns
    /// `nil` when the pass itself failed (the last good set stays put on the Mac),
    /// and the empty list when it ran and saw no hand.
    private func findHands(in pixelBuffer: CVPixelBuffer, timestamp: Double,
                           tracked: Bool, turns: UInt8, lift: LiftContext?) -> [PhoneHandSample]? {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = maximumHandCount
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                            orientation: Self.cgOrientation(forQuarterTurnsCW: turns),
                                            options: [:])
        guard (try? handler.perform([request])) != nil else { return nil }

        return (request.results ?? []).map { observation in
            var joints: [PhoneHandJoint: PhoneHandJointSample] = [:]
            let points = (try? observation.recognizedPoints(.all)) ?? [:]
            for (name, point) in points {
                guard point.confidence >= minimumJointConfidence,
                      let joint = Self.handJoint(name) else { continue }
                let upright = SIMD2<Float>(Float(point.location.x), Float(point.location.y))
                var sample = PhoneHandJointSample(point: upright,
                                                  confidence: Float(point.confidence))
                if let lift, let world = worldPosition(ofUpright: upright, turns: turns, lift: lift) {
                    sample.hasWorldPosition = true
                    sample.worldPosition = world
                }
                joints[joint] = sample
            }
            let chirality: PhoneHandChirality = switch observation.chirality {
            case .left: .left
            case .right: .right
            default: .unknown
            }
            return PhoneHandSample(tracked: tracked, timestamp: timestamp,
                                   chirality: chirality,
                                   confidence: Float(observation.confidence),
                                   joints: joints)
        }
    }

    /// Lift one upright joint point into ARKit world space: back onto the
    /// camera-native depth grid by the shared quarter-turn arithmetic, a median
    /// depth from the window around its pixel, the unprojection through the
    /// depth-grid intrinsics (camera space: +x right, +y up, looking down −z),
    /// and the camera pose onto the front of that.
    private func worldPosition(ofUpright p: SIMD2<Float>, turns: UInt8,
                               lift: LiftContext) -> SIMD3<Float>? {
        let b = PhoneWire.bufferPoint(fromUpright: p, quarterTurnsCW: turns)
        let col = Int((b.x * Float(lift.width)).rounded(.down))
        let row = Int((b.y * Float(lift.height)).rounded(.down))
        guard let depth = medianDepth(atCol: col, row: row, lift: lift) else { return nil }

        let x = (Float(col) - lift.cx) / lift.fx * depth
        let y = -(Float(row) - lift.cy) / lift.fy * depth
        let world = lift.transform * SIMD4<Float>(x, y, -depth, 1)
        return SIMD3<Float>(world.x, world.y, world.z)
    }

    /// The median of the valid depth samples in the window around a pixel, or
    /// `nil` when every sample there is a hole: robust to the dropouts that sit
    /// exactly where a fingertip meets the background.
    private func medianDepth(atCol col: Int, row: Int, lift: LiftContext) -> Float? {
        var samples: [Float] = []
        let r = depthWindowRadius
        samples.reserveCapacity((2 * r + 1) * (2 * r + 1))
        for y in max(0, row - r)...min(lift.height - 1, row + r) where lift.height > 0 {
            for x in max(0, col - r)...min(lift.width - 1, col + r) where lift.width > 0 {
                let d = lift.depth[y * lift.width + x]
                if d > 0, d.isFinite { samples.append(d) }
            }
        }
        guard !samples.isEmpty else { return nil }
        return samples.sorted()[samples.count / 2]
    }

    /// The image orientation that stands the camera-native buffer upright for the
    /// model, from the same quarter-turn count everything else uses.
    private static func cgOrientation(forQuarterTurnsCW turns: UInt8) -> CGImagePropertyOrientation {
        switch turns % 4 {
        case 1:  return .right
        case 2:  return .down
        case 3:  return .left
        default: return .up
        }
    }

    /// Map the model's joint name onto the wire's joint. An explicit switch, not a
    /// rawValue match: the model's rawValues are its own internal strings.
    private static func handJoint(_ name: VNHumanHandPoseObservation.JointName) -> PhoneHandJoint? {
        switch name {
        case .wrist:      return .wrist
        case .thumbCMC:   return .thumbCMC
        case .thumbMP:    return .thumbMP
        case .thumbIP:    return .thumbIP
        case .thumbTip:   return .thumbTip
        case .indexMCP:   return .indexMCP
        case .indexPIP:   return .indexPIP
        case .indexDIP:   return .indexDIP
        case .indexTip:   return .indexTip
        case .middleMCP:  return .middleMCP
        case .middlePIP:  return .middlePIP
        case .middleDIP:  return .middleDIP
        case .middleTip:  return .middleTip
        case .ringMCP:    return .ringMCP
        case .ringPIP:    return .ringPIP
        case .ringDIP:    return .ringDIP
        case .ringTip:    return .ringTip
        case .littleMCP:  return .littleMCP
        case .littlePIP:  return .littlePIP
        case .littleDIP:  return .littleDIP
        case .littleTip:  return .littleTip
        default:          return nil
        }
    }
}
