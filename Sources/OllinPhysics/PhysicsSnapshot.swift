import Foundation
import Compression
import simd
import Ollin
internal import CJolt

/// Everything a `World3D` holds, captured at one moment: the bodies with their
/// shapes and their poses, the joints between them, and the world's own
/// settings. Take one with `World3D.snapshot()`, put it back with
/// `World3D.restore(_:)`, and write it to a file to keep it.
///
/// ```swift
/// let settled = world.snapshot()      // after the pile has come to rest
/// // …knock it over, rummage through it…
/// world.restore(settled)              // exactly the pile you had
/// ```
///
/// A snapshot is the answer to a pile that took a while to make. Simulating is
/// reproducible within one build but not across them: the solver runs in
/// floating point, a toolchain that moves one ulp moves the last bounce, and a
/// toppling stack magnifies that into a different heap. A saved pile has
/// nothing left to compute, so it comes back the same on any machine.
///
/// ```swift
/// // in setup()
/// if let saved = try? PhysicsSnapshot(contentsOf: file) {
///     world.restore(saved)
/// } else {
///     buildAndSettle()
///     try? world.snapshot().write(to: file)
/// }
/// ```
///
/// What it holds is the rigid tier: `Body3D`s (with their colliders, poses,
/// motion, and every knob `addBody` takes), the `Joint3D`s between them,
/// gears and racks, the collision-group table, and the world's `gravity`,
/// `ground`, `bounce`, `maxTimestep`, `unitsPerMeter`, and `water`. Characters,
/// vehicles, ragdolls, and soft bodies are each built from something a
/// snapshot has no way to carry (a rig, a wheel layout, a skinned scene, a
/// mesh), so they are left out, with a note naming what was skipped. Contacts
/// are left out too: they are worked out again by the next `step(dt:)`.
public struct PhysicsSnapshot: Sendable, Equatable {

    /// The bytes. Write them anywhere; hand them back to `init(data:)`.
    public let data: Data

    /// How many rigid bodies it holds.
    public let bodyCount: Int

    /// How many joints it holds, gear and rack links included.
    public let jointCount: Int

    /// Reads a snapshot's bytes back, or `nil` if they are not a snapshot (or
    /// are in a format this version of Ollin does not read).
    public init?(data: Data) {
        guard let header = SnapshotHeader(of: data) else { return nil }
        self.data = data
        self.bodyCount = header.bodies
        self.jointCount = header.joints
    }

    /// Reads a snapshot from a file written by `write(to:)`.
    public init(contentsOf url: URL) throws {
        guard let snapshot = PhysicsSnapshot(data: try Data(contentsOf: url)) else {
            throw Failure.unreadable
        }
        self = snapshot
    }

    /// Reads a snapshot bundled as a resource. Pass the bundle explicitly
    /// (`.module` from a sketch's own target).
    public init?(resource name: String, extension ext: String = "physics",
                 in bundle: Bundle) {
        guard let url = bundle.url(forResource: name, withExtension: ext),
              let snapshot = try? PhysicsSnapshot(contentsOf: url) else {
            return nil
        }
        self = snapshot
    }

    /// Writes the snapshot to a file.
    public func write(to url: URL) throws {
        try data.write(to: url)
    }

    /// What goes wrong reading a snapshot.
    public enum Failure: Error {
        /// The bytes are not a snapshot, or were written by a later version.
        case unreadable
    }

    /// Builds a snapshot from an already-encoded payload, compressing it when
    /// that comes out smaller. A world is mostly arrays of `Double`s whose
    /// high bytes repeat, which is exactly what a general compressor is good
    /// at: a settled heap of primitives shrinks about ninefold, and a world
    /// carrying scenery about twofold.
    init(payload: Data, bodies: Int, joints: Int) {
        let squeezed = SnapshotCompression.compress(payload)
        var writer = SnapshotWriter()
        writer.magic()
        writer.u32(UInt32(PhysicsSnapshot.version))
        writer.u32(UInt32(bodies))
        writer.u32(UInt32(joints))
        writer.u8(squeezed == nil ? 0 : 1)
        writer.u32(UInt32(payload.count))
        writer.u64(SnapshotChecksum.of(payload))
        self.data = writer.data + (squeezed ?? payload)
        self.bodyCount = bodies
        self.jointCount = joints
    }

    /// The bytes a reader walks: the payload, unpacked if it was packed, and
    /// only if it is all there. The checksum is what makes a truncated or
    /// damaged snapshot *refused* rather than half-read, which the reader
    /// running out of bytes cannot do on its own: a packed payload cut short
    /// still unpacks to a full-length buffer of rubbish, and rubbish parses.
    var payload: Data? {
        guard let header = SnapshotHeader(of: data) else { return nil }
        let stored = Data(data.dropFirst(SnapshotHeader.size))
        let unpacked = header.isCompressed
            ? SnapshotCompression.decompress(stored, to: header.payloadBytes)
            : stored
        guard let unpacked, unpacked.count == header.payloadBytes,
              SnapshotChecksum.of(unpacked) == header.checksum else { return nil }
        return unpacked
    }

    /// The names of the geometry this snapshot declines to hold, in the order
    /// they were first used, so a sketch can see what a resolver will be asked
    /// for before restoring anything. Empty for a snapshot that names nothing,
    /// which is the default and the self-contained case.
    ///
    /// ```swift
    /// for name in saved.assetNames { print("needs \(name)") }
    /// ```
    public var assetNames: [String] {
        guard let payload else { return [] }
        var reader = SnapshotReader(payload)
        guard let count = try? reader.count() else { return [] }
        var names: [String] = []
        for _ in 0 ..< count {
            guard let name = try? reader.string() else { return names }
            names.append(name)
        }
        return names
    }

    /// The format this build writes, and the only one it reads.
    static let version = 4

    /// The body index a joint anchored to `World3D.groundBody` carries, since
    /// the floor slab is not one of the saved bodies.
    static let groundIndex: UInt32 = 0xFFFF_FFFF
}

// MARK: - Capturing and restoring

extension World3D {

    /// Capture everything in the world right now: every rigid body with its
    /// shape, pose, and motion, every joint between them, and the world's own
    /// settings.
    ///
    /// The bodies come back in the order they are in now, so an index into
    /// `bodies` still names the same body after a restore, though the `Body3D`
    /// objects themselves are new ones.
    public func snapshot() -> PhysicsSnapshot {
        var writer = SnapshotWriter()

        // The names of everything this snapshot declines to hold, so a reader
        // can ask what it will be needing without unpacking the rest.
        var named: [String] = []
        for name in bodies.compactMap(\.assetName) where !named.contains(name) {
            named.append(name)
        }
        for name in softBodies.compactMap(\.assetName) where !named.contains(name) {
            named.append(name)
        }
        writer.u32(UInt32(named.count))
        for name in named { writer.string(name) }

        // World settings.
        writer.vector(gravity)
        writer.optionalDouble(ground)
        writer.f64(bounce)
        writer.f64(maxTimestep)
        writer.f64(unitsPerMeter)
        writer.water(water)
        writer.f64(waterPhase)

        // The collision-group table: the names in the order the solver indexes
        // them, then every pair that has been told to pass through.
        writer.u32(UInt32(groupNames.count))
        for name in groupNames { writer.string(name.name) }
        writer.u32(UInt32(groupIndex(groundGroup)))
        var separated: [(UInt32, UInt32)] = []
        for a in 0 ..< groupNames.count {
            for b in a ..< groupNames.count where !collides(groupNames[a], with: groupNames[b]) {
                separated.append((UInt32(a), UInt32(b)))
            }
        }
        writer.u32(UInt32(separated.count))
        for pair in separated { writer.u32(pair.0); writer.u32(pair.1) }

        // A vehicle's chassis is an ordinary body in `bodies`, but it comes
        // back as part of its vehicle rather than as a loose crate, so it is
        // written in the vehicle section. It still takes a body index, after
        // the loose ones, so a joint can name it (a trailer on a hitch).
        let driven = Set(vehicles.map { ObjectIdentifier($0.body) })
        var saved: [Body3D] = []
        var index: [CJoltBodyID: UInt32] = [:]
        for body in bodies where !driven.contains(ObjectIdentifier(body)) {
            index[body.id] = UInt32(saved.count)
            saved.append(body)
        }
        for (offset, vehicle) in vehicles.enumerated() {
            index[vehicle.body.id] = UInt32(saved.count + offset)
        }
        if let groundBody { index[groundBody.id] = PhysicsSnapshot.groundIndex }
        // A rope is nothing but its mesh too, but its mesh is a handful of
        // points, so it carries itself and needs no name.
        let savedSoft = softBodies.filter { $0.assetName != nil || $0 is Rope3D }
        if savedSoft.count < softBodies.count {
            noteOnce("a soft body is nothing but its mesh, so it is saved only "
                     + "when it has an assetName to write down in place of it; "
                     + "set one, and say what it means with "
                     + "restore(_:resolving:)")
        }

        writer.u32(UInt32(saved.count))
        for body in saved { writer.body(body, in: self) }

        // Structural joints first, then the links written against them, since
        // a link names two joints by where they land in this list.
        var structural: [Joint3D] = []
        var position: [ObjectIdentifier: UInt32] = [:]
        for joint in joints {
            guard !joint.isGrab, joint.link == nil, joint.kind != nil,
                  index[joint.a] != nil, index[joint.b] != nil else { continue }
            position[ObjectIdentifier(joint)] = UInt32(structural.count)
            structural.append(joint)
        }
        writer.u32(UInt32(structural.count))
        for joint in structural {
            writer.u32(index[joint.a]!)
            writer.u32(index[joint.b]!)
            writer.joint(joint)
        }

        var links: [(UInt32, UInt32, JointLink3D)] = []
        for joint in joints {
            guard let link = joint.link,
                  let a = joint.linkedA.flatMap({ position[ObjectIdentifier($0)] }),
                  let b = joint.linkedB.flatMap({ position[ObjectIdentifier($0)] })
            else { continue }
            links.append((a, b, link))
        }
        writer.u32(UInt32(links.count))
        for link in links {
            writer.u32(link.0)
            writer.u32(link.1)
            writer.link(link.2)
        }

        // The tiers above a loose body. Each is written by value: none of them
        // holds anything heavier than the shapes a body already writes, so
        // what kept them out was an encoding rather than a limit.
        writer.u32(UInt32(characters.count))
        for character in characters { writer.character(character, in: self) }

        writer.u32(UInt32(vehicles.count))
        for vehicle in vehicles { writer.vehicle(vehicle, in: self) }

        writer.u32(UInt32(ragdolls.count))
        for ragdoll in ragdolls { writer.ragdoll(ragdoll, in: self) }

        writer.u32(UInt32(savedSoft.count))
        for body in savedSoft { writer.softBody(body, in: self) }

        return PhysicsSnapshot(payload: writer.data,
                               bodies: saved.count + vehicles.count,
                               joints: structural.count + links.count)
    }

