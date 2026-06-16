import Foundation
import simd
import Ollin
import OllinPhone

/// Sweep a tethered iPhone around a room and watch the whole space build up as one
/// point cloud — the fusion sibling of `PhoneDepthCloud`. Where that sketch draws the
/// single slice of depth in front of the lens, this one keeps every slice: each new
/// frame is placed by the phone's 6DoF camera pose into ARKit's fixed world space and
/// merged, so panning the phone across a room paints the room.
///
/// Setup: install **Ollin Capture** on a LiDAR iPhone (a Pro model), launch it, tap
/// the **World** segment, and connect the cable. Then move the phone slowly to sweep —
/// walls, furniture, and corners accumulate. Press **R** to clear and start a fresh
/// scan; drag to spin the view by hand.
///
/// The fusion is a `WorldCloud`: it keeps one point per small cube of space (here
/// 2.5 cm), so re-seeing a wall refreshes it in place rather than piling up, and the
/// scan can run as long as you like without the cloud growing without bound.
@main
final class PhoneWorldScan: Sketch {

    let device = PhoneDevice()

    // Fuse the sweep at 2.5 cm voxels — fine enough to read a room, coarse enough to
    // stay light over a long scan.
    var world = WorldCloud(voxelSize: 0.025)
    // The last depth frame fused, so each frame is added exactly once (draw runs
    // faster than frames stream in).
    var lastFused: Int?

    // The orbit framing, eased frame-to-frame so it drifts smoothly as the scan grows.
    var orbitCenter = Vector3.zero
    var orbitRadius = 2.0
    var framed = false

    override func setup() {
        device.start()
    }

    override func draw() {
        background(Color(white: 0.04))

        // Fuse each fresh frame once: place its camera-space cloud into world space
        // with the frame's camera→world pose and merge. A `.low` confidence floor
        // keeps the dimmer/farther LiDAR samples, and the range drops far-wall noise.
        if let id = device.latestDepthFrameID, id != lastFused,
           let pose = device.latestPose,
           let cameraCloud = device.pointCloud(minimumConfidence: .low,
                                               depthRange: 0.3...5.0, pointSize: 0.013) {
            world.add(cameraCloud, transformedBy: pose)
            lastFused = id
        }

        guard !world.isEmpty else {
            return drawStatus(device.waitingMessage + "\n\n" +
                              "Open Ollin Capture on a LiDAR iPhone, tap the World tab,\n" +
                              "connect the cable, then sweep the phone across the room.",
                              style: .info)
        }

        // Frame the fused cloud: orbit its centroid at a radius set by how spread out
        // it is. Ease toward the target so the view glides as the scan keeps growing.
        let center = centroid(world.cloud)
        let radius = max(0.8, spread(world.cloud, around: center) * 3)
        if framed {
            orbitCenter = orbitCenter.lerp(to: center, 0.06)
            orbitRadius += (radius - orbitRadius) * 0.06
        } else {
            orbitCenter = center
            orbitRadius = radius
            framed = true
        }

        let azimuth = mouseIsPressed ? map(mouseX, 0, width, .pi, -.pi) : time * 0.2
        camera(.orbiting(target: orbitCenter, radius: orbitRadius, azimuth: azimuth,
                         elevation: 0.22, fieldOfView: .pi / 3))
        drawPointCloud(world.cloud)

        drawCaption("PhoneWorldScan — \(world.count) pts fused; sweep the phone, R to reset")
    }

    override func keyPressed() {
        if key == "r" || key == "R" {
            world.reset()
            framed = false
            lastFused = nil
        }
    }

    private func centroid(_ cloud: PointCloud) -> Vector3 {
        var sum = Vector3.zero
        for p in cloud.points { sum += p.position }
        return sum / Double(cloud.count)
    }

    private func spread(_ cloud: PointCloud, around center: Vector3) -> Double {
        var total = 0.0
        for p in cloud.points { total += p.position.distanceSquared(to: center) }
        return (total / Double(cloud.count)).squareRoot()
    }
}
