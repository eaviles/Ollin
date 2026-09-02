import Foundation
import simd

/// How a freshly-arrived cloud lined up against the scene already fused: the result
/// of `WorldCloud.align(_:from:)` and `WorldCloud.add(_:correcting:)`.
///
/// A depth camera that reports its own pose reports it with a small error, and the
/// error grows over a long sweep: the tracker has nothing to check itself against, so
/// each frame's mistake is added to the last one. Left alone, a wall seen at the start
/// of a scan and again at the end lands in two places, and the fused cloud thickens
/// into a smear. Lining the new frame up against the scene already fused takes that
/// error out again, one frame at a time.
public struct CloudAlignment: Sendable {

    /// The pose the cloud was actually placed with, as a camera→world transform. Use
    /// this instead of the reported pose to draw anything else the depth source
    /// reports in the same space (the camera itself, a hit test, a room mesh).
    public var pose: simd_float4x4

    /// The fix carried over the reported pose: `pose == correction * reportedPose`.
    /// It holds the whole drift found so far, not just this frame's share.
    public var correction: simd_float4x4

    /// The share of the sampled points that found a surface to match, 0 to 1. A sweep
    /// that turns to face a wall it has never seen reads low here, and the fix is
    /// held back rather than guessed.
    public var overlap: Double

    /// The typical distance left between a sampled point and the surface it matched,
    /// in world units (meters for a depth feed). It is measured along the surface
    /// normal, which is the quantity the fit makes as small as it can.
    public var error: Double

    /// How many rounds of the fit ran. It stops early once a round stops moving the
    /// cloud, so a well-tracked frame costs one or two.
    public var passes: Int

    /// How well the geometry pinned the answer down, 0 to 1.
    ///
    /// A fit can only find an error it can see. A camera facing one flat wall is free to
    /// slide along it and turn about its normal, and every one of those poses fits the
    /// wall exactly as well, so three of the six numbers are not measured at all. This
    /// says how far the surfaces in view are from that: 1 is a corner that pins
    /// everything, and a value near zero is a fit that could not have answered.
    ///
    /// It is read from the fit's own normal equations, as the smallest of their six
    /// eigenvalues over the largest. The fit already refuses to guess a direction the
    /// geometry does not pin down, so a low reading here is not a wrong answer: it is a
    /// *partial* one, and the parts it did not measure keep whatever error they had.
    /// That matters most when the answer is being kept as a measurement rather than used
    /// on the spot, which is what `minStability` is for.
    public var stability: Double

    /// Whether this frame's fit was accepted. When it is false the cloud still went
    /// in at `pose`, but with the fix carried over from earlier frames rather than a
    /// new one: too little overlap, too few points, or a jump big enough to look like
    /// a mistake.
    public var applied: Bool

    /// The parameters on the fit. The defaults suit a hand-held room sweep at a few
    /// centimeters per voxel; nothing here has to be set for that case.
    public struct Settings: Sendable {

        /// How many of the incoming cloud's points to fit through. The fit needs a
        /// spread of surfaces, not every sample, so a thousand or so is plenty and
        /// the cost is close to linear in this number.
        public var samples: Int = 1200

        /// The most rounds of the fit to run. It stops as soon as a round stops
        /// moving the cloud, so this is a ceiling and not a cost.
        public var passes: Int = 6

        /// How far from a point to look for the surface it belongs to, in world
        /// units. Bigger catches a bigger error and costs more; the search widens
        /// in whole voxels, so a range under one voxel behaves as one voxel.
        public var range: Double = 0.05

        /// The least overlap to trust, 0 to 1. Below it the fit is held back.
        public var minOverlap: Double = 0.3

        /// The biggest move to accept, in world units. A fit that asks for more than
        /// this is refused: over one frame it is a mistake, not a drift.
        public var maxShift: Double = 0.25

        /// The biggest turn to accept, in radians.
        public var maxTurn: Double = .pi / 12

