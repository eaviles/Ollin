import Foundation
import Compression
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

    /// The format this build writes, and the only one it reads.
    static let version = 2

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

        // A vehicle's chassis is an ordinary body in `bodies`, so it would be
        // saved as a loose crate and come back without its wheels. Leave it out
        // rather than restore something that is no longer a vehicle.
        let driven = Set(vehicles.map { ObjectIdentifier($0.body) })
        var saved: [Body3D] = []
        var index: [CJoltBodyID: UInt32] = [:]
        for body in bodies where !driven.contains(ObjectIdentifier(body)) {
            index[body.id] = UInt32(saved.count)
            saved.append(body)
        }
        if let groundBody { index[groundBody.id] = PhysicsSnapshot.groundIndex }
        if !vehicles.isEmpty || !characters.isEmpty || !ragdolls.isEmpty
            || !softBodies.isEmpty {
            noteOnce("a snapshot holds rigid bodies and the joints between "
                     + "them; the world's characters, vehicles, ragdolls, and "
                     + "soft bodies are built from rigs and meshes it cannot "
                     + "carry, so they are left out and the sketch adds them "
                     + "back after restoring")
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

        return PhysicsSnapshot(payload: writer.data, bodies: saved.count,
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
    public func restore(_ snapshot: PhysicsSnapshot) {
        guard let payload = snapshot.payload else {
            noteOnce("this snapshot could not be read; the world is unchanged")
            return
        }
        var reader = SnapshotReader(payload)
        do {
            try rebuild(from: &reader)
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
    public func load(contentsOf url: URL) -> Bool {
        guard let snapshot = try? PhysicsSnapshot(contentsOf: url) else { return false }
        restore(snapshot)
        return true
    }

    private func rebuild(from reader: inout SnapshotReader) throws {
        // Read the whole thing before touching the world, so a truncated file
        // leaves the pile that is already there standing.
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

        for saved in savedBodies {
            let body = addBody(saved.collider, at: saved.position,
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
        }

        let restedPoses = savedBodies.map {
            Pose3D(position: $0.position, rotation: $0.rotation)
        }
        var madeJoints: [Joint3D] = []
        for saved in savedJoints {
            guard let a = restored(saved.a), let b = restored(saved.b) else { continue }
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
    }

    /// The restored body a saved index names, the floor slab included.
    private func restored(_ index: UInt32) -> Body3D? {
        if index == PhysicsSnapshot.groundIndex { return groundBody }
        return bodies.indices.contains(Int(index)) ? bodies[Int(index)] : nil
    }

    /// Stand a body at a pose without waking it: a sleeping pile is moved
    /// around while its joints are made and has to still be asleep after. The
    /// floor slab never moves; it is wherever `ground` puts it.
    private func place(_ body: Body3D, at pose: Pose3D) {
        guard body !== groundBody else { return }
        withFloats3(meters(from: pose.position)) {
            cjolt_body_set_position(handle, body.id, $0, false)
        }
        withFloats4((Float(pose.rotation.x), Float(pose.rotation.y),
                     Float(pose.rotation.z), Float(pose.rotation.w))) {
            cjolt_body_set_rotation(handle, body.id, $0, false)
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

/// One rigid body as a snapshot holds it.
private struct SavedBody {
    var collider: Collider3D
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
        collider(body.collider)
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
}

// MARK: - Reading

/// Walks a snapshot's bytes. Every read is bounds-checked and throws rather
/// than trapping, so a truncated or foreign file is refused instead of
/// crashing a sketch.
private struct SnapshotReader {
    private let data: Data
    private var offset: Int

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
        let collider = try collider()
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
        return SavedBody(collider: collider, position: pose.position,
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
}
