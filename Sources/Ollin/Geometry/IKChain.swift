import Foundation

/// A chain of rigid segments that reaches for a target: the inverse-kinematics
/// helper behind tentacles, limbs, and procedural creatures. Hold one, then
/// each frame point it somewhere (`reach(toward:)` keeps the base planted,
/// `drag(to:)` lets the whole chain trail its tip like a rope) and draw the
/// `joints` however you like.
///
/// ```swift
/// let arm = IKChain(from: center, segments: 12, length: 30)
///
/// override func draw() {
///     arm.reach(toward: Vector2(mouseX, mouseY))
///     drawPolyline(arm.joints)
/// }
/// ```
///
/// Two solvers, one aesthetic choice: `.fabrik` (the default) spreads the
/// motion evenly along the chain and settles into smooth, natural poses;
/// `.ccd` favors the joints near the tip, so the chain whips and curls.
/// `maxBend` stiffens every joint to a maximum angle against its neighbor,
/// which is what turns a floppy rope into a spine. Solving is warm-started
/// from the current pose each call, so a chain moves coherently frame to
/// frame. No randomness anywhere: a scripted target retraces the same motion
/// every run.
///
/// Implemented from the published techniques (Aristidou and Lasenby, *FABRIK:
/// A fast, iterative solver for the Inverse Kinematics problem*, Graphical
/// Models 73(5), 2011; Wang and Chen 1991 and Lander 1998 for cyclic
/// coordinate descent), not ported.
public final class IKChain {

    /// How `reach(toward:)` solves the chain.
    public enum Solver: Sendable {
        /// Iterate a tip-to-base and a base-to-tip pass, each re-placing
        /// joints at their segment length toward where they were. Spreads
        /// motion evenly along the chain; the smooth, natural default.
        case fabrik
        /// Cyclic coordinate descent: swing each joint in turn to aim the tip
        /// at the target, sweeping from the tip's joint to the base. Favors
        /// the joints near the tip, so the chain whips and curls.
        case ccd
    }

    /// The joint positions, base first, tip last (one more than the segment
    /// count). Read them to draw; the solvers move them.
    public private(set) var joints: [Vector2]

    /// The fixed segment lengths, captured from the joints at creation.
    public private(set) var lengths: [Double]

    /// The solver `reach(toward:)` runs. Switch it live; the pose carries.
    public var solver: Solver = .fabrik

    /// The stiffness limit: the largest angle (radians) a segment may bend
    /// against its neighbor, applied at every interior joint by both solvers
    /// and by `drag(to:)`. `nil` (the default) bends freely. Constraints can
    /// put a target out of reach, in which case the chain settles as close as
    /// it can.
    public var maxBend: Double?

    /// The largest swing (radians) one joint may take per solver sweep, for
    /// `.ccd` only: a damping clamp that trades convergence speed for smooth,
    /// kink-free motion. `nil` (the default) swings freely.
    public var maxTurn: Double?

    /// The first joint: where the chain is planted for `reach(toward:)`.
    public var base: Vector2 { joints[0] }

    /// The last joint: the end that reaches.
    public var tip: Vector2 { joints[joints.count - 1] }

    /// The chain's full reach: the sum of the segment lengths.
    public let totalLength: Double

    /// A chain through explicit joint positions (at least two). Segment
    /// lengths are captured from these points and stay fixed from then on.
    public init(joints: [Vector2]) {
        precondition(joints.count >= 2, "IKChain needs at least two joints")
        self.joints = joints
        var lengths = [Double]()
        lengths.reserveCapacity(joints.count - 1)
        for i in 0 ..< joints.count - 1 {
            lengths.append(max(joints[i].distance(to: joints[i + 1]), 1e-9))
        }
        self.lengths = lengths
        self.totalLength = lengths.reduce(0, +)
    }

    /// A straight chain of `segments` equal segments, planted at `base` and
    /// laid out along `angle` (radians, 0 points right).
    public convenience init(from base: Vector2, segments: Int, length: Double,
                            angle: Double = .pi / 2) {
        let count = max(segments, 1)
        let step = Vector2(angle: angle, length: max(length, 1e-9))
        self.init(joints: (0 ... count).map { base + step * Double($0) })
    }

    // MARK: - Solving

    /// Move the chain so the tip reaches for `target` while the base stays
    /// planted, running the active `solver` for up to `iterations` passes or
    /// until the tip is within `tolerance` of the target (or the solve stops
    /// making progress, which constraints can force). Returns whether the tip
    /// ended within tolerance.
    @discardableResult
    public func reach(toward target: Vector2, iterations: Int = 10,
                      tolerance: Double = 1) -> Bool {
        switch solver {
        case .fabrik: return reachFABRIK(toward: target, iterations: iterations, tolerance: tolerance)
        case .ccd: return reachCCD(toward: target, iterations: iterations, tolerance: tolerance)
        }
    }