        /// The least `stability` to trust, 0 to 1. Below it the fit is held back.
        ///
        /// The default of zero never refuses on this ground, which is right for a live
        /// feed: a partial answer against a bare wall still beats no answer, and the next
        /// frame that sees a corner puts the rest right. Raise it when the fit is being
        /// kept as a *measurement* of where two places stand relative to each other,
        /// since there the unmeasured directions are believed forever after.
        public var minStability: Double = 0

        public init() {}
    }

    /// The result for a frame nothing could be done with, where the pose passes through.
    static func unchanged(_ pose: simd_float4x4, correction: simd_float4x4) -> CloudAlignment {
        CloudAlignment(pose: pose, correction: correction, overlap: 0, error: 0,
                       passes: 0, stability: 0, applied: false)
    }
}

// MARK: - The fit

extension WorldCloud {

    /// Line `source` up against the scene already fused and report the pose it should
    /// go in at, without changing anything. `add(_:correcting:)` is the one-call form.
    ///
    /// `reportedPose` is the camera→world transform the depth source reports. The
    /// returned pose is that one with the drift taken out.
    public mutating func align(_ source: PointCloud,
                               from reportedPose: simd_float4x4,
                               settings: CloudAlignment.Settings = .init()) -> CloudAlignment {
        // The fix found so far is the starting guess: the tracker's own frame-to-frame
        // motion is good, so what is left to find is only the error added since the
        // last frame.
        let carried = correction * reportedPose
        guard !isEmpty, source.count >= 6, settings.samples >= 6, settings.passes >= 1 else {
            return .unchanged(carried, correction: correction)
        }

        // Take every nth point. A depth frame arrives in scan order, so a fixed step
        // spreads the samples over the whole image, and the same frame always gives
        // the same fit.
        let step = Swift.max(1, source.count / settings.samples)
        var picked: [Vector3] = []
        picked.reserveCapacity(source.count / step + 1)
        var index = 0
        while index < source.count {
            picked.append(source.points[index].position)
            index += step
        }

        let rings = Swift.max(1, Swift.min(3, Int((settings.range / voxelSize).rounded(.up))))
        let reach = Swift.max(settings.range, voxelSize)
        let reachSquared = reach * reach

        var current = carried
        var pairs: [SurfacePair] = []
        pairs.reserveCapacity(picked.count)
        var overlap = 0.0
        var error = 0.0
        var passes = 0
        var stability = 0.0
        var refused = false

        for _ in 0 ..< settings.passes {
            pairs.removeAll(keepingCapacity: true)
            var squared = 0.0
            var matched = 0
            for point in picked {
                let placed = current.transforming(point)
                guard let found = surface(near: placed, rings: rings, within: reachSquared)
                else { continue }
                // Landing on a known surface is the overlap; a surface too thinly
                // covered to give a normal still counts as seen, it just cannot be
                // fitted through.
                matched += 1
                guard let normal = found.normal else { continue }
                let gap = normal.dot(found.position - placed)
                squared += gap * gap
                pairs.append(SurfacePair(source: placed, target: found.position,
                                         normal: normal))
            }
            passes += 1
            overlap = Double(matched) / Double(picked.count)
            error = pairs.isEmpty ? 0 : (squared / Double(pairs.count)).squareRoot()

            guard pairs.count >= 6, overlap >= settings.minOverlap else {
                refused = true
                break
            }
            guard let solved = solvePointToPlane(pairs) else {
                refused = true
                break
            }
            stability = solved.stability
            current = solved.move * current

            // A round that no longer moves the cloud has found its answer.
            if solved.move.shift < 1e-5, solved.move.turn < 1e-5 { break }
        }

        // A fit that asks for a jump is a fit that matched the wrong surfaces. Keep
        // what earlier frames established rather than believe it.
        let asked = current * carried.inverse
        if asked.shift > settings.maxShift || asked.turn > settings.maxTurn {
            refused = true
        }
        // A fit the geometry could not pin down answered only some of the six numbers,
        // and left the rest as they were. That is the right thing to do with it here,
        // but it is the wrong thing to hand on as a measurement.
        if stability < settings.minStability { refused = true }

        guard !refused else {
            return CloudAlignment(pose: carried, correction: correction, overlap: overlap,
                                  error: error, passes: passes, stability: stability,
                                  applied: false)
        }

        return CloudAlignment(pose: current, correction: current * reportedPose.inverse,
                              overlap: overlap, error: error, passes: passes,
                              stability: stability, applied: true)
    }

