import Foundation
@testable import Ollin
import Testing

/// Pure-CPU checks on writing a `Mesh` out for fabrication.
///
/// The load-bearing ones are the three a picture cannot show: that a flat-shaded
/// generator, which is a pile of loose triangles until it is welded, comes out
/// as a closed manifold solid; that winding follows the mesh's normals rather
/// than its authored index order; and that the model stands up on z. Each is
/// checked against the counterfactual that would fail without the treatment.
///
/// The written files are read back with the shipped loaders (`Mesh(contentsOf:)`
/// for STL and OBJ, the `.usdz` ZIP reader plus `XMLDocument` for 3MF), so the
/// tests exercise the actual bytes rather than the writer's own idea of them.
/// No GPU.
@Suite
struct MeshExportTests {

    // MARK: Support

    private func temporaryURL(_ name: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-mesh-export-\(UUID().uuidString)-\(name)")
    }

    /// Every undirected edge and how many triangles use it.
    private func edgeUse(positions: Int, indices: [UInt32]) -> [Int: Int] {
        var counts: [Int: Int] = [:]
        for t in stride(from: 0, to: indices.count, by: 3) {
            let tri = [Int(indices[t]), Int(indices[t + 1]), Int(indices[t + 2])]
            for e in 0 ..< 3 {
                let a = tri[e], b = tri[(e + 1) % 3]
                counts[min(a, b) * positions + max(a, b), default: 0] += 1
            }
        }
        return counts
    }

    /// A closed tetrahedron built by hand, wound outward, with outward normals.
    /// Small enough that every index can be reasoned about.
    private func tetrahedron() -> Mesh {
        let p = [Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(0, 10, 0), Vector3(0, 0, 10)]
        let indices: [UInt32] = [0, 2, 1, 0, 1, 3, 0, 3, 2, 1, 2, 3]
        // Outward normals from the geometry itself, so the winding pass agrees
        // with the authored order.
        var normals = [Vector3](repeating: .zero, count: 4)
        for t in stride(from: 0, to: indices.count, by: 3) {
            let a = p[Int(indices[t])], b = p[Int(indices[t + 1])], c = p[Int(indices[t + 2])]
            let face = (b - a).cross(c - a)
            for k in 0 ..< 3 { normals[Int(indices[t + k])] += face }
        }
        return Mesh(positions: p, normals: normals.map(\.normalized), indices: indices)
    }

    // MARK: The welding that makes a generator printable

    @Test func aFlatShadedGeneratorIsOnlyASolidOnceItIsWelded() {
        let sphere = Mesh.icosphere(radius: 10, subdivisions: 2)

        // As authored: every triangle carries its own corners, so no edge is
        // shared and the whole surface reads as holes. This is the counterfactual
        // the welding exists for.
        let raw = edgeUse(positions: sphere.positions.count, indices: sphere.indices)
        #expect(raw.values.allSatisfy { $0 == 1 })

        // Prepared for writing: one connected, closed surface.
        let check = sphere.printCheck()
        #expect(check.isClosed)
        #expect(check.boundaryEdgeCount == 0)
        #expect(check.nonManifoldEdgeCount == 0)
        #expect(check.isConsistentlyOriented)
        #expect(check.isPrintable)
        #expect(check.vertexCount < sphere.positions.count)
        #expect(check.triangleCount == sphere.triangleCount)
    }

    @Test func everyEdgeOfAWrittenSolidIsSharedByExactlyTwoTriangles() throws {
        let prepared = try #require(FabricationMesh(Mesh.box(width: 4, height: 6, depth: 8), upAxis: .z))
        let uses = edgeUse(positions: prepared.positions.count, indices: prepared.indices)
        #expect(uses.values.allSatisfy { $0 == 2 })
    }

    // MARK: Winding

