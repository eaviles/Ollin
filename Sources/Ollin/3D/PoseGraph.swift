import Foundation
import simd

/// A set of poses tied together by measured moves between them, straightened so that
/// every measurement is contradicted as little as it can be.
///
/// A scan is a chain: each pose was reached from the one before it, and the move between
/// them was measured. Every measurement is a little wrong, so the chain bends, and by the
/// end of a long sweep the last pose can be a long way from the truth. One more
/// measurement changes that. When the camera comes back to a place it has already been,
/// the move between a late pose and an early one can be measured directly, and the chain
/// becomes a loop that no longer closes. Sharing that disagreement out over every pose in
/// between is what straightens the whole scan, and it is what one bent chain can never do
/// for itself.
///
/// The solve is least squares: each edge contributes the difference between the move it
/// measured and the move the current poses imply, and the poses are moved to make the
/// total of those differences as small as it can be. Written from Grisetti, Kümmerle,
/// Stachniss and Burgard, *A Tutorial on Graph-Based SLAM* (IEEE Intelligent
/// Transportation Systems Magazine, 2010), with the on-manifold increment and its
/// numerically-differentiated derivatives from Blanco-Claraco, *A Tutorial on SE(3)
/// Transformation Parameterizations and On-Manifold Optimization* (2010/2021).
struct PoseGraph {

    /// One measured move: standing at `from`, the camera reached `to` by `measured`.
    struct Edge {
        /// The pose the move starts at.
        var from: Int
        /// The pose it ends at.
        var to: Int
        /// The move itself, as a `from`→`to` transform.
        var measured: simd_float4x4
        /// How much this measurement is trusted, against the others. It is an inverse
        /// variance, so twice as trustworthy is twice the number, and it scales the
        /// whole 6-vector the edge contributes.
        var weight: Double = 1
        /// Whether a wild disagreement on this edge should be capped rather than
        /// believed. A move measured between neighbors is never in doubt; a move
        /// measured between a late pose and an early one might be a mistaken match, and
        /// one of those left uncapped can bend a whole scan around itself.
        var robust: Bool = false
    }

    /// The knobs on the straightening. The defaults suit a room-scale sweep in meters.
    struct Settings {
        /// The most rounds to run. It stops as soon as a round stops moving the poses.
        var passes: Int = 25

        /// How far from the camera a turn is weighed, in world units. Turns are measured
        /// in radians and moves in meters, and the two have to be made comparable before
        /// they can be added up. This is the distance at which they are: a turn of one
        /// radian is weighed as heavily as a move of `turnScale` meters, because that is
        /// how far it drags a point standing that far away.
        var turnScale: Double = 2.0

        /// Where a robust edge stops being believed in full, as a weighted residual
        /// length. Past it the edge keeps pulling with the same strength rather than an
        /// ever-growing one.
        var huber: Double = 0.15

        /// The most rounds the inner linear solve may run.
        var solverPasses: Int = 120

        /// The inner solve stops once the residual has fallen this far below its start.
        var solverTolerance: Double = 1e-8

        /// A round that moves every pose less than this, in world units and radians, has
        /// found its answer.
        var settled: Double = 1e-7

        init() {}
    }

    /// What a straightening did.
    struct Report {
        /// How many rounds ran.
        var passes: Int
        /// The typical weighted disagreement left on an edge, after the straightening.
        var error: Double
        /// The furthest any pose moved, in world units. It is the size of the snap.
        var moved: Double
    }

    /// The poses, as camera→world transforms. `straighten` rewrites them in place.
    var poses: [simd_float4x4]

    /// The measured moves between them.
    var edges: [Edge] = []

    /// The pose held still. The measurements only ever say where poses are *relative to
    /// each other*, so the whole scan could slide or turn as one and contradict nothing.
    /// Holding one pose still is what settles that, and the first one is the natural
    /// choice: it is where the scan started.
    var held: Int = 0

    init(poses: [simd_float4x4]) {
        self.poses = poses
    }

    // MARK: - The straightening

