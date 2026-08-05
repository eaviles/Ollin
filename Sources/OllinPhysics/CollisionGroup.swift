import Foundation
import Ollin
internal import CJolt

/// A name for a set of things that collide, so a world can be told which sets
/// pass straight through each other. Everything starts in `.default`, where
/// everything touches everything; a group is only ever as meaningful as the
/// rules a sketch writes about it.
///
/// A group is a string, so it costs one word wherever a body is made:
///
/// ```swift
/// world.addBody(.sphere(radius: 0.2), at: p, group: "sparks")
/// world.ignoreCollisions(between: "sparks", and: "sparks")   // they pass through each other
/// world.ignoreCollisions(between: "sparks", and: "player")   // and through the player
/// ```
///
/// The rule is said once and reads both ways: there is no way to state that
/// sparks ignore the player but forget that the player ignores sparks.
public struct CollisionGroup: Hashable, Sendable, ExpressibleByStringLiteral,
                              CustomStringConvertible {

    /// The group's name. Groups with the same name are the same group.
    public let name: String

    public init(_ name: String) {
        self.name = name
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    /// The group everything is in until it is put in another one.
    public static let `default` = CollisionGroup("default")

    public var description: String { name }
}

// Which groups touch which. The world holds one table, the bodies hold their
// group, and the solver consults both wherever a pair can meet: finding
// contacts, answering a query, sweeping a character, and feeling for the road
// under a wheel.
extension World3D {

    /// How many collision groups a world can hold at once. Naming more than
    /// this keeps the extras in `.default` rather than aliasing them onto a
    /// group already in use, which would filter the wrong things.
    public static var maxCollisionGroups: Int { Int(CJOLT_MAX_GROUPS) }

    /// Every collision group this world has been told about, in the order they
    /// were first named, `.default` first. Useful for finding the typo when a
    /// rule seems to have done nothing: a misspelled name is a *new* group, and
    /// it shows up here.
    public var collisionGroups: [CollisionGroup] { groupNames }

    /// Say that two groups pass through each other. Symmetric, and stated once:
    ///
    /// ```swift
    /// world.ignoreCollisions(between: "debris", and: "player")
    /// world.ignoreCollisions(between: "debris", and: "debris")  // and through itself
    /// ```
    ///
    /// Naming a group here is enough to create it, so the rule can be written
    /// before anything is in either group. It takes effect on the next
    /// `step(dt:)`, which is also when a pair that was already touching comes
    /// apart.
    public func ignoreCollisions(between a: CollisionGroup, and b: CollisionGroup) {
        setCollisions(between: a, and: b, to: false)
    }

    /// Undo an `ignoreCollisions(between:and:)`: the two groups touch again.
    public func allowCollisions(between a: CollisionGroup, and b: CollisionGroup) {
        setCollisions(between: a, and: b, to: true)
    }

    /// Whether two groups currently collide. True unless something said
    /// otherwise, the diagonal included (two bodies in one group collide with
    /// each other by default).
    public func collides(_ a: CollisionGroup, with b: CollisionGroup) -> Bool {
        cjolt_world_group_collision(handle, groupIndex(a), groupIndex(b))
    }

    private func setCollisions(between a: CollisionGroup, and b: CollisionGroup,
                               to collide: Bool) {
        cjolt_world_set_group_collision(handle, groupIndex(a), groupIndex(b), collide)
        // A rule written while a filtered pair is asleep on top of each other
        // would not be looked at again until something else woke them.
        wakeEverything()
    }

    /// The solver's index for a group, naming it for the first time if need be.
    /// The table is a fixed size, so a world that runs out of room keeps every
    /// further name in the default group rather than aliasing one of the
    /// groups already in use.
    func groupIndex(_ group: CollisionGroup) -> Int32 {
        if let index = groupIndices[group] { return index }
        guard groupNames.count < World3D.maxCollisionGroups else {
            noteOnce("a world holds \(World3D.maxCollisionGroups) collision "
                     + "groups; \"\(group)\" and any further ones stay in the "
                     + "default group")
            return 0
        }
        let index = Int32(groupNames.count)
        groupIndices[group] = index
        groupNames.append(group)
        return index
    }

    /// The group a solver index names, for reading a body's group back.
    func group(at index: Int32) -> CollisionGroup {
        let slot = Int(index)
        return groupNames.indices.contains(slot) ? groupNames[slot] : .default
    }

    /// Wakes every body so a changed rule is acted on rather than waited out.
    private func wakeEverything() {
        for body in bodies where body.kind != .static { body.wake() }
        for ragdoll in ragdolls { ragdoll.wake() }
        for soft in softBodies { soft.wake() }
    }
}