    /// Empty the world and build back what a snapshot holds: the same bodies
    /// with the same shapes, in the same poses, moving the same way, joined the
    /// same way, under the same settings.
    ///
    /// Restoring goes through the ordinary `addBody` and `connect` calls, so a
    /// restored world is one a sketch could have built by hand. Anything the
    /// world was holding beforehand is gone, characters, vehicles, ragdolls,
    /// and soft bodies included.
    public func restore(_ snapshot: PhysicsSnapshot,
                        resolving resolve: PhysicsAssetResolver? = nil) {
        guard let payload = snapshot.payload else {
            noteOnce("this snapshot could not be read; the world is unchanged")
            return
        }
        var reader = SnapshotReader(payload)
        do {
            try rebuild(from: &reader, resolving: resolve)
        } catch {
            noteOnce("this snapshot could not be read; the world is unchanged")
        }
    }

    /// Take a snapshot and write it to a file.
    public func save(to url: URL) throws {
        try snapshot().write(to: url)
    }

    /// Read a snapshot from a file and restore it. Returns false, leaving the
    /// world alone, when the file is missing or unreadable.
    @discardableResult
    public func load(contentsOf url: URL,
                     resolving resolve: PhysicsAssetResolver? = nil) -> Bool {
        guard let snapshot = try? PhysicsSnapshot(contentsOf: url) else { return false }
        restore(snapshot, resolving: resolve)
        return true
    }

    private func rebuild(from reader: inout SnapshotReader,
                         resolving resolve: PhysicsAssetResolver?) throws {
        // Read the whole thing before touching the world, so a truncated file
        // leaves the pile that is already there standing. The leading name
        // table is for a reader asking what it needs; each body carries its
        // own name, so nothing here reads it back.
        for _ in 0 ..< (try reader.count()) { _ = try reader.string() }

        let gravity = try reader.vector()
        let ground = try reader.optionalDouble()
        let bounce = try reader.f64()
        let maxTimestep = try reader.f64()
        let unitsPerMeter = try reader.f64()
        let water = try reader.water()
        let waterPhase = try reader.f64()

        var names: [CollisionGroup] = []
        for _ in 0 ..< (try reader.count()) {
            names.append(CollisionGroup(try reader.string()))
        }
        let groundGroupIndex = try reader.u32()
        var separated: [(UInt32, UInt32)] = []
        for _ in 0 ..< (try reader.count()) {
            separated.append((try reader.u32(), try reader.u32()))
        }

        var savedBodies: [SavedBody] = []
        for _ in 0 ..< (try reader.count()) { savedBodies.append(try reader.body()) }

        var savedJoints: [SavedJoint] = []
        for _ in 0 ..< (try reader.count()) { savedJoints.append(try reader.joint()) }

        var savedLinks: [(UInt32, UInt32, JointLink3D)] = []
        for _ in 0 ..< (try reader.count()) {
            savedLinks.append((try reader.u32(), try reader.u32(), try reader.link()))
        }

        var savedCharacters: [SavedCharacter] = []
        for _ in 0 ..< (try reader.count()) {
            savedCharacters.append(try reader.character())
        }

        var savedVehicles: [SavedVehicle] = []
        for _ in 0 ..< (try reader.count()) { savedVehicles.append(try reader.vehicle()) }

        var savedRagdolls: [SavedRagdoll] = []
        for _ in 0 ..< (try reader.count()) { savedRagdolls.append(try reader.ragdoll()) }

        var savedSoftBodies: [SavedSoftBody] = []
        for _ in 0 ..< (try reader.count()) {
            savedSoftBodies.append(try reader.softBody())
        }

        // Everything read: now the world can be emptied.
        removeAll()

        // The group table is rebuilt in the saved order, which is the solver's
        // own indexing, so a body's saved group index still names its group.
        // The solver's pair rules survive `removeAll()`, so every pair either
        // world knew about is set back to what the snapshot says.
        let previousGroups = groupNames.count
        groupNames = [.default]
        groupIndices = [.default: 0]
        for name in names.dropFirst() { _ = groupIndex(name) }
        let known = max(previousGroups, groupNames.count)
        for a in 0 ..< known {
            for b in a ..< known {
                cjolt_world_set_group_collision(handle, Int32(a), Int32(b), true)
            }
        }
        for pair in separated {
            cjolt_world_set_group_collision(handle, Int32(pair.0), Int32(pair.1), false)
        }

        // Take the old floor away before the scale moves, so it is built once,
        // from the snapshot's own level, group, bounce, and unit scale.
        self.ground = nil
        self.unitsPerMeter = unitsPerMeter
        self.bounce = bounce
        self.maxTimestep = maxTimestep
        self.gravity = gravity
        groundGroup = group(at: Int32(groundGroupIndex))
        self.ground = ground
        self.water = water
        self.waterPhase = waterPhase
        waterMoved = false

        // A body whose geometry was named and could not be found is left out
        // rather than restored wearing something else, and the joints that
        // named it are dropped with it. The saved indices still have to line
        // up, so the gaps are kept as nils.
        var restoredBodies: [Body3D?] = []
        for saved in savedBodies {
            guard let collider = saved.collider.resolved(by: resolve,
                                                         note: { noteOnce($0) })
            else {
                restoredBodies.append(nil)
                continue
            }
            let body = addBody(collider, at: saved.position,
                               kind: saved.kind, isSensor: saved.isSensor,
                               rotated: 0, axis: .unitY, density: saved.density,
                               friction: saved.friction,
                               restitution: saved.restitution, mass: nil,
                               centerOfMass: .zero, freedom: saved.freedom,
                               gravityScale: saved.gravityScale,
                               checksPath: saved.checksPath,
                               group: group(at: Int32(saved.group)),
                               orientation: saved.rotation,
                               velocity: saved.velocity,
                               angularVelocity: saved.angularVelocity,
                               asleep: !saved.isAwake)
            body.buoyancy = saved.buoyancy
            body.assetName = saved.assetName
            restoredBodies.append(body)
        }

        // Vehicles next, because a chassis is an ordinary body that lands in
        // `bodies` right after the loose ones, which is the index a joint may
        // have been saved naming (a trailer on a hitch).
        for saved in savedVehicles { restoredBodies.append(restoreVehicle(saved)) }

        let restedPoses = savedBodies.map {
            Pose3D(position: $0.position, rotation: $0.rotation)
        } + savedVehicles.map(\.pose)
        var madeJoints: [Joint3D] = []
        for saved in savedJoints {
            guard let a = restored(saved.a, in: restoredBodies),
                  let b = restored(saved.b, in: restoredBodies) else { continue }
            // A joint's zero is the pose its two bodies were in when it was
            // made, so they stand back there while it is made and are then put
            // back where the snapshot found them. Neither move wakes them.
            place(a, at: saved.poseA)
            place(b, at: saved.poseB)
            let joint = connect(a, b, saved.kind)
            joint.friction = saved.friction
            if restedPoses.indices.contains(Int(saved.a)) {
                place(a, at: restedPoses[Int(saved.a)])
            }
            if restedPoses.indices.contains(Int(saved.b)) {
                place(b, at: restedPoses[Int(saved.b)])
            }
            madeJoints.append(joint)
        }

        for link in savedLinks {
            let a = Int(link.0), b = Int(link.1)
            guard madeJoints.indices.contains(a), madeJoints.indices.contains(b) else {
                continue
            }
            connect(madeJoints[a], madeJoints[b], link.2)
        }

        for saved in savedCharacters {
            let character = addCharacter(radius: saved.radius, height: saved.height,
                                         at: saved.position,
                                         stepHeight: saved.stepHeight,
                                         stickToFloorDistance: saved.stickToFloorDistance,
                                         maxSlope: saved.maxSlope, mass: saved.mass,
                                         pushStrength: saved.pushStrength,
                                         group: group(at: Int32(saved.group)))
            character.velocity = saved.velocity
            character.facing = saved.facing
        }

        for saved in savedRagdolls { restoreRagdoll(saved) }
        for saved in savedSoftBodies { restoreSoftBody(saved, resolving: resolve) }
    }

