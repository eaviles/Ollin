import CoreGraphics
import Foundation
@testable import Ollin
import simd
import Testing

/// CPU checks on joining meshes (`Mesh.joined(_:)`) and baking a placement
/// into one (`placed(_:)`): the vertices in order with the indices offset to
/// them, what rides along and under which rule, and a placement's positions,
/// normals and tangents against the matrix a `MeshInstance` composes. The
/// rendered equivalence with the parts drawn apart is the Metal-gated test at
/// the bottom.
@Suite
struct MeshJoinTests {

    private static func triangle(at x: Double) -> Mesh {
        Mesh(positions: [Vector3(x, 0, 0), Vector3(x + 1, 0, 0), Vector3(x, 1, 0)],
             normals: [.unitZ, .unitZ, .unitZ], indices: [0, 1, 2])
    }

    // MARK: Joining

    @Test func joinedConcatenatesVerticesAndOffsetsIndices() {
        let a = Self.triangle(at: 0), b = Self.triangle(at: 5)
        let joined = Mesh.joined([a, b])
        #expect(joined.positions == a.positions + b.positions)
        #expect(joined.normals == a.normals + b.normals)
        #expect(joined.indices == [0, 1, 2, 3, 4, 5])
        #expect(joined.triangleCount == 2)
        #expect(joined.uvs.isEmpty && joined.colors.isEmpty && joined.tangents.isEmpty)
        #expect(joined.material == nil)
    }

    @Test func joiningNothingOrEmptyPartsGivesAnEmptyMesh() {
        #expect(Mesh.joined([]).isEmpty)
        #expect(Mesh.joined([Mesh(positions: [], indices: [])]).isEmpty)
        // An empty part among live ones is left out, and shifts nothing.
        let live = Mesh.joined([Mesh(positions: [], indices: []), Self.triangle(at: 0)])
        #expect(live.indices == [0, 1, 2])
        #expect(live.positions.count == 3)
    }

    /// A part with no normals faces +z when drawn alone, so the join writes
    /// that for it wherever any part carries normals; when none does, the
    /// result carries none either.
    @Test func normalsAreFilledOnlyWhenSomePartHasThem() {
        var bare = Self.triangle(at: 0)
        bare.normals = []
        let withSome = Mesh.joined([bare, Self.triangle(at: 5)])
        #expect(withSome.normals == [.unitZ, .unitZ, .unitZ, .unitZ, .unitZ, .unitZ])
        var other = Self.triangle(at: 5)
        other.normals = []
        #expect(Mesh.joined([bare, other]).normals.isEmpty)
    }

