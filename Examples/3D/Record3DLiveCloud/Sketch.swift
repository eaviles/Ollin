import Foundation
import Ollin
import OllinRecord3D

/// A **live** RGBD point cloud streamed from a tethered iPhone — the live sibling
/// of `Record3DCloud`, and the next slice of the iPhone-as-a-sensor-array work.
/// Where that example orbits a recorded `.r3d` file, this one borrows the phone's
/// depth camera in real time: move in front of the lens and the cloud moves.
///
/// Setup: open the **Record3D** app on a LiDAR or TrueDepth iPhone, enable **USB
/// streaming** in its Settings, and keep it on the live screen. Plug the phone into
/// the Mac with a cable. The connection retries on its own, so starting the stream
/// (or plugging in) after this sketch is already running just begins the feed.
///
/// Each frame's color image and full-quality metric depth map unproject with the
/// stream's true camera intrinsics into a colored cloud, framed and spun so the
/// depth reads as real space. The transport is the standard usbmuxd tunnel; the
/// frame format is read clean-room from the wire.
///
/// Record3D is by Marek Šimoník (record3d.app) — credited as the capture app and
/// the source of the stream format, which Ollin reads clean-room from its public
/// structure (the `record3d` library is LGPL-2.1 and never copied).
@main
final class Record3DLiveCloud: Sketch {

    let device = Record3DDevice()

    // The orbit framing, eased frame-to-frame so live sensor noise doesn't jitter it.
    var orbitCenter: Vector3?
    var orbitRadius = 0.0

    override func setup() {
        device.start()
    }

    override func draw() {
        background(Color(white: 0.04))

        guard let frame = device.latestFrame else {
            return drawStatus(device.waitingMessage + "\n\n" +
                              "Open Record3D on the iPhone, enable USB streaming in Settings,\n" +
                              "keep it on the live screen, and connect the cable.", style: .info)
        }

        // Tune for the camera in use: the front TrueDepth camera is short-range and
        // noisy past a meter (a face up close), so clamp tight and demand high
        // confidence; the rear LiDAR reaches across a room, so open the range up.
        let tuning = Tuning.forCamera(frame.camera)
        let cloud = frame.pointCloud(minimumConfidence: tuning.confidence,
                                     depthRange: tuning.range, pointSize: tuning.pointSize)
        guard !cloud.isEmpty else { return }

        // Frame the cloud: orbit its centroid at a radius set by how spread out it is.
        var sum = Vector3.zero
        for p in cloud.points { sum += p.position }
        let center = sum / Double(cloud.count)
        var spread = 0.0
        for p in cloud.points { spread += p.position.distanceSquared(to: center) }
        let radius = max(0.6, (spread / Double(cloud.count)).squareRoot() * 3)

        // Live depth flickers frame to frame (sensor noise, points crossing the
        // confidence/range filters); ease the framing toward it so the cloud holds
        // steady while real motion is still followed.
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

        drawCaption("Record3DLiveCloud — \(tuning.label), \(frame.depthWidth)×\(frame.depthHeight) depth, " +
                    "\(cloud.count) pts; drag to spin")
    }

    /// The per-camera point-cloud settings — derived from which camera is streaming.
    struct Tuning {
        let range: ClosedRange<Double>
        let confidence: DepthConfidence
        let pointSize: Double
        let label: String

        static func forCamera(_ camera: Record3DCamera) -> Tuning {
            switch camera {
            case .trueDepth:   // front: a face up close, noisy background
                return Tuning(range: 0.2...1.2, confidence: .high, pointSize: 0.004,
                              label: "TrueDepth (front)")
            case .lidar:       // rear: a whole room
                return Tuning(range: 0.3...5.0, confidence: .medium, pointSize: 0.009,
                              label: "LiDAR (rear)")
            case .unknown:
                return Tuning(range: 0.1...8.0, confidence: .medium, pointSize: 0.006,
                              label: "depth camera")
            }
        }
    }
}
