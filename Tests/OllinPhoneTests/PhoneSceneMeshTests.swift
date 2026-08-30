import Testing
import Foundation
import simd
import Ollin
@testable import OllinPhone

/// Exercises the reconstructed-room mesh: the `.sceneMesh` wire payload, placing a
/// block into world space, and the block set a sketch draws from. All GPU-free, so
/// it runs anywhere, with no phone attached.
@Suite(.timeLimit(.minutes(1))) struct PhoneSceneMeshTests {

    // MARK: The wire

    @Test func roundTripsABlock() {
        let message = PhoneMessage.sceneMesh(block(id: UUID(), transform: moveAndTurn))
        #expect(roundTrip(message) == message)
    }

    /// The scan number rides along so the Mac can tell one run of the scanner from
    /// the next. It has to survive both a full block and a retirement.
    @Test func theScanNumberSurvivesTheWire() throws {
        var sample = block(id: UUID(), transform: matrix_identity_float4x4)
        sample.scan = 0xDEAD_BEEF
        guard case .sceneMesh(let back)? = roundTrip(.sceneMesh(sample)) else {
            Issue.record("the block did not come back")
            return
        }
        #expect(back.scan == 0xDEAD_BEEF)

        let retired = PhoneSceneMeshSample(isTracked: false, timestamp: 1, id: UUID(),
                                           scan: 7, isRemoved: true,
                                           transform: matrix_identity_float4x4)
        guard case .sceneMesh(let retiredBack)? = roundTrip(.sceneMesh(retired)) else {
            Issue.record("the retirement did not come back")
            return
        }
        #expect(retiredBack.scan == 7)
    }

    @Test func roundTripsABlockWithNoLabels() {
        var sample = block(id: UUID(), transform: matrix_identity_float4x4)
        sample.surfaces = []
        #expect(roundTrip(.sceneMesh(sample)) == .sceneMesh(sample))
    }

    /// A retirement carries the id and nothing else, which is what makes it cheap
    /// enough to send the moment ARKit drops a block.
    @Test func roundTripsARetirement() {
        let id = UUID()
        let sample = PhoneSceneMeshSample(isTracked: true, timestamp: 9.5, id: id,
                                          isRemoved: true, transform: moveAndTurn)
        let back = roundTrip(.sceneMesh(sample))
        #expect(back == .sceneMesh(sample))
        guard case .sceneMesh(let decoded)? = back else { return }
        #expect(decoded.id == id)
        #expect(decoded.vertices.isEmpty)
        #expect(decoded.triangleIndices.isEmpty)
    }

    /// The wire carries one label byte per triangle, so the case order is the
    /// contract. Pinned the way the blendshape order is.
    @Test func labelsAreContiguousFromZero() {
        #expect(PhoneSurface.allCases.count == 8)
        for (i, surface) in PhoneSurface.allCases.enumerated() {
            #expect(surface.rawValue == UInt8(i))
        }
        #expect(PhoneSurface.unclassified.rawValue == 0)
    }

    @Test func aTruncatedBlockDecodesToNothing() {
        let full = PhoneWire.encode(.sceneMesh(block(id: UUID(), transform: matrix_identity_float4x4)))
        guard let header = PhoneHeader.parse(full) else {
            Issue.record("the framed block had no readable header")
            return
        }
        let start = full.startIndex + PhoneWire.headerByteCount
        let payload = full.subdata(in: start ..< full.endIndex)
        // Cut the geometry in half; the counts then promise more than is there.
        let short = payload.prefix(payload.count / 2)
        #expect(PhoneWire.decode(header: header, payload: Data(short)) == nil)
    }

    // MARK: Placing a block

    /// The anchor reports its mesh around its own origin, so the transform is what
    /// puts the block in the room. A position moves and turns; a direction only
    /// turns.
    @Test func aBlockArrivesInWorldSpace() throws {
        var sample = block(id: UUID(), transform: moveAndTurn)
        sample.vertices = [SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 0, 0), SIMD3<Float>(0, 0, 1)]
        sample.normals = [SIMD3<Float>(1, 0, 0), SIMD3<Float>(1, 0, 0), SIMD3<Float>(1, 0, 0)]
        sample.triangleIndices = [0, 1, 2]
        sample.surfaces = [PhoneSurface.floor]

        let chunk = try #require(phoneSceneChunk(from: sample))
        // A quarter turn about z sends +x to +y, then the move adds (10, 2, 3).
        #expect(close(chunk.positions[0], Vector3(10, 3, 3)))
        #expect(close(chunk.positions[1], Vector3(10, 2, 3)))
        #expect(close(chunk.positions[2], Vector3(10, 2, 4)))
        // The same turn reaches the normal, but the move does not.
        #expect(close(chunk.normals[0], Vector3(0, 1, 0)))
    }

    @Test func aRetirementIsNotABlock() {
        let sample = PhoneSceneMeshSample(isTracked: true, timestamp: 0, id: UUID(),
                                          isRemoved: true, transform: matrix_identity_float4x4)
        #expect(phoneSceneChunk(from: sample) == nil)
    }

    /// An index past the end of the vertex list would read off the end when the mesh
    /// draws, so the whole block is refused rather than half-drawn.
    @Test func aBlockThatDisagreesWithItselfIsRefused() {
        var sample = block(id: UUID(), transform: matrix_identity_float4x4)
        sample.triangleIndices = [0, 1, 99]
        #expect(phoneSceneChunk(from: sample) == nil)
    }

    // MARK: The block set

    @Test func aBetterReadingReplacesABlockInPlace() throws {
        let id = UUID()
        var room = PhoneSceneMesh()
        room.apply(try #require(phoneSceneChunk(from: block(id: id, transform: matrix_identity_float4x4))))

        var better = block(id: id, transform: matrix_identity_float4x4)
        better.vertices.append(SIMD3<Float>(2, 2, 2))
        better.normals.append(SIMD3<Float>(0, 1, 0))
        room.apply(try #require(phoneSceneChunk(from: better)))

        #expect(room.chunkCount == 1)
        #expect(room.chunks[0].positions.count == 5)
    }

    /// Removing from the middle shifts every later block down, so the set has to
    /// find them again. If it does not, a later block's next reading lands on the
    /// wrong entry.
    @Test func aRetiredBlockLeavesTheRestAddressable() throws {
        let ids = [UUID(), UUID(), UUID()]
        var room = PhoneSceneMesh()
        for id in ids {
            room.apply(try #require(phoneSceneChunk(from: block(id: id, transform: matrix_identity_float4x4))))
        }
        room.remove(ids[0])
        #expect(room.chunkCount == 2)

        // The last block reports again; it must overwrite itself, not append.
        var better = block(id: ids[2], transform: matrix_identity_float4x4)
        better.vertices.append(SIMD3<Float>(5, 5, 5))
        better.normals.append(SIMD3<Float>(0, 1, 0))
        room.apply(try #require(phoneSceneChunk(from: better)))

        #expect(room.chunkCount == 2)
        #expect(room.chunks.map(\.id) == [ids[1], ids[2]])
        #expect(room.chunks[1].positions.count == 5)
    }

    @Test func resetForgetsEverything() throws {
        var room = PhoneSceneMesh()
        room.apply(try #require(phoneSceneChunk(from: block(id: UUID(), transform: matrix_identity_float4x4))))
        room.reset()
        #expect(room.isEmpty)
        #expect(room.chunkCount == 0)
        #expect(room.mesh.isEmpty)
    }

    // MARK: Drawing

    /// Every block indexes its own vertices from zero, so the combined mesh has to
    /// push each block's indices past the blocks before it.
    @Test func theWholeRoomOffsetsEachBlocksIndices() throws {
        var room = PhoneSceneMesh()
        for _ in 0..<2 {
            room.apply(try #require(phoneSceneChunk(from: block(id: UUID(), transform: matrix_identity_float4x4))))
        }
        let mesh = room.mesh
        #expect(mesh.positions.count == 8)
        #expect(mesh.normals.count == 8)
        #expect(mesh.indices == [0, 1, 2, 1, 2, 3, 4, 5, 6, 5, 6, 7])
        #expect(mesh.triangleCount == room.triangleCount)
    }

    /// Normals pair with positions by index. A block that arrives without them would
    /// shift every later block's normal onto the wrong vertex, so the combined mesh
    /// gives up its normals entirely rather than pair them wrongly.
    @Test func aBlockWithNoNormalsDoesNotShiftTheRest() throws {
        var bare = block(id: UUID(), transform: matrix_identity_float4x4)
        bare.normals = []

        var room = PhoneSceneMesh()
        room.apply(try #require(phoneSceneChunk(from: block(id: UUID(), transform: matrix_identity_float4x4))))
        room.apply(try #require(phoneSceneChunk(from: bare)))

        let mesh = room.mesh
        #expect(mesh.positions.count == 8)
        #expect(mesh.normals.isEmpty)
        #expect(mesh.indices.count == 12)
    }

    @Test func aBlockKnowsItsOwnBox() throws {
        let chunk = try #require(phoneSceneChunk(from: block(id: UUID(), transform: matrix_identity_float4x4)))
        #expect(close(chunk.bounds.min, Vector3(0, 0, 0)))
        #expect(close(chunk.bounds.max, Vector3(1, 0, 1)))
    }

    /// Filtering keeps the triangles asked for and only the vertices those triangles
    /// reach, so asking for the floor of a room does not carry the walls' vertices.
    @Test func filteringKeepsOnlyWhatItAsksFor() throws {
        var room = PhoneSceneMesh()
        room.apply(try #require(phoneSceneChunk(from: block(id: UUID(), transform: matrix_identity_float4x4))))

        let floor = room.mesh(of: .floor)
        #expect(floor.triangleCount == 1)
        // The block's two triangles are (0,1,2) and (1,2,3); the floor one reaches
        // three of the four vertices, so the fourth does not travel.
        #expect(floor.positions.count == 3)
        #expect(floor.indices == [0, 1, 2])

        let both = room.mesh(of: .floor, .wall)
        #expect(both.triangleCount == 2)
        #expect(both.positions.count == 4)

        #expect(room.mesh(of: .ceiling).isEmpty)
    }

    @Test func filteringAnUnlabelledRoomFindsNothing() throws {
        var sample = block(id: UUID(), transform: matrix_identity_float4x4)
        sample.surfaces = []
        var room = PhoneSceneMesh()
        room.apply(try #require(phoneSceneChunk(from: sample)))
        #expect(room.foundSurfaces.isEmpty)
        #expect(room.mesh(of: .floor).isEmpty)
        // The plain mesh is unaffected: the room is still there, just unlabelled.
        #expect(room.mesh.triangleCount == 2)
    }

    /// A color belongs to a triangle and a mesh color belongs to a vertex, so each
    /// triangle has to get its own three corners.
    @Test func paintingGivesEveryTriangleItsOwnCorners() throws {
        var room = PhoneSceneMesh()
        room.apply(try #require(phoneSceneChunk(from: block(id: UUID(), transform: matrix_identity_float4x4))))

        let painted = room.mesh { $0 == .floor ? .red : .blue }
        #expect(painted.triangleCount == 2)
        #expect(painted.positions.count == 6)
        #expect(painted.colors.count == 6)
        #expect(painted.normals.count == 6)
        #expect(painted.colors[0] == .red && painted.colors[2] == .red)
        #expect(painted.colors[3] == .blue && painted.colors[5] == .blue)
    }

    @Test func theBoundsCoverEveryBlock() throws {
        var room = PhoneSceneMesh()
        room.apply(try #require(phoneSceneChunk(from: block(id: UUID(), transform: matrix_identity_float4x4))))
        var far = block(id: UUID(), transform: matrix_identity_float4x4)
        far.vertices = far.vertices.map { $0 + SIMD3<Float>(5, 5, 5) }
        room.apply(try #require(phoneSceneChunk(from: far)))

        let bounds = room.bounds
        #expect(close(bounds.min, Vector3(0, 0, 0)))
        #expect(close(bounds.max, Vector3(6, 5, 6)))
        #expect(close(room.center, Vector3(3, 2.5, 3)))
    }

    @Test func anEmptyRoomHasNothingToSay() {
        let room = PhoneSceneMesh()
        #expect(room.isEmpty)
        #expect(room.vertexCount == 0)
        #expect(room.triangleCount == 0)
        #expect(room.mesh.isEmpty)
        #expect(close(room.center, .zero))
    }

    // MARK: Helpers

    /// A quarter turn about z (which sends +x to +y), then a move to (10, 2, 3).
    private var moveAndTurn: simd_float4x4 {
        simd_float4x4(SIMD4<Float>(0, 1, 0, 0),
                      SIMD4<Float>(-1, 0, 0, 0),
                      SIMD4<Float>(0, 0, 1, 0),
                      SIMD4<Float>(10, 2, 3, 1))
    }

    /// A four-vertex block of two triangles: the first labeled floor, the second
    /// wall, sharing two vertices so a filter has something to drop.
    private func block(id: UUID, transform: simd_float4x4) -> PhoneSceneMeshSample {
        PhoneSceneMeshSample(
            isTracked: true, timestamp: 4.25, id: id, isRemoved: false, transform: transform,
            vertices: [SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 0, 0),
                       SIMD3<Float>(0, 0, 1), SIMD3<Float>(1, 0, 1)],
            normals: [SIMD3<Float>(0, 1, 0), SIMD3<Float>(0, 1, 0),
                      SIMD3<Float>(0, 1, 0), SIMD3<Float>(0, 1, 0)],
            triangleIndices: [0, 1, 2, 1, 2, 3],
            surfaces: [PhoneSurface.floor, PhoneSurface.wall])
    }

    private func close(_ a: Vector3, _ b: Vector3, _ tolerance: Double = 1e-5) -> Bool {
        abs(a.x - b.x) < tolerance && abs(a.y - b.y) < tolerance && abs(a.z - b.z) < tolerance
    }

    /// Encode a message, split the framed bytes back into header + payload the way
    /// the reader does, and decode: the full wire trip.
    private func roundTrip(_ message: PhoneMessage) -> PhoneMessage? {
        let data = PhoneWire.encode(message)
        guard let header = PhoneHeader.parse(data) else { return nil }
        let start = data.startIndex + PhoneWire.headerByteCount
        let payload = data.subdata(in: start ..< data.endIndex)
        return PhoneWire.decode(header: header, payload: payload)
    }
}
