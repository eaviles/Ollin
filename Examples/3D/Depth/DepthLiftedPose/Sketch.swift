import Foundation
import Ollin
import OllinVision
import OllinRecord3D

/// A body skeleton lifted into true 3D space from a tethered iPhone — the depth
/// feed and 2D pose composed into a figure that stands at its real distance.
///
/// A `BodyTracker` finds the 2D pose in the phone's color frames; each joint is
/// then back-projected through the same frame's metric depth and intrinsics
/// (`body.lifted(through:)`), landing in the camera's 3D space — the *same* space
/// the depth cloud lives in. So the bright skeleton sits inside the person's own
/// point cloud, at their true distance, and the whole scene orbits as one.
///
/// Where `BodyTracker3D` *guesses* a skeleton's depth from a flat image, this
/// reads it: with the iPhone's real depth the joints are measured, not estimated.
///
/// Setup: open **Record3D** on a LiDAR or TrueDepth iPhone, enable **USB
/// streaming** in Settings, keep it on the live screen, and plug in the cable.
/// Stand far enough back that your body is in frame. The connection retries on its
/// own, so starting the stream after this sketch is running just begins the feed.
///
/// Record3D is by Marek Šimoník (record3d.app) — the capture app and the source of
/// the stream format, read clean-room from its public structure (the `record3d`
/// library is LGPL-2.1 and never copied). Body pose is Apple's Vision model and
/// needs an Apple-silicon Mac.
@main
final class DepthLiftedPose: Sketch {

    let device = Record3DDevice()
    lazy var bodies = BodyTracker(device)

    // Orbit framing, eased frame-to-frame so live sensor noise doesn't jitter it.
    var orbitCenter: Vector3?
    var orbitRadius = 0.0

    override func setup() {
        device.start()
        _ = bodies   // attach the body tracker to the phone's color frames
    }

    override func draw() {
        background(Color(white: 0.04))

        guard let frame = device.latestFrame else {
            return drawStatus(device.waitingMessage + "\n\n" +
                              "Open Record3D on the iPhone, enable USB streaming in Settings,\n" +
                              "keep it on the live screen, and connect the cable.", style: .info)
        }
        if let reason = bodies.unavailableReason {
            return drawStatus(reason, style: .warning)   // body pose needs Apple silicon
        }

        // The person, as a depth cloud — tuned for whichever camera is streaming.
        let tuning = Tuning.forCamera(frame.camera)
        let cloud = frame.pointCloud(minimumConfidence: tuning.confidence,
                                     depthRange: tuning.range, pointSize: tuning.pointSize)
        guard !cloud.isEmpty else { return }

        // Every 2D pose lifted into the cloud's own metric space — BodyTracker finds
        // everyone in view, so several people lift into the same depth frame at their
        // true relative positions. The bodies are from the most recent analyzed color
        // frame; lifting through *this* frame's depth is the best distance available.
        let poses = bodies.bodies.lifted(through: frame).filter { $0.center != nil }

        // Frame the scene: orbit the centroid of the lifted skeletons when we have
        // any, else the cloud's, at a radius set by how spread out the cloud is.
        var sum = Vector3.zero
        for p in cloud.points { sum += p.position }
        let cloudCenter = sum / Double(cloud.count)
        var spread = 0.0
        for p in cloud.points { spread += p.position.distanceSquared(to: cloudCenter) }
        let poseCenters = poses.compactMap { $0.center }
        let center = poseCenters.isEmpty
            ? cloudCenter
            : poseCenters.reduce(.zero, +) / Double(poseCenters.count)
        let radius = max(0.8, (spread / Double(cloud.count)).squareRoot() * 3)

        if let c = orbitCenter {
            orbitCenter = c.lerp(to: center, 0.08)
            orbitRadius += (radius - orbitRadius) * 0.08
        } else {
            orbitCenter = center
            orbitRadius = radius
        }

        cameraShowcase(.turntable(period: .tau / 0.3), target: orbitCenter ?? center, radius: orbitRadius,
                    elevation: 0.18, fieldOfView: .pi / 3)

        drawPointCloud(cloud)
        // One bright color per person so several skeletons read apart in the cloud.
        let skeletonColors = [Color(hex: 0xFFC23C), Color(hex: 0x4FE0C0),
                              Color(hex: 0xFF7AB0), Color(hex: 0x8AB4FF)]
        for (i, pose) in poses.enumerated() {
            drawPointCloud(pose.cloud(jointSize: 0.07, boneSize: 0.022,
                                      color: skeletonColors[i % skeletonColors.count]))
        }

        let n = poses.count
        let joints = poses.reduce(0) { $0 + $1.positions.count }
        let status = n == 0 ? "step into frame"
            : "\(n) \(n == 1 ? "person" : "people"), \(joints) joints lifted"
        drawCaption("DepthLiftedPose — \(tuning.label), \(status); drag to spin")
    }

    /// Per-camera point-cloud settings, derived from which camera is streaming.
    struct Tuning {
        let range: ClosedRange<Double>
        let confidence: DepthConfidence
        let pointSize: Double
        let label: String

        static func forCamera(_ camera: Record3DCamera) -> Tuning {
            switch camera {
            case .trueDepth:   // front: upper body up close, noisy background
                return Tuning(range: 0.2...1.6, confidence: .high, pointSize: 0.004,
                              label: "TrueDepth (front)")
            case .lidar:       // rear: a whole standing figure across the room
                return Tuning(range: 0.4...5.0, confidence: .medium, pointSize: 0.009,
                              label: "LiDAR (rear)")
            case .unknown:
                return Tuning(range: 0.2...6.0, confidence: .medium, pointSize: 0.006,
                              label: "depth camera")
            }
        }
    }
}