    /// Build one saved surface back. The mesh comes from the resolver, since a
    /// soft body is nothing but its mesh; without one it is left out and said
    /// so, the way a named collider that resolves to nothing is.
    private func restoreSoftBody(_ saved: SavedSoftBody,
                                 resolving resolve: PhysicsAssetResolver?) {
        let turn = simd_quatd(ix: saved.rotation.imag.x, iy: saved.rotation.imag.y,
                              iz: saved.rotation.imag.z, r: saved.rotation.real)
            .normalized
        // A rope carried its own rest shape, so it needs nothing resolved: it
        // is rebuilt on the polyline it was built on, with each rod already
        // turned the way it was, and then stood in the shape it had reached.
        if let rope = saved.rope {
            guard let body = makeRope(points: rope.points, position: saved.position,
                                      rotation: turn, thickness: rope.thickness,
                                      sides: rope.sides, mass: saved.mass,
                                      stiffness: saved.stiffness, bend: saved.bend,
                                      damping: saved.damping,
                                      friction: saved.friction,
                                      restitution: saved.restitution,
                                      iterations: saved.iterations,
                                      pinned: nil, maxStretch: saved.maxStretch,
                                      group: group(at: Int32(saved.group)),
                                      rodRotations: rope.rodRotations)
            else { return }
            if !saved.assetName.isEmpty { body.assetName = saved.assetName }
            for index in saved.pinned { body.pin(index) }
            body.restoreState(positions: saved.positions, velocities: saved.velocities)
            return
        }
        guard let mesh = resolve?(saved.assetName)?.mesh else {
            noteOnce("this world names a soft body's mesh \"\(saved.assetName)\" "
                     + "that nothing was handed back for, so the surface is "
                     + "left out; pass a resolver to restore(_:resolving:)")
            return
        }
        if !saved.fingerprint.matches(AssetFingerprint(of: mesh)) {
            noteOnce("the mesh named \"\(saved.assetName)\" is not what it was "
                     + "when this world was saved, so the surface in it may "
                     + "not fit")
        }
        // Built where it was built, so its rest shape is in the frame the
        // saved particle positions were measured against, then stood back in
        // the shape it had reached.
        guard let body = makeSoftBody(mesh: mesh, position: saved.position,
                                      rotation: turn, mass: saved.mass,
                                      stiffness: saved.stiffness,
                                      bend: saved.bend, pressure: saved.pressure,
                                      damping: saved.damping,
                                      friction: saved.friction,
                                      restitution: saved.restitution,
                                      iterations: saved.iterations,
                                      vertexRadius: saved.vertexRadius,
                                      twoSided: saved.twoSided, pinned: nil,
                                      group: group(at: Int32(saved.group)),
                                      skeleton: [], carriedBy: nil, sway: nil,
                                      backStop: nil,
                                      maxStretch: saved.maxStretch,
                                      restoredSkin: saved.skin)
        else { return }
        body.assetName = saved.assetName
        for index in saved.pinned { body.pin(index) }
        body.restoreState(positions: saved.positions, velocities: saved.velocities)
    }

    /// Build one saved vehicle back: the chassis through the ordinary
    /// `addVehicle` call, then the state the solver does not take at create.
    @discardableResult
    private func restoreVehicle(_ saved: SavedVehicle) -> Body3D? {
        let wheels = saved.wheels.map { spec -> Wheel3D in
            let wheel = Wheel3D.wheel(at: spec.position, radius: spec.radius,
                                      width: spec.width, steers: spec.steers,
                                      driven: spec.driven)
            wheel.maxSteerAngle = spec.maxSteerAngle
            wheel.casterAngle = spec.casterAngle
            wheel.suspensionLength = spec.suspensionLength
            wheel.suspensionTravel = spec.suspensionTravel
            wheel.suspensionFrequency = spec.suspensionFrequency
            wheel.suspensionDamping = spec.suspensionDamping
            wheel.brakeTorque = spec.brakeTorque
            wheel.handBrakeTorque = spec.handBrakeTorque
            wheel.grip = spec.grip
            return wheel
        }
        // `addVehicle` takes an angle and an axis, so the saved orientation
        // goes on after: the chassis is a body like any other underneath.
        guard let vehicle = addVehicle(saved.collider, at: saved.pose.position,
                                       wheels: wheels, mass: saved.mass,
                                       engineTorque: saved.engineTorque,
                                       topSpeed: saved.topSpeed,
                                       centerOfMass: saved.centerOfMass,
                                       friction: saved.friction,
                                       balances: saved.balances,
                                       maxLeanAngle: saved.maxLeanAngle,
                                       tracked: saved.tracked,
                                       group: group(at: Int32(saved.group)))
        else { return nil }
        place(vehicle.body, at: saved.pose)
        vehicle.body.velocity = saved.velocity
        vehicle.body.angularVelocity = saved.angularVelocity
        vehicle.antiRollStiffness = saved.antiRollStiffness
        vehicle.maxTilt = saved.maxTilt
        vehicle.wheelContact = saved.wheelContact
        vehicle.throttle = saved.throttle
        vehicle.steering = saved.steering
        vehicle.brake = saved.brake
        vehicle.handBrake = saved.handBrake
        vehicle.restoreDrivetrain(rpm: saved.rpm, gear: saved.gear,
                                  clutch: saved.clutch,
                                  wheelSpins: saved.wheels.map {
                                      (rate: $0.spinRate, angle: $0.spin)
                                  })
        if !saved.isAwake { vehicle.body.sleep() }
        return vehicle.body
    }

    /// Build one saved figure back from its fitting. A ragdoll is made in the
    /// pose it was fitted in, exactly as a joint is made in the pose its bodies
    /// held, so the limbs are moved to where the snapshot found them after.
    private func restoreRagdoll(_ saved: SavedRagdoll) {
        guard let ragdoll = addRagdoll(plan: saved.plan, limits: saved.limits,
                                       friction: saved.friction,
                                       group: group(at: Int32(saved.group)))
        else { return }
        ragdoll.kind = saved.kind
        for (limb, pose) in zip(ragdoll.limbs, saved.poses) {
            place(limb.body, at: pose.pose)
            limb.body.velocity = pose.velocity
            limb.body.angularVelocity = pose.angularVelocity
            if !pose.isAwake { limb.body.sleep() }
        }
    }

    /// The restored body a saved index names, the floor slab included, or nil
    /// when that body was left out because its geometry could not be found.
    private func restored(_ index: UInt32, in built: [Body3D?]) -> Body3D? {
        if index == PhysicsSnapshot.groundIndex { return groundBody }
        return built.indices.contains(Int(index)) ? built[Int(index)] : nil
    }

