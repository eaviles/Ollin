import Foundation
import simd
import Ollin

/// A room walked all the way around and back to the door, scanned two ways at
/// once and shown side by side. The left half always lines each frame up
/// against what has already been fused; **C** cycles what the right half does:
/// trusting the camera's reported pose, lining frames up the same way, or also
/// recognizing the place it started from.
///
/// A depth camera that reports its own pose reports it with a small error. The
/// error is far too small to see in one frame, and it never goes away, so it
/// piles up. After a minute of sweeping, a wall seen at the start and again at
/// the end lands in two places and the scan turns to fog. That is drift, and
/// the right half's first mode (`add(_:transformedBy:)`, which just trusts the
/// pose) is what it does.
///
/// Lining every frame up against the scan (`add(_:correcting:)`) slides and
/// turns each frame until it sits on the surfaces already fused, keeps the
/// fix, and reuses it on the next frame. The walls stay one wall thick, and
/// that is the left half. What it cannot do is reach back: each frame agreed
/// with the frame before it, so the chain is smooth, and it still leans. By
/// the far side of the walk the wall is a good way from where it really is,
/// and nothing in the sweep knows.
///
/// The last mode (`ScanGraph`) keeps a **keyframe** every so often, and when a
/// new one lands where an old one stood it matches the two directly. That
/// match is a measurement between a late pose and an early one, so the chain
/// becomes a loop that does not quite close, and the gap can be shared out
/// over every pose between them. Watch the right half at the moment the walk
/// comes home: the whole room snaps.
///
/// Look straight down, because from overhead each wall is a line and a scan
/// that leaned draws that line twice. Nothing is plugged in: the room, the
/// walk and the drift are all made up, so every mode gets exactly the same
/// frames. Sweep a real room with `PhoneWorldScan`, which calls the same
/// methods. Press **R** to walk it again.
@main
final class ClosedLoopScan: Sketch {

    // Two halls side by side, seen from overhead, want a wide frame more than a tall one.
    override var canvasSize: CanvasSize { .size(1440, 810) }

    // The hall, in meters. It is wide enough that the camera's short reach never takes in
    // the far side, which is what leaves the walk a lean to find when it comes home.
    let hallWidth = 10.0, hallDepth = 8.0, hallHeight = 2.6

    /// What the right half shows; **C** cycles it. All three scans run on every
    /// frame of the walk, so switching is instant, mid-walk or after.
    enum Mode: Int, CaseIterable {
        case reported, lined, closed
    }
    var mode = Mode.closed

    /// The pose-trusting scan: each frame fused where the camera said it stood.
    var loose = WorldCloud(voxelSize: 0.05)
    /// The left scan: each frame lined up against what is already fused.
    var lined = WorldCloud(voxelSize: 0.05)
    /// The loop-closing scan: the same, and it recognizes where it has been.
    var closed = ScanGraph(voxelSize: 0.05)

    var room: [PointCloud.Point] = []
    var walked = 0
    let walkFrames = 260

    /// The error the tracking has piled up so far, and how far it has carried the camera
    /// from where it really stands.
    var drift = matrix_identity_float4x4
    var lostItsPlaceBy = 0.0
    /// What the lining-up fit had left over on the latest frame.
    var leftOver = 0.0
    /// Where the pose-trusting scan put the camera, and where the left scan put it, kept
    /// so each walk can be drawn. The loop-closing scan keeps its own in
    /// `closed.keyframes`, and rewrites them when it straightens.
    var reportedWalk: [simd_float4x4] = []
    var linedWalk: [simd_float4x4] = []
    /// Where the camera really was at each of those, so each scan can be scored against
    /// the truth. A real scan never has this, which is the whole difficulty.
    var trueWalk: [simd_float4x4] = []
    /// The last place the loop-closing scan recognized, and how far the room moved when
    /// it did.
    var recognized: ScanGraph.Loop?
    var recognizedAt = -100.0
    /// The largest the room has moved on being recognized, over the whole walk.
    var biggestSnap = 0.0

    override func setup() {
        randomSeed(7)                                  // the same sensor noise every run
        var settings = ScanGraph.Settings()
        settings.keyframeDetail = 0.06                 // what a straightened scan keeps
        closed = ScanGraph(voxelSize: 0.05, settings: settings)
        room = builtRoom()
    }