    @Test func windingFollowsTheNormalsRatherThanTheAuthoredOrder() throws {
        var reversed = tetrahedron()
        // Wind it inward while leaving the outward normals alone, which is the
        // state a mesh built by extruding a profile arrives in.
        for t in stride(from: 0, to: reversed.indices.count, by: 3) {
            reversed.indices.swapAt(t + 1, t + 2)
        }

        let prepared = try #require(FabricationMesh(reversed, upAxis: .y))
        let volume = FabricationMesh.signedVolume(positions: prepared.positions,
                                                  indices: prepared.indices)
        #expect(volume > 0)   // flipped back to face out

        // The counterfactual: the same reversed indices with the normals reversed
        // too. Now nothing disagrees, so the writer leaves it, and the check is
        // what reports the problem.
        let agreeing = Mesh(positions: reversed.positions,
                            normals: reversed.normals.map { $0 * -1 },
                            indices: reversed.indices)
        let insideOut = try #require(FabricationMesh(agreeing, upAxis: .y))
        #expect(FabricationMesh.signedVolume(positions: insideOut.positions,
                                             indices: insideOut.indices) < 0)
        #expect(agreeing.printCheck().isInsideOut)
        #expect(!agreeing.printCheck().isPrintable)
    }

    @Test func aMeshWithNoNormalsIsJudgedByTheVolumeItEncloses() throws {
        var reversed = tetrahedron()
        reversed.normals = []
        for t in stride(from: 0, to: reversed.indices.count, by: 3) {
            reversed.indices.swapAt(t + 1, t + 2)
        }
        let prepared = try #require(FabricationMesh(reversed, upAxis: .y))
        #expect(FabricationMesh.signedVolume(positions: prepared.positions,
                                             indices: prepared.indices) > 0)
    }

    // MARK: Orientation

    @Test func theModelStandsUpOnZ() throws {
        // Twice as tall as it is wide or deep, in Ollin's y-up world.
        let tall = Mesh.box(width: 2, height: 20, depth: 4)

        let standing = try #require(FabricationMesh(tall, upAxis: .z))
        let size = standing.printSize()
        #expect(abs(size.z - 20) < 1e-9)   // height moved onto z
        #expect(abs(size.x - 2) < 1e-9)
        #expect(abs(size.y - 4) < 1e-9)    // depth, from the old z

        // The counterfactual: left as authored, the height is still on y and it
        // would lie on its side on a platform.
        let asAuthored = try #require(FabricationMesh(tall, upAxis: .y))
        #expect(abs(asAuthored.printSize().y - 20) < 1e-9)
    }

    @Test func turningTheModelUprightDoesNotTurnItInsideOut() throws {
        let standing = try #require(FabricationMesh(Mesh.icosphere(radius: 5, subdivisions: 1),
                                                   upAxis: .z))
        // A quarter turn is a rotation, so the volume it encloses keeps its sign.
        #expect(FabricationMesh.signedVolume(positions: standing.positions,
                                             indices: standing.indices) > 0)
    }

    // MARK: STL

    @Test func stlReadsBackThroughTheShippedLoader() throws {
        let sphere = Mesh.icosphere(radius: 8, subdivisions: 2)
        let url = temporaryURL("sphere.stl")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(sphere.write(to: url))

        let reloaded = try #require(Mesh(contentsOf: url))
        #expect(reloaded.triangleCount == sphere.triangleCount)

        // Same solid, standing on z.
        let written = try #require(FabricationMesh(sphere, upAxis: .z))
        let expected = written.printSize()
        let actual = reloaded.size
        #expect(abs(actual.x - expected.x) < 1e-3)
        #expect(abs(actual.y - expected.y) < 1e-3)
        #expect(abs(actual.z - expected.z) < 1e-3)
    }

    @Test func theStlHeaderDoesNotStartWithSolid() throws {
        // A binary file whose first five bytes read "solid" gets taken for the
        // text form by readers that sniff, and then parsed as garbage.
        let data = try #require(tetrahedron().data(as: .stl))
        let header = String(decoding: data.prefix(5), as: UTF8.self)
        #expect(header != "solid")
        #expect(data.count == 84 + 4 * 50)
    }

    // MARK: OBJ

    @Test func objReadsBackThroughTheShippedLoader() throws {
        let mesh = tetrahedron()
        let url = temporaryURL("tetra.obj")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(mesh.write(to: url))

        let reloaded = try #require(Mesh(contentsOf: url))
        #expect(reloaded.triangleCount == 4)
        #expect(reloaded.positions.count == 4)   // shared vertices survived the trip
        #expect(reloaded.printCheck().isClosed)
    }

    // MARK: 3MF

    /// The model XML inside a written 3MF package, opened the way any consumer
    /// would: unzip, then parse.
    private func threeMFModel(_ mesh: Mesh, unit: ModelUnit = .millimeter) throws -> XMLElement {
        let data = try #require(mesh.data(as: .threeMF, unit: unit))
        let archive = try USDZipArchive(data: data)
        #expect(archive.entryNames.contains("[Content_Types].xml"))
        #expect(archive.entryNames.contains("_rels/.rels"))
        #expect(archive.entryNames.contains("3D/3dmodel.model"))
        let model = try #require(archive.data(named: "3D/3dmodel.model"))
        return try #require(try XMLDocument(data: model).rootElement())
    }

    @Test func theThreeMFPackageOpensAndParses() throws {
        let mesh = tetrahedron()
        let root = try threeMFModel(mesh)

        #expect(root.name == "model")
        // The core namespace is what says this is a 3MF model rather than some
        // other XML with a <model> in it. A parser reads it as the element's
        // namespace, not as an attribute called xmlns.
        #expect(root.uri == "http://schemas.microsoft.com/3dmanufacturing/core/2015/02")
        #expect(root.attribute(forName: "unit")?.stringValue == "millimeter")

        let object = try #require(root.elements(forName: "resources").first?
            .elements(forName: "object").first)
        #expect(object.attribute(forName: "id")?.stringValue == "1")
        #expect(object.attribute(forName: "type")?.stringValue == "model")

        let meshNode = try #require(object.elements(forName: "mesh").first)
        let vertices = try #require(meshNode.elements(forName: "vertices").first).children ?? []
        let triangles = try #require(meshNode.elements(forName: "triangles").first).children ?? []
        #expect(vertices.count == 4)
        #expect(triangles.count == 4)

        // The build has to name the object, or a consumer has nothing to make.
        let item = try #require(root.elements(forName: "build").first?
            .elements(forName: "item").first)
        #expect(item.attribute(forName: "objectid")?.stringValue == "1")
    }

    @Test func everyThreeMFTriangleNamesThreeDistinctVerticesInRange() throws {
        let root = try threeMFModel(Mesh.icosphere(radius: 6, subdivisions: 2))
        let meshNode = try #require(root.elements(forName: "resources").first?
            .elements(forName: "object").first?.elements(forName: "mesh").first)
        let vertexCount = (try #require(meshNode.elements(forName: "vertices").first)
            .children ?? []).count

        var seen = 0
        for case let triangle as XMLElement in try #require(meshNode.elements(forName: "triangles").first).children ?? [] {
            let corners = ["v1", "v2", "v3"].compactMap {
                triangle.attribute(forName: $0)?.stringValue.flatMap(Int.init)
            }
            #expect(corners.count == 3)
            #expect(Set(corners).count == 3)                        // distinct, per the spec
            #expect(corners.allSatisfy { $0 >= 0 && $0 < vertexCount })
            seen += 1
        }
        #expect(seen > 0)
    }

    @Test func theUnitIsRecordedInTheThreeMFAndNowhereElse() throws {
        let mesh = tetrahedron()
        let root = try threeMFModel(mesh, unit: .centimeter)
        #expect(root.attribute(forName: "unit")?.stringValue == "centimeter")

        // STL and OBJ have no place to record it, so declaring one must not
        // silently rescale the geometry either.
        #expect(mesh.data(as: .stl, unit: .centimeter) == mesh.data(as: .stl, unit: .inch))
        #expect(mesh.data(as: .obj, unit: .centimeter) == mesh.data(as: .obj, unit: .meter))
    }

    @Test func writingTheSameMeshTwiceGivesTheSameBytes() throws {
        // The package holds no clock, so a generated model is comparable and
        // committable like any other artifact.
        let mesh = Mesh.icosphere(radius: 3, subdivisions: 1)
        for format in MeshFileFormat.allCases {
            #expect(mesh.data(as: format) == mesh.data(as: format))
        }
    }

    @Test func theZipCarriesTheStandardChecksum() {
        // The published check value for the CRC-32 a ZIP entry uses.
        #expect(ZipWriter.crc32(Data("123456789".utf8)) == 0xCBF4_3926)
    }

    // MARK: The check

    @Test func aHoleIsReportedAsBoundaryEdges() {
        var holed = tetrahedron()
        holed.indices.removeLast(3)          // take one face off
        let check = holed.printCheck()
        #expect(!check.isClosed)
        #expect(check.boundaryEdgeCount == 3)
        #expect(!check.isPrintable)
        #expect(check.problems.contains { $0.contains("hole") })
    }

    @Test func degenerateTrianglesAreDroppedAndCounted() {
        var withSliver = tetrahedron()
        // A triangle whose three corners are one point has no area and no side.
        withSliver.indices.append(contentsOf: [0, 0, 0])
        let check = withSliver.printCheck()
        #expect(check.degenerateTriangleCount == 1)
        #expect(check.triangleCount == 4)
        #expect(check.isPrintable)
    }

    @Test func theCheckReportsThePhysicalSizeAndVolume() {
        let check = Mesh.box(width: 2, height: 3, depth: 4).printCheck()
        #expect(abs(check.size.x - 2) < 1e-9)
        #expect(abs(check.size.y - 4) < 1e-9)   // depth, once it is standing on z
        #expect(abs(check.size.z - 3) < 1e-9)   // height
        #expect(abs(check.volume - 24) < 1e-9)
    }

    @Test func anEmptyMeshIsReportedRatherThanWritten() {
        let empty = Mesh(positions: [], indices: [])
        #expect(empty.data(as: .stl) == nil)
        #expect(!empty.printCheck().isPrintable)
        #expect(!empty.write(to: temporaryURL("empty.stl")))
    }

    @Test func anUnknownExtensionIsRefusedWithoutWriting() {
        let url = temporaryURL("model.gcode")
        #expect(!tetrahedron().write(to: url))
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func theFormatCanBeNamedForAnyExtension() throws {
        let url = temporaryURL("model.bin")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(tetrahedron().write(to: url, as: .stl))
        let written = try Data(contentsOf: url)
        #expect(written.count == 84 + 4 * 50)
    }
}

private extension FabricationMesh {
    /// The bounding size of the prepared mesh, for the orientation checks.
    func printSize() -> Vector3 {
        var lo = positions[0], hi = positions[0]
        for p in positions {
            lo = Vector3(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z))
            hi = Vector3(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z))
        }
        return hi - lo
    }
}
