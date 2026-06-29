import Foundation
import simd
import Ollin
import OllinPhone

/// A **live** world-facing point cloud streamed from a tethered iPhone's rear LiDAR
/// through the Ollin Capture app — the depth sibling of `PhoneBodyPose`/`PhoneFace`.
/// Point the phone at the room and the cloud is the room.
///
/// Setup: install **Ollin Capture** on a LiDAR iPhone (a Pro model), launch it, tap
/// the **World** segment, and connect the cable. The connection retries on its own,
/// so tapping World (or plugging in) after this sketch is already running just begins
/// the feed.
///
/// Each frame's color image and metric depth map unproject with the stream's true
/// camera intrinsics into a colored cloud, framed and spun so the depth reads as real
/// space. The transport is the standard usbmuxd tunnel; the wire format is Ollin's own.
@main
final class PhoneDepthCloud: Sketch {

    let device = PhoneDevice()

    // The orbit framing, eased frame-to-frame so live sensor noise doesn't jitter it.
    var orbitCenter: Vector3?
    var orbitRadius = 0.0

    override func setup() {
        device.start()
    }

    override func draw() {
        background(Color(white: 0.04))

        // The rear LiDAR depth map is a fixed 256×192 (~49k samples) — ARKit's ceiling
        // for scene depth — so density comes from keeping samples, not adding them: a
        // `.low` confidence floor keeps the dimmer/farther points `.medium` would drop,
        // and a slightly larger splat reads as a solid surface rather than dots.
        guard let pose = device.latestPose,
              let cameraCloud = device.pointCloud(minimumConfidence: .low,
                                                  depthRange: 0.3...5.0, pointSize: 0.014),
              !cameraCloud.isEmpty else {
            return drawStatus(device.waitingMessage + "\n\n" +
                              "Open Ollin Capture on a LiDAR iPhone, tap the World tab,\n" +
                              "and connect the cable.", style: .info)
        }

        // The LiDAR depth arrives in the camera's native (landscape) frame, so a
        // portrait-held phone yields a cloud rolled 90°. Re-orient each point with the
        // camera pose's rotation (the w = 0 multiply drops the translation, so the
        // cloud stays centered near the origin) — ARKit's world is gravity-aligned, so
        // this stands the scene upright however the phone is held.
        var cloud = PointCloud()
        cloud.points.reserveCapacity(cameraCloud.count)
        for p in cameraCloud.points {
            let w = pose * SIMD4<Float>(Float(p.position.x), Float(p.position.y), Float(p.position.z), 0)
            cloud.add(Vector3(Double(w.x), Double(w.y), Double(w.z)), color: p.color, size: p.size)
        }

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

        cameraShowcase(.turntable(period: .tau / 0.3), target: orbitCenter ?? center, radius: orbitRadius,
                    elevation: 0.18, fieldOfView: .pi / 3)
        drawPointCloud(cloud)

        if let frame = device.latestDepthFrame {
            drawCaption("PhoneDepthCloud — \(frame.depthWidth)×\(frame.depthHeight) depth, " +
                        "\(cloud.count) pts; drag to spin")
        }
    }
}