    override func draw() {
        background(Color(white: 0.05))

        // One frame of the walk per drawn frame, then the pair just turns.
        if walked < walkFrames {
            let truth = cameraPose(at: Double(walked) / Double(walkFrames))
            let seen = whatTheCameraSees(from: truth)
            let reported = drift * truth

            loose.add(seen, transformedBy: reported)
            let alone = lined.add(seen, correcting: reported)
            let update = closed.add(seen, correcting: reported)
            leftOver = alone.error
            if update.keyframe != nil {
                reportedWalk.append(reported)
                linedWalk.append(alone.pose)
                trueWalk.append(truth)
            }
            if let loop = update.loop, loop.moved > 0.01 {
                recognized = loop
                recognizedAt = time
                biggestSnap = max(biggestSnap, loop.moved)
            }

            lostItsPlaceBy = Vector3.zero.transformed(by: truth)
                .distance(to: Vector3.zero.transformed(by: reported))
            drift = drift * driftStep()
            walked += 1
        }

        // Straight down on both scans at once, orthographic and fixed, so any difference
        // between the halves is theirs and not the camera's.
        let apart = hallWidth * 0.58
        camera(.orthographic(eye: Vector3(0, 26, 0.001), target: .zero, height: hallDepth + 5.5))
        drawPointCloud(lined.cloud.transformed(by: sideways(-apart)))
        drawWalk(linedWalk, shiftedBy: -apart)
        switch mode {
        case .reported:
            drawPointCloud(loose.cloud.transformed(by: sideways(apart)))
            drawWalk(reportedWalk, shiftedBy: apart)
        case .lined:
            drawPointCloud(lined.cloud.transformed(by: sideways(apart)))
            drawWalk(linedWalk, shiftedBy: apart)
        case .closed:
            drawPointCloud(closed.cloud.transformed(by: sideways(apart)))
            drawWalk(closed.keyframes.map(\.pose), shiftedBy: apart)
        }
        drawTrueWalls(shiftedBy: -apart)
        drawTrueWalls(shiftedBy: apart)

        drawLabels()
    }

    override func keyPressed() {
        if key == "r" || key == "R" {
            loose.reset()
            lined.reset()
            closed.reset()
            reportedWalk.removeAll()
            linedWalk.removeAll()
            trueWalk.removeAll()
            drift = matrix_identity_float4x4
            walked = 0
            leftOver = 0
            recognized = nil
            recognizedAt = -100
            biggestSnap = 0
        }
        if key == "c" || key == "C" {
            mode = Mode(rawValue: (mode.rawValue + 1) % Mode.allCases.count) ?? .closed
        }
    }

    // MARK: - The hall

    /// Four walls, a floor, a block in the middle, and eight crates standing about.
    ///
    /// The crates earn their place. A camera facing one bare wall can slide along it and
    /// turn about its normal and fit it exactly as well every time, so a match made there
    /// would report three measured numbers and three invented ones. Anything standing off
    /// the wall pins them, which is why a real room is easier to scan than a corridor.
    private func builtRoom() -> [PointCloud.Point] {
        var points: [PointCloud.Point] = []
        let spacing = 0.06
        let size = 0.035

        func surface(_ u: Double, _ v: Double, _ color: Color,
                     _ place: (Double, Double) -> Vector3) {
            var a = 0.0
            while a <= u {
                var b = 0.0
                while b <= v {
                    points.append(PointCloud.Point(position: place(a, b), color: color,
                                                   size: size))
                    b += spacing
                }
                a += spacing
            }
        }

        let halfWidth = hallWidth / 2, halfDepth = hallDepth / 2
        let wallColor = Color(red: 0.82, green: 0.50, blue: 0.42)
        let floorColor = Color(white: 0.42)
        surface(hallWidth, hallHeight, wallColor) { Vector3($0 - halfWidth, $1, -halfDepth) }
        surface(hallWidth, hallHeight, wallColor) { Vector3($0 - halfWidth, $1, halfDepth) }
        surface(hallDepth, hallHeight, wallColor) { Vector3(-halfWidth, $1, $0 - halfDepth) }
        surface(hallDepth, hallHeight, wallColor) { Vector3(halfWidth, $1, $0 - halfDepth) }
        surface(hallWidth, hallDepth, floorColor) { Vector3($0 - halfWidth, 0, $1 - halfDepth) }

        let crateColor = Color(red: 0.52, green: 0.78, blue: 0.58)
        for crate in 0 ..< 8 {
            let angle = 2 * .pi * Double(crate) / 8
            let middle = Vector3(cos(angle) * (halfWidth - 0.7), 0, sin(angle) * (halfDepth - 0.7))
            let edge = 0.6 + 0.15 * Double(crate % 3)
            surface(edge, edge, crateColor) { middle + Vector3($0 - edge / 2, edge, $1 - edge / 2) }
            surface(edge, edge, crateColor) { middle + Vector3($0 - edge / 2, $1, -edge / 2) }
            surface(edge, edge, crateColor) { middle + Vector3($0 - edge / 2, $1, edge / 2) }
            surface(edge, edge, crateColor) { middle + Vector3(-edge / 2, $1, $0 - edge / 2) }
            surface(edge, edge, crateColor) { middle + Vector3(edge / 2, $1, $0 - edge / 2) }
        }
        return points
    }

