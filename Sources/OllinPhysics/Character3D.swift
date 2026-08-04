import Foundation
import Ollin
internal import CJolt

/// A walking figure in a `World3D`: a capsule that walks, climbs steps, slides
/// off slopes too steep to hold it, and jumps, driven from `draw()` the way
/// mouse and key state are. It is not a rigid body (nothing tumbles it, and it
/// stops where the geometry says it must), which is what makes it feel like
/// something you steer rather than something you throw.
///
/// Make one on the world, tell it where you want to go each frame, and draw it
/// from `position`:
///
/// ```swift
/// let walker = world.addCharacter(radius: 0.3, height: 1.8, at: Vector3(0, 2, 0))
/// // each frame:
/// var heading = Vector3.zero
/// if isKeyDown(.leftArrow)  { heading.x -= 1 }
/// if isKeyDown(.rightArrow) { heading.x += 1 }
/// walker.move(heading.normalized * 3)
/// if isKeyDown(.space) { walker.jump() }
/// world.step(dt: deltaTime)
/// withCharacter(walker) { drawCapsule(height: 1.2, radius: 0.3) }
/// ```
///
/// `position` is the character's *feet*, so a figure drawn standing on the
/// origin lands on the ground where it should.
public final class Character3D {

    /// What is under the character's feet, which decides whether it may walk.
    public enum GroundState {
        /// Standing on ground it can walk on.
        case onGround
        /// Held up by a slope past `maxSlope`: it can't climb any further, and
        /// slides if the sketch keeps pulling it down.
        case onSteepSlope
        /// Touching something that can't support it (a wall, a ceiling).
        case notSupported
        /// Touching nothing.
        case inAir
    }

    /// The world this character walks in. Unowned: the world holds it.
    unowned let world: World3D

    /// The underlying solver character.
    let handle: OpaquePointer

    /// The capsule's radius, in world units.
    public let radius: Double

    /// The capsule's whole standing height (both caps included), in world
    /// units: the character spans `position` … `position + height` on +y.
    public let height: Double

    /// The character's stand-in among the ordinary bodies: a kinematic body
    /// carried along inside the capsule, so ray picks find the character,
    /// `world.contacts` names it, and a sensor sees it walk in.
    ///
    /// ```swift
    /// if goal.isTouching(walker.body) { score += 1 }
    /// ```
    ///
    /// It is not in `world.bodies` (a drawing loop never asked for a capsule
    /// where the sketch draws its own figure), and its `position` is the
    /// stand-in's centre rather than the character's feet, which
    /// `character.position` reports.
    public private(set) var body: Body3D!

    /// Free-form tag so a sketch can hang its own data off a character.
    public var userData: Any?

    /// The horizontal velocity the character is trying to walk at, in world
    /// units per second (its vertical part is ignored: falling and jumping are
    /// the world's business). It holds until changed, so a character told to
    /// walk keeps walking; set it every frame from the keys. `move(_:)` is the
    /// sugar for it.
    public var desiredVelocity: Vector3 = .zero

    /// The steepest slope the character can walk up, in radians. Anything
    /// steeper holds it (`groundState` reads `.onSteepSlope`) but can't be
    /// climbed. The default of 50° clears a normal ramp and stops a wall.
    public var maxSlope: Double = 50 * .pi / 180 {
        didSet { cjolt_character_set_max_slope(handle, Float(maxSlope)) }
    }

    /// The tallest step the character walks up without jumping, in world
    /// units: a stair, a kerb, a ledge. `0` turns stepping off, and the
    /// character stops at anything it can't slide over.
    public var stepHeight: Double {
        didSet { cjolt_character_set_step_height(handle, world.meters(from: stepHeight)) }
    }

    /// How far the character may be pulled back down onto a floor it would
    /// otherwise skip off, in world units. Without it a character walking over
    /// the crest of a slope launches into the air for a few frames; `0` turns
    /// that stickiness off.
    public var stickToFloorDistance: Double {
        didSet {
            cjolt_character_set_stick_to_floor(handle,
                                               world.meters(from: stickToFloorDistance))
        }
    }

    /// The character's weight in kilograms: what it presses down with onto a
    /// dynamic body it stands on (a raft sinks, a seesaw tips).
    public var mass: Double = 70 {
        didSet { cjolt_character_set_mass(handle, Float(max(0, mass))) }
    }

    /// The hardest the character can shove a dynamic body sideways, in
    /// newtons. `0` makes it unable to push at all: crates become immovable
    /// walls it has to walk around.
    public var pushStrength: Double = 100 {
        didSet { cjolt_character_set_max_strength(handle, Float(max(0, pushStrength))) }
    }