    /// Stand a body at a pose without waking it: a sleeping pile is moved
    /// around while its joints are made and has to still be asleep after. The
    /// floor slab never moves; it is wherever `ground` puts it.
    private func place(_ body: Body3D, at pose: Pose3D) {
        guard body !== groundBody else { return }
        // Both at once, never one then the other: the solver holds a body by
        // its center of mass, so a position written against the orientation
        // the body still has lands a shape that sits off its own origin (a
        // ragdoll limb) a fraction out of place.
        withFloats3(meters(from: pose.position)) { position in
            withFloats4((Float(pose.rotation.x), Float(pose.rotation.y),
                         Float(pose.rotation.z), Float(pose.rotation.w))) { rotation in
                cjolt_body_set_pose(handle, body.id, position, rotation, false)
            }
        }
    }
}

/// A body's place in the world: where it stands and which way it faces. Used
/// both by the snapshot and by every joint, which remembers the poses its two
/// bodies held when it was made.
struct Pose3D: Sendable, Equatable {
    var position: Vector3
    /// The orientation quaternion, `(x, y, z, w)`.
    var rotation: SIMD4<Double>

    static let identity = Pose3D(position: .zero, rotation: SIMD4(0, 0, 0, 1))

    init(position: Vector3, rotation: SIMD4<Double>) {
        self.position = position
        self.rotation = rotation
    }

    init(of body: Body3D) {
        let q = body.quaternion
        self.init(position: body.position,
                  rotation: SIMD4(Double(q.0), Double(q.1), Double(q.2), Double(q.3)))
    }
}

/// A body's collider as a snapshot holds it: either the whole shape, or the
/// name of the geometry it was cut from, waiting for a resolver to say what
/// that name means.
private enum SavedCollider {
    case ready(Collider3D)
    case namedMesh(String, AssetFingerprint)
    case namedHeightfield(String, AssetFingerprint,
                          width: Double, depth: Double, height: Double)

    /// The name this collider is waiting on, if any.
    var name: String? {
        switch self {
        case .ready: return nil
        case .namedMesh(let name, _): return name
        case .namedHeightfield(let name, _, _, _, _): return name
        }
    }

    /// The shape, once a resolver has said what the name means. `nil` when the
    /// name resolved to nothing, or to the wrong kind of geometry.
    func resolved(by resolve: PhysicsAssetResolver?, note: (String) -> Void)
        -> Collider3D? {
        switch self {
        case .ready(let collider):
            return collider
        case .namedMesh(let name, let print):
            guard let mesh = resolve?(name)?.mesh else {
                note("this world names a mesh \"\(name)\" that nothing was "
                     + "handed back for, so the body wearing it is left out; "
                     + "pass a resolver to restore(_:resolving:)")
                return nil
            }
            warnIfChanged(name, print, AssetFingerprint(of: mesh), note)
            return .mesh(mesh)
        case .namedHeightfield(let name, let print, let width, let depth, let height):
            guard let field = resolve?(name)?.heightfield else {
                note("this world names a heightfield \"\(name)\" that nothing "
                     + "was handed back for, so the body wearing it is left "
                     + "out; pass a resolver to restore(_:resolving:)")
                return nil
            }
            warnIfChanged(name, print, AssetFingerprint(of: .heightfield(field)), note)
            return .heightfield(field, width: width, depth: depth, height: height)
        }
    }

    /// A name that now resolves to different geometry is restored anyway (the
    /// poses are still the best answer there is), but it is said out loud,
    /// because a pose saved against one shape rarely fits another.
    private func warnIfChanged(_ name: String, _ saved: AssetFingerprint,
                               _ found: AssetFingerprint, _ note: (String) -> Void) {
        guard !saved.matches(found) else { return }
        note("the geometry named \"\(name)\" is not what it was when this "
             + "world was saved, so the poses in it may not fit")
    }
}

/// One rigid body as a snapshot holds it.
private struct SavedBody {
    var collider: SavedCollider
    var assetName: String?
    var position: Vector3
    var rotation: SIMD4<Double>
    var velocity: Vector3
    var angularVelocity: Vector3
    var kind: Body3D.Kind
    var isSensor: Bool
    var density: Double
    var friction: Double
    var restitution: Double
    var buoyancy: Double
    var gravityScale: Double
    var freedom: Freedom3D
    var checksPath: Bool
    var group: UInt32
    var isAwake: Bool
}

/// One walking figure as a snapshot holds it: a capsule and a handful of
/// numbers, which is all a character ever was.
private struct SavedCharacter {
    var radius: Double
    var height: Double
    var position: Vector3
    var stepHeight: Double
    var stickToFloorDistance: Double
    var maxSlope: Double
    var mass: Double
    var pushStrength: Double
    var group: UInt32
    var velocity: Vector3
    var facing: Double
}

/// One wheel as a snapshot holds it: where it is bolted on and everything it
/// was tuned to.
private struct SavedWheel {
    /// How fast it was turning and how far it had already rolled.
    var spinRate: Double
    var spin: Double
    var position: Vector3
    var radius: Double
    var width: Double
    var steers: Bool
    var driven: Bool
    var maxSteerAngle: Double
    var casterAngle: Double
    var suspensionLength: Double
    var suspensionTravel: Double
    var suspensionFrequency: Double
    var suspensionDamping: Double
    var brakeTorque: Double
    var handBrakeTorque: Double
    var grip: Double
}

/// One driveable machine as a snapshot holds it: its chassis, its wheels, its
/// gearing, and what the driver was asking for.
private struct SavedVehicle {
    var collider: Collider3D
    var pose: Pose3D
    var velocity: Vector3
    var angularVelocity: Vector3
    var mass: Double
    var friction: Double
    var centerOfMass: Vector3
    var group: UInt32
    var isAwake: Bool
    var engineTorque: Double
    var topSpeed: Double
    var antiRollStiffness: Double
    var maxTilt: Double?
    var wheelContact: Vehicle3D.WheelContact
    var balances: Bool
    var maxLeanAngle: Double
    var tracked: Bool
    var throttle: Double
    var steering: Double
    var brake: Double
    var handBrake: Double
    var rpm: Double
    var gear: Int
    var clutch: Double
    var wheels: [SavedWheel]
}

/// Where one limb of a figure has got to.
private struct SavedLimbPose {
    var pose: Pose3D
    var velocity: Vector3
    var angularVelocity: Vector3
    var isAwake: Bool
}

/// One figure as a snapshot holds it: the fitting rather than the skin. The
/// skinned `Scene` it was fitted from is the sketch's own asset, still loaded,
/// and still what `scene.apply(ragdoll)` writes the simulated pose back onto.
private struct SavedRagdoll {
    var plan: RagdollPlan
    var limits: [RagdollLimit]
    var friction: Double
    var group: UInt32
    var kind: Body3D.Kind
    var poses: [SavedLimbPose]
}

/// One soft body as a snapshot holds it: the name of the mesh it was built
/// from, the numbers it was built with, and where every particle has got to.
private struct SavedSoftBody {
    var assetName: String
    var fingerprint: AssetFingerprint
    var position: Vector3
    var rotation: simd_quatd
    var mass: Double
    var stiffness: Double
    var bend: Double
    var pressure: Double
    var damping: Double
    var friction: Double
    var restitution: Double
    var iterations: Int
    var vertexRadius: Double
    var twoSided: Bool
    var group: UInt32
    var positions: [Vector3]
    var velocities: [Vector3]
    var pinned: [Int]
    var maxStretch: Double?
    /// What a skeleton was carrying, written down because the closures that
    /// decided it are a sketch's and cannot be carried, the same reason the
    /// pinned list is here.
    var skin: SoftBody3D.Skin
    /// What makes it a rope rather than a surface: its own rest polyline, how
    /// thick it draws, and the way each rod was turned. All small, which is why
    /// a rope needs no `assetName` to be saved when a surface does.
    var rope: SavedRope?
}

/// A rope's own build data, small enough to carry rather than name.
private struct SavedRope {
    var points: [Vector3]
    var thickness: Double
    var sides: Int
    var rodRotations: [simd_quatd]
}

/// One joint as a snapshot holds it.
private struct SavedJoint {
    var a: UInt32
    var b: UInt32
    var kind: JointKind3D
    var friction: Double
    var poseA: Pose3D
    var poseB: Pose3D
}

// MARK: - The header

/// What sits in front of a snapshot's payload: enough to tell one from any
/// other bytes, to refuse a format this build does not read, to say what is
/// inside without unpacking it, and to unpack it.
private struct SnapshotHeader {
    var bodies: Int
    var joints: Int
    var isCompressed: Bool
    var payloadBytes: Int
    var checksum: UInt64

    /// magic(8) + version(4) + bodies(4) + joints(4) + flags(1) + length(4)
    /// + checksum(8).
    static let size = 33