    // MARK: - The walk

    /// Where the camera really is at `t`, 0 to 1: once round the block and a little past
    /// where it began, facing out at the wall and tipped down the way a phone is held.
    private func cameraPose(at t: Double) -> simd_float4x4 {
        let angle = t * 1.12 * .tau
        let stand = Vector3(cos(angle) * (hallWidth / 2 - 1.4), 1.4,
                            sin(angle) * (hallDepth / 2 - 1.2))
        let outward = simd_quatf(angle: Float(-angle - .pi / 2), axis: SIMD3<Float>(0, 1, 0))
        let down = simd_quatf(angle: -0.35, axis: SIMD3<Float>(1, 0, 0))
        var pose = simd_float4x4(outward * down)
        pose.columns.3 = SIMD4<Float>(Float(stand.x), Float(stand.y), Float(stand.z), 1)
        return pose
    }

    /// What the tracking gets wrong each frame: a small step that always leans the same
    /// way, which is what makes it pile up instead of averaging out.
    private func driftStep() -> simd_float4x4 {
        let turn = simd_quatf(angle: 0.00062, axis: simd_normalize(SIMD3<Float>(0.15, 1, 0.1)))
        var step = simd_float4x4(turn)
        step.columns.3 = SIMD4<Float>(0.00066, 0.00009, -0.00048, 1)
        return step
    }

    /// The slice of the hall in front of the lens, in camera space. The reach is short,
    /// so the far side of the hall is never in frame: that is what leaves the walk with a
    /// lean to find at the end, rather than seeing the whole room at once and having
    /// nothing left to correct.
    private func whatTheCameraSees(from pose: simd_float4x4) -> PointCloud {
        let eye = Vector3.zero.transformed(by: pose)
        let forward = Vector3(0, 0, -1).transformed(by: pose) - eye
        let cone = cos(0.58)
        let inverse = pose.inverse

        var cloud = PointCloud()
        cloud.points.reserveCapacity(room.count / 6)
        for point in room {
            let toward = point.position - eye
            let distance = toward.length
            guard distance > 0.4, distance < 3.6 else { continue }
            guard forward.dot(toward) / distance > cone else { continue }
            // A real depth camera reads each point a little long or a little short, and
            // the error grows with distance. Without that the fit is perfect every frame
            // and never creeps, which is exactly the thing this sketch is about.
            var moved = point
            let seenAt = point.position.transformed(by: inverse)
            moved.position = seenAt * (1 + randomGaussian(mean: 0, deviation: 0.004))
            cloud.points.append(moved)
        }
        return cloud
    }

    // MARK: - Drawing

    /// The path a scan thinks the camera took, as a line of small marks. A walk that
    /// leaned closes as a spiral; a straightened one closes as a ring.
    private func drawWalk(_ poses: [simd_float4x4], shiftedBy shift: Double) {
        guard poses.count > 1 else { return }
        var trail = PointCloud()
        for (index, pose) in poses.enumerated() {
            let at = Vector3.zero.transformed(by: pose)
            let fade = Double(index) / Double(max(poses.count - 1, 1))
            trail.points.append(PointCloud.Point(
                position: at + Vector3(shift, 0.9, 0),
                color: Color(red: 1.0, green: 0.86 - fade * 0.5, blue: 0.30), size: 0.09))
        }
        drawPointCloud(trail)
    }