    /// Which way the character faces, in radians about +y. Nothing in the
    /// simulation depends on it (the capsule is round), so it is there for the
    /// figure you draw: point it along the heading and the walker turns.
    public var facing: Double = 0 {
        didSet {
            let half = facing / 2
            withFloats4((0, Float(sin(half)), 0, Float(cos(half)))) {
                cjolt_character_set_rotation(handle, $0)
            }
        }
    }

    /// A jump asked for since the last step, in world units per second. Held
    /// until the step, which grants it only if the character is on the ground.
    private var pendingJump: Double?

    init?(world: World3D, radius: Double, height: Double, position: Vector3,
          stepHeight: Double, stickToFloorDistance: Double, maxSlope: Double,
          mass: Double, pushStrength: Double) {
        // A capsule needs room for both caps; a height under two radii would
        // leave no cylinder between them.
        let r = max(0.001, radius)
        let h = max(2 * r + 0.001, height)
        var desc = CJoltCharacterDesc()
        desc.radius = world.meters(from: r)
        desc.height = world.meters(from: h)
        let p = world.meters(from: position)
        desc.position = (p.0, p.1, p.2)
        desc.rotation = (0, 0, 0, 1)
        desc.maxSlopeAngle = Float(maxSlope)
        desc.stepHeight = world.meters(from: max(0, stepHeight))
        desc.stickToFloor = world.meters(from: max(0, stickToFloorDistance))
        desc.mass = Float(max(0, mass))
        desc.maxStrength = Float(max(0, pushStrength))
        // The library's own defaults: far enough ahead to find a sliding
        // direction, and penetration resolved within one update.
        desc.predictiveContactDistance = 0.1
        desc.penetrationRecoverySpeed = 1

        guard let handle = withUnsafePointer(to: &desc, {
            cjolt_character_create(world.handle, $0)
        }) else { return nil }

        self.world = world
        self.handle = handle
        self.radius = r
        self.height = h
        self.stepHeight = max(0, stepHeight)
        self.stickToFloorDistance = max(0, stickToFloorDistance)
        self.maxSlope = maxSlope
        self.mass = max(0, mass)
        self.pushStrength = max(0, pushStrength)

        // The inner body stands in for the character among the ordinary
        // bodies. Registered by id so a contact can name it, but kept out of
        // `world.bodies` for the same reason the ground slab is.
        let innerID = cjolt_character_get_inner_body(handle)
        let inner = Body3D(world: world, id: innerID,
                           collider: .capsule(height: h - 2 * r, radius: r),
                           kind: .kinematic, density: 1)
        inner.userData = self
        self.body = inner
        world.bodyByID[innerID] = inner
    }

    deinit {
        cjolt_character_destroy(world.handle, handle)
    }

    // MARK: Driving it

    /// Walk at `velocity` (world units per second). Only the horizontal part
    /// is used; gravity and jumps own the vertical. Call it every frame from
    /// the keys, passing `.zero` to stand still:
    ///
    /// ```swift
    /// walker.move(heading.normalized * walkSpeed)
    /// ```
    public func move(_ velocity: Vector3) {
        desiredVelocity = velocity
    }

    /// Walk across the ground plane at `x` units per second east and `z` units
    /// per second south.
    public func move(x: Double, z: Double) {
        desiredVelocity = Vector3(x, 0, z)
    }

    /// Ask to jump at `speed` world units per second on the next step. It is
    /// granted only if the character is on the ground then, so calling it
    /// every frame while a key is held gives a hop each time it lands.
    public func jump(_ speed: Double = 4) {
        pendingJump = speed
    }

    /// Stop dead: no walking velocity, no fall speed carried over.
    public func stop() {
        desiredVelocity = .zero
        velocity = .zero
    }

    // MARK: Where it is

    /// The character's feet, in world units: the point to draw a standing
    /// figure from. Setting it teleports, and re-reads what is underfoot.
    public var position: Vector3 {
        get {
            let out = readFloats3 { cjolt_character_get_position(handle, $0) }
            return world.units(from: out.0, out.1, out.2)
        }
        set {
            withFloats3(world.meters(from: newValue)) {
                cjolt_character_set_position(handle, $0)
            }
            cjolt_character_refresh_contacts(world.handle, handle)
        }
    }