    init?(of data: Data) {
        var reader = SnapshotReader(data)
        guard let magic = try? reader.bytes(8),
              magic.elementsEqual(Array("OLLNPHYS".utf8)),
              let version = try? reader.u32(),
              Int(version) == PhysicsSnapshot.version,
              let bodies = try? reader.u32(), let joints = try? reader.u32(),
              let flags = try? reader.u8(), let length = try? reader.u32(),
              let checksum = try? reader.u64()
        else { return nil }
        self.bodies = Int(bodies)
        self.joints = Int(joints)
        self.isCompressed = flags & 1 != 0
        self.payloadBytes = Int(length)
        self.checksum = checksum
    }
}

/// A cheap hash over a payload, so a snapshot can tell whether the bytes it
/// was handed are the bytes it wrote. FNV-1a: not a cryptographic digest, and
/// it does not need to be. What it has to catch is a file cut short, a byte
/// flipped, or bytes from something else entirely.
private enum SnapshotChecksum {
    static func of(_ data: Data) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 0x1000_0000_01b3
        }
        return hash
    }
}

/// Packing for a snapshot's payload. LZFSE, the system codec, so nothing is
/// vendored and the result is the same bytes on every machine.
private enum SnapshotCompression {

    /// The packed payload, or nil when packing it would not make it smaller
    /// (the codec says so itself by refusing a destination this size).
    static func compress(_ source: Data) -> Data? {
        guard !source.isEmpty else { return nil }
        var packed = Data(count: source.count)
        let written = packed.withUnsafeMutableBytes { destination -> Int in
            source.withUnsafeBytes { input -> Int in
                guard let out = destination.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let raw = input.baseAddress?.assumingMemoryBound(to: UInt8.self)
                else { return 0 }
                return compression_encode_buffer(out, source.count, raw, source.count,
                                                 nil, COMPRESSION_LZFSE)
            }
        }
        guard written > 0 else { return nil }
        return packed.prefix(written)
    }

    /// The payload a `compress` produced, or nil when the bytes are not what
    /// the header said they were.
    static func decompress(_ packed: Data, to size: Int) -> Data? {
        guard size > 0, packed.count > 0 else { return nil }
        var unpacked = Data(count: size)
        let written = unpacked.withUnsafeMutableBytes { destination -> Int in
            packed.withUnsafeBytes { input -> Int in
                guard let out = destination.baseAddress?.assumingMemoryBound(to: UInt8.self),
                      let raw = input.baseAddress?.assumingMemoryBound(to: UInt8.self)
                else { return 0 }
                return compression_decode_buffer(out, size, raw, packed.count,
                                                 nil, COMPRESSION_LZFSE)
            }
        }
        return written == size ? unpacked : nil
    }
}

// MARK: - Writing

/// Appends little-endian values to a growing buffer. Every number is written
/// as a `Double`, so what a body reads back out of the solver is exactly what
/// goes in, whatever the world's unit scale is.
private struct SnapshotWriter {
    var data = Data()

    mutating func magic() { data.append(contentsOf: Array("OLLNPHYS".utf8)) }

    mutating func bool(_ value: Bool) { data.append(value ? 1 : 0) }

    mutating func u8(_ value: UInt8) { data.append(value) }

    mutating func u32(_ value: UInt32) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    mutating func u64(_ value: UInt64) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    mutating func f64(_ value: Double) {
        withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
    }

    /// Single precision, for the numbers the solver itself keeps that way: a
    /// skin's bind matrices and leash lengths never had more.
    mutating func f32(_ value: Float) {
        withUnsafeBytes(of: value.bitPattern.littleEndian) { data.append(contentsOf: $0) }
    }

    mutating func vector(_ value: Vector3) {
        f64(value.x); f64(value.y); f64(value.z)
    }

    mutating func vector2(_ value: Vector2) { f64(value.x); f64(value.y) }

    mutating func quaternion(_ value: SIMD4<Double>) {
        f64(value.x); f64(value.y); f64(value.z); f64(value.w)
    }

    mutating func pose(_ value: Pose3D) {
        vector(value.position); quaternion(value.rotation)
    }

    mutating func string(_ value: String) {
        let bytes = Array(value.utf8)
        u32(UInt32(bytes.count))
        data.append(contentsOf: bytes)
    }

    mutating func doubles(_ values: [Double]) {
        u32(UInt32(values.count))
        for value in values { f64(value) }
    }

    mutating func vectors(_ values: [Vector3]) {
        u32(UInt32(values.count))
        for value in values { vector(value) }
    }

    mutating func optionalDouble(_ value: Double?) {
        bool(value != nil)
        f64(value ?? 0)
    }

    mutating func range(_ value: ClosedRange<Double>?) {
        bool(value != nil)
        f64(value?.lowerBound ?? 0)
        f64(value?.upperBound ?? 0)
    }

    mutating func water(_ value: Water?) {
        bool(value != nil)
        guard let value else { return }
        f64(value.level)
        f64(value.density)
        f64(value.linearDrag)
        f64(value.angularDrag)
        vector(value.flow)
        bool(value.waves != nil)
        f64(value.waves?.amplitude ?? 0)
        f64(value.waves?.wavelength ?? 1)
        f64(value.waves?.speed ?? 0)
        f64(value.waves?.heading ?? 0)
    }

    /// A collider, with the bulk of it replaced by a name when the body it
    /// belongs to has one. Only the two heavy cases have anything to name, and
    /// only at the top level: a mesh nested inside a compound is written whole,
    /// since the name belongs to the body rather than to one of its parts.
    mutating func collider(_ value: Collider3D, named name: String?) {
        if let name {
            switch value {
            case .mesh(let mesh):
                u8(11)
                string(name)
                fingerprint(AssetFingerprint(of: mesh))
                return
            case .heightfield(let field, let width, let depth, let height):
                u8(12)
                string(name)
                fingerprint(AssetFingerprint(of: .heightfield(field)))
                f64(width); f64(depth); f64(height)
                return
            default:
                break
            }
        }
        collider(value)
    }

    mutating func fingerprint(_ value: AssetFingerprint) {
        u32(UInt32(max(0, value.pieces)))
        u32(UInt32(max(0, value.parts)))
        u64(value.hash)
    }

    mutating func collider(_ value: Collider3D) {
        switch value {
        case .sphere(let radius):
            u8(0); f64(radius)
        case .box(let width, let height, let depth):
            u8(1); f64(width); f64(height); f64(depth)
        case .capsule(let height, let radius):
            u8(2); f64(height); f64(radius)
        case .cylinder(let height, let radius):
            u8(3); f64(height); f64(radius)
        case .taperedCapsule(let height, let top, let bottom):
            u8(4); f64(height); f64(top); f64(bottom)
        case .taperedCylinder(let height, let top, let bottom):
            u8(5); f64(height); f64(top); f64(bottom)
        case .cone(let height, let radius):
            u8(6); f64(height); f64(radius)
        case .hull(let points):
            u8(7); vectors(points)
        case .mesh(let mesh):
            u8(8)
            vectors(mesh.positions)
            vectors(mesh.normals)
            u32(UInt32(mesh.uvs.count))
            for uv in mesh.uvs { vector2(uv) }
            u32(UInt32(mesh.indices.count))
            for index in mesh.indices { u32(index) }
        case .heightfield(let field, let width, let depth, let height):
            u8(9)
            u32(UInt32(field.columns))
            u32(UInt32(field.rows))
            doubles(field.values)
            f64(width); f64(depth); f64(height)
        case .compound(let parts):
            u8(10)
            u32(UInt32(parts.count))
            for part in parts {
                collider(part.collider)
                vector(part.position)
                f64(part.angle)
                vector(part.axis)
                f64(part.density)
            }
        }
    }

    mutating func body(_ body: Body3D, in world: World3D) {
        string(body.assetName ?? "")
        collider(body.collider, named: body.assetName)
        pose(Pose3D(of: body))
        vector(body.velocity)
        vector(body.angularVelocity)
        u8(body.kind == .dynamic ? 0 : (body.kind == .static ? 1 : 2))
        bool(body.isSensor)
        f64(body.density)
        f64(body.friction)
        f64(body.restitution)
        f64(body.buoyancy)
        f64(body.gravityScale)
        u32(body.freedom.rawValue)
        bool(body.checksPath)
        u32(UInt32(world.groupIndex(body.group)))
        bool(body.isAwake)
    }

