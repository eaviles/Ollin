import Foundation
import simd
import Ollin

/// The same room scanned twice, side by side: once trusting the camera's own idea of
/// where it is, and once lining every frame up against what has already been fused.
///
/// A depth camera that reports its own pose reports it with a small error. The error is
/// far too small to see in one frame, and it never goes away, so it piles up. After a
/// minute of sweeping, a wall seen at the start and again at the end lands in two
/// places and the scan turns to fog. That is drift, and the left half of this sketch is
/// what it does.
///
/// The right half calls `add(_:correcting:)` instead of `add(_:transformedBy:)`. Each
/// frame is slid and turned until it sits on the surfaces already fused, and the fix is
/// kept and reused on the next frame. The walls stay one wall thick.
///
/// Nothing is plugged in here: the room, the sweep and the drift are all made up, so
/// the sketch runs anywhere and both halves get exactly the same frames. Sweep a real
/// room with `PhoneWorldScan`, which calls the same method. Press **R** to run the
/// sweep again.
@main
final class DriftCorrectedScan: Sketch {

    // The room, in meters: a box a person could stand in.
    let roomWidth = 4.0, roomDepth = 3.0, roomHeight = 2.5

    // Fuse both scans the same way, so the only difference is the correction.
    var loose = WorldCloud(voxelSize: 0.03)
    var held = WorldCloud(voxelSize: 0.03)

    var room: [PointCloud.Point] = []
    var swept = 0
    let sweepFrames = 120

    /// The error the tracking has piled up so far.
    var drift = matrix_identity_float4x4
    /// How far the reported camera position ended up from the true one, in meters,
    /// and what the last fit had left over.
    var lostItsPlaceBy = 0.0
    var leftOver = 0.0

    override func setup() {
        room = builtRoom()
    }

    override func draw() {
        background(Color(white: 0.05))

        // One frame of the sweep per drawn frame, then the pair just turns.
        if swept < sweepFrames {
            let truth = cameraPose(at: Double(swept) / Double(sweepFrames))
            let seen = whatTheCameraSees(from: truth)
            let reported = drift * truth

            loose.add(seen, transformedBy: reported)
            let fix = held.add(seen, correcting: reported)

            // What the tracking got wrong by now, measured where it matters: the gap
            // between where the camera really stood and where it said it stood.
            lostItsPlaceBy = Vector3.zero.transformed(by: truth)
                .distance(to: Vector3.zero.transformed(by: reported))
            leftOver = fix.error

            drift = drift * driftStep()
            swept += 1
        }

        // Stand the two scans beside each other, and turn each one about its own
        // middle rather than flying the camera around the pair. The camera is
        // orthographic and fixed, so both halves are drawn at exactly the same size
        // from exactly the same angle: any difference between them is theirs.
        //
        // Looking down into the room is what makes drift visible: from overhead each
        // wall is a line, and a scan that drifted draws that line twice.
        let apart = roomWidth * 0.72
        let spin = spinning(time * 0.16)
        let across = 2 * (apart + Vector3(roomWidth, 0, roomDepth).length / 2) + 0.6
        camera(.orthographic(eye: Vector3(0, 16, 4.5), target: Vector3(0, roomHeight * 0.3, 0),
                             height: across))
        drawPointCloud(loose.cloud.transformed(by: sideways(-apart) * spin))
        drawPointCloud(held.cloud.transformed(by: sideways(apart) * spin))

        drawLabels()
    }

    override func keyPressed() {
        if key == "r" || key == "R" {
            loose.reset()
            held.reset()
            drift = matrix_identity_float4x4
            swept = 0
        }
    }

    // MARK: - The room

    /// Four walls, a floor and a ceiling, each in its own color so a smeared surface
    /// reads as one. Points sit on a 3 cm lattice, about what a depth camera returns
    /// across a room.
    private func builtRoom() -> [PointCloud.Point] {
        var points: [PointCloud.Point] = []
        let spacing = 0.03
        let size = 0.02
        let corner = Vector3(-roomWidth / 2, 0, -roomDepth / 2)

        func surface(_ u: Double, _ v: Double, _ color: Color,
                     _ place: (Double, Double) -> Vector3) {
            var a = 0.0
            while a <= u {
                var b = 0.0
                while b <= v {
                    points.append(PointCloud.Point(position: place(a, b) + corner,
                                                   color: color, size: size))
                    b += spacing
                }
                a += spacing
            }
        }

        surface(roomWidth, roomHeight, Color(red: 0.86, green: 0.42, blue: 0.36)) {
            Vector3($0, $1, 0)
        }
        surface(roomWidth, roomHeight, Color(red: 0.35, green: 0.62, blue: 0.86)) {
            Vector3($0, $1, roomDepth)
        }
        surface(roomHeight, roomDepth, Color(red: 0.90, green: 0.76, blue: 0.36)) {
            Vector3(0, $0, $1)
        }
        surface(roomHeight, roomDepth, Color(red: 0.46, green: 0.80, blue: 0.56)) {
            Vector3(roomWidth, $0, $1)
        }
        surface(roomWidth, roomDepth, Color(white: 0.55)) { Vector3($0, 0, $1) }
        return points                                     // open at the top, to look in
    }

