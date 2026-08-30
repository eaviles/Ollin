import Testing
import Foundation
import simd
import Ollin
@testable import OllinPhone

/// Exercises the flat surfaces the phone finds and the light it measures: the
/// `.plane` and `.light` wire payloads, placing a surface into world space, the set
/// a sketch reads, and how a light reading becomes a color and a `Light`. All
/// GPU-free, so it runs anywhere, with no phone attached.
@Suite(.timeLimit(.minutes(1))) struct PhonePlanesTests {

    // MARK: The wire

    @Test func roundTripsASurface() {
        let message = PhoneMessage.plane(square(id: UUID(), transform: moveAndTurn))
        #expect(roundTrip(message) == message)
    }

    /// A retirement carries the id and nothing else, which is what makes it cheap
    /// enough to send the moment ARKit merges one surface into another.
    @Test func roundTripsARetirement() throws {
        let id = UUID()
        let sample = PhonePlaneSample(isTracked: true, timestamp: 9.5, id: id, scan: 7,
                                      isRemoved: true, transform: moveAndTurn)
        #expect(roundTrip(.plane(sample)) == .plane(sample))
        guard case .plane(let back)? = roundTrip(.plane(sample)) else {
            Issue.record("the retirement did not come back")
            return
        }
        #expect(back.id == id)
        #expect(back.scan == 7)
        #expect(back.boundary.isEmpty)
    }

    /// The scan number tells the Mac one run of the scanner from the next, so it has
    /// to survive a full surface as well as a retirement.
    @Test func theScanNumberSurvivesTheWire() throws {
        var sample = square(id: UUID(), transform: matrix_identity_float4x4)
        sample.scan = 0xDEAD_BEEF
        guard case .plane(let back)? = roundTrip(.plane(sample)) else {
            Issue.record("the surface did not come back")
            return
        }
        #expect(back.scan == 0xDEAD_BEEF)
    }

    /// Both bytes that say what a surface is ride the wire on their own, so they are
    /// worth reading back by hand rather than trusting the whole-value compare.
    @Test func theLabelAndTheFacingSurviveTheWire() throws {
        var sample = square(id: UUID(), transform: matrix_identity_float4x4)
        sample.alignment = .vertical
        sample.surface = .window
        guard case .plane(let back)? = roundTrip(.plane(sample)) else {
            Issue.record("the surface did not come back")
            return
        }
        #expect(back.alignment == .vertical)
        #expect(back.surface == .window)
    }

    /// The wire carries the facing as one byte, so the case order is the contract.
    @Test func facingsAreContiguousFromZero() {
        #expect(PhonePlaneAlignment.allCases.count == 2)
        for (i, alignment) in PhonePlaneAlignment.allCases.enumerated() {
            #expect(alignment.rawValue == UInt8(i))
        }
    }

    @Test func aTruncatedSurfaceDecodesToNothing() {
        let full = PhoneWire.encode(.plane(square(id: UUID(), transform: matrix_identity_float4x4)))
        guard let header = PhoneHeader.parse(full) else {
            Issue.record("the framed surface had no readable header")
            return
        }
        let start = full.startIndex + PhoneWire.headerByteCount
        let payload = full.subdata(in: start ..< full.endIndex)
        // Cut the outline in half; the count then promises more than is there.
        let short = payload.prefix(payload.count / 2)
        #expect(PhoneWire.decode(header: header, payload: Data(short)) == nil)
    }

    @Test func roundTripsTheRoomsLight() {
        let message = PhoneMessage.light(PhoneLightSample(timestamp: 4.5,
                                                          ambientIntensity: 640,
                                                          colorTemperature: 3100))
        #expect(roundTrip(message) == message)
    }

    /// Face mode adds a direction and the 27 coefficients, so the longer payload has
    /// to survive too.
    @Test func roundTripsALightWithADirection() throws {
        let harmonics = (0..<27).map { Float($0) * 0.125 }
        let sample = PhoneLightSample(timestamp: 8, ambientIntensity: 1200,
                                      colorTemperature: 6900, hasDirection: true,
                                      direction: SIMD3<Float>(0, -1, 0),
                                      directionalIntensity: 1800,
                                      sphericalHarmonics: harmonics)
        #expect(roundTrip(.light(sample)) == .light(sample))
        guard case .light(let back)? = roundTrip(.light(sample)) else {
            Issue.record("the light did not come back")
            return
        }
        #expect(back.sphericalHarmonics.count == 27)
    }

    // MARK: Placing a surface

    /// The anchor reports its outline around its own origin, so the transform is what
    /// puts the surface in the room. A position moves and turns; the facing only
    /// turns.
    @Test func aSurfaceArrivesInWorldSpace() throws {
        var sample = square(id: UUID(), transform: moveAndTurn)
        sample.center = SIMD3<Float>(1, 0, 0)

        let plane = try #require(phonePlane(from: sample))
        // A quarter turn about z sends +x to +y, then the move adds (10, 2, 3).
        #expect(close(plane.center, Vector3(10, 3, 3)))
        // The same turn reaches the facing, but the move does not: +y becomes -x.
        #expect(close(plane.normal, Vector3(-1, 0, 0)))
        #expect(plane.boundary.count == 4)
    }

    @Test func aRetirementIsNotASurface() {
        let sample = PhonePlaneSample(isTracked: true, timestamp: 0, id: UUID(),
                                      isRemoved: true, transform: matrix_identity_float4x4)
        #expect(phonePlane(from: sample) == nil)
    }

    /// A fan built the wrong way round faces backwards, and the surface then vanishes
    /// from the side you are looking at. So an outline that disagrees with the
    /// anchor's own facing is turned around on arrival.
    @Test func anOutlineWoundTheWrongWayIsTurnedRound() throws {
        var sample = square(id: UUID(), transform: matrix_identity_float4x4)
        // Clockwise seen from above, which is the wrong way for a surface facing up.
        sample.boundary = [SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 0, 0),
                           SIMD3<Float>(1, 0, 1), SIMD3<Float>(0, 0, 1)]

        let plane = try #require(phonePlane(from: sample))
        #expect(close(plane.normal, Vector3(0, 1, 0)))
        #expect(fanNormal(plane.boundary).dot(plane.normal) > 0)
        // Turning it round is a reversal, not a rebuild: the same four corners.
        #expect(plane.boundary.count == 4)
        #expect(close(plane.area, 1))
    }

    /// An outline already wound the right way is left alone.
    @Test func anOutlineWoundTheRightWayIsLeftAlone() throws {
        let sample = square(id: UUID(), transform: matrix_identity_float4x4)
        let plane = try #require(phonePlane(from: sample))
        #expect(close(plane.boundary[0], Vector3(0, 0, 0)))
        #expect(fanNormal(plane.boundary).dot(plane.normal) > 0)
    }

    /// A surface with no reported outline still has a box, so it becomes a rectangle
    /// and everything downstream has one shape to handle instead of two. The box is
    /// turned by its own angle, which is how a table at an angle measures as a table.
    @Test func aSurfaceWithNoOutlineGetsOneFromItsBox() throws {
        var sample = PhonePlaneSample(isTracked: true, timestamp: 1, id: UUID(),
                                      transform: matrix_identity_float4x4,
                                      center: SIMD3<Float>(1, 0, 2),
                                      width: 2, height: 4,
                                      rotationOnYAxis: .pi / 2)
        sample.boundary = []

        let plane = try #require(phonePlane(from: sample))
        #expect(plane.boundary.count == 4)
        // The quarter turn swaps which way the long side runs.
        #expect(close(plane.bounds.min, Vector3(-1, 0, 1)))
        #expect(close(plane.bounds.max, Vector3(3, 0, 3)))
        #expect(close(plane.area, 8))
        #expect(fanNormal(plane.boundary).dot(plane.normal) > 0)
    }

    @Test func aSurfaceWithNoOutlineAndNoSizeIsRefused() {
        let sample = PhonePlaneSample(isTracked: true, timestamp: 1, id: UUID(),
                                      transform: matrix_identity_float4x4)
        #expect(phonePlane(from: sample) == nil)
    }

    // MARK: The set of surfaces

    @Test func aBetterReadingReplacesASurfaceInPlace() throws {
        let id = UUID()
        var room = PhonePlanes()
        room.apply(try #require(phonePlane(from: square(id: id, transform: matrix_identity_float4x4))))

        var wider = square(id: id, transform: matrix_identity_float4x4)
        wider.boundary = wider.boundary.map { $0 * 2 }
        room.apply(try #require(phonePlane(from: wider)))

        #expect(room.count == 1)
        #expect(close(room.planes[0].area, 4))
    }

    /// Removing from the middle shifts every later surface down, so the set has to
    /// find them again. If it does not, a later surface's next reading lands on the
    /// wrong entry.
    @Test func aRetiredSurfaceLeavesTheRestAddressable() throws {
        let ids = [UUID(), UUID(), UUID()]
        var room = PhonePlanes()
        for id in ids {
            room.apply(try #require(phonePlane(from: square(id: id, transform: matrix_identity_float4x4))))
        }
        room.remove(ids[0])
        #expect(room.count == 2)

        var wider = square(id: ids[2], transform: matrix_identity_float4x4)
        wider.boundary = wider.boundary.map { $0 * 3 }
        room.apply(try #require(phonePlane(from: wider)))

        #expect(room.count == 2)
        #expect(room.planes.map(\.id) == [ids[1], ids[2]])
        #expect(close(room.planes[1].area, 9))
    }

    @Test func resetForgetsEverything() throws {
        var room = PhonePlanes()
        room.apply(try #require(phonePlane(from: square(id: UUID(), transform: matrix_identity_float4x4))))
        room.reset()
        #expect(room.isEmpty)
        #expect(room.count == 0)
        #expect(room.mesh.isEmpty)
    }

    /// The biggest surface is the one with the most surface, not the one with the
    /// biggest box around it. A long thin shelf can have a huge box and very little
    /// of it, and picking that as the floor would put the sketch on a shelf.
    @Test func theBiggestSurfaceIsMeasuredOnItsOutline() throws {
        var wide = square(id: UUID(), transform: matrix_identity_float4x4)
        wide.boundary = wide.boundary.map { $0 * 2 }      // 2 by 2, area 4
        wide.width = 2; wide.height = 2

        var shelf = square(id: UUID(), transform: matrix_identity_float4x4)
        shelf.boundary = [SIMD3<Float>(0, 0, 0), SIMD3<Float>(0, 0, 0.5),
                          SIMD3<Float>(4, 0, 0.5), SIMD3<Float>(4, 0, 0)]   // area 2
        shelf.width = 4; shelf.height = 4                 // but a much bigger box

        var room = PhonePlanes()
        room.apply(try #require(phonePlane(from: wide)))
        room.apply(try #require(phonePlane(from: shelf)))

        #expect(room.largest?.id == wide.id)
    }

    /// A label arrives late, so a sketch that wants a ground to stand on gets the
    /// lowest flat surface until the phone has decided what it is.
    @Test func theFloorFallsBackToTheLowestFlatSurface() throws {
        var room = PhonePlanes()

        var table = square(id: UUID(), transform: matrix_identity_float4x4)
        table.center = SIMD3<Float>(0, 0.75, 0)
        table.boundary = table.boundary.map { $0 + SIMD3<Float>(0, 0.75, 0) }
        var ground = square(id: UUID(), transform: matrix_identity_float4x4)
        var wall = square(id: UUID(), transform: matrix_identity_float4x4)
        wall.alignment = .vertical
        wall.center = SIMD3<Float>(0, -2, 0)
        wall.boundary = wall.boundary.map { $0 + SIMD3<Float>(0, -2, 0) }

        room.apply(try #require(phonePlane(from: table)))
        room.apply(try #require(phonePlane(from: ground)))
        room.apply(try #require(phonePlane(from: wall)))

        // The wall is lower than either flat surface, and it is still not the floor.
        #expect(room.floor?.id == ground.id)
        #expect(room.flat.count == 2)
        #expect(room.upright.count == 1)

        // Once the phone labels the table top, an explicit floor label still wins.
        ground.surface = PhoneSurface.floor
        room.apply(try #require(phonePlane(from: ground)))
        #expect(room.floor?.id == ground.id)
        #expect(room.foundSurfaces.contains(.floor))
    }

    @Test func filteringKeepsOnlyTheLabelsAskedFor() throws {
        var room = PhonePlanes()
        var table = square(id: UUID(), transform: matrix_identity_float4x4)
        table.surface = PhoneSurface.table
        var wall = square(id: UUID(), transform: matrix_identity_float4x4)
        wall.surface = PhoneSurface.wall
        room.apply(try #require(phonePlane(from: table)))
        room.apply(try #require(phonePlane(from: wall)))

        #expect(room.planes(of: .table).count == 1)
        #expect(room.planes(of: .table, .wall).count == 2)
        #expect(room.planes(of: .ceiling).isEmpty)
        #expect(room.largest(of: .ceiling) == nil)
    }

    /// Every surface indexes its own outline from zero, so the combined mesh has to
    /// push each one's indices past the surfaces before it.
    @Test func theWholeRoomOffsetsEachSurfacesIndices() throws {
        var room = PhonePlanes()
        for _ in 0..<2 {
            room.apply(try #require(phonePlane(from: square(id: UUID(), transform: matrix_identity_float4x4))))
        }
        let mesh = room.mesh { _ in .red }
        #expect(mesh.positions.count == 8)
        #expect(mesh.normals.count == 8)
        #expect(mesh.colors.count == 8)
        // A four-corner outline fans into two triangles.
        #expect(mesh.indices == [0, 1, 2, 0, 2, 3, 4, 5, 6, 4, 6, 7])
    }

    @Test func theBoundsCoverEverySurface() throws {
        var room = PhonePlanes()
        room.apply(try #require(phonePlane(from: square(id: UUID(), transform: matrix_identity_float4x4))))
        var far = square(id: UUID(), transform: matrix_identity_float4x4)
        far.boundary = far.boundary.map { $0 + SIMD3<Float>(5, 5, 5) }
        room.apply(try #require(phonePlane(from: far)))

        #expect(close(room.bounds.min, Vector3(0, 0, 0)))
        #expect(close(room.bounds.max, Vector3(6, 5, 6)))
        #expect(close(room.center, Vector3(3, 2.5, 3)))
    }

    @Test func anEmptyRoomHasNothingToSay() {
        let room = PhonePlanes()
        #expect(room.isEmpty)
        #expect(room.count == 0)
        #expect(room.largest == nil)
        #expect(room.floor == nil)
        #expect(room.mesh.isEmpty)
        #expect(close(room.center, .zero))
    }

    // MARK: The room's light

    /// A thousand lumens is an ordinary room, so that is where the multiplier reads
    /// 1. A sketch multiplies by this, so the scale is the whole point of it.
    @Test func lightReadsAsAMultiplierAndAColor() {
        let dim = PhoneLight(PhoneLightSample(timestamp: 1, ambientIntensity: 500,
                                              colorTemperature: 2700))
        #expect(close(dim.lumens, 500))
        #expect(close(dim.intensity, 0.5))
        #expect(close(dim.kelvin, 2700))
        // A warm room is redder than it is blue.
        #expect(dim.color.red > dim.color.blue)
        // The ambient color is the room's white turned down by how dim the room is.
        #expect(close(dim.ambient.red, dim.color.red * 0.5))
        #expect(dim.key == nil)
        #expect(dim.direction == nil)
        #expect(dim.sphericalHarmonics == nil)
    }

    /// A very bright room must not multiply a sketch into pure white, so the ambient
    /// color stops climbing.
    @Test func aVeryBrightRoomStopsClimbing() {
        let sun = PhoneLight(PhoneLightSample(timestamp: 1, ambientIntensity: 40_000,
                                              colorTemperature: 6500))
        #expect(close(sun.intensity, 40))
        #expect(sun.ambient.red <= 1.5)
    }

    /// Face mode is the only one that knows where the light comes from, and what it
    /// knows arrives ready to add to a scene.
    @Test func faceModeBringsALightYouCanAdd() throws {
        let light = PhoneLight(PhoneLightSample(timestamp: 1, ambientIntensity: 1000,
                                                colorTemperature: 6500, hasDirection: true,
                                                direction: SIMD3<Float>(0, -2, 0),
                                                directionalIntensity: 1500,
                                                sphericalHarmonics: [Float](repeating: 0.5, count: 27)))
        let direction = try #require(light.direction)
        // The direction arrives as a unit vector whatever length it came in as.
        #expect(close(direction.length, 1))
        #expect(close(direction.y, -1))
        #expect(close(try #require(light.keyIntensity), 1.5))
        #expect(light.sphericalHarmonics?.count == 27)

        let key = try #require(light.key)
        #expect(key.kind == .directional)
        #expect(close(key.intensity, 1.5))
    }

    // MARK: Helpers

    /// A quarter turn about z (which sends +x to +y), then a move to (10, 2, 3).
    private var moveAndTurn: simd_float4x4 {
        simd_float4x4(SIMD4<Float>(0, 1, 0, 0),
                      SIMD4<Float>(-1, 0, 0, 0),
                      SIMD4<Float>(0, 0, 1, 0),
                      SIMD4<Float>(10, 2, 3, 1))
    }

    /// A one-meter square lying flat, wound the right way for a surface facing up.
    private func square(id: UUID, transform: simd_float4x4) -> PhonePlaneSample {
        PhonePlaneSample(isTracked: true, timestamp: 4.25, id: id, isRemoved: false,
                         transform: transform, center: .zero, width: 1, height: 1,
                         rotationOnYAxis: 0, alignment: .horizontal,
                         surface: .unclassified,
                         boundary: [SIMD3<Float>(0, 0, 0), SIMD3<Float>(0, 0, 1),
                                    SIMD3<Float>(1, 0, 1), SIMD3<Float>(1, 0, 0)])
    }

    /// The direction a fan built from these points faces.
    private func fanNormal(_ points: [Vector3]) -> Vector3 {
        var sum = Vector3.zero
        guard points.count >= 3 else { return sum }
        for i in 1..<(points.count - 1) {
            sum += (points[i] - points[0]).cross(points[i + 1] - points[0])
        }
        return sum
    }

    private func close(_ a: Vector3, _ b: Vector3, _ tolerance: Double = 1e-5) -> Bool {
        abs(a.x - b.x) < tolerance && abs(a.y - b.y) < tolerance && abs(a.z - b.z) < tolerance
    }

    private func close(_ a: Double, _ b: Double, _ tolerance: Double = 1e-5) -> Bool {
        abs(a - b) < tolerance
    }

    /// Encode a message, split the framed bytes back into header + payload the way
    /// the reader does, and decode it again.
    private func roundTrip(_ message: PhoneMessage) -> PhoneMessage? {
        let data = PhoneWire.encode(message)
        guard let header = PhoneHeader.parse(data) else { return nil }
        let start = data.startIndex + PhoneWire.headerByteCount
        let payload = data.subdata(in: start ..< data.endIndex)
        return PhoneWire.decode(header: header, payload: payload)
    }
}
