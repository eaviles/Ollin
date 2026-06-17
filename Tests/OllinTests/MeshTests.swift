import Testing
@testable import Ollin

/// GPU-free checks on the primitive mesh generators: vertex/index plumbing,
/// unit-length normals, valid index ranges, and origin-centered, correctly-sized
/// bounds. These pin the parametric math without needing Metal.
struct MeshTests {

    /// Every generated mesh: indices are a triangle list, reference real vertices,
    /// normals match positions, and normals are unit length.
    @Test func generatorsAreWellFormed() {
        let meshes: [(String, Mesh)] = [
            ("box", .box(size: 2)),
            ("sphere", .sphere(radius: 1, segments: 12, rings: 8)),
            ("cylinder", .cylinder(radius: 1, height: 2, segments: 12)),
            ("plane", .plane(width: 2, depth: 2, segments: 2)),
            ("torus", .torus(radius: 1, tube: 0.3, segments: 16, sides: 10)),
            ("cone", .cone(radius: 1, height: 2, segments: 12)),
            ("pyramid", .pyramid(width: 1, depth: 1, height: 1.5)),
            ("helix", .helix(radius: 1, tube: 0.2, turns: 2, height: 2, segments: 60, sides: 8)),
            ("icosahedron", .icosahedron(radius: 1)),
            ("dodecahedron", .dodecahedron(radius: 1)),
            ("torusKnot", .torusKnot(p: 2, q: 3, radius: 1, tube: 0.2, segments: 80, sides: 8)),
        ]
        for (name, mesh) in meshes {
            #expect(!mesh.isEmpty, "\(name) should not be empty")
            #expect(mesh.indices.count % 3 == 0, "\(name) indices must be a triangle list")
            #expect(mesh.normals.count == mesh.positions.count, "\(name) normals must match positions")
            for i in mesh.indices {
                #expect(Int(i) < mesh.positions.count, "\(name) index \(i) out of range")
            }
            for n in mesh.normals {
                #expect(abs(n.length - 1) < 1e-6, "\(name) normal not unit length: \(n.length)")
            }
        }
    }

    /// A cube has 6 faces × 2 triangles = 12 triangles, each face flat-normaled.
    @Test func boxHasTwelveTriangles() {
        let box = Mesh.box(size: 1)
        #expect(box.triangleCount == 12)
        // The set of distinct normals is the six axis directions.
        let axes = Set(box.normals.map { "\(Int($0.x.rounded())),\(Int($0.y.rounded())),\(Int($0.z.rounded()))" })
        #expect(axes.count == 6)
    }

    /// The regular polyhedra have their defining face counts: icosahedron 20
    /// triangles, dodecahedron 12 pentagons = 36 triangles (3 per pentagon fan).
    @Test func polyhedraHaveExpectedFaceCounts() {
        #expect(Mesh.icosahedron(radius: 1).triangleCount == 20)
        #expect(Mesh.dodecahedron(radius: 1).triangleCount == 36)
        // Every polyhedron vertex sits on the bounding sphere of the given radius.
        for p in Mesh.icosahedron(radius: 2).positions {
            #expect(abs(p.length - 2) < 1e-6)
        }
        for p in Mesh.dodecahedron(radius: 2).positions {
            #expect(abs(p.length - 2) < 1e-6)
        }
    }

    /// Generated primitives are centered on the origin, with bounds matching their
    /// requested size.
    @Test func primitivesAreCenteredAndSized() {
        func bounds(_ m: Mesh) -> (Vector3, Vector3) {
            var lo = Vector3(.greatestFiniteMagnitude, .greatestFiniteMagnitude, .greatestFiniteMagnitude)
            var hi = Vector3(-.greatestFiniteMagnitude, -.greatestFiniteMagnitude, -.greatestFiniteMagnitude)
            for p in m.positions {
                lo = Vector3(min(lo.x, p.x), min(lo.y, p.y), min(lo.z, p.z))
                hi = Vector3(max(hi.x, p.x), max(hi.y, p.y), max(hi.z, p.z))
            }
            return (lo, hi)
        }

        let (blo, bhi) = bounds(.box(width: 2, height: 4, depth: 6))
        #expect(abs(blo.x + 1) < 1e-9 && abs(bhi.x - 1) < 1e-9)
        #expect(abs(blo.y + 2) < 1e-9 && abs(bhi.y - 2) < 1e-9)
        #expect(abs(blo.z + 3) < 1e-9 && abs(bhi.z - 3) < 1e-9)

        let (slo, shi) = bounds(.sphere(radius: 1.5, segments: 24, rings: 16))
        for v in [slo.x, slo.y, slo.z] { #expect(abs(v + 1.5) < 1e-6) }
        for v in [shi.x, shi.y, shi.z] { #expect(abs(v - 1.5) < 1e-6) }

        // A torus spans radius+tube across x/z and ±tube in y.
        let (tlo, thi) = bounds(.torus(radius: 1, tube: 0.25, segments: 32, sides: 16))
        #expect(abs(thi.x - 1.25) < 1e-6 && abs(tlo.x + 1.25) < 1e-6)
        #expect(abs(thi.y - 0.25) < 1e-6 && abs(tlo.y + 0.25) < 1e-6)
    }
}
