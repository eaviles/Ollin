@testable import Ollin
import Testing
import simd
import Foundation

/// Pure CPU checks on the drift correction that keeps a long depth sweep registered:
/// the point-to-plane solve, the pose recovery it drives, and the guards that hold it
/// back when the geometry cannot answer. No Metal device, so these run everywhere.
@Suite
struct CloudRegistrationTests {

    // MARK: - A scene to sweep

    /// Three walls meeting at the origin. Three planes at right angles pin all six
    /// degrees of freedom, which is what a real room corner does for a scanner.
    private func roomPoints(spacing: Double = 0.02, extent: Double = 2.0) -> [Vector3] {
        var points: [Vector3] = []
        var u = 0.0
        while u <= extent {
            var v = 0.0
            while v <= extent {
                points.append(Vector3(u, v, 0))
                points.append(Vector3(0, u, v))
                points.append(Vector3(u, 0, v))
                v += spacing
            }
            u += spacing
        }
        return points
    }

    /// How far a point sits off the nearest of the three walls. A fused scan that
    /// stays registered keeps this small; one that drifts smears it out.
    private func offTheWall(_ p: Vector3) -> Double {
        min(abs(p.x), abs(p.y), abs(p.z))
    }

    private func thickness(of cloud: PointCloud) -> Double {
        var squared = 0.0
        for point in cloud.points { squared += offTheWall(point.position) * offTheWall(point.position) }
        return (squared / Double(max(cloud.count, 1))).squareRoot()
    }

    private func pose(_ x: Double, _ y: Double, _ z: Double,
                      turn: Double = 0, axis: Vector3 = Vector3(0, 1, 0)) -> simd_float4x4 {
        let unit = axis.normalized
        let rotation = simd_quatf(angle: Float(turn),
                                  axis: SIMD3<Float>(Float(unit.x), Float(unit.y), Float(unit.z)))
        var m = simd_float4x4(rotation)
        m.columns.3 = SIMD4<Float>(Float(x), Float(y), Float(z), 1)
        return m
    }