    mutating func joint(_ joint: Joint3D) {
        switch joint.kind {
        case .revolute(let at, let axis, let limits)?:
            u8(0); vector(at); vector(axis); range(limits)
        case .ball(let at)?:
            u8(1); vector(at)
        case .swingTwist(let at, let axis, let swing, let twist)?:
            u8(2); vector(at); vector(axis); f64(swing)
            f64(twist.lowerBound); f64(twist.upperBound)
        case .distance(let from, let to, let length, let stiffness)?:
            u8(3); vector(from); vector(to); optionalDouble(length); f64(stiffness)
        case .weld?:
            u8(4)
        case .prismatic(let at, let axis, let limits)?:
            u8(5); vector(at); vector(axis); range(limits)
        case .path(let points, let looping, let alignment)?:
            u8(6); vectors(points); bool(looping)
            switch alignment {
            case .free: u8(0)
            case .rolls: u8(1)
            case .followsPath: u8(2)
            case .fixed: u8(3)
            }
        case .pulley(let from, let over, let and, let to, let ratio, let taut)?:
            u8(7); vector(from); vector(over); vector(and); vector(to)
            f64(ratio); bool(taut)
        case .allowing(let freedom, let at, let travel, let rotation)?:
            u8(8); u32(freedom.rawValue); vector(at); range(travel); range(rotation)
        case nil:
            u8(4) // unreachable: kind-less joints are filtered out before here
        }
        f64(joint.friction)
        pose(joint.connectPoseA)
        pose(joint.connectPoseB)
    }

    mutating func link(_ link: JointLink3D) {
        switch link {
        case .gear(let ratio): u8(0); f64(ratio)
        case .rackAndPinion(let travel): u8(1); f64(travel)
        }
    }

    mutating func character(_ character: Character3D, in world: World3D) {
        f64(character.radius)
        f64(character.height)
        vector(character.position)
        f64(character.stepHeight)
        f64(character.stickToFloorDistance)
        f64(character.maxSlope)
        f64(character.mass)
        f64(character.pushStrength)
        u32(UInt32(world.groupIndex(character.group)))
        vector(character.velocity)
        f64(character.facing)
    }

    mutating func vehicle(_ vehicle: Vehicle3D, in world: World3D) {
        // The chassis, written the way any body is, so a restore builds it
        // through `addVehicle` and it lands in `world.bodies` as it was.
        collider(vehicle.body.collider)
        pose(Pose3D(of: vehicle.body))
        vector(vehicle.body.velocity)
        vector(vehicle.body.angularVelocity)
        f64(vehicle.chassisMass)
        f64(vehicle.body.friction)
        vector(vehicle.centerOfMass)
        u32(UInt32(world.groupIndex(vehicle.body.group)))
        bool(vehicle.body.isAwake)

        // The machine.
        f64(vehicle.engineTorque)
        f64(vehicle.topSpeed)
        f64(vehicle.antiRollStiffness)
        optionalDouble(vehicle.maxTilt)
        switch vehicle.wheelContact {
        case .ray: u8(0)
        case .sphere: u8(1)
        case .cylinder: u8(2)
        }
        bool(vehicle.balances)
        f64(vehicle.maxLeanAngle)
        bool(vehicle.isTracked)

        // What the driver is asking for right now.
        f64(vehicle.throttle)
        f64(vehicle.steering)
        f64(vehicle.brake)
        f64(vehicle.handBrake)

        // What the drivetrain is doing. Without it a restored machine has to
        // spin its wheels and its engine up from rest, which a moving one
        // notices: measured, a car at speed fell 6.4 units behind over two
        // seconds, and lands within 0.06 with it.
        f64(vehicle.rpm)
        f64(Double(vehicle.gear))
        f64(vehicle.clutch)

        u32(UInt32(vehicle.wheels.count))
        for wheel in vehicle.wheels { self.wheel(wheel) }
    }

    mutating func wheel(_ wheel: Wheel3D) {
        f64(wheel.spinRate)
        f64(wheel.spin)
        vector(wheel.position)
        f64(wheel.radius)
        f64(wheel.width)
        bool(wheel.steers)
        bool(wheel.driven)
        f64(wheel.maxSteerAngle)
        f64(wheel.casterAngle)
        f64(wheel.suspensionLength)
        f64(wheel.suspensionTravel)
        f64(wheel.suspensionFrequency)
        f64(wheel.suspensionDamping)
        f64(wheel.brakeTorque)
        f64(wheel.handBrakeTorque)
        f64(wheel.grip)
    }

    mutating func softBody(_ body: SoftBody3D, in world: World3D) {
        // The name stands in for the mesh; everything else here is either a
        // number the body was built with or the state it has reached.
        string(body.assetName ?? "")
        fingerprint(AssetFingerprint(of: body.sourceMesh))
        vector(body.buildPosition)
        let q = body.buildRotation
        f64(q.imag.x); f64(q.imag.y); f64(q.imag.z); f64(q.real)
        f64(body.buildMass)
        f64(body.buildStiffness)
        f64(body.buildBend)
        f64(body.pressure)
        f64(body.buildDamping)
        f64(body.buildFriction)
        f64(body.buildRestitution)
        u32(UInt32(max(0, body.iterations)))
        f64(body.vertexRadius)
        bool(body.buildTwoSided)
        u32(UInt32(world.groupIndex(body.group)))

        let positions = body.particlePositions
        let velocities = body.particleVelocities
        u32(UInt32(positions.count))
        for point in positions { vector(point) }
        for index in positions.indices {
            vector(index < velocities.count ? velocities[index] : .zero)
        }
        // Which particles are held, which is a decision the sketch made with a
        // closure the snapshot cannot carry.
        var pinned: [UInt32] = []
        for index in 0 ..< body.particleCount where body.isPinned(index) {
            pinned.append(UInt32(index))
        }
        u32(UInt32(pinned.count))
        for index in pinned { u32(index) }

        // How far it may reach from what holds it, and what a skeleton was
        // carrying. A surface no skeleton carries writes two zero counts.
        f64(body.buildMaxStretch ?? 0)
        let skin = body.skinning
        u32(UInt32(skin.binds.count))
        for bind in skin.binds {
            for column in 0 ..< 4 {
                f32(bind[column].x); f32(bind[column].y)
                f32(bind[column].z); f32(bind[column].w)
            }
        }
        u32(UInt32(skin.vertices.count))
        for carried in skin.vertices {
            u32(UInt32(max(0, carried.vertex)))
            u32(carried.joints.0)
            f32(carried.weights.0)
            f32(carried.maxDistance)
            f32(carried.backStopDistance)
            f32(carried.backStopRadius)
        }

        // A rope's own rest shape, which is small enough to write down rather
        // than name, plus the way each rod is turned: without those the solver
        // would open every rod in its rest frame and haul the rope round to the
        // shape it is actually in, which reads as a spring on the first frame.
        let rope = body as? Rope3D
        u32(UInt32(rope?.points.count ?? 0))
        if let rope {
            for point in rope.points { vector(point) }
            f64(rope.thickness)
            u32(UInt32(max(3, rope.sides)))
            let frames = rope.rodOrientations()
            u32(UInt32(frames.count))
            for q in frames {
                f32(Float(q.imag.x)); f32(Float(q.imag.y))
                f32(Float(q.imag.z)); f32(Float(q.real))
            }
        }
    }

    mutating func ragdoll(_ ragdoll: Ragdoll3D, in world: World3D) {
        // The fitting, which is what the skinned scene was worked down to and
        // the only part of a figure the solver actually needs.
        u32(UInt32(ragdoll.plan.skinJointCount))
        u32(UInt32(ragdoll.plan.limbs.count))
        for limb in ragdoll.plan.limbs {
            u32(UInt32(max(0, limb.skinIndex)))
            string(limb.name)
            u32(UInt32(max(0, limb.sourceIndex)))
            // The root's parent is -1, which a count cannot hold.
            u32(limb.parent < 0 ? PhysicsSnapshot.groundIndex : UInt32(limb.parent))
            collider(limb.collider)
            vector(limb.shapeCenter)
            f64(limb.shapeAngle)
            vector(limb.shapeAxis)
            vector(limb.jointOrigin)
            f64(Double(limb.jointRotation.imag.x))
            f64(Double(limb.jointRotation.imag.y))
            f64(Double(limb.jointRotation.imag.z))
            f64(Double(limb.jointRotation.real))
            vector(limb.worldAxis)
            f64(limb.mass)
        }
        for limit in ragdoll.jointLimits {
            f64(limit.swing)
            f64(limit.twist.lowerBound)
            f64(limit.twist.upperBound)
        }
        f64(ragdoll.limbFriction)
        u32(UInt32(world.groupIndex(ragdoll.limbGroup)))
        u8(ragdoll.kind == .dynamic ? 0 : (ragdoll.kind == .static ? 1 : 2))

        // Where the figure has actually got to, which is not where it was fitted.
        for limb in ragdoll.limbs {
            pose(Pose3D(of: limb.body))
            vector(limb.body.velocity)
            vector(limb.body.angularVelocity)
            bool(limb.body.isAwake)
        }
    }
}

