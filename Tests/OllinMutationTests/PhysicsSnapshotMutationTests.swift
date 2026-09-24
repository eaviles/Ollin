import Foundation
import Testing
import OllinMutation
@testable import Ollin
@testable import OllinPhysics

/// A saved physics world, the one binary file a sketch writes for itself and
/// may be handed back from anywhere. Two runs: the file mutated whole, which a
/// checksum mostly refuses at the door (so that run is about the header and
/// the packed payload's declared size), and the payload mutated and sealed
/// again with a checksum that matches, which is what reaches the body, joint,
/// and water readers and the world they are restored into.
@Suite(.enabled(if: !underThreadSanitizer, fileRunReason))
struct PhysicsSnapshotMutationTests {

    static func savedWorld() -> PhysicsSnapshot {
        let world = World3D()
        world.ground = -2
        let frame = world.addBody(.box(width: 1, height: 0.2, depth: 1), at: .zero, kind: .static)
        let door = world.addBody(.box(width: 1.4, height: 0.1, depth: 0.6), at: Vector3(1, 0, 0))
        let ball = world.addBody(.sphere(radius: 0.3), at: Vector3(0, 3, 0))
        let hinge = world.connect(frame, door, .revolute(at: .zero, axis: .unitZ, limits: -0.02...1.2))
        hinge.drive(to: 0.8, frequency: 6)
        world.connect(frame, ball, .distance(from: frame.position, to: ball.position))
        world.water = Water(level: -1, density: 1.2)
        _ = try? world.addVehicle(.box(width: 1.8, height: 0.6, depth: 4), at: Vector3(6, 1, 0),
                                  wheels: [.wheel(at: Vector3(0.9, -0.1, 1.3), steers: true),
                                           .wheel(at: Vector3(-0.9, -0.1, -1.3), driven: true)])
        world.addCharacter(radius: 0.33, height: 1.7, at: Vector3(-6, 2, 0))
        if let cloth = try? world.addSoftBody(from: sheet, at: Vector3(0, 4, 3), mass: 1, stiffness: 0.8,
                                              pinned: { $0.z < -0.4 }) {
            cloth.assetName = "sheet"
        }
        for _ in 0..<30 { world.advance(by: 1.0 / 60) }
        return world.snapshot()
    }

    /// The soft body's surface, named in the snapshot rather than held in it.
    static let sheet = Mesh.plane(width: 1, depth: 1, segments: 3)

    /// A payload sealed the way the writer seals it: the header, uncompressed,
    /// with the payload's own length and checksum.
    static func sealed(_ payload: [UInt8], bodies: Int, joints: Int) -> [UInt8] {
        var out = Array("OLLNPHYS".utf8)
        func u32(_ v: Int) { withUnsafeBytes(of: UInt32(truncatingIfNeeded: v).littleEndian) { out += $0 } }
        u32(PhysicsSnapshot.version)
        u32(bodies)
        u32(joints)
        out.append(0)
        u32(payload.count)
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in payload { hash ^= UInt64(byte); hash &*= 0x1000_0000_01b3 }
        withUnsafeBytes(of: hash.littleEndian) { out += $0 }
        return out + payload
    }

    /// Read and restored, which is the reader's whole work. Stepping the
    /// restored world is the solver's: a world of finite, bounded numbers can
    /// still hold a configuration the solver's debug build checks for by
    /// stopping (two shapes meeting at a single point), and a world built by
    /// hand can reach the same one, so that is no reader's to refuse.
    ///
    /// One world takes every case: a restore replaces all the world holds
    /// (and a refused one leaves it as it was), and a world brings up the
    /// solver's own threads, which a world a case would pay thousands of times.
    static func restore(_ bytes: [UInt8], into world: World3D) throws -> Bool {
        let snapshot = try PhysicsSnapshot(data: Data(bytes))
        _ = snapshot.assetNames
        try world.restore(snapshot) { $0 == "sheet" ? .mesh(sheet) : nil }
        _ = world.bodies.map(\.position)
        return true
    }

    @Test func wholeFiles() {
        let saved = Self.savedWorld()
        let world = World3D()
        let report = MutationRun.run("physics-file", seeds: [[UInt8](saved.data)], count: 300,
                                     allocations: fileBound) { try Self.restore($0, into: world) }
        #expect(report.seedsRefused.isEmpty, "\(report)")
        #expect(report.oversizedCount == 0, "\(report)")
    }

    @Test func sealedPayloads() throws {
        let saved = Self.savedWorld()
        let payload = try #require(saved.payload.map { [UInt8]($0) })
        let world = World3D()
        let report = MutationRun.run("physics-payload", seeds: [payload], count: 300,
                                     allocations: fileBound) { bytes in
            try Self.restore(Self.sealed(bytes, bodies: saved.bodyCount, joints: saved.jointCount), into: world)
        }
        #expect(report.seedsRefused.isEmpty, "\(report)")
        #expect(report.oversizedCount == 0, "\(report)")
    }
}
