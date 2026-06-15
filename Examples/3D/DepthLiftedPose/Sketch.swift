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

        // The 2D pose lifted into the cloud's own metric space. The body is from
        // the most recent analyzed color frame; lifting through *this* frame's
        // depth is the best-registered distance available.
        let pose = bodies.bodies.first?.lifted(through: frame)

        // Frame the figure: orbit the skeleton's centroid when we have one, else
        // the cloud's, at a radius set by how spread out the cloud is.
        var sum = Vector3.zero
        for p in cloud.points { sum += p.position }
        let cloudCenter = sum / Double(cloud.count)
        var spread = 0.0
        for p in cloud.points { spread += p.position.distanceSquared(to: cloudCenter) }
        let center = pose?.center ?? cloudCenter
        let radius = max(0.8, (spread / Double(cloud.count)).squareRoot() * 3)

        if let c = orbitCenter {
            orbitCenter = c.lerp(to: center, 0.08)
            orbitRadius += (radius - orbitRadius) * 0.08
        } else {
            orbitCenter = center
            orbitRadius = radius
        }

        let azimuth = mouseIsPressed ? map(mouseX, 0, width, .pi, -.pi) : time * 0.3
        camera(.orbiting(target: orbitCenter ?? center, radius: orbitRadius, azimuth: azimuth,
                         elevation: 0.18, fieldOfView: .pi / 3))

        drawPointCloud(cloud)
        if let pose {
            // Bright and large so the figure reads against its own depth cloud.
            drawPointCloud(pose.cloud(jointSize: 0.07, boneSize: 0.022, color: Color(hex: 0xFFC23C)))
        }

        let status = pose.map { "\($0.positions.count) joints lifted" } ?? "step into frame"
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