// MARK: - Reading

/// Walks a snapshot's bytes. Every read is bounds-checked and throws rather
/// than trapping, so a truncated or foreign file is refused instead of
/// crashing a sketch.
private struct SnapshotReader {
    private let data: Data
    fileprivate var offset: Int

    init(_ data: Data) {
        self.data = data
        self.offset = 0
    }

    enum Failure: Error { case truncated, unknownTag }

    mutating func bytes(_ count: Int) throws -> [UInt8] {
        guard count >= 0, offset + count <= data.count else { throw Failure.truncated }
        let start = data.startIndex + offset
        defer { offset += count }
        return Array(data[start ..< start + count])
    }

    mutating func u8() throws -> UInt8 { try bytes(1)[0] }

    mutating func bool() throws -> Bool { try u8() != 0 }

    mutating func u32() throws -> UInt32 {
        let raw = try bytes(4)
        return UInt32(raw[0]) | UInt32(raw[1]) << 8 | UInt32(raw[2]) << 16
            | UInt32(raw[3]) << 24
    }

    /// A count that has to fit in what is left, so a corrupt length cannot ask
    /// for a billion-element array before the read fails.
    mutating func count() throws -> Int {
        let value = Int(try u32())
        guard value <= data.count - offset else { throw Failure.truncated }
        return value
    }

    mutating func u64() throws -> UInt64 {
        let raw = try bytes(8)
        var pattern: UInt64 = 0
        for (shift, byte) in raw.enumerated() { pattern |= UInt64(byte) << (8 * shift) }
        return pattern
    }

    mutating func f64() throws -> Double {
        Double(bitPattern: try u64())
    }

    mutating func f32() throws -> Float {
        let raw = try bytes(4)
        var pattern: UInt32 = 0
        for (shift, byte) in raw.enumerated() { pattern |= UInt32(byte) << (8 * shift) }
        return Float(bitPattern: pattern)
    }

    mutating func vector() throws -> Vector3 {
        Vector3(try f64(), try f64(), try f64())
    }

    mutating func vector2() throws -> Vector2 {
        Vector2(try f64(), try f64())
    }

    mutating func quaternion() throws -> SIMD4<Double> {
        SIMD4(try f64(), try f64(), try f64(), try f64())
    }

    mutating func pose() throws -> Pose3D {
        Pose3D(position: try vector(), rotation: try quaternion())
    }

    mutating func string() throws -> String {
        let length = try count()
        return String(decoding: try bytes(length), as: UTF8.self)
    }

    mutating func doubles() throws -> [Double] {
        let n = try count()
        var values: [Double] = []
        values.reserveCapacity(n)
        for _ in 0 ..< n { values.append(try f64()) }
        return values
    }

    mutating func vectors() throws -> [Vector3] {
        let n = try count()
        var values: [Vector3] = []
        values.reserveCapacity(n)
        for _ in 0 ..< n { values.append(try vector()) }
        return values
    }

    mutating func optionalDouble() throws -> Double? {
        let has = try bool()
        let value = try f64()
        return has ? value : nil
    }

    mutating func range() throws -> ClosedRange<Double>? {
        let has = try bool()
        let low = try f64()
        let high = try f64()
        return has ? low...max(low, high) : nil
    }

    mutating func water() throws -> Water? {
        guard try bool() else { return nil }
        let level = try f64()
        let density = try f64()
        let linearDrag = try f64()
        let angularDrag = try f64()
        let flow = try vector()
        let hasWaves = try bool()
        let amplitude = try f64()
        let wavelength = try f64()
        let speed = try f64()
        let heading = try f64()
        return Water(level: level, density: density, linearDrag: linearDrag,
                     angularDrag: angularDrag, flow: flow,
                     waves: hasWaves ? Water.Waves(amplitude: amplitude,
                                                   wavelength: wavelength,
                                                   speed: speed, heading: heading)
                                     : nil)
    }

    /// A body's own collider, which may be a name standing in for geometry the
    /// snapshot declined to hold. Nested colliders (a compound's parts) go
    /// through `collider()` instead, since a name belongs to a body.
    mutating func topCollider() throws -> SavedCollider {
        let mark = offset
        switch try u8() {
        case 11:
            return .namedMesh(try string(), try fingerprint())
        case 12:
            return .namedHeightfield(try string(), try fingerprint(),
                                     width: try f64(), depth: try f64(),
                                     height: try f64())
        default:
            offset = mark
            return .ready(try collider())
        }
    }

    mutating func fingerprint() throws -> AssetFingerprint {
        // Plain numbers, not lengths in this stream: a fingerprint counts the
        // pieces of geometry that is *not* here, which is exactly why `count()`
        // (which bounds a length against the bytes left) is the wrong reader.
        AssetFingerprint(pieces: Int(try u32()), parts: Int(try u32()),
                         hash: try u64())
    }

    mutating func collider() throws -> Collider3D {
        switch try u8() {
        case 0: return .sphere(radius: try f64())
        case 1: return .box(width: try f64(), height: try f64(), depth: try f64())
        case 2: return .capsule(height: try f64(), radius: try f64())
        case 3: return .cylinder(height: try f64(), radius: try f64())
        case 4: return .taperedCapsule(height: try f64(), topRadius: try f64(),
                                       bottomRadius: try f64())
        case 5: return .taperedCylinder(height: try f64(), topRadius: try f64(),
                                        bottomRadius: try f64())
        case 6: return .cone(height: try f64(), radius: try f64())
        case 7: return .hull(try vectors())
        case 8:
            let positions = try vectors()
            let normals = try vectors()
            var uvs: [Vector2] = []
            for _ in 0 ..< (try count()) { uvs.append(try vector2()) }
            var indices: [UInt32] = []
            for _ in 0 ..< (try count()) { indices.append(try u32()) }
            var mesh = Mesh(positions: positions, normals: normals, indices: indices)
            mesh.uvs = uvs
            return .mesh(mesh)
        case 9:
            let columns = Int(try u32())
            let rows = Int(try u32())
            let values = try doubles()
            guard columns > 0, rows > 0, values.count == columns * rows else {
                throw Failure.truncated
            }
            return .heightfield(Heightfield(columns: columns, rows: rows, values: values),
                                width: try f64(), depth: try f64(), height: try f64())
        case 10:
            var parts: [Collider3D.Part] = []
            for _ in 0 ..< (try count()) {
                parts.append(.part(try collider(), at: try vector(),
                                   rotated: try f64(), axis: try vector(),
                                   density: try f64()))
            }
            return .compound(parts)
        default:
            throw Failure.unknownTag
        }
    }

    mutating func body() throws -> SavedBody {
        let name = try string()
        let shape = try topCollider()
        let pose = try pose()
        let velocity = try vector()
        let spin = try vector()
        let kind: Body3D.Kind
        switch try u8() {
        case 0: kind = .dynamic
        case 1: kind = .static
        case 2: kind = .kinematic
        default: throw Failure.unknownTag
        }
        return SavedBody(collider: shape, assetName: name.isEmpty ? nil : name,
                         position: pose.position,
                         rotation: pose.rotation, velocity: velocity,
                         angularVelocity: spin, kind: kind,
                         isSensor: try bool(), density: try f64(),
                         friction: try f64(), restitution: try f64(),
                         buoyancy: try f64(), gravityScale: try f64(),
                         freedom: Freedom3D(rawValue: try u32()),
                         checksPath: try bool(), group: try u32(),
                         isAwake: try bool())
    }

    mutating func joint() throws -> SavedJoint {
        let a = try u32()
        let b = try u32()
        let kind: JointKind3D
        switch try u8() {
        case 0: kind = .revolute(at: try vector(), axis: try vector(),
                                 limits: try range())
        case 1: kind = .ball(at: try vector())
        case 2:
            let at = try vector()
            let axis = try vector()
            let swing = try f64()
            let low = try f64()
            let high = try f64()
            kind = .swingTwist(at: at, axis: axis, swing: swing,
                               twist: low...max(low, high))
        case 3: kind = .distance(from: try vector(), to: try vector(),
                                 length: try optionalDouble(), stiffness: try f64())
        case 4: kind = .weld
        case 5: kind = .prismatic(at: try vector(), axis: try vector(),
                                  limits: try range())
        case 6:
            let points = try vectors()
            let looping = try bool()
            let alignment: JointKind3D.PathAlignment
            switch try u8() {
            case 0: alignment = .free
            case 1: alignment = .rolls
            case 2: alignment = .followsPath
            case 3: alignment = .fixed
            default: throw Failure.unknownTag
            }
            kind = .path(through: points, looping: looping, alignment: alignment)
        case 7: kind = .pulley(from: try vector(), over: try vector(),
                               and: try vector(), to: try vector(),
                               ratio: try f64(), taut: try bool())
        case 8: kind = .allowing(Freedom3D(rawValue: try u32()), at: try vector(),
                                 travel: try range(), rotation: try range())
        default: throw Failure.unknownTag
        }
        return SavedJoint(a: a, b: b, kind: kind, friction: try f64(),
                          poseA: try pose(), poseB: try pose())
    }

