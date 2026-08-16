import Foundation
import simd
import Ollin
import OllinPhone

/// Sweep a tethered iPhone around a room and watch the whole space build up as one
/// point cloud, the fusion sibling of `PhoneDepthCloud`. Where that sketch draws the
/// single slice of depth in front of the lens, this one keeps every slice: each new
/// frame is placed by the phone's 6DoF camera pose into ARKit's fixed world space and
/// merged, so panning the phone across a room paints the room.
///
/// Setup: install **Ollin Capture** on a LiDAR iPhone (a Pro model), launch it, tap
/// the **World** segment, and connect the cable. Then move the phone slowly to sweep.
/// Walls, furniture, and corners accumulate. Press **R** to clear and start a fresh
/// scan; drag to spin the view by hand.
///
/// The fusion is a `WorldCloud`: it keeps one point per small cube of space (here
/// 2.5 cm), so re-seeing a wall refreshes it in place rather than piling up, and the
/// scan can run as long as you like without the cloud growing without bound.
///
/// Each frame is also lined up against what has already been fused before it is
/// merged, which is what keeps a long sweep from smearing: the phone's own tracking
/// is a little wrong every frame, and the error piles up until a wall lands in two
/// places. Press **C** to cycle what the sweep does about that: the pose as reported,
/// each frame lined up against the scan, or that plus recognizing a place already
/// scanned and straightening the whole room when it comes back to one. See
/// `DriftCorrectedScan` and `ClosedLoopScan` for the same three side by side, with no
/// phone needed.
@main
final class PhoneWorldScan: Sketch {

    /// What the sweep does about the phone's own tracking error.
    enum Keeping: CaseIterable {
        /// Place every frame where the phone says it is.
        case asReported
        /// Line each frame up against the scan before merging it.
        case linedUp
        /// That, and recognize a place already scanned.
        case closingLoops
    }

    let device = PhoneDevice()

    // Fuse the sweep at 2.5 cm voxels: fine enough to read a room, coarse enough to
    // stay light over a long scan.
    var world = WorldCloud(voxelSize: 0.025)
    var scan = ScanGraph(voxelSize: 0.025)
    // The last depth frame fused, so each frame is added exactly once (draw runs
    // faster than frames stream in).
    var lastFused: Int?

    // What the sweep is doing about drift, what the last fit had left over (meters),
    // and the last place it recognized.
    var keeping = Keeping.linedUp
    var leftOver = 0.0
    var recognized: ScanGraph.Loop?

    /// The fused cloud of whichever way the sweep is being kept.
    var fused: PointCloud { keeping == .closingLoops ? scan.cloud : world.cloud }

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
            switch keeping {
            case .asReported:
                world.add(cameraCloud, transformedBy: pose)
            case .linedUp:
                leftOver = world.add(cameraCloud, correcting: pose).error
            case .closingLoops:
                let update = scan.add(cameraCloud, correcting: pose)
                leftOver = update.alignment.error
                if let loop = update.loop { recognized = loop }
            }
            lastFused = id
        }

        guard !fused.isEmpty else {
            return drawStatus(device.waitingMessage + "\n\n" +
                              "Open Ollin Capture on a LiDAR iPhone, tap the World tab,\n" +
                              "connect the cable, then sweep the phone across the room.",
                              style: .info)
        }

        // Frame the fused cloud: orbit its centroid at a radius set by how spread out
        // it is. Ease toward the target so the view glides as the scan keeps growing.
        let center = centroid(fused)
        let radius = max(0.8, spread(fused, around: center) * 3)
        if framed {
            orbitCenter = orbitCenter.lerp(to: center, 0.06)
            orbitRadius += (radius - orbitRadius) * 0.06
        } else {
            orbitCenter = center
            orbitRadius = radius
            framed = true
        }

        cameraShowcase(.turntable(period: .tau / 0.2), target: orbitCenter, radius: orbitRadius,
                    elevation: 0.22, fieldOfView: .pi / 3)
        drawPointCloud(fused)

        drawCaption(caption())
    }

    private func caption() -> String {
        switch keeping {
        case .asReported:
            return "PhoneWorldScan: \(fused.count) pts fused, pose as reported; "
                + "C to line it up, R to reset"
        case .linedUp:
            return String(format: "PhoneWorldScan: %d pts fused, lined up to %.0f mm; "
                          + "C to close loops too, R to reset", fused.count, leftOver * 1000)
        case .closingLoops:
            let met = recognized.map {
                String(format: ", last place met moved the room %.0f cm", $0.moved * 100)
            } ?? ""
            return String(format: "PhoneWorldScan: %d pts fused, %d kept, lined up to %.0f mm%@; "
                          + "C for the reported pose, R to reset",
                          fused.count, scan.keyframes.count, leftOver * 1000, met)
        }
    }

    override func keyPressed() {
        if key == "r" || key == "R" { startOver() }
        // Changing what the sweep does mid-scan would mix two spaces, so start over.
        if key == "c" || key == "C" {
            let all = Keeping.allCases
            keeping = all[(all.firstIndex(of: keeping)! + 1) % all.count]
            startOver()
        }
    }

    private func startOver() {
        world.reset()
        scan.reset()
        recognized = nil
        framed = false
        lastFused = nil
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