    /// The biggest distance two poses disagree by, measured over probe points spread
    /// through the working volume rather than on the matrices themselves.
    private func disagreement(_ a: simd_float4x4, _ b: simd_float4x4) -> Double {
        let probes = [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1),
                      Vector3(1, 1, 1), Vector3(-1, 0.5, 2)]
        var worst = 0.0
        for probe in probes {
            worst = max(worst, a.transforming(probe).distance(to: b.transforming(probe)))
        }
        return worst
    }

    /// The room as one camera would see it: world points brought into camera space.
    private func seen(_ points: [Vector3], from cameraPose: simd_float4x4) -> PointCloud {
        PointCloud(positions: points).transformed(by: cameraPose.inverse)
    }

    // MARK: - The solve itself

    @Test func solverRecoversAKnownSmallMove() {
        // Target points on three walls, each with the wall's normal.
        var pairs: [SurfacePair] = []
        let move = pose(0.03, -0.02, 0.01, turn: 0.04, axis: Vector3(0.3, 1, 0.2))
        var u = 0.1
        while u <= 1.0 {
            var v = 0.1
            while v <= 1.0 {
                for (target, normal) in [(Vector3(u, v, 0), Vector3(0, 0, 1)),
                                         (Vector3(0, u, v), Vector3(1, 0, 0)),
                                         (Vector3(u, 0, v), Vector3(0, 1, 0))] {
                    // The source sits where the move would have taken the target from.
                    let source = move.inverse.transforming(target)
                    pairs.append(SurfacePair(source: source, target: target, normal: normal))
                }
                v += 0.1
            }
            u += 0.1
        }

        let solved = solvePointToPlane(pairs)
        #expect(solved != nil)
        // One round of the linear approximation lands close; ICP would run more.
        #expect(disagreement(solved!.move, move) < 2e-3)
    }

    /// The linear system is built from an approximate rotation matrix, and that matrix
    /// is not a rotation: it stretches by a little more the bigger the angle is. The
    /// answer has to be rebuilt from the recovered angles as a true rotation, or every
    /// round of the fit swells the scan a little, and the swelling compounds over a
    /// sweep. Nothing else in this suite would notice, because at the tiny angles a
    /// well-tracked frame asks for, the two matrices agree.
    @Test func solverAnswersWithATrueRotation() {
        var pairs: [SurfacePair] = []
        let move = pose(0.05, 0.02, -0.03, turn: 0.3, axis: Vector3(0.4, 1, 0.5))
        var u = 0.1
        while u <= 1.0 {
            var v = 0.1
            while v <= 1.0 {
                for (target, normal) in [(Vector3(u, v, 0), Vector3(0, 0, 1)),
                                         (Vector3(0, u, v), Vector3(1, 0, 0)),
                                         (Vector3(u, 0, v), Vector3(0, 1, 0))] {
                    pairs.append(SurfacePair(source: move.inverse.transforming(target),
                                             target: target, normal: normal))
                }
                v += 0.1
            }
            u += 0.1
        }

        let solved = solvePointToPlane(pairs)
        #expect(solved != nil)
        let m = solved!.move
        let columns = [SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z),
                       SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z),
                       SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z)]
        for column in columns {
            #expect(abs(Double(simd_length(column)) - 1) < 1e-6)
        }
        #expect(abs(Double(simd_dot(columns[0], columns[1]))) < 1e-6)
        #expect(abs(Double(simd_dot(columns[0], columns[2]))) < 1e-6)
        #expect(abs(Double(simd_dot(columns[1], columns[2]))) < 1e-6)
    }

    @Test func solverRefusesTooFewPairs() {
        let pairs = (0 ..< 5).map {
            SurfacePair(source: Vector3(Double($0), 0, 0), target: Vector3(Double($0), 0, 0.01),
                        normal: Vector3(0, 0, 1))
        }
        #expect(solvePointToPlane(pairs) == nil)
    }

    @Test func solverLeavesAnUnseenDirectionAlone() {
        // One plane only: it says nothing about sliding along itself. The solve must
        // answer zero there rather than a huge number.
        var pairs: [SurfacePair] = []
        var u = 0.0
        while u <= 1.0 {
            var v = 0.0
            while v <= 1.0 {
                pairs.append(SurfacePair(source: Vector3(u + 0.05, v + 0.05, 0.02),
                                         target: Vector3(u, v, 0), normal: Vector3(0, 0, 1)))
                v += 0.05
            }
            u += 0.05
        }
        let solved = solvePointToPlane(pairs)
        #expect(solved != nil)
        // It should push the points down onto the plane, and not slide them sideways.
        let moved = solved!.move.transforming(Vector3(0.5, 0.5, 0.02))
        #expect(abs(moved.z) < 1e-4)
        #expect(abs(moved.x - 0.5) < 1e-3)
        #expect(abs(moved.y - 0.5) < 1e-3)
        // And it should say so: one plane pins three of the six numbers at most.
        #expect(solved!.stability < 1e-6, "one plane read as \(solved!.stability)")
    }

    // MARK: - Recovering a pose against a fused scene

    @Test func aWrongPoseIsPutBack() {
        let points = roomPoints()
        let truth = pose(0.5, 0.6, 0.7, turn: 0.2)

        var world = WorldCloud(voxelSize: 0.01)
        world.add(seen(points, from: truth), transformedBy: truth)

        // The same frame handed over with a pose 4 cm and 2 degrees off.
        let wrong = pose(0.54, 0.58, 0.71, turn: 0.2 + 0.035)
        let fix = world.align(seen(points, from: truth), from: wrong)

        #expect(fix.applied)
        #expect(fix.overlap > 0.9)
        #expect(disagreement(wrong, truth) > 0.03)          // the error was real
        #expect(disagreement(fix.pose, truth) < 0.006)      // and it is gone
        #expect(fix.error < 0.006)
    }

    @Test func aRightPoseIsLeftAlone() {
        let points = roomPoints()
        let truth = pose(0.4, 0.4, 0.4)

        var world = WorldCloud(voxelSize: 0.01)
        world.add(seen(points, from: truth), transformedBy: truth)
        let fix = world.align(seen(points, from: truth), from: truth)

        #expect(fix.applied)
        #expect(disagreement(fix.pose, truth) < 0.002)
        #expect(fix.passes <= 3)                            // it stops as soon as it can
    }

    @Test func theFirstFrameGoesInAsReported() {
        var world = WorldCloud(voxelSize: 0.02)
        let reported = pose(1, 2, 3, turn: 0.3)
        let fix = world.add(seen(roomPoints(), from: reported), correcting: reported)

        #expect(!fix.applied)                               // nothing to line up against
        #expect(fix.pose == reported)
        #expect(world.correction == matrix_identity_float4x4)
        #expect(!world.isEmpty)
    }

    // MARK: - A sweep that drifts

    /// The heart of it: fuse the same room over many frames while the reported pose
    /// wanders off a little more each time, and compare what lands.
    private func sweep(correcting: Bool, frames: Int = 24) -> (cloud: PointCloud, fix: simd_float4x4) {
        let points = roomPoints(spacing: 0.03)
        var world = WorldCloud(voxelSize: 0.015)

        // Each frame adds a couple of millimeters and a fifth of a degree of error,
        // which is the shape of a real tracker's drift.
        let step = pose(0.002, 0.0005, -0.001, turn: 0.0035, axis: Vector3(0.2, 1, 0.1))
        var drift = matrix_identity_float4x4

        for frame in 0 ..< frames {
            let truth = pose(0.5 + 0.01 * Double(frame), 0.5, 0.5,
                             turn: 0.02 * Double(frame))
            let reported = drift * truth
            let camera = seen(points, from: truth)
            if correcting {
                world.add(camera, correcting: reported)
            } else {
                world.add(camera, transformedBy: reported)
            }
            drift = drift * step
        }
        return (world.cloud, world.correction)
    }

    @Test func aDriftingSweepSmearsAndTheFixTakesItOut() {
        let loose = sweep(correcting: false)
        let held = sweep(correcting: true)

        // Uncorrected, the walls thicken well past the fusion grid.
        #expect(thickness(of: loose.cloud) > 0.02)
        // Corrected, they stay about as thin as one voxel allows.
        #expect(thickness(of: held.cloud) < 0.008)
        #expect(thickness(of: held.cloud) < thickness(of: loose.cloud) / 3)

        // And the fix that was found is a real one, not the identity.
        #expect(held.fix.shift > 0.01 || held.fix.turn > 0.01)
    }

    @Test func aDriftingSweepKeepsTheCloudSmaller() {
        // A smear is also more points: a wall in two places fills twice the voxels.
        let loose = sweep(correcting: false)
        let held = sweep(correcting: true)
        #expect(held.cloud.count < loose.cloud.count)
    }

    // MARK: - The guards

    @Test func aFrameWithNothingInCommonIsRefused() {
        let points = roomPoints()
        let truth = pose(0.5, 0.5, 0.5)
        var world = WorldCloud(voxelSize: 0.02)
        world.add(seen(points, from: truth), transformedBy: truth)
        world.correction = pose(0.01, 0, 0)                 // an earlier fix to protect

        // A pose that puts the frame in a different room entirely.
        let lost = pose(40, 40, 40)
        let fix = world.align(seen(points, from: truth), from: lost)

        #expect(!fix.applied)
        #expect(fix.overlap < 0.3)
        #expect(fix.pose == world.correction * lost)        // the earlier fix survives
    }

    @Test func aJumpIsRefusedEvenWhenItMatches() {
        let points = roomPoints()
        let truth = pose(0.5, 0.5, 0.5)
        var world = WorldCloud(voxelSize: 0.02)
        world.add(seen(points, from: truth), transformedBy: truth)

        var settings = CloudAlignment.Settings()
        settings.maximumShift = 0.001                       // refuse anything real
        let wrong = pose(0.53, 0.5, 0.5)
        let fix = world.align(seen(points, from: truth), from: wrong, settings: settings)

        #expect(!fix.applied)
        #expect(fix.pose == wrong)
    }

    @Test func oneFlatWallCorrectsAcrossItAndNotAlongIt() {
        // A single wall: the fit can see how far off it the frame sits, and cannot
        // see where along it the frame sits. It must fix the first and leave the
        // second alone rather than slide the scan sideways.
        var points: [Vector3] = []
        var u = 0.0
        while u <= 2.0 {
            var v = 0.0
            while v <= 2.0 {
                points.append(Vector3(u, v, 0))
                v += 0.02
            }
            u += 0.02
        }
        let truth = pose(0.5, 0.5, 0.5)
        var world = WorldCloud(voxelSize: 0.01)
        world.add(seen(points, from: truth), transformedBy: truth)

        // Off the wall by 2 cm, and along it by 5 cm.
        let wrong = pose(0.55, 0.5, 0.52)
        let fix = world.align(seen(points, from: truth), from: wrong)

        let placed = fix.pose.transforming(Vector3.zero)
        #expect(abs(Double(placed.z) - 0.5) < 0.004)        // pushed back onto the wall
        #expect(abs(Double(placed.x) - 0.55) < 0.01)        // and not slid along it
        #expect(placed.x.isFinite && placed.y.isFinite && placed.z.isFinite)
    }

    // MARK: - Housekeeping

    @Test func theSameSweepTwiceGivesTheSameAnswer() {
        let first = sweep(correcting: true, frames: 8)
        let second = sweep(correcting: true, frames: 8)
        #expect(first.cloud.count == second.cloud.count)
        #expect(first.fix == second.fix)
    }

    @Test func resetForgetsTheFix() {
        let points = roomPoints()
        let truth = pose(0.5, 0.5, 0.5)
        var world = WorldCloud(voxelSize: 0.02)
        world.add(seen(points, from: truth), transformedBy: truth)
        world.add(seen(points, from: truth), correcting: pose(0.52, 0.5, 0.5))
        #expect(world.correction != matrix_identity_float4x4)

        world.reset()
        #expect(world.correction == matrix_identity_float4x4)
        #expect(world.isEmpty)
    }

    @Test func theFixCarriesToTheNextFrame() {
        let points = roomPoints()
        let truth = pose(0.5, 0.5, 0.5)
        var world = WorldCloud(voxelSize: 0.01)
        world.add(seen(points, from: truth), transformedBy: truth)

        // The same steady error twice over. The first frame has to find it; the
        // second starts from it and has almost nothing left to do.
        let wrong = pose(0.53, 0.51, 0.5, turn: 0.03)
        let first = world.add(seen(points, from: truth), correcting: wrong)
        let second = world.add(seen(points, from: truth), correcting: wrong)

        #expect(first.applied)
        #expect(second.applied)
        #expect(second.passes <= first.passes)
        #expect(second.error <= first.error + 1e-6)
        #expect(disagreement(second.pose, truth) < 0.006)
    }
}
