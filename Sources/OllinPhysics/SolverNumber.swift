import Foundation
import Ollin

/// The numbers a solver holds, defined once for a snapshot's and a sketch's
/// own.
///
/// Both solvers keep single precision and stop simulating sensibly kilometers
/// from their origin, and a value that is not a number, an infinity, or a
/// magnitude far past that either stops a debug build inside the solver (the
/// 3D solver asserts on it one step later, in its integrator; the 2D one at
/// the call) or, in a release build, spreads through everything it touches,
/// since one such position poisons the broad phase and every contact after
/// it. So a number is checked where it crosses into the bridge, never inside
/// it: a snapshot's by the reader, which throws; a sketch's own by the world,
/// which leaves the thing as it was and says so once, or throws where the call
/// already throws for what it cannot build.
enum SolverNumber {

    /// The largest magnitude a world's numbers may have: a billion units. The
    /// solver keeps single precision and stops simulating sensibly kilometers
    /// from its origin, and its own debug build checks that nothing it holds
    /// passes 1e15 meters, so a number past this is refused at the bridge
    /// rather than handed over.
    static let largestMagnitude = 1e9

    static func holds(_ value: Double) -> Bool {
        value.isFinite && abs(value) <= largestMagnitude
    }

    static func holds(_ value: Vector3) -> Bool {
        holds(value.x) && holds(value.y) && holds(value.z)
    }

    static func holds(_ value: Vector2) -> Bool {
        holds(value.x) && holds(value.y)
    }

    /// What is wrong with `value`, for a note, or `nil` when the solver holds
    /// it.
    static func complaint(_ value: Double) -> String? {
        if value.isNaN { return "a value that is not a number" }
        if value.isInfinite { return "an infinite value" }
        if abs(value) > largestMagnitude { return "a value past a billion units" }
        return nil
    }

    static func complaint(_ value: Vector3) -> String? {
        complaint(value.x) ?? complaint(value.y) ?? complaint(value.z)
    }

    static func complaint(_ value: Vector2) -> String? {
        complaint(value.x) ?? complaint(value.y)
    }

    /// A rotation: finite, and long enough to be made a unit one.
    static func complaint(_ rotation: Rotation3D) -> String? {
        if let wrong = complaint(rotation.x) ?? complaint(rotation.y)
            ?? complaint(rotation.z) ?? complaint(rotation.w) {
            return wrong
        }
        let length = rotation.x * rotation.x + rotation.y * rotation.y
            + rotation.z * rotation.z + rotation.w * rotation.w
        return length > 1e-12 ? nil : "a rotation too short to be made a unit one"
    }

    /// An axis: a held direction with some length to it.
    static func axisComplaint(_ axis: Vector3) -> String? {
        complaint(axis) ?? (axis.lengthSquared > 1e-18 ? nil : "a direction of zero length")
    }

    static func axisComplaint(_ axis: Vector2) -> String? {
        complaint(axis) ?? (axis.lengthSquared > 1e-18 ? nil : "a direction of zero length")
    }

    /// The first complaint among `values`, or `nil`.
    static func complaint(in values: some Sequence<Vector3>) -> String? {
        for value in values {
            if let wrong = complaint(value) { return wrong }
        }
        return nil
    }
}

/// A world that checks a sketch's numbers at the bridge. When one is not a
/// number the solver holds, the world leaves things as they were and says so
/// once through its own `noteOnce`, or, in a call that already throws for what
/// it cannot build, throws `PhysicsError.unbuildable` naming the number.
protocol SolverNoting: AnyObject {
    func noteOnce(_ message: String)
}

extension SolverNoting {

    // MARK: A setter: keep what was there, and say so

    /// Whether `value` is a number the solver holds. When it is not, a
    /// one-time note names `what` and what was wrong, and the caller leaves
    /// things as they were. `orUnbounded` lets `.infinity` through, for a
    /// limit that means none.
    func holds(_ value: Double, _ what: String, orUnbounded: Bool = false) -> Bool {
        if orUnbounded, value == .infinity { return true }
        return accepts(SolverNumber.complaint(value), what, else: "ignoring it")
    }

    func holds(_ value: Vector3, _ what: String) -> Bool {
        accepts(SolverNumber.complaint(value), what, else: "ignoring it")
    }

    func holds(_ value: Vector2, _ what: String) -> Bool {
        accepts(SolverNumber.complaint(value), what, else: "ignoring it")
    }

    func holds(_ rotation: Rotation3D, _ what: String) -> Bool {
        accepts(SolverNumber.complaint(rotation), what, else: "ignoring it")
    }

    func holdsAxis(_ axis: Vector3, _ what: String) -> Bool {
        accepts(SolverNumber.axisComplaint(axis), what, else: "ignoring it")
    }

    // MARK: A creation argument: fall back to the default, and say so

    /// `value` when the solver holds it, else `fallback`, with a one-time note
    /// naming `what`.
    func held(_ value: Double, _ what: String, or fallback: Double,
              orUnbounded: Bool = false) -> Double {
        if orUnbounded, value == .infinity { return value }
        return accepts(SolverNumber.complaint(value), what, else: "using the default")
            ? value : fallback
    }

    func held(_ value: Vector3, _ what: String, or fallback: Vector3) -> Vector3 {
        accepts(SolverNumber.complaint(value), what, else: "using the default")
            ? value : fallback
    }

    func held(_ value: Vector2, _ what: String, or fallback: Vector2) -> Vector2 {
        accepts(SolverNumber.complaint(value), what, else: "using the default")
            ? value : fallback
    }

    /// An optional argument: `nil`, the parameter's own default, when the
    /// solver cannot hold the value.
    func held(_ value: Double?, _ what: String) -> Double? {
        guard let value else { return nil }
        return accepts(SolverNumber.complaint(value), what, else: "using the default")
            ? value : nil
    }

    /// `axis` when it is a held direction of some length, else straight up.
    func heldAxis(_ axis: Vector3, _ what: String) -> Vector3 {
        accepts(SolverNumber.axisComplaint(axis), what, else: "using the default")
            ? axis : .unitY
    }

    // MARK: A call that throws for what it cannot build

    func check(_ value: Double, _ what: String, orUnbounded: Bool = false) throws {
        if orUnbounded, value == .infinity { return }
        try refuse(SolverNumber.complaint(value), what)
    }

    func check(_ value: Vector3, _ what: String) throws {
        try refuse(SolverNumber.complaint(value), what)
    }

    func check(_ value: Double?, _ what: String) throws {
        if let value { try check(value, what) }
    }

    func check(_ value: Vector3?, _ what: String) throws {
        if let value { try check(value, what) }
    }

    func checkAxis(_ axis: Vector3, _ what: String) throws {
        try refuse(SolverNumber.axisComplaint(axis), what)
    }

    // MARK: The note and the error

    /// `true` when there is no complaint; else the note, once, and `false`.
    func accepts(_ complaint: String?, _ what: String, else action: String) -> Bool {
        guard let complaint else { return true }
        noteOnce("\(what) was given \(complaint); \(action)")
        return false
    }

    private func refuse(_ complaint: String?, _ what: String) throws {
        if let complaint {
            throw PhysicsError.unbuildable("\(what) was given \(complaint)")
        }
    }
}

extension World3D: SolverNoting {}
extension World: SolverNoting {}