    /// The velocity the character is *trying* to move at, in world units per
    /// second: the walking speed the sketch asked for plus whatever falling or
    /// jumping has added. It is the intent, not the outcome, so a character
    /// walking into a wall still reads its full walking speed. For how fast it
    /// actually got to move, read `actualVelocity`.
    public var velocity: Vector3 {
        get {
            let out = readFloats3 { cjolt_character_get_velocity(handle, $0) }
            return world.units(from: out.0, out.1, out.2)
        }
        set {
            withFloats3(world.meters(from: newValue)) {
                cjolt_character_set_velocity(handle, $0)
            }
        }
    }

    /// How fast the character actually moved on the last step, in world units
    /// per second, measured from the ground it covered. This is the one to
    /// drive a walk cycle from: pressed against a wall or a crate too heavy to
    /// shift it reads near zero, however fast `velocity` says it is walking.
    ///
    /// ```swift
    /// let pace = Vector2(walker.actualVelocity.x, walker.actualVelocity.z).length
    /// let stride = sin(time * 8) * min(1, pace / walkSpeed)
    /// ```
    public private(set) var actualVelocity: Vector3 = .zero

    /// What is under the character's feet.
    public var groundState: GroundState {
        switch cjolt_character_get_ground_state(handle) {
        case CJOLT_GROUND_ON_GROUND: return .onGround
        case CJOLT_GROUND_ON_STEEP: return .onSteepSlope
        case CJOLT_GROUND_NOT_SUPPORTED: return .notSupported
        default: return .inAir
        }
    }

    /// Whether the character is standing on ground it can walk on: the test to
    /// gate a jump, or to switch a walk cycle to a falling pose.
    public var isOnGround: Bool { groundState == .onGround }

    /// The surface normal under the character's feet (`.zero` in the air).
    /// Tilt a drawn figure toward it to lean into a slope.
    public var groundNormal: Vector3 {
        let out = readFloats3 { cjolt_character_get_ground_normal(handle, $0) }
        return Vector3(Double(out.0), Double(out.1), Double(out.2))
    }

    /// How fast the ground itself is moving, in world units per second: a
    /// character standing on a moving platform rides along with it.
    public var groundVelocity: Vector3 {
        let out = readFloats3 { cjolt_character_get_ground_velocity(handle, $0) }
        return world.units(from: out.0, out.1, out.2)
    }

    /// The body the character is standing on, or `nil` in the air. The ground
    /// slab reads as `world.groundBody`.
    public var groundBody: Body3D? {
        let id = cjolt_character_get_ground_body(handle)
        guard id != CJOLT_BODY_INVALID else { return nil }
        return world.bodyByID[id]
    }

    /// Whether a surface with this normal is too steep for the character to
    /// walk on, by its own `maxSlope`.
    public func isSlopeTooSteep(_ normal: Vector3) -> Bool {
        var steep = false
        withFloats3((Float(normal.x), Float(normal.y), Float(normal.z))) {
            steep = cjolt_character_is_slope_too_steep(handle, $0)
        }
        return steep
    }

    // MARK: Stepping (called by the world)

    /// Compose this step's velocity and sweep the character through the world.
    ///
    /// The composition is the library's own recipe, and each line earns its
    /// place: standing on the ground the character inherits the ground's
    /// velocity (so a moving platform carries it) rather than keeping its own
    /// fall speed, which is also the only moment a jump can be added; in the
    /// air it keeps just its vertical velocity, so gravity accumulates. The
    /// walking velocity is added last, and always, so the sketch still steers
    /// mid-jump.
    func advance(dt: Double) {
        let up = Vector3(0, 1, 0)
        let current = velocity
        let vertical = up * current.dot(up)
        let ground = groundVelocity
        // Rising away from the ground faster than a small tolerance means the
        // character is already leaving it: no second jump, no re-grounding.
        let towardsGround = (vertical.y - ground.y) < 0.1 * world.unitsPerMeter

        var next: Vector3
        if groundState == .onGround, !isSlopeTooSteep(groundNormal) {
            next = ground
            if let jump = pendingJump, towardsGround {
                next += up * jump
            }
        } else {
            next = vertical
        }
        next += world.gravity * dt
        // Only the horizontal part: the vertical is the world's to decide.
        next += Vector3(desiredVelocity.x, 0, desiredVelocity.z)
        velocity = next
        pendingJump = nil

        let before = position
        withFloats3(world.meters(from: world.gravity)) {
            cjolt_character_update(world.handle, handle, Float(dt), $0)
        }
        // What the world let it do, as opposed to what it asked for: the
        // sweep may have stopped it dead against a wall while `velocity` still
        // reads a full walking pace.
        actualVelocity = (position - before) / dt
    }
}