    // MARK: - The sweep

    /// Where the camera really is at `t`, 0 to 1: standing near the middle of the room
    /// and turning on the spot, the way a phone is swept by hand.
    private func cameraPose(at t: Double) -> simd_float4x4 {
        let stand = Vector3(sin(t * .tau) * 0.35, 1.45, cos(t * .tau) * 0.35)
        let turn = simd_quatf(angle: Float(t * .pi * 1.6), axis: SIMD3<Float>(0, 1, 0))
        var pose = simd_float4x4(turn)
        pose.columns.3 = SIMD4<Float>(Float(stand.x), Float(stand.y), Float(stand.z), 1)
        return pose
    }

    /// What the tracking gets wrong each frame: a small step that always leans the same
    /// way, which is what makes it pile up instead of averaging out. A couple of
    /// millimeters and an eighth of a degree, which is smaller than a real camera's.
    private func driftStep() -> simd_float4x4 {
        let turn = simd_quatf(angle: 0.0022, axis: simd_normalize(SIMD3<Float>(0.2, 1, 0.15)))
        var step = simd_float4x4(turn)
        step.columns.3 = SIMD4<Float>(0.0016, 0.0004, -0.0011, 1)
        return step
    }

    /// The slice of the room in front of the lens, brought into camera space. A depth
    /// camera only ever returns what it can see, and that partial view is what the
    /// correction has to work from.
    private func whatTheCameraSees(from pose: simd_float4x4) -> PointCloud {
        let eye = Vector3.zero.transformed(by: pose)
        let forward = Vector3(0, 0, -1).transformed(by: pose) - eye
        let cone = cos(0.62)                              // about a 70 degree lens
        let inverse = pose.inverse

        var cloud = PointCloud()
        cloud.points.reserveCapacity(room.count / 3)
        for point in room {
            let toward = point.position - eye
            let distance = toward.length
            guard distance > 0.35, distance < 6 else { continue }
            guard forward.dot(toward) / distance > cone else { continue }
            var moved = point
            moved.position = point.position.transformed(by: inverse)
            cloud.points.append(moved)
        }
        return cloud
    }

    private func sideways(_ x: Double) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4<Float>(Float(x), 0, 0, 1)
        return m
    }

    /// A turn about the room's own middle, so a scan spins in place.
    private func spinning(_ angle: Double) -> simd_float4x4 {
        let middle = Vector3(0, roomHeight / 2, 0)
        let turn = simd_float4x4(simd_quatf(angle: Float(angle), axis: SIMD3<Float>(0, 1, 0)))
        var back = matrix_identity_float4x4
        back.columns.3 = SIMD4<Float>(Float(-middle.x), Float(-middle.y), Float(-middle.z), 1)
        var forth = matrix_identity_float4x4
        forth.columns.3 = SIMD4<Float>(Float(middle.x), Float(middle.y), Float(middle.z), 1)
        return forth * turn * back
    }

    // MARK: - Saying which is which

    private func drawLabels() {
        textSize(30)
        textAlign(.center)
        fill(Color(red: 0.95, green: 0.62, blue: 0.55))
        drawText("as the camera reported it", width * 0.25, 74)
        fill(Color(red: 0.60, green: 0.88, blue: 0.72))
        drawText("lined up against the scan", width * 0.75, 74)

        textSize(21)
        fill(Color(white: 0.72))
        drawText("\(loose.count) points", width * 0.25, 110)
        drawText("\(held.count) points", width * 0.75, 110)

        drawCaption(String(
            format: swept < sweepFrames
                ? "sweeping %d of %d: the camera has lost its place by %.0f cm, "
                    + "and the fit has %.0f mm left over"
                : "the camera lost its place by %3$.0f cm over %2$d frames, "
                    + "and the fit had %4$.0f mm left over. R to run it again",
            swept, sweepFrames, lostItsPlaceBy * 100, leftOver * 1000))
    }
}