    /// Line `source` up against what is already fused, then merge it: the drift
    /// correcting sibling of `add(_:transformedBy:)`.
    ///
    /// ```swift
    /// var world = WorldCloud(voxelSize: 0.025)
    /// // each new frame, in draw():
    /// if let frame = device.latestFrame, let pose = device.latestPose {
    ///     world.add(frame.pointCloud(...), correcting: pose)
    /// }
    /// ```
    ///
    /// The fix it finds is kept (see `correction`) and used as the starting guess for
    /// the next frame, so a sweep that runs for minutes stays registered instead of
    /// smearing. The first frame has nothing to line up against and goes in as
    /// reported.
    @discardableResult
    public mutating func add(_ source: PointCloud,
                             correcting reportedPose: simd_float4x4,
                             settings: CloudAlignment.Settings = .init()) -> CloudAlignment {
        let alignment = align(source, from: reportedPose, settings: settings)
        if alignment.applied { correction = alignment.correction }
        add(source, transformedBy: alignment.pose)
        return alignment
    }
}

// MARK: - Point-to-plane, solved as a linear system

/// One matched pair: a point of the arriving cloud, the fused point it belongs to,
/// and the surface normal there. The fit makes the distance from the point to that
/// surface's *plane* small, which converges far faster than the distance to the
/// point itself.
struct SurfacePair {
    var source: Vector3
    var target: Vector3
    var normal: Vector3
}