    /// Move the poses until the measurements agree as well as they can, and report what
    /// that took. The held pose does not move.
    @discardableResult
    mutating func straighten(_ settings: Settings = .init()) -> Report {
        guard poses.count >= 2, !edges.isEmpty else {
            return Report(passes: 0, error: 0, moved: 0)
        }
        let started = poses
        let inverses = edges.map { $0.measured.inverse }
        let count = poses.count
        let width = count * 6

        var lambda = 1e-4
        var cost = totalCost(poses, inverses, settings)
        var passes = 0

        var blocks: [EdgeBlocks] = []
        var gradient = [Double](repeating: 0, count: width)
        var diagonal = [Double](repeating: 0, count: width)
        var built = false

        while passes < settings.passes {
            if !built {
                (blocks, gradient, diagonal) = buildSystem(poses, inverses, settings)
                built = true
            }
            let step = solve(blocks: blocks, gradient: gradient, diagonal: diagonal,
                             lambda: lambda, settings: settings)
            passes += 1

            var moved = 0.0
            var candidate = poses
            for index in 0 ..< count where index != held {
                let base = index * 6
                let turn = Vector3(step[base], step[base + 1], step[base + 2])
                let move = Vector3(step[base + 3], step[base + 4], step[base + 5])
                candidate[index] = retracted(poses[index], turn: turn, move: move)
                moved = Swift.max(moved, Swift.max(turn.length, move.length))
            }

            let next = totalCost(candidate, inverses, settings)
            if next <= cost {
                poses = candidate
                cost = next
                built = false
                lambda = Swift.max(lambda * 0.3, 1e-9)
                if moved < settings.settled { break }
            } else {
                // The step overshot. Pull it back toward the gradient and try the same
                // system again, rather than rebuilding it.
                lambda *= 8
                if lambda > 1e6 { break }
            }
        }

        var shifted = 0.0
        for (before, after) in zip(started, poses) {
            let gap = Vector3(Double(after.columns.3.x - before.columns.3.x),
                              Double(after.columns.3.y - before.columns.3.y),
                              Double(after.columns.3.z - before.columns.3.z))
            shifted = Swift.max(shifted, gap.length)
        }
        let residual = edges.isEmpty ? 0 : (cost / Double(edges.count)).squareRoot()
        return Report(passes: passes, error: residual, moved: shifted)
    }

    // MARK: - The system

    /// The two 6×6 derivative blocks one edge contributes, and the weights they carry.
    private struct EdgeBlocks {
        var from: Int
        var to: Int
        var a: [Double]         // 36, ∂residual/∂(the from pose's increment)
        var b: [Double]         // 36, ∂residual/∂(the to pose's increment)
        var info: [Double]      // 6, the diagonal weight on each component
    }

    /// How far an edge's measurement is from the move the current poses imply, as a
    /// turn and a move in the `from` pose's own frame.
    private func residual(_ edge: Edge, inverseMeasured: simd_float4x4,
                          from: simd_float4x4, to: simd_float4x4) -> [Double] {
        let gap = inverseMeasured * (from.inverse * to)
        let turn = turnOf(gap)
        return [turn.x, turn.y, turn.z,
                Double(gap.columns.3.x), Double(gap.columns.3.y), Double(gap.columns.3.z)]
    }

    /// The weight each of the six components carries, once the turn has been put in the
    /// same units as the move and a robust edge has been capped.
    private func information(_ edge: Edge, residual: [Double],
                             _ settings: Settings) -> [Double] {
        let move = edge.weight
        let turn = edge.weight * settings.turnScale * settings.turnScale
        var scale = 1.0
        if edge.robust {
            var squared = 0.0
            for index in 0 ..< 3 { squared += turn * residual[index] * residual[index] }
            for index in 3 ..< 6 { squared += move * residual[index] * residual[index] }
            let length = squared.squareRoot()
            if length > settings.huber { scale = settings.huber / length }
        }
        return [turn * scale, turn * scale, turn * scale,
                move * scale, move * scale, move * scale]
    }

    /// The weighted disagreement over every edge, which is what the straightening makes
    /// small.
    private func totalCost(_ poses: [simd_float4x4], _ inverses: [simd_float4x4],
                           _ settings: Settings) -> Double {
        var total = 0.0
        for (index, edge) in edges.enumerated() {
            let e = residual(edge, inverseMeasured: inverses[index],
                             from: poses[edge.from], to: poses[edge.to])
            let info = information(edge, residual: e, settings)
            for k in 0 ..< 6 { total += info[k] * e[k] * e[k] }
        }
        return total
    }