    /// Where the walls really are, laid over both scans as a thin white outline. Without
    /// something known to compare against, a scan that leaned and a scan that did not
    /// both just look like a room.
    private func drawTrueWalls(shiftedBy shift: Double) {
        var outline = PointCloud()
        let halfWidth = hallWidth / 2, halfDepth = hallDepth / 2
        let step = 0.05
        var along = -halfWidth
        while along <= halfWidth {
            for z in [-halfDepth, halfDepth] {
                outline.points.append(PointCloud.Point(
                    position: Vector3(along + shift, 1.3, z),
                    color: Color(white: 1.0), size: 0.045))
            }
            along += step
        }
        var across = -halfDepth
        while across <= halfDepth {
            for x in [-halfWidth, halfWidth] {
                outline.points.append(PointCloud.Point(
                    position: Vector3(x + shift, 1.3, across),
                    color: Color(white: 1.0), size: 0.045))
            }
            across += step
        }
        drawPointCloud(outline)
    }

    /// How far each kept pose ended up from where the camera really stood: the middling
    /// one, and the one where the walk came home.
    ///
    /// Two numbers rather than the worst of them, because they say different things. A
    /// loop pulls the two ends of the walk together and shares the difference along
    /// everything between, so it earns most of what it earns at the end, and the middle
    /// can be left about where it was. The worst reading alone would report only the
    /// middle and hide the whole point.
    private func strayed(_ walk: [simd_float4x4]) -> (typical: Double, home: Double) {
        var each: [Double] = []
        for index in 0 ..< min(walk.count, trueWalk.count) {
            each.append(Vector3.zero.transformed(by: walk[index])
                .distance(to: Vector3.zero.transformed(by: trueWalk[index])))
        }
        guard !each.isEmpty else { return (0, 0) }
        return (each.sorted()[each.count / 2], each[each.count - 1])
    }

    private func sideways(_ x: Double) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4<Float>(Float(x), 0, 0, 1)
        return m
    }

    // MARK: - Saying which is which

    private var rightTitle: String {
        switch mode {
        case .reported: return "as the camera reported it"
        case .lined:    return "lined up against the scan"
        case .closed:   return "and knows where it has been"
        }
    }

    private var rightStats: String {
        switch mode {
        case .reported:
            let score = strayed(reportedWalk)
            return String(format: "%d points, %.0f cm out, %.0f cm at the end",
                          loose.count, score.typical * 100, score.home * 100)
        case .lined:
            let score = strayed(linedWalk)
            return String(format: "%d points, %.0f cm out, %.0f cm at the end",
                          lined.count, score.typical * 100, score.home * 100)
        case .closed:
            let score = strayed(closed.keyframes.map(\.pose))
            return String(format: "%d points, %d kept, %.0f cm out, %.0f cm at the end",
                          closed.count, closed.keyframes.count,
                          score.typical * 100, score.home * 100)
        }
    }

    private func drawLabels() {
        textSize(30)
        textAlign(.center)
        fill(Color(red: 0.95, green: 0.62, blue: 0.55))
        drawText("lined up frame by frame", width * 0.25, 74)
        fill(Color(red: 0.60, green: 0.88, blue: 0.72))
        drawText(rightTitle, width * 0.75, 74)

        textSize(19)
        fill(Color(white: 0.72))
        let alone = strayed(linedWalk)
        drawText(String(format: "%d points, %.0f cm out, %.0f cm at the end",
                        lined.count, alone.typical * 100, alone.home * 100), width * 0.25, 110)
        drawText(rightStats, width * 0.75, 110)

        // Say so, loudly and briefly, at the moment the walk comes home.
        if mode == .closed, let loop = recognized, time - recognizedAt < 2.6 {
            textSize(26)
            fill(Color(red: 1.0, green: 0.86, blue: 0.30)
                .withAlpha(1 - (time - recognizedAt) / 2.6))
            drawText(String(format: "been here before: the room moved %.0f cm",
                            max(loop.moved, biggestSnap) * 100), width * 0.75, 150)
        }

        let closedCount = closed.loops.count
        let plural = closedCount == 1 ? "" : "s"
        if walked < walkFrames {
            drawCaption(String(format: "walking %d of %d: the camera has lost its place by %.0f cm, "
                    + "the fit has %.0f mm left over, and %d place%@ recognized. C picks the right half",
                walked, walkFrames, lostItsPlaceBy * 100, leftOver * 1000, closedCount, plural))
        } else {
            drawCaption(String(format: "walked %d frames, lost its place by %.0f cm, recognized %d place%@. "
                    + "R walks it again, C picks the right half",
                walkFrames, lostItsPlaceBy * 100, closedCount, plural))
        }
    }
}