    /// Texture coordinates and tangents survive only when every part has a
    /// full set; vertex colors survive when any part has one, the others
    /// filled white; the material is the first any part carries.
    @Test func whatRidesAlongFollowsTheLoaderRules() {
        var a = Self.triangle(at: 0), b = Self.triangle(at: 5)
        a.uvs = [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]
        a.tangents = [MeshTangent(.unitX), MeshTangent(.unitX), MeshTangent(.unitX)]
        b.colors = [.red, .red, .red]
        b.material = MeshMaterial(baseColor: .blue)
        let half = Mesh.joined([a, b])
        #expect(half.uvs.isEmpty)
        #expect(half.tangents.isEmpty)
        #expect(half.colors == [.white, .white, .white, .red, .red, .red])
        #expect(half.material?.baseColor == .blue)

        b.uvs = [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1)]
        b.tangents = [MeshTangent(.unitY, handedness: -1), MeshTangent(.unitY), MeshTangent(.unitY)]
        a.material = MeshMaterial(baseColor: .green)
        let full = Mesh.joined([a, b])
        #expect(full.uvs == a.uvs + b.uvs)
        #expect(full.tangents.count == 6)
        #expect(full.tangents[3].direction == .unitY && full.tangents[3].handedness == -1)
        #expect(full.material?.baseColor == .green)
    }

    /// A triangle that points past its own part's vertices would, offset,
    /// land in the next part; it is left out instead.
    @Test func aTrianglePastItsPartIsDropped() {
        var a = Self.triangle(at: 0)
        a.indices += [0, 1, 7]
        let joined = Mesh.joined([a, Self.triangle(at: 5)])
        #expect(joined.indices == [0, 1, 2, 3, 4, 5])
    }

    /// The join is what `Mesh.text` builds a word from, so a word is its
    /// glyphs joined in order.
    @Test func textIsItsGlyphsJoined() {
        let glyphs = Mesh.textGlyphs("Ab", size: 1, depth: 0.2)
        let word = Mesh.text("Ab", size: 1, depth: 0.2)
        let joined = Mesh.joined(glyphs)
        #expect(word.positions == joined.positions)
        #expect(word.indices == joined.indices)
        #expect(word.positions.count == glyphs.reduce(0) { $0 + $1.positions.count })
    }

    // MARK: Placing

    @Test func placedMovesPositionsByThePlacementMatrix() {
        let box = Mesh.box(width: 2, height: 1, depth: 0.5)
        let placement = MeshInstance(position: Vector3(1, 2, 3), rotation: Vector3(0.3, 0.2, 0.1),
                                     scale: Vector3(2, 1, 0.5))
        let placed = box.placed(placement)
        let m = placement.matrix
        #expect(placed.positions.count == box.positions.count)
        for (p, q) in zip(box.positions, placed.positions) {
            let w = m * SIMD4<Float>(Float(p.x), Float(p.y), Float(p.z), 1)
            #expect(q == Vector3(Double(w.x), Double(w.y), Double(w.z)))
        }
        #expect(placed.indices == box.indices)
        #expect(placed.uvs == box.uvs)
        #expect(placed.normals.count == box.normals.count)
    }

    /// Under a non-uniform scale the normals go through the inverse
    /// transpose, so a face's normal stays perpendicular to the face and unit
    /// length, where scaling it like a position would tilt it.
    @Test func placedNormalsStayPerpendicularUnderNonUniformScale() {
        let box = Mesh.box(size: 1)
        let placement = MeshInstance(rotation: Vector3(0.4, 0, 0), scale: Vector3(3, 1, 0.25))
        let placed = box.placed(placement)
        #expect(placed.normals.count == box.normals.count)
        for n in placed.normals { #expect(abs(n.length - 1) < 1e-5) }
        for t in stride(from: 0, to: placed.indices.count, by: 3) {
            let a = placed.positions[Int(placed.indices[t])]
            let b = placed.positions[Int(placed.indices[t + 1])]
            let c = placed.positions[Int(placed.indices[t + 2])]
            let face = (b - a).cross(c - a).normalized
            let n = placed.normals[Int(placed.indices[t])]
            #expect(abs(face.dot(n) - 1) < 1e-4, "face \(face) normal \(n)")
        }
    }

    /// A tangent is a surface direction, so it turns with the linear part and
    /// stays unit; its handedness is kept.
    @Test func placedTangentsTurnWithTheSurface() {
        var quad = Self.triangle(at: 0)
        quad.tangents = [MeshTangent(.unitX, handedness: -1), MeshTangent(.unitX), MeshTangent(.unitX)]
        let placed = quad.placed(MeshInstance(rotation: Vector3(0, 0, .pi / 2), scale: Vector3(5, 5, 5)))
        for t in placed.tangents {
            #expect(abs(t.direction.length - 1) < 1e-6)
            #expect(t.direction.distance(to: .unitY) < 1e-6)
        }
        #expect(placed.tangents[0].handedness == -1)
    }

    /// A placement's tint lands in the vertex colors: a full set for a mesh
    /// with none, and multiplied into one it already has.
    @Test func placedTintBecomesVertexColor() {
        let tri = Self.triangle(at: 0)
        let tinted = tri.placed(MeshInstance(color: Color(red: 0.5, green: 1, blue: 0.25)))
        #expect(tinted.colors == [Color(red: 0.5, green: 1, blue: 0.25),
                                  Color(red: 0.5, green: 1, blue: 0.25),
                                  Color(red: 0.5, green: 1, blue: 0.25)])
        var colored = tri
        colored.colors = [.white, Color(red: 1, green: 0.5, blue: 1), .black]
        let twice = colored.placed(MeshInstance(color: Color(red: 0.5, green: 0.5, blue: 1)))
        #expect(twice.colors == [Color(red: 0.5, green: 0.5, blue: 1),
                                 Color(red: 0.5, green: 0.25, blue: 1),
                                 .black])
        // No tint leaves the colors alone.
        #expect(colored.placed(MeshInstance()).colors == colored.colors)
        #expect(tri.placed(MeshInstance(position: Vector3(1, 0, 0))).colors.isEmpty)
    }
}