    /// Build the derivative blocks, the gradient, and the diagonal the inner solve
    /// preconditions with.
    ///
    /// The derivatives are taken numerically, by nudging a pose along each of the six
    /// directions it can move in and watching the residual: the increment lives in the
    /// tangent space rather than in the sixteen numbers of the matrix, so a central
    /// difference taken through the same retraction the step is applied with is exact to
    /// the order that matters and cannot disagree with it.
    private func buildSystem(_ poses: [simd_float4x4], _ inverses: [simd_float4x4],
                             _ settings: Settings)
        -> (blocks: [EdgeBlocks], gradient: [Double], diagonal: [Double]) {
        let nudge = 1e-4
        var blocks: [EdgeBlocks] = []
        blocks.reserveCapacity(edges.count)
        var gradient = [Double](repeating: 0, count: poses.count * 6)
        var diagonal = [Double](repeating: 0, count: poses.count * 6)

        for (index, edge) in edges.enumerated() {
            let inverse = inverses[index]
            let from = poses[edge.from]
            let to = poses[edge.to]
            let e = residual(edge, inverseMeasured: inverse, from: from, to: to)
            let info = information(edge, residual: e, settings)

            var a = [Double](repeating: 0, count: 36)
            var b = [Double](repeating: 0, count: 36)
            for column in 0 ..< 6 {
                let plus = nudged(from, column: column, by: nudge)
                let minus = nudged(from, column: column, by: -nudge)
                let up = residual(edge, inverseMeasured: inverse, from: plus, to: to)
                let down = residual(edge, inverseMeasured: inverse, from: minus, to: to)
                for row in 0 ..< 6 { a[row * 6 + column] = (up[row] - down[row]) / (2 * nudge) }

                let ahead = nudged(to, column: column, by: nudge)
                let behind = nudged(to, column: column, by: -nudge)
                let far = residual(edge, inverseMeasured: inverse, from: from, to: ahead)
                let near = residual(edge, inverseMeasured: inverse, from: from, to: behind)
                for row in 0 ..< 6 { b[row * 6 + column] = (far[row] - near[row]) / (2 * nudge) }
            }

            let fromBase = edge.from * 6
            let toBase = edge.to * 6
            for column in 0 ..< 6 {
                var gradientFrom = 0.0, gradientTo = 0.0
                var diagonalFrom = 0.0, diagonalTo = 0.0
                for row in 0 ..< 6 {
                    let weighted = info[row] * e[row]
                    gradientFrom += a[row * 6 + column] * weighted
                    gradientTo += b[row * 6 + column] * weighted
                    diagonalFrom += info[row] * a[row * 6 + column] * a[row * 6 + column]
                    diagonalTo += info[row] * b[row * 6 + column] * b[row * 6 + column]
                }
                gradient[fromBase + column] += gradientFrom
                gradient[toBase + column] += gradientTo
                diagonal[fromBase + column] += diagonalFrom
                diagonal[toBase + column] += diagonalTo
            }

            blocks.append(EdgeBlocks(from: edge.from, to: edge.to, a: a, b: b, info: info))
        }

        let heldBase = held * 6
        for column in 0 ..< 6 {
            gradient[heldBase + column] = 0
            diagonal[heldBase + column] = 0
        }
        return (blocks, gradient, diagonal)
    }