    mutating func link() throws -> JointLink3D {
        switch try u8() {
        case 0: return .gear(ratio: try f64())
        case 1: return .rackAndPinion(travelPerTurn: try f64())
        default: throw Failure.unknownTag
        }
    }

    mutating func character() throws -> SavedCharacter {
        SavedCharacter(radius: try f64(), height: try f64(), position: try vector(),
                       stepHeight: try f64(), stickToFloorDistance: try f64(),
                       maxSlope: try f64(), mass: try f64(), pushStrength: try f64(),
                       group: try u32(), velocity: try vector(), facing: try f64())
    }

    mutating func vehicle() throws -> SavedVehicle {
        let collider = try collider()
        let pose = try pose()
        let velocity = try vector()
        let spin = try vector()
        let mass = try f64()
        let friction = try f64()
        let centerOfMass = try vector()
        let group = try u32()
        let isAwake = try bool()

        let engineTorque = try f64()
        let topSpeed = try f64()
        let antiRoll = try f64()
        let maxTilt = try optionalDouble()
        let contact: Vehicle3D.WheelContact
        switch try u8() {
        case 0: contact = .ray
        case 1: contact = .sphere
        case 2: contact = .cylinder
        default: throw Failure.unknownTag
        }
        let balances = try bool()
        let maxLean = try f64()
        let tracked = try bool()

        let throttle = try f64()
        let steering = try f64()
        let brake = try f64()
        let handBrake = try f64()
        let rpm = try f64()
        let gear = Int(try f64())
        let clutch = try f64()

        var wheels: [SavedWheel] = []
        for _ in 0 ..< (try count()) { wheels.append(try wheel()) }

        return SavedVehicle(collider: collider, pose: pose, velocity: velocity,
                            angularVelocity: spin, mass: mass, friction: friction,
                            centerOfMass: centerOfMass, group: group,
                            isAwake: isAwake, engineTorque: engineTorque,
                            topSpeed: topSpeed, antiRollStiffness: antiRoll,
                            maxTilt: maxTilt, wheelContact: contact,
                            balances: balances, maxLeanAngle: maxLean,
                            tracked: tracked, throttle: throttle,
                            steering: steering, brake: brake,
                            handBrake: handBrake, rpm: rpm, gear: gear,
                            clutch: clutch, wheels: wheels)
    }

    mutating func wheel() throws -> SavedWheel {
        SavedWheel(spinRate: try f64(), spin: try f64(),
                   position: try vector(), radius: try f64(), width: try f64(),
                   steers: try bool(), driven: try bool(),
                   maxSteerAngle: try f64(), casterAngle: try f64(),
                   suspensionLength: try f64(), suspensionTravel: try f64(),
                   suspensionFrequency: try f64(), suspensionDamping: try f64(),
                   brakeTorque: try f64(), handBrakeTorque: try f64(),
                   grip: try f64())
    }

    mutating func softBody() throws -> SavedSoftBody {
        let name = try string()
        let print = try fingerprint()
        let position = try vector()
        let qx = try f64(), qy = try f64(), qz = try f64(), qw = try f64()
        let mass = try f64()
        let stiffness = try f64()
        let bend = try f64()
        let pressure = try f64()
        let damping = try f64()
        let friction = try f64()
        let restitution = try f64()
        let iterations = Int(try u32())
        let vertexRadius = try f64()
        let twoSided = try bool()
        let group = try u32()

        let particles = try count()
        var positions: [Vector3] = []
        positions.reserveCapacity(particles)
        for _ in 0 ..< particles { positions.append(try vector()) }
        var velocities: [Vector3] = []
        velocities.reserveCapacity(particles)
        for _ in 0 ..< particles { velocities.append(try vector()) }
        var pinned: [Int] = []
        for _ in 0 ..< (try count()) { pinned.append(Int(try u32())) }

        let stretch = try f64()
        var skin = SoftBody3D.Skin()
        // The bind count is a length in the stream, so it may be bounds
        // checked; sixteen floats each.
        for _ in 0 ..< (try count()) {
            var m = matrix_identity_float4x4
            for column in 0 ..< 4 {
                m[column] = SIMD4<Float>(try f32(), try f32(), try f32(), try f32())
            }
            skin.binds.append(m)
        }
        for _ in 0 ..< (try count()) {
            var carried = CJoltSoftSkinVertex()
            carried.vertex = Int32(try u32())
            carried.joints.0 = try u32()
            carried.weights.0 = try f32()
            carried.maxDistance = try f32()
            carried.backStopDistance = try f32()
            carried.backStopRadius = try f32()
            skin.vertices.append(carried)
        }
        skin.flatBinds = SoftBody3D.flattened(skin.binds)

        var rope: SavedRope?
        // A point count of zero says this is a surface, not a rope.
        let ropePoints = try count()
        if ropePoints > 0 {
            var points: [Vector3] = []
            points.reserveCapacity(ropePoints)
            for _ in 0 ..< ropePoints { points.append(try vector()) }
            let thickness = try f64()
            let sides = Int(try u32())
            var frames: [simd_quatd] = []
            for _ in 0 ..< (try count()) {
                frames.append(simd_quatd(ix: Double(try f32()), iy: Double(try f32()),
                                         iz: Double(try f32()), r: Double(try f32())))
            }
            rope = SavedRope(points: points, thickness: thickness, sides: sides,
                             rodRotations: frames)
        }

        return SavedSoftBody(assetName: name, fingerprint: print,
                             position: position,
                             rotation: simd_quatd(ix: qx, iy: qy, iz: qz, r: qw),
                             mass: mass, stiffness: stiffness, bend: bend,
                             pressure: pressure, damping: damping,
                             friction: friction, restitution: restitution,
                             iterations: iterations, vertexRadius: vertexRadius,
                             twoSided: twoSided, group: group,
                             positions: positions, velocities: velocities,
                             pinned: pinned,
                             maxStretch: stretch > 0 ? stretch : nil,
                             skin: skin, rope: rope)
    }

    mutating func ragdoll() throws -> SavedRagdoll {
        var plan = RagdollPlan()
        plan.skinJointCount = Int(try u32())
        let limbCount = try count()
        for _ in 0 ..< limbCount {
            let skinIndex = Int(try u32())
            let name = try string()
            let sourceIndex = Int(try u32())
            let rawParent = try u32()
            let parent = rawParent == PhysicsSnapshot.groundIndex ? -1 : Int(rawParent)
            let collider = try collider()
            let shapeCenter = try vector()
            let shapeAngle = try f64()
            let shapeAxis = try vector()
            let jointOrigin = try vector()
            let qx = try f64(), qy = try f64(), qz = try f64(), qw = try f64()
            plan.limbs.append(RagdollPlan.PlannedLimb(
                skinIndex: skinIndex, name: name, sourceIndex: sourceIndex,
                parent: parent, collider: collider, shapeCenter: shapeCenter,
                shapeAngle: shapeAngle, shapeAxis: shapeAxis,
                jointOrigin: jointOrigin,
                jointRotation: simd_quatf(ix: Float(qx), iy: Float(qy),
                                          iz: Float(qz), r: Float(qw)),
                worldAxis: try vector(), mass: try f64()))
        }
        var limits: [RagdollLimit] = []
        for _ in 0 ..< limbCount {
            let swing = try f64()
            let low = try f64()
            let high = try f64()
            limits.append(RagdollLimit(swing: swing, twist: low...max(low, high)))
        }
        let friction = try f64()
        let group = try u32()
        let kind: Body3D.Kind
        switch try u8() {
        case 0: kind = .dynamic
        case 1: kind = .static
        case 2: kind = .kinematic
        default: throw Failure.unknownTag
        }
        var poses: [SavedLimbPose] = []
        for _ in 0 ..< limbCount {
            poses.append(SavedLimbPose(pose: try pose(), velocity: try vector(),
                                       angularVelocity: try vector(),
                                       isAwake: try bool()))
        }
        return SavedRagdoll(plan: plan, limits: limits, friction: friction,
                            group: group, kind: kind, poses: poses)
    }
}