    /// Pin the tip to `target` and let the rest of the chain trail after it,
    /// base included: the classic dragged tentacle. One tip-to-base pass, so
    /// it's cheap enough to call every frame with no iteration count.
    public func drag(to target: Vector2) {
        let n = lengths.count
        joints[n] = target
        for i in stride(from: n - 1, through: 0, by: -1) {
            joints[i] = joints[i + 1] + placedDirection(from: i + 1, toward: i) * lengths[i]
        }
    }

    /// Plant the base somewhere else, carrying the whole pose rigidly along.
    public func moveBase(to position: Vector2) {
        let offset = position - joints[0]
        for i in joints.indices { joints[i] += offset }
    }

    // MARK: - FABRIK

    private func reachFABRIK(toward target: Vector2, iterations: Int, tolerance: Double) -> Bool {
        let n = lengths.count
        let anchor = joints[0]

        // Out of reach: stretch straight toward the target and stop. Each
        // joint lands on the base-to-target ray, so bends are zero and any
        // stiffness limit is satisfied by construction.
        if anchor.distance(to: target) >= totalLength {
            for i in 0 ..< n {
                let offset = target - joints[i]
                let direction = offset.lengthSquared > 1e-18 ? offset.normalized : Vector2.unitX
                joints[i + 1] = joints[i] + direction * lengths[i]
            }
            return anchor.distance(to: target) <= totalLength + tolerance
        }

        var previousTipDistance = Double.infinity
        for _ in 0 ..< max(iterations, 1) {
            // Tip-to-base pass: pin the tip to the target, walk in re-placing
            // each joint at its segment length toward where it was.
            joints[n] = target
            for i in stride(from: n - 1, through: 0, by: -1) {
                joints[i] = joints[i + 1] + placedDirection(from: i + 1, toward: i) * lengths[i]
            }
            // Base-to-tip pass: re-plant the base, walk out the same way.
            joints[0] = anchor
            for i in 0 ..< n {
                joints[i + 1] = joints[i] + placedDirection(from: i, toward: i + 1) * lengths[i]
            }

            let tipDistance = joints[n].distance(to: target)
            if tipDistance <= tolerance { return true }
            // No further progress (a constrained or degenerate pose): stop
            // rather than spin on an unattainable target.
            if previousTipDistance - tipDistance < tolerance * 1e-3 { return false }
            previousTipDistance = tipDistance
        }
        return joints[n].distance(to: target) <= tolerance
    }

    /// The direction to place the joint at `moving` from the just-placed
    /// joint at `placed`: toward where it currently is, bent no further than
    /// `maxBend` from the neighboring segment already placed in this pass.
    private func placedDirection(from placed: Int, toward moving: Int) -> Vector2 {
        // The neighbor segment the bend is measured against: the one on the
        // far side of the placed joint, pointing along the pass direction.
        let beyond = placed + (placed - moving)
        let reference: Vector2? = joints.indices.contains(beyond)
            ? directionOrNil(from: joints[beyond], to: joints[placed]) : nil

        let offset = joints[moving] - joints[placed]
        var direction: Vector2
        if offset.lengthSquared > 1e-18 {
            direction = offset.normalized
        } else {
            // Degenerate (the two points coincide): continue straight.
            direction = reference ?? .unitX
        }
        if let maxBend, let reference {
            let bend = reference.angle(to: direction)
            if abs(bend) > maxBend {
                direction = reference.rotated(by: bend > 0 ? maxBend : -maxBend)
            }
        }
        return direction
    }

    private func directionOrNil(from a: Vector2, to b: Vector2) -> Vector2? {
        let offset = b - a
        return offset.lengthSquared > 1e-18 ? offset.normalized : nil
    }

    // MARK: - CCD

    private func reachCCD(toward target: Vector2, iterations: Int, tolerance: Double) -> Bool {
        let n = lengths.count
        for _ in 0 ..< max(iterations, 1) {
            var swept = 0.0
            for j in stride(from: n - 1, through: 0, by: -1) {
                let pivot = joints[j]
                let toTip = joints[n] - pivot
                let toTarget = target - pivot
                guard toTip.lengthSquared > 1e-12, toTarget.lengthSquared > 1e-12 else { continue }

                // The swing that aims the tip at the target from this joint.
                var turn = toTip.angle(to: toTarget)
                if let maxTurn {
                    turn = min(max(turn, -maxTurn), maxTurn)
                }
                // Keep this segment within the stiffness limit against the
                // one before it.
                if let maxBend, j > 0,
                   let inbound = directionOrNil(from: joints[j - 1], to: pivot),
                   let outbound = directionOrNil(from: pivot, to: joints[j + 1]) {
                    let bend = inbound.angle(to: outbound)
                    turn = min(max(turn, -maxBend - bend), maxBend - bend)
                }
                guard abs(turn) > 1e-12 else { continue }

                for k in (j + 1) ... n {
                    joints[k] = joints[k].rotated(by: turn, around: pivot)
                }
                swept += abs(turn)
                if joints[n].distanceSquared(to: target) <= tolerance * tolerance { return true }
            }
            // A whole sweep that barely moved is a stall (constraints or a
            // local minimum): stop rather than spin.
            if swept < 1e-9 { return false }
        }
        return joints[n].distanceSquared(to: target) <= tolerance * tolerance
    }
}
