import Foundation
import ARKit
import simd

/// Runs plain ARKit world tracking and streams the phone's own pose as a pointer,
/// with the thumb on the screen beside it.
///
/// Every other streamer here describes the room. This one describes the person
/// holding the phone, so the screen is part of the sensor: the pad under the thumb
/// writes into `press` and `slide`, and the next camera frame carries them out with
/// the pose. That keeps one message per frame rather than two streams the Mac would
/// have to line up.
///
/// It asks for nothing but world tracking, so any ARKit phone can be a wand. ARKit
/// delivers its delegate callbacks on the main thread, so `onWand` fires on main,
/// which is also where the pad writes.
final class WandStreamer: NSObject, ARSessionDelegate, LightReporting {

    /// Fired (on the main thread) once per camera frame.
    var onWand: ((PhoneWandSample) -> Void)?

    let lightSampler = LightSampler()

    /// Whether world tracking is available at all (every ARKit device).
    var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }

    private let session = ARSession()

    /// What the thumb is doing. Written by the pad on the main thread and read by
    /// the frame callback on the same thread, so no lock is needed.
    private var pressed = false
    private var pressCount: UInt32 = 0
    private var touch: SIMD2<Float>?

    func start() {
        guard isSupported else { return }
        session.delegate = self
        let config = ARWorldTrackingConfiguration()
        // A wand needs its own place in the room and nothing else, so no plane
        // detection, no scene depth, no segmentation: the cheapest session ARKit
        // runs, which leaves the phone's budget to holding tracking steady.
        config.planeDetection = []
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
    }

    func stop() {
        session.pause()
        pressed = false
        touch = nil
    }

    // MARK: The screen as the button

    /// A finger has landed. The count rises here rather than on release, so a
    /// sketch sees a press the moment it happens.
    func press(at point: SIMD2<Float>) {
        if !pressed { pressCount &+= 1 }
        pressed = true
        touch = point
    }

    /// The finger has moved while still down.
    func slide(to point: SIMD2<Float>) {
        guard pressed else { return }
        touch = point
    }

    /// The finger has left the screen.
    func release() {
        pressed = false
        touch = nil
    }

    // MARK: ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        lightSampler.report(frame)
        // `normal` is the only state whose pose is worth anything. The others are
        // reported rather than dropped, so the Mac can say "hold still" instead of
        // going quiet, and so the button keeps working while tracking recovers.
        let tracking: Bool
        switch frame.camera.trackingState {
        case .normal: tracking = true
        default:      tracking = false
        }
        let sample = PhoneWandSample(isTracked: tracking,
                                     timestamp: frame.timestamp,
                                     transform: frame.camera.transform,
                                     quarterTurnsCW: captureQuarterTurns(),
                                     isPressed: pressed,
                                     pressCount: pressCount,
                                     hasTouch: touch != nil,
                                     touch: touch ?? .zero)
        onWand?(sample)
    }
}