/// The rigid transform that makes the point-to-plane error over `pairs` as small as
/// it can be, found as a linear least-squares problem.
///
/// The exact problem is not linear, because the three rotation angles sit inside sines
/// and cosines. When the angles are small, `sin θ ≈ θ` and `cos θ ≈ 1` turn it into
/// six linear equations per pair, which is what makes this cheap enough to run several
/// times a frame. Each round leaves a smaller angle than the last, so the
/// approximation gets better as it goes.
///
/// The six unknowns are the three angles and the three offsets. Row `i` of the system
/// is the cross product of the point and its normal followed by the normal itself, and
/// the right-hand side is how far the point sits off the plane today. The normal
/// equations are then solved through the eigenvectors of a symmetric 6×6 matrix, which
/// is what lets a direction the geometry does not pin down (a sweep of one blank wall
/// pins five of the six) be dropped rather than filled with noise.
///
/// The recovered angles are turned back into a true rotation matrix, not the
/// approximate one the linear system was built from: that one is not a rotation, and
/// feeding it back would shear the cloud a little more every round.
///
/// It also reports how well the pairs pinned the answer down, as the smallest of the
/// system's six eigenvalues over the largest. That ratio is the standard reading of an
/// ICP fit's geometric stability, from Gelfand, Ikemoto, Rusinkiewicz and Levoy,
/// *Geometrically Stable Sampling for the ICP Algorithm* (3DIM 2003): a shape with a
/// small eigenvalue has a direction it can slide along, and the eigenvector says which.
///
/// Implemented from Kok-Lim Low, *Linear Least-Squares Optimization for Point-to-Plane
/// ICP Surface Registration* (UNC TR04-004, 2004).
func solvePointToPlane(_ pairs: [SurfacePair]) -> (move: simd_float4x4, stability: Double)? {
    guard pairs.count >= 6 else { return nil }

    // Angles and distances have to be comparable in size for the solve to be steady,
    // so the fit runs on points centered on the batch and scaled to about unit size.
    var centroid = Vector3.zero
    for pair in pairs { centroid += pair.source }
    centroid /= Double(pairs.count)
    var spread = 0.0
    for pair in pairs { spread += pair.source.distanceSquared(to: centroid) }
    let scale = Swift.max((spread / Double(pairs.count)).squareRoot(), 1e-6)

    var ata = [Double](repeating: 0, count: 36)
    var atb = [Double](repeating: 0, count: 6)
    var row = [Double](repeating: 0, count: 6)

    for pair in pairs {
        let s = (pair.source - centroid) / scale
        let d = (pair.target - centroid) / scale
        let n = pair.normal
        let cross = s.cross(n)
        row[0] = cross.x; row[1] = cross.y; row[2] = cross.z
        row[3] = n.x; row[4] = n.y; row[5] = n.z
        let residual = n.dot(d - s)

        for i in 0 ..< 6 {
            atb[i] += row[i] * residual
            for j in i ..< 6 { ata[i * 6 + j] += row[i] * row[j] }
        }
    }
    for i in 0 ..< 6 {                      // mirror the half that was filled
        for j in 0 ..< i { ata[i * 6 + j] = ata[j * 6 + i] }
    }

    guard let solved = solveSymmetric6(ata, atb) else { return nil }
    let x = solved.answer

    let alpha = x[0], beta = x[1], gamma = x[2]
    let translation = Vector3(x[3], x[4], x[5]) * scale

    let (sa, ca) = (sin(alpha), cos(alpha))
    let (sb, cb) = (sin(beta), cos(beta))
    let (sg, cg) = (sin(gamma), cos(gamma))
    let rotation = simd_double3x3(columns: (
        SIMD3(cg * cb, sg * cb, -sb),
        SIMD3(-sg * ca + cg * sb * sa, cg * ca + sg * sb * sa, cb * sa),
        SIMD3(sg * sa + cg * sb * ca, -cg * sa + sg * sb * ca, cb * ca)
    ))

    // The fit was solved about the batch center, so put that center back: turn about
    // it, then move.
    let center = SIMD3(centroid.x, centroid.y, centroid.z)
    let offset = center - rotation * center + SIMD3(translation.x, translation.y, translation.z)
    guard offset.x.isFinite, offset.y.isFinite, offset.z.isFinite else { return nil }

    let move = simd_float4x4(columns: (
        SIMD4(Float(rotation.columns.0.x), Float(rotation.columns.0.y), Float(rotation.columns.0.z), 0),
        SIMD4(Float(rotation.columns.1.x), Float(rotation.columns.1.y), Float(rotation.columns.1.z), 0),
        SIMD4(Float(rotation.columns.2.x), Float(rotation.columns.2.y), Float(rotation.columns.2.z), 0),
        SIMD4(Float(offset.x), Float(offset.y), Float(offset.z), 1)
    ))
    return (move, solved.stability)
}

