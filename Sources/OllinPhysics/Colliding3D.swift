import Foundation
import Ollin
internal import CJolt

/// Something a `World3D` holds that can touch and be touched: an ordinary
/// `Body3D`, or a `SoftBody3D`.
///
/// A contact and a query hit name one of these rather than a body, because a
/// cloth is not a `Body3D`. It has no single pose, no mass an impulse can push,
/// and nothing to hang a joint off, so what a sketch may do with one is
/// genuinely different, and the type is what says so:
///
/// ```swift
/// for contact in world.contacts where contact.phase == .began {
///     splash(at: contact.point)                       // works for either kind
///     if let crate = contact.other(than: raft) as? Body3D {
///         crate.applyImpulse(Vector3(0, 2, 0))        // only a solid takes one
///     }
/// }
/// ```
public protocol Colliding3D: AnyObject {

    /// Which collision group it is in: what it passes through is whatever the
    /// world's `ignoreCollisions(between:and:)` rules say about that group.
    var group: CollisionGroup { get set }

    /// Whether the solver is still simulating it, or it has settled to sleep.
    var isAwake: Bool { get }

    /// Wakes it, so a change it should answer takes effect.
    func wake()

    /// Anything a sketch hung on it.
    var userData: Any? { get set }
}

extension Body3D: Colliding3D {}
extension SoftBody3D: Colliding3D {}

extension World3D {

    /// Whatever the world knows by this solver id, of either kind. Contacts and
    /// query hits both come back as ids, and either kind may answer.
    func colliding(at id: CJoltBodyID) -> (any Colliding3D)? {
        bodyByID[id] ?? softBodyByID[id]
    }

    /// The solver id behind either kind, for the touch bookkeeping (which is
    /// kept in ids so a body that has left the world cannot be reached through
    /// a stale list).
    func identifier(of thing: any Colliding3D) -> CJoltBodyID? {
        if let body = thing as? Body3D { return body.id }
        if let soft = thing as? SoftBody3D { return soft.bodyID }
        return nil
    }
}
