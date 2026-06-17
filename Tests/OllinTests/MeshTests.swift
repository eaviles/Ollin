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
            ("tetrahedron", .tetrahedron(radius: 1)),
            ("octahedron", .octahedron(radius: 1)),
            ("capsule", .capsule(radius: 0.5, height: 1, segments: 12, rings: 4)),
            ("roundedBox", .roundedBox(size: 1, radius: 0.2, segments: 6)),
            ("icosphere", .icosphere(radius: 1, subdivisions: 2)),
            ("mobius", .mobius(radius: 1, width: 0.4, segments: 40, sides: 6)),
            ("klein", .klein(scale: 0.3, segments: 30, sides: 12)),
            ("superellipsoid", .superellipsoid(radius: 1, e1: 0.5, e2: 0.5, segments: 24, rings: 12)),
            ("supershape", .supershape(radius: 1, m: 6, n1: 0.3, n2: 1, n3: 1, segments: 40, rings: 20)),
            ("tube", .tube(along: [Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0)], radius: 0.1, sides: 6)),
            ("extrude", .extrude(Profile.star(points: 5, outerRadius: 1, innerRadius: 0.5), depth: 0.5)),
            ("lathe", .lathe([Vector2(0.1, -0.5), Vector2(0.5, 0), Vector2(0.1, 0.5)], segments: 16)),
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

    /// UV-emitting generators (sphere, plane) carry one texture coordinate per vertex,
    /// each in [0, 1]; a generator without a natural parameterization (box) ships none.
    @Test func uvGeneratorsAreAligned() {
        for (name, mesh) in [("sphere", Mesh.sphere(radius: 1, segments: 12, rings: 8)),
                             ("plane", Mesh.plane(width: 2, depth: 2, segments: 3))] {
            #expect(mesh.uvs.count == mesh.positions.count, "\(name) uvs must match positions")
            for uv in mesh.uvs {
                #expect(uv.x >= 0 && uv.x <= 1 && uv.y >= 0 && uv.y <= 1, "\(name) uv out of [0,1]: \(uv)")
            }
        }
        #expect(Mesh.box(size: 1).uvs.isEmpty, "box has no natural UVs")
    }

    /// `textured(_:)` attaches a material (carried through `normalized`); a mesh with a
    /// texture but no UVs has nothing to map against, so it stays effectively flat.
    @Test func texturedAttachesMaterial() {
        let image = Image(width: 4, height: 4, color: .red)
        let globe = Mesh.sphere(radius: 1, segments: 8, rings: 6).textured(image, baseColor: .white)
        #expect(globe.material?.texture != nil)
        #expect(globe.material?.baseColor == .white)
        #expect(globe.uvs.count == globe.positions.count)
        // Material survives the recenter/scale transform.
        #expect(globe.normalized(scale: 2).material?.texture != nil)
        // A textured box carries the material but no UVs — the render path falls back
        // to a flat base-color surface.
        let box = Mesh.box(size: 1).textured(image)
        #expect(box.material?.texture != nil)
        #expect(box.uvs.isEmpty)
    }

    /// A cube has 6 faces × 2 triangles = 12 triangles, each face flat-normaled.
    @Test func boxHasTwelveTriangles() {
        let box = Mesh.box(size: 1)
        #expect(box.triangleCount == 12)
        // The set of distinct normals is the six axis directions.
        let axes = Set(box.normals.map { "\(Int($0.x.rounded())),\(Int($0.y.rounded())),\(Int($0.z.rounded()))" })
        #expect(axes.count == 6)
    }

    /// The polyhedra have their defining face counts: tetrahedron 4, octahedron 8,
    /// icosahedron 20 triangles, dodecahedron 12 pentagons = 36 triangles, and the
    /// icosphere is the icosahedron subdivided ×4 per level (20·4ⁿ).
    @Test func polyhedraHaveExpectedFaceCounts() {
        #expect(Mesh.tetrahedron(radius: 1).triangleCount == 4)
        #expect(Mesh.octahedron(radius: 1).triangleCount == 8)
        #expect(Mesh.icosahedron(radius: 1).triangleCount == 20)
        #expect(Mesh.dodecahedron(radius: 1).triangleCount == 36)
        #expect(Mesh.icosphere(radius: 1, subdivisions: 0).triangleCount == 20)
        #expect(Mesh.icosphere(radius: 1, subdivisions: 2).triangleCount == 20 * 16)
        // Every polyhedron / icosphere vertex sits on the bounding sphere.
        for p in Mesh.icosahedron(radius: 2).positions { #expect(abs(p.length - 2) < 1e-6) }
        for p in Mesh.dodecahedron(radius: 2).positions { #expect(abs(p.length - 2) < 1e-6) }
        for p in Mesh.icosphere(radius: 2, subdivisions: 2).positions { #expect(abs(p.length - 2) < 1e-6) }
    }

    /// Extrude builds a closed solid `depth` deep along z; lathe revolves a profile.
    @Test func extrudeAndLatheAreWellFormed() {
        let prism = Mesh.extrude(Profile.rectangle(width: 2, height: 1), depth: 0.5)
        #expect(!prism.isEmpty)
        // Spans ±0.25 in z (the extrusion depth) and the rectangle's extent in x/y.
        let zs = prism.positions.map(\.z)
        #expect(abs((zs.max() ?? 0) - 0.25) < 1e-9 && abs((zs.min() ?? 0) + 0.25) < 1e-9)
        let xs = prism.positions.map(\.x)
        #expect(abs((xs.max() ?? 0) - 1) < 1e-9 && abs((xs.min() ?? 0) + 1) < 1e-9)

        let bowl = Mesh.lathe([Vector2(0.1, -0.5), Vector2(0.6, 0), Vector2(0.1, 0.5)], segments: 24)
        #expect(!bowl.isEmpty)
        // Revolution reaches the profile's max radius all the way around.
        let maxR = bowl.positions.map { ($0.x * $0.x + $0.z * $0.z).squareRoot() }.max() ?? 0
        #expect(abs(maxR - 0.6) < 1e-6)
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