/// Solve a symmetric 6×6 system through its eigenvectors, dropping any direction the
/// matrix barely constrains instead of dividing by almost nothing. A row-reduced
/// solve would answer such a direction with a huge, meaningless number; this answers
/// it with zero, which reads as "the geometry does not say", and is what keeps a sweep
/// of one flat wall from sliding along it.
///
/// It reports the smallest eigenvalue over the largest along with the answer, which is
/// how far the geometry was from pinning all six numbers down.
private func solveSymmetric6(_ matrix: [Double], _ rhs: [Double])
    -> (answer: [Double], stability: Double)? {
    var a = matrix
    var v = [Double](repeating: 0, count: 36)
    for i in 0 ..< 6 { v[i * 6 + i] = 1 }

    for _ in 0 ..< 24 {
        var off = 0.0
        for p in 0 ..< 6 { for q in (p + 1) ..< 6 { off += a[p * 6 + q] * a[p * 6 + q] } }
        var size = 0.0
        for i in 0 ..< 6 { size += a[i * 6 + i] * a[i * 6 + i] }
        if off <= 1e-30 * Swift.max(size, 1e-300) { break }

        for p in 0 ..< 5 {
            for q in (p + 1) ..< 6 {
                let apq = a[p * 6 + q]
                guard abs(apq) > 1e-300 else { continue }
                let app = a[p * 6 + p], aqq = a[q * 6 + q]
                let theta = 0.5 * atan2(2 * apq, aqq - app)
                let c = cos(theta), s = sin(theta)

                a[p * 6 + p] = c * c * app - 2 * s * c * apq + s * s * aqq
                a[q * 6 + q] = s * s * app + 2 * s * c * apq + c * c * aqq
                a[p * 6 + q] = 0
                a[q * 6 + p] = 0
                for k in 0 ..< 6 where k != p && k != q {
                    let akp = a[k * 6 + p], akq = a[k * 6 + q]
                    a[k * 6 + p] = c * akp - s * akq
                    a[p * 6 + k] = a[k * 6 + p]
                    a[k * 6 + q] = s * akp + c * akq
                    a[q * 6 + k] = a[k * 6 + q]
                }
                for k in 0 ..< 6 {
                    let vkp = v[k * 6 + p], vkq = v[k * 6 + q]
                    v[k * 6 + p] = c * vkp - s * vkq
                    v[k * 6 + q] = s * vkp + c * vkq
                }
            }
        }
    }

    var largest = 0.0
    var smallest = Double.greatestFiniteMagnitude
    for i in 0 ..< 6 {
        largest = Swift.max(largest, abs(a[i * 6 + i]))
        smallest = Swift.min(smallest, abs(a[i * 6 + i]))
    }
    guard largest > 0, largest.isFinite else { return nil }
    let stability = smallest / largest

    // Where a direction stops counting as measured. It is a *conditioning* cutoff and
    // not a numerical one, which is the whole point: a direction a thousandth as well
    // pinned as the best one is not a faint signal to be amplified, it is a surface the
    // points are free to slide along, and answering it divides a little noise by a very
    // small number. Set near the floating-point floor instead, the solve answers it, and
    // a camera facing one flat wall slides along it a few centimeters a frame while every
    // other reading, overlap and leftover error alike, stays perfect.
    let unmeasured = 1e-3

    var x = [Double](repeating: 0, count: 6)
    for j in 0 ..< 6 {
        let eigenvalue = a[j * 6 + j]
        guard eigenvalue > largest * unmeasured else { continue }   // it cannot say
        var projection = 0.0
        for k in 0 ..< 6 { projection += v[k * 6 + j] * rhs[k] }
        let weight = projection / eigenvalue
        for k in 0 ..< 6 { x[k] += weight * v[k * 6 + j] }
    }
    for value in x where !value.isFinite { return nil }
    return (x, stability)
}

// MARK: - Reading a transform

extension simd_float4x4 {

    /// How far this transform moves the origin, in world units.
    var shift: Double {
        let t = columns.3
        return Double(sqrt(t.x * t.x + t.y * t.y + t.z * t.z))
    }

    /// How far this transform turns, in radians.
    ///
    /// Read from the sine and the cosine together rather than from the trace alone.
    /// The trace gives the cosine, and near no turn at all the cosine is flat: every
    /// angle under about a thirtieth of a degree reads as the same number in single
    /// precision, so a test for "has it stopped moving" built on it can never pass.
    /// The off-diagonal part gives the sine, which stays sharp exactly there.
    var turn: Double {
        let sine = Vector3(Double(columns.1.z - columns.2.y),
                           Double(columns.2.x - columns.0.z),
                           Double(columns.0.y - columns.1.x)).length / 2
        let cosine = (Double(columns.0.x + columns.1.y + columns.2.z) - 1) / 2
        return atan2(Swift.min(sine, 1), cosine)
    }
}
