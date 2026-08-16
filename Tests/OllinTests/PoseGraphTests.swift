@testable import Ollin
import Testing
import simd
import Foundation

/// Pure CPU checks on the pose graph that straightens a scan once the camera recognises
/// a place it has already been: the small-turn algebra it is built on, the straightening
/// itself, and the guards around a match that cannot be trusted. No Metal device, so
/// these run everywhere.
@Suite
struct PoseGraphTests {

    // MARK: - Building poses to test with

    private func pose(_ x: Double, _ y: Double, _ z: Double,
                      turn: Double = 0, axis: Vector3 = Vector3(0, 1, 0)) -> simd_float4x4 {
        let unit = axis.normalized
        let rotation = simd_quatf(angle: Float(turn),
                                  axis: SIMD3<Float>(Float(unit.x), Float(unit.y), Float(unit.z)))
        var m = simd_float4x4(rotation)
        m.columns.3 = SIMD4<Float>(Float(x), Float(y), Float(z), 1)
        return m
    }

    /// The position a pose puts the camera at.
    private func place(_ m: simd_float4x4) -> Vector3 {
        Vector3(Double(m.columns.3.x), Double(m.columns.3.y), Double(m.columns.3.z))
    }

    /// The biggest distance two poses disagree by, measured over probe points spread
    /// through the working volume rather than on the matrices themselves.
    private func disagreement(_ a: simd_float4x4, _ b: simd_float4x4) -> Double {
        let probes = [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1),
                      Vector3(1, 1, 1), Vector3(-1, 0.5, 2)]
        var worst = 0.0
        for probe in probes {
            worst = Swift.max(worst, a.transforming(probe).distance(to: b.transforming(probe)))
        }
        return worst
    }

    /// Eight camera stations around a circle, each looking out from it: a sweep that
    /// walks all the way round a room and comes back to where it started.
    private func circuit(stations: Int = 8, radius: Double = 2) -> [simd_float4x4] {
        (0 ..< stations).map { index in
            let angle = 2 * .pi * Double(index) / Double(stations)
            return pose(cos(angle) * radius, 0.2, sin(angle) * radius, turn: angle)
        }
    }

    // MARK: - The small-turn algebra underneath

    @Test func aTurnSurvivesBeingWrittenDownAndReadBack() {
        let turns = [Vector3(0.01, 0, 0), Vector3(0, 0.3, 0), Vector3(0.2, -0.4, 0.1),
                     Vector3(1.2, 0.3, -0.7), Vector3.zero]
        for turn in turns {
            var m = matrix_identity_float4x4
            let r = rotation(turningBy: turn)
            m.columns.0 = SIMD4<Float>(r.columns.0.x, r.columns.0.y, r.columns.0.z, 0)
            m.columns.1 = SIMD4<Float>(r.columns.1.x, r.columns.1.y, r.columns.1.z, 0)
            m.columns.2 = SIMD4<Float>(r.columns.2.x, r.columns.2.y, r.columns.2.z, 0)
            let read = turnOf(m)
            #expect(read.distance(to: turn) < 1e-4,
                    "wrote \(turn), read \(read)")
        }
    }

    /// Half a turn is where the sine vanishes and the axis has to be recovered another
    /// way. It is the one angle the ordinary formula cannot answer at all.
    @Test func halfATurnStillReportsItsAxis() {
        for axis in [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1),
                     Vector3(1, 1, 0).normalized] {
            let turn = axis.normalized * .pi
            var m = matrix_identity_float4x4
            let r = rotation(turningBy: turn)
            m.columns.0 = SIMD4<Float>(r.columns.0.x, r.columns.0.y, r.columns.0.z, 0)
            m.columns.1 = SIMD4<Float>(r.columns.1.x, r.columns.1.y, r.columns.1.z, 0)
            m.columns.2 = SIMD4<Float>(r.columns.2.x, r.columns.2.y, r.columns.2.z, 0)
            let read = turnOf(m)
            #expect(abs(read.length - .pi) < 1e-3)
            // The direction is what matters; half a turn one way is half a turn the other.
            #expect(abs(abs(read.normalized.dot(axis.normalized)) - 1) < 1e-3)
        }
    }

    @Test func nudgingAPoseKeepsItAPose() {
        let start = pose(1, 2, 3, turn: 0.7, axis: Vector3(0.3, 1, -0.2))
        let moved = retracted(start, turn: Vector3(0.05, -0.02, 0.01), move: Vector3(0.1, 0, -0.3))
        let r = rotationPart(moved)
        // Its columns are still at right angles and still of length one.
        for column in [r.columns.0, r.columns.1, r.columns.2] {
            #expect(abs(simd_length(column) - 1) < 1e-5)
        }
        #expect(abs(simd_dot(r.columns.0, r.columns.1)) < 1e-5)
        #expect(abs(simd_dot(r.columns.1, r.columns.2)) < 1e-5)
        #expect(abs(simd_dot(r.columns.0, r.columns.2)) < 1e-5)
    }

    // MARK: - Straightening

    @Test func aChainThatAlreadyAgreesIsLeftAlone() {
        let truth = circuit()
        var graph = PoseGraph(poses: truth)
        for index in 0 ..< truth.count - 1 {
            graph.edges.append(.init(from: index, to: index + 1,
                                     measured: truth[index].inverse * truth[index + 1]))
        }
        let report = graph.straighten()
        #expect(report.moved < 1e-4)
        for (before, after) in zip(truth, graph.poses) {
            #expect(disagreement(before, after) < 1e-4)
        }
    }

    /// Every measurement is exact, but the poses start in the wrong places. There is one
    /// arrangement that contradicts nothing, and the straightening has to find it.
    @Test func exactMeasurementsRecoverTheTruth() {
        let truth = circuit()
        var graph = PoseGraph(poses: truth)
        for index in 0 ..< truth.count - 1 {
            graph.edges.append(.init(from: index, to: index + 1,
                                     measured: truth[index].inverse * truth[index + 1]))
        }
        graph.edges.append(.init(from: truth.count - 1, to: 0,
                                 measured: truth[truth.count - 1].inverse * truth[0]))

        // Push every pose but the first somewhere wrong, by a repeatable amount.
        var random = SplitMix64(seed: 7)
        for index in 1 ..< graph.poses.count {
            let turn = Vector3(Double.random(in: -0.2...0.2, using: &random),
                               Double.random(in: -0.2...0.2, using: &random),
                               Double.random(in: -0.2...0.2, using: &random))
            let move = Vector3(Double.random(in: -0.3...0.3, using: &random),
                               Double.random(in: -0.3...0.3, using: &random),
                               Double.random(in: -0.3...0.3, using: &random))
            graph.poses[index] = retracted(graph.poses[index], turn: turn, move: move)
        }

        graph.straighten()
        for (index, expected) in truth.enumerated() {
            #expect(disagreement(expected, graph.poses[index]) < 1e-2,
                    "pose \(index) did not come back")
        }
    }

    /// The real case: the moves between neighbours are each a little wrong, so the chain
    /// bends, and the last pose ends up far from the first even though the camera came
    /// back to it. Measuring that one move directly is what fixes the whole chain.
    @Test func aLoopSharesTheDriftOutOverTheWholeChain() {
        let truth = circuit(stations: 16, radius: 2)
        var graph = PoseGraph(poses: [truth[0]])
        var measurements: [simd_float4x4] = []

        // Each measured move carries a small, always-the-same-way error, which is what
        // makes drift pile up rather than cancel.
        let slip = retracted(matrix_identity_float4x4, turn: Vector3(0, 0.02, 0),
                             move: Vector3(0.01, 0, 0))
        for index in 0 ..< truth.count - 1 {
            let measured = (truth[index].inverse * truth[index + 1]) * slip
            measurements.append(measured)
            graph.poses.append(graph.poses[index] * measured)
            graph.edges.append(.init(from: index, to: index + 1, measured: measured))
        }

        let before = graph.poses.enumerated().map { disagreement(truth[$0.offset], $0.element) }
        #expect(before.max()! > 0.3, "the drift has to be worth fixing")

        // The camera comes back to where it started, and this time the move is measured
        // against the place itself rather than against the pose before it.
        graph.edges.append(.init(from: truth.count - 1, to: 0,
                                 measured: truth[truth.count - 1].inverse * truth[0],
                                 weight: 1, robust: true))
        let report = graph.straighten()

        let after = graph.poses.enumerated().map { disagreement(truth[$0.offset], $0.element) }
        #expect(after.max()! < before.max()! * 0.4,
                "worst error went from \(before.max()!) to \(after.max()!)")
        #expect(report.moved > 0.1, "the map should visibly snap")
    }

    /// The measurements only ever say where the poses are relative to each other, so the
    /// whole scan could slide off as one and contradict nothing. One pose is held still
    /// to settle that, and it must not move even a little.
    @Test func theHeldPoseNeverMoves() {
        let truth = circuit(stations: 10)
        var graph = PoseGraph(poses: truth)
        let slip = retracted(matrix_identity_float4x4, turn: Vector3(0, 0.03, 0),
                             move: Vector3(0.02, 0, 0))
        graph.poses = [truth[0]]
        for index in 0 ..< truth.count - 1 {
            let measured = (truth[index].inverse * truth[index + 1]) * slip
            graph.poses.append(graph.poses[index] * measured)
            graph.edges.append(.init(from: index, to: index + 1, measured: measured))
        }
        graph.edges.append(.init(from: truth.count - 1, to: 0,
                                 measured: truth[truth.count - 1].inverse * truth[0]))

        let held = graph.poses[graph.held]
        graph.straighten()
        #expect(disagreement(held, graph.poses[graph.held]) == 0)
    }

    /// A place wrongly recognised is the one failure that can wreck a whole scan, so a
    /// loop is allowed to pull only so hard. The same wrong match left uncapped drags
    /// the map after it.
    @Test func aWrongLoopIsCappedRatherThanBelieved() {
        func mapWithLoop(robust: Bool) -> [simd_float4x4] {
            let truth = circuit(stations: 12)
            var graph = PoseGraph(poses: [truth[0]])
            for index in 0 ..< truth.count - 1 {
                let measured = truth[index].inverse * truth[index + 1]
                graph.poses.append(graph.poses[index] * measured)
                graph.edges.append(.init(from: index, to: index + 1, measured: measured))
            }
            // A match that is simply wrong: it claims the camera came back to a place it
            // is nowhere near.
            let nonsense = truth[truth.count - 1].inverse * truth[0]
            graph.edges.append(.init(from: truth.count - 1, to: 0,
                                     measured: retracted(nonsense, turn: Vector3(0, 0.6, 0),
                                                         move: Vector3(1.5, 0, 0)),
                                     weight: 1, robust: robust))
            graph.straighten()
            return graph.poses
        }

        let truth = circuit(stations: 12)
        let capped = mapWithLoop(robust: true)
        let believed = mapWithLoop(robust: false)
        let cappedWorst = capped.enumerated().map { disagreement(truth[$0.offset], $0.element) }.max()!
        let believedWorst = believed.enumerated().map { disagreement(truth[$0.offset], $0.element) }.max()!
        #expect(cappedWorst < believedWorst * 0.75,
                "capped \(cappedWorst) against believed \(believedWorst)")
    }

    @Test func aGraphWithNothingInItIsHarmless() {
        var empty = PoseGraph(poses: [])
        let report = empty.straighten()
        #expect(report.passes == 0)
        #expect(report.moved == 0)

        var lonely = PoseGraph(poses: [matrix_identity_float4x4])
        #expect(lonely.straighten().moved == 0)
    }
}
