import Foundation
import Ollin
internal import CJolt

/// One touch between two bodies in a `World3D`, reported the way input is: the
/// solver records them while it steps, and `world.contacts` holds the list from
/// the most recent `step(dt:)` for `draw()` to read.
///
/// ```swift
/// world.step(dt: deltaTime)
/// for contact in world.contacts where contact.phase == .began {
///     sparks.append(Spark(at: contact.point, strength: contact.speed))
/// }
/// ```
///
/// Contacts are per body *pair*: a crate resting on a mesh floor touches it
/// along many triangles, but that is one `began` when it lands and one `ended`
/// when it lifts.
public struct Contact3D {

    /// Whether the two bodies just started touching or just stopped.
    public enum Phase { case began, ended }

    public let phase: Phase

    /// The two bodies, in a fixed order (not "the one that moved").
    public let a: Body3D
    public let b: Body3D

    /// Where they touched, in world units. `.zero` for an `ended` contact: by
    /// the time the solver notices a touch is over there is no longer a point
    /// to report (the body may even be gone).
    public let point: Vector3

    /// Unit normal at the touch, pointing from `a` toward `b`. `.zero` when
    /// `ended`.
    public let normal: Vector3

    /// How fast the two were closing along the normal when they met, in world
    /// units per second, measured before the solver answered the collision, so
    /// it reads the force of the impact rather than what was left after the
    /// bounce. `0` when `ended`, and `0` for two bodies that slid into contact
    /// rather than struck.
    public let speed: Double

    /// Whether `body` is one of the two.
    public func involves(_ body: Body3D) -> Bool { a === body || b === body }

    /// The far side of the contact from `body`, or `nil` if `body` isn't in it.
    public func other(than body: Body3D) -> Body3D? {
        if a === body { return b }
        if b === body { return a }
        return nil
    }
}

extension World3D {

    /// Drain the solver's per-step buffer into `contacts`, and keep the
    /// per-body touch lists in step with it. Called at the end of `step`.
    func drainContacts() {
        let count = Int(cjolt_world_contact_count(handle))
        guard count > 0 else {
            if !contacts.isEmpty { contacts = [] }
            return
        }
        var events = [CJoltContactEvent](repeating: CJoltContactEvent(),
                                         count: count)
        let written = events.withUnsafeMutableBufferPointer {
            Int(cjolt_world_drain_contacts(handle, $0.baseAddress, Int32(count)))
        }

        var drained: [Contact3D] = []
        drained.reserveCapacity(written)
        for event in events.prefix(written) {
            switch event.phase {
            case CJOLT_CONTACT_BEGAN:
                touchingIDs[event.bodyA, default: []].insertSorted(event.bodyB)
                touchingIDs[event.bodyB, default: []].insertSorted(event.bodyA)
            default:
                touchingIDs[event.bodyA]?.removeSorted(event.bodyB)
                touchingIDs[event.bodyB]?.removeSorted(event.bodyA)
            }
            // A body destroyed last frame still has its partings to report;
            // the touch lists above are already clean, so the event itself is
            // dropped rather than handed over half-resolved.
            guard let a = bodyByID[event.bodyA], let b = bodyByID[event.bodyB] else {
                continue
            }
            let began = event.phase == CJOLT_CONTACT_BEGAN
            drained.append(Contact3D(
                phase: began ? .began : .ended, a: a, b: b,
                point: began ? units(from: event.point.0, event.point.1,
                                     event.point.2) : .zero,
                normal: began ? Vector3(Double(event.normal.0),
                                        Double(event.normal.1),
                                        Double(event.normal.2)) : .zero,
                speed: began ? Double(event.speed) * unitsPerMeter : 0))
        }
        contacts = drained
    }

    /// Forget every touch involving `body` (it is leaving the world).
    func forgetTouches(of body: CJoltBodyID) {
        for partner in touchingIDs[body] ?? [] {
            touchingIDs[partner]?.removeSorted(body)
        }
        touchingIDs[body] = nil
    }
}

// Touch partners are kept in sorted arrays rather than a `Set`: the order a
// sketch reads them in has to be the same on every run (the catalog's
// determinism rule), and these lists are short enough that a linear insert
// costs nothing.
extension Array where Element == CJoltBodyID {
    mutating func insertSorted(_ value: CJoltBodyID) {
        var index = 0
        while index < count, self[index] < value { index += 1 }
        guard index == count || self[index] != value else { return }
        insert(value, at: index)
    }

    mutating func removeSorted(_ value: CJoltBodyID) {
        if let index = firstIndex(of: value) { remove(at: index) }
    }
}