    /// Multiply a tangent-space vector by the system matrix without ever assembling it.
    /// Each edge touches only its own two poses, so the product is a walk over the
    /// edges, and the matrix that a scan of a few hundred poses would need never has to
    /// exist.
    private func multiply(_ vector: [Double], blocks: [EdgeBlocks],
                          diagonal: [Double], lambda: Double) -> [Double] {
        var result = [Double](repeating: 0, count: vector.count)
        var product = [Double](repeating: 0, count: 6)
        for block in blocks {
            let fromBase = block.from * 6
            let toBase = block.to * 6
            for row in 0 ..< 6 {
                var sum = 0.0
                for column in 0 ..< 6 {
                    sum += block.a[row * 6 + column] * vector[fromBase + column]
                    sum += block.b[row * 6 + column] * vector[toBase + column]
                }
                product[row] = block.info[row] * sum
            }
            for column in 0 ..< 6 {
                var atFrom = 0.0, atTo = 0.0
                for row in 0 ..< 6 {
                    atFrom += block.a[row * 6 + column] * product[row]
                    atTo += block.b[row * 6 + column] * product[row]
                }
                result[fromBase + column] += atFrom
                result[toBase + column] += atTo
            }
        }
        for index in 0 ..< result.count {
            result[index] += lambda * Swift.max(diagonal[index], 1e-12) * vector[index]
        }
        let heldBase = held * 6
        for column in 0 ..< 6 { result[heldBase + column] = 0 }
        return result
    }

    /// Solve for the step by conjugate gradients, preconditioned on the diagonal.
    /// The system is sparse and never assembled, so an iterative solve is the natural
    /// fit: every round costs one walk over the edges.
    private func solve(blocks: [EdgeBlocks], gradient: [Double], diagonal: [Double],
                       lambda: Double, settings: Settings) -> [Double] {
        let width = gradient.count
        var x = [Double](repeating: 0, count: width)
        var r = gradient.map { -$0 }
        let heldBase = held * 6
        for column in 0 ..< 6 { r[heldBase + column] = 0 }

        func preconditioned(_ v: [Double]) -> [Double] {
            var out = [Double](repeating: 0, count: width)
            for index in 0 ..< width {
                let d = diagonal[index] * (1 + lambda)
                out[index] = d > 1e-12 ? v[index] / d : 0
            }
            for column in 0 ..< 6 { out[heldBase + column] = 0 }
            return out
        }

        var z = preconditioned(r)
        var p = z
        var rz = dot(r, z)
        let target = dot(r, r) * settings.solverTolerance
        guard rz.isFinite, rz > 0 else { return x }

        for _ in 0 ..< settings.solverPasses {
            let ap = multiply(p, blocks: blocks, diagonal: diagonal, lambda: lambda)
            let denominator = dot(p, ap)
            guard denominator > 0, denominator.isFinite else { break }
            let alpha = rz / denominator
            for index in 0 ..< width {
                x[index] += alpha * p[index]
                r[index] -= alpha * ap[index]
            }
            if dot(r, r) <= target { break }
            z = preconditioned(r)
            let next = dot(r, z)
            guard next.isFinite, next > 0 else { break }
            let beta = next / rz
            rz = next
            for index in 0 ..< width { p[index] = z[index] + beta * p[index] }
        }
        for value in x where !value.isFinite { return [Double](repeating: 0, count: width) }
        return x
    }

    private func dot(_ a: [Double], _ b: [Double]) -> Double {
        var total = 0.0
        for index in 0 ..< a.count { total += a[index] * b[index] }
        return total
    }

    /// A pose nudged along one of the six directions its increment can take.
    private func nudged(_ pose: simd_float4x4, column: Int, by amount: Double) -> simd_float4x4 {
        var turn = Vector3.zero
        var move = Vector3.zero
        switch column {
        case 0: turn = Vector3(amount, 0, 0)
        case 1: turn = Vector3(0, amount, 0)
        case 2: turn = Vector3(0, 0, amount)
        case 3: move = Vector3(amount, 0, 0)
        case 4: move = Vector3(0, amount, 0)
        default: move = Vector3(0, 0, amount)
        }
        return retracted(pose, turn: turn, move: move)
    }
}

// MARK: - Moving a pose by a small amount