/// GPU equivalence: a joined mesh, drawn once at the origin, renders the same
/// picture as its parts drawn one by one under the transform stack. The bake
/// runs the same float arithmetic the per-frame mesh path runs on a placed
/// mesh, so positions agree to the bit; a normal re-normalized in double on
/// its way through the identity path can differ from the float one by an
/// ulp, which is why the comparison allows a level and not zero.
@Suite(.serialized)
@MainActor
struct MeshJoinRenderTests {

    @Test(.enabled(if: Snapshot.hasMetal))
    func aJoinedMeshRendersAsItsPartsDrawnApart() throws {
        let joined = try #require(OllinApp.image(of: JoinedABSketch(joined: true)))
        let apart = try #require(OllinApp.image(of: JoinedABSketch(joined: false)))
        let diff = try #require(imageDifference(joined, apart))
        #expect(diff.max <= 1, "joined vs apart max difference \(diff.max) (mean \(diff.mean))")
        #expect(diff.mean < 0.01, "joined vs apart mean difference \(diff.mean)")
    }
}

/// Three parts, each lit, shadowed and non-uniformly scaled, drawn as one
/// joined mesh or as three placements of the transform stack.
private final class JoinedABSketch: Sketch {
    override var canvasSize: CanvasSize { .square(256) }
    private let joined: Bool

    init(joined: Bool) {
        self.joined = joined
        super.init()
    }

    required init() {
        self.joined = true
        super.init()
    }

    private static let parts: [(Mesh, MeshInstance)] = [
        (Mesh.box(width: 1.2, height: 0.5, depth: 0.8),
         MeshInstance(position: Vector3(-1.1, 0.25, 0.2), rotation: Vector3(0, 0.6, 0))),
        (Mesh.sphere(radius: 0.55, segments: 24, rings: 12),
         MeshInstance(position: Vector3(0.9, 0.7, -0.3), scale: Vector3(1.4, 0.8, 1))),
        (Mesh.cylinder(radius: 0.3, height: 1.4),
         MeshInstance(position: Vector3(0.2, 0.7, 1.1), rotation: Vector3(0.3, 0, 0.5))),
    ]

    override func draw() {
        background(Color(hex: 0x101218))
        camera(Camera3D(eye: Vector3(4, 4, 6), target: Vector3(0, 0.5, 0)))
        ambientLight(Color(white: 0.15))
        directionalLight(Color(white: 1), direction: Vector3(-0.5, -0.85, -0.35), intensity: 1)
        castShadows()

        withState {
            fill(Color(white: 0.8))
            drawPlane(width: 10, depth: 10)
        }

        specular(0.3)
        specularSharpness(32)
        fill(Color(hex: 0xB8C4E8))

        if joined {
            drawMesh(Mesh.joined(Self.parts.map { $0.0.placed($0.1) }))
        } else {
            for (mesh, at) in Self.parts {
                withState {
                    translate(at.position)
                    rotateX(at.rotation.x)
                    rotateY(at.rotation.y)
                    rotateZ(at.rotation.z)
                    scale(at.scale.x, at.scale.y, at.scale.z)
                    drawMesh(mesh)
                }
            }
        }
    }
}