/// A pose with a small turn and a small move applied: the turn about the pose's own
/// axes, the move along the world's.
///
/// A rotation cannot be nudged by adding to its numbers, because the result stops being
/// a rotation. This is the way to add a small amount to one and keep it a rotation, and
/// keeping the same one throughout is what lets a derivative be taken through it.
func retracted(_ pose: simd_float4x4, turn: Vector3, move: Vector3) -> simd_float4x4 {
    let turned = rotationPart(pose) * rotation(turningBy: turn)
    var result = pose
    result.columns.0 = SIMD4<Float>(turned.columns.0.x, turned.columns.0.y, turned.columns.0.z, 0)
    result.columns.1 = SIMD4<Float>(turned.columns.1.x, turned.columns.1.y, turned.columns.1.z, 0)
    result.columns.2 = SIMD4<Float>(turned.columns.2.x, turned.columns.2.y, turned.columns.2.z, 0)
    result.columns.3 = SIMD4<Float>(pose.columns.3.x + Float(move.x),
                                    pose.columns.3.y + Float(move.y),
                                    pose.columns.3.z + Float(move.z),
                                    pose.columns.3.w)
    return result
}

/// The turning part of a transform, with the move dropped.
func rotationPart(_ m: simd_float4x4) -> simd_float3x3 {
    simd_float3x3(columns: (SIMD3<Float>(m.columns.0.x, m.columns.0.y, m.columns.0.z),
                            SIMD3<Float>(m.columns.1.x, m.columns.1.y, m.columns.1.z),
                            SIMD3<Float>(m.columns.2.x, m.columns.2.y, m.columns.2.z)))
}

/// The rotation that turns by `v` radians about the axis `v` points along.
func rotation(turningBy v: Vector3) -> simd_float3x3 {
    let angle = v.length
    guard angle > 1e-12 else { return matrix_identity_float3x3 }
    let a = v / angle
    let s = sin(angle), c = cos(angle), t = 1 - c
    let (x, y, z) = (a.x, a.y, a.z)
    return simd_float3x3(columns: (
        SIMD3<Float>(Float(t * x * x + c), Float(t * x * y + s * z), Float(t * x * z - s * y)),
        SIMD3<Float>(Float(t * x * y - s * z), Float(t * y * y + c), Float(t * y * z + s * x)),
        SIMD3<Float>(Float(t * x * z + s * y), Float(t * y * z - s * x), Float(t * z * z + c))
    ))
}

/// How far and about what axis a transform turns, as one vector whose length is the
/// angle in radians. The inverse of `rotation(turningBy:)`.
///
/// Read from the sine and the cosine together: near no turn at all the cosine alone is
/// flat, and every small angle would read as the same number.
func turnOf(_ m: simd_float4x4) -> Vector3 {
    let skew = Vector3(Double(m.columns.1.z - m.columns.2.y),
                       Double(m.columns.2.x - m.columns.0.z),
                       Double(m.columns.0.y - m.columns.1.x)) / 2
    let sine = skew.length
    let cosine = (Double(m.columns.0.x + m.columns.1.y + m.columns.2.z) - 1) / 2
    let angle = atan2(min(sine, 1), max(min(cosine, 1), -1))

    if sine > 1e-9 { return skew * (angle / sine) }
    if cosine > 0 { return skew }               // no turn worth speaking of

    // Half a turn: the sine is zero here too, so the axis has to come from the
    // symmetric part instead, where it survives as the one direction the transform
    // leaves alone.
    let diagonal = Vector3(Double(m.columns.0.x), Double(m.columns.1.y), Double(m.columns.2.z))
    var axis = Vector3(((diagonal.x + 1) / 2).squareRoot(),
                       ((diagonal.y + 1) / 2).squareRoot(),
                       ((diagonal.z + 1) / 2).squareRoot())
    if axis.x >= axis.y, axis.x >= axis.z, axis.x > 1e-9 {
        axis = Vector3(axis.x,
                       Double(m.columns.1.x + m.columns.0.y) / (4 * axis.x),
                       Double(m.columns.2.x + m.columns.0.z) / (4 * axis.x))
    } else if axis.y >= axis.z, axis.y > 1e-9 {
        axis = Vector3(Double(m.columns.1.x + m.columns.0.y) / (4 * axis.y),
                       axis.y,
                       Double(m.columns.2.y + m.columns.1.z) / (4 * axis.y))
    } else if axis.z > 1e-9 {
        axis = Vector3(Double(m.columns.2.x + m.columns.0.z) / (4 * axis.z),
                       Double(m.columns.2.y + m.columns.1.z) / (4 * axis.z),
                       axis.z)
    } else {
        return .zero
    }
    return axis.normalized * angle
}
