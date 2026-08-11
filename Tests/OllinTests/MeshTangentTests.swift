import CoreGraphics
import Foundation
@testable import Ollin
import Testing

/// The tangent basis behind normal mapping: `generatingTangents()` (MikkTSpace
/// over the mesh's own uvs) and the `normalMapped(_:scale:)` sugar. The CPU
/// half pins what the generator must return on surfaces whose basis is known
/// by hand (a quad's tangent is the direction u increases in, a mirrored quad
/// flips only its handedness), plus the alignment, orthogonality, and
/// determinism rules everything downstream leans on. The Metal-gated probes
/// pin the draw contract end to end: a map bends shading on flat geometry
/// (against the mapless counterfactual), green pushes toward image-up (the
/// glTF-style convention the generated basis serves), the tangent bakes
/// through the model transform, and `normalScale: 0` takes the plain textured
/// path byte for byte.
@Suite
@MainActor
struct MeshTangentTests {

    /// A single quad in the x-y plane facing +z, consistently wound (CCW seen
    /// from +z, agreeing with its normals), u increasing along +x and v
    /// increasing along -y (the image convention: v runs down), as two
    /// triangles sharing vertices, the welded case.
    private func quad(flipU: Bool = false) -> Mesh {
        let u0 = flipU ? 1.0 : 0.0, u1 = flipU ? 0.0 : 1.0
        return Mesh(
            positions: [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(0, 1, 0)],
            normals: [Vector3](repeating: Vector3(0, 0, 1), count: 4),
            indices: [0, 1, 2, 0, 2, 3],
            uvs: [Vector2(u0, 1), Vector2(u1, 1), Vector2(u1, 0), Vector2(u0, 0)])
    }

    @Test func quadTangentPointsAlongIncreasingU() {
        let mesh = quad().generatingTangents()
        #expect(mesh.tangents.count == mesh.positions.count)
        for t in mesh.tangents {
            // u increases along +x, so the tangent is +x exactly.
            #expect(abs(t.direction.x - 1) < 1e-4)
            #expect(abs(t.direction.y) < 1e-4)
            #expect(abs(t.direction.z) < 1e-4)
        }
        // No seams in one flat quad: nothing splits, the index list survives.
        #expect(mesh.positions.count == 4)
        #expect(mesh.indices == [0, 1, 2, 0, 2, 3])
    }

    @Test func mirroredUVsFlipOnlyTheHandedness() {
        let plain = quad().generatingTangents()
        let mirrored = quad(flipU: true).generatingTangents()
        // Mirrored u: the tangent runs the other way and the handedness flips
        // with it, so the bitangent (v's direction on the surface) is unchanged.
        for t in mirrored.tangents {
            #expect(abs(t.direction.x + 1) < 1e-4)
        }
        let s0 = plain.tangents[0].handedness
        let s1 = mirrored.tangents[0].handedness
        #expect(abs(abs(s0) - 1) < 1e-6)
        #expect(abs(abs(s1) - 1) < 1e-6)
        #expect(s0 == -s1)
    }

    @Test func quadBitangentPointsTowardImageUp() {
        // The convention this pins is the load-bearing one: MikkTSpace's
        // handedness * (normal × tangent) points toward *decreasing* v, i.e.
        // up the map image, which is exactly what makes green-up
        // (OpenGL-convention, glTF-style) normal maps light correctly. For
        // this quad v increases along -y, so the bitangent must be +y.
        let mesh = quad().generatingTangents()
        let t = mesh.tangents[0]
        let n = Vector3(0, 0, 1)
        let b = n.cross(t.direction) * t.handedness
        #expect(abs(b.y - 1) < 1e-4)
        #expect(abs(b.x) < 1e-4)
    }

    @Test func sphereTangentsAreUnitAndOrthogonal() {
        let mesh = Mesh.sphere(radius: 1, segments: 24, rings: 12).generatingTangents()
        #expect(mesh.tangents.count == mesh.positions.count)
        var checked = 0
        for i in 0..<mesh.positions.count {
            let t = mesh.tangents[i]
            let len = t.direction.length
            #expect(abs(len - 1) < 1e-3)
            #expect(abs(t.handedness).isEqual(to: 1))
            // Perpendicular to the vertex normal it was built against.
            let dot = t.direction.dot(mesh.normals[i])
            #expect(abs(dot) < 2e-3)
            checked += 1
        }
        #expect(checked > 0)
    }

    @Test func generationIsDeterministic() {
        let a = Mesh.sphere(radius: 1, segments: 16, rings: 8).generatingTangents()
        let b = Mesh.sphere(radius: 1, segments: 16, rings: 8).generatingTangents()
        #expect(a.positions.count == b.positions.count)
        #expect(a.indices == b.indices)
        for (ta, tb) in zip(a.tangents, b.tangents) {
            #expect(ta == tb)
        }
    }

    @Test func meshWithoutUVsComesBackUnchanged() {
        var mesh = quad()
        mesh.uvs = []
        let out = mesh.generatingTangents()
        #expect(out.tangents.isEmpty)
        #expect(out.positions.count == mesh.positions.count)
    }

    @Test func normalMappedAttachesMapAndTangents() {
        let map = Image(width: 4, height: 4, color: Color(red: 0.5, green: 0.5, blue: 1, alpha: 1))
        let mesh = quad().normalMapped(map, scale: 0.75)
        #expect(mesh.material?.normalTexture != nil)
        #expect(mesh.material?.normalScale == 0.75)
        #expect(mesh.tangents.count == mesh.positions.count)
        // Composes with textured() in either order: the base texture setter
        // keeps the normal side.
        let base = Image(width: 4, height: 4, color: .white)
        let both = quad().normalMapped(map).textured(base)
        #expect(both.material?.texture != nil)
        #expect(both.material?.normalTexture != nil)
    }

    // MARK: Render probes

    private func pixel(of image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        if let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                               bytesPerRow: w * 4, space: space, bitmapInfo: info) {
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        let i = (y * w + x) * 4
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
    }

    private func imageBytes(_ image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        if let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                               bytesPerRow: w * 4, space: space, bitmapInfo: info) {
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return data
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aNormalMapBendsShadingOnFlatGeometry() throws {
        // The split map tilts the left half's normals toward -x and the right
        // half's toward +x; under a light from the right the two halves must
        // shade apart, while the mapless counterfactual shades them equal.
        let mapped = try #require(OllinApp.image(of: TangentProbe.make(.split), frame: 1))
        let left = pixel(of: mapped, x: 64, y: 128).r
        let right = pixel(of: mapped, x: 192, y: 128).r
        #expect(right - left > 40, "expected the +x-tilted half far brighter, got \(left) vs \(right)")
        let control = try #require(OllinApp.image(of: TangentProbe.make(.mapless), frame: 1))
        let cl = pixel(of: control, x: 64, y: 128).r
        let cr = pixel(of: control, x: 192, y: 128).r
        #expect(abs(cl - cr) <= 2, "the flat control must shade evenly, got \(cl) vs \(cr)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func greenBendsTowardImageUp() throws {
        // The convention probe: under a light from above, a green-heavy map
        // (normals tilted toward image-up, the glTF-style green-up encoding)
        // must brighten the surface, and a green-light map must darken it,
        // bracketing the flat map. This is what pins the whole basis chain:
        // MikkTSpace handedness, the packed vertex tangent, and the shader's
        // sign * cross(N, T) bitangent agreeing end to end.
        let up = try #require(OllinApp.image(of: TangentProbe.make(.greenHigh), frame: 1))
        let flat = try #require(OllinApp.image(of: TangentProbe.make(.flat), frame: 1))
        let down = try #require(OllinApp.image(of: TangentProbe.make(.greenLow), frame: 1))
        let bUp = pixel(of: up, x: 128, y: 128).r
        let bFlat = pixel(of: flat, x: 128, y: 128).r
        let bDown = pixel(of: down, x: 128, y: 128).r
        #expect(bUp > bFlat + 20, "green-up must brighten under a light from above: \(bUp) vs \(bFlat)")
        #expect(bDown < bFlat - 20, "green-down must darken under a light from above: \(bDown) vs \(bFlat)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func tangentsBakeThroughTheModelTransform() throws {
        // A half-turn about z swaps the halves' places *and* their tilts, so a
        // correctly baked tangent keeps the bright side on the right; only the
        // failure this pins (tangents left in mesh space while the geometry
        // rotates) flips it to the left. Verified red by exactly that sabotage.
        let turned = try #require(OllinApp.image(of: TangentProbe.make(.splitTurned), frame: 1))
        #expect(pixel(of: turned, x: 192, y: 128).r - pixel(of: turned, x: 64, y: 128).r > 40,
                "the turned quad must stay bright on the right")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func scaleZeroIsByteIdenticalToTheMaplessTexturedMesh() throws {
        // normalScale 0 is the off switch: the drawer routes the mesh down the
        // plain textured pipeline, so the frame is byte-identical to the same
        // mesh with no normal map attached at all.
        let off = try #require(OllinApp.image(of: TangentProbe.make(.scaleZero), frame: 1))
        let none = try #require(OllinApp.image(of: TangentProbe.make(.texturedOnly), frame: 1))
        #expect(imageBytes(off) == imageBytes(none))
    }
}

/// The camera-facing quad the tangent render probes draw: uvs with u along +x
/// and v running down (top-left origin), one directional light per mode, a
/// solid or split authored normal map.
private final class TangentProbe: Sketch {
    enum Mode { case mapless, split, splitTurned, flat, greenHigh, greenLow, scaleZero, texturedOnly }
    var mode = Mode.mapless

    static func make(_ mode: Mode) -> TangentProbe {
        let probe = TangentProbe()
        probe.mode = mode
        return probe
    }

    override var canvasSize: CanvasSize { .square(256) }

    private func solidMap(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Image {
        var bytes = [UInt8](repeating: 0, count: 8 * 8 * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            bytes[i] = r; bytes[i + 1] = g; bytes[i + 2] = b; bytes[i + 3] = 255
        }
        return Image(width: 8, height: 8, premultipliedRGBA: bytes)!
    }

    /// Left half tilts -x (red 25), right half +x (red 230), z at 204.
    private func splitMap() -> Image {
        var bytes = [UInt8](repeating: 0, count: 8 * 8 * 4)
        for y in 0..<8 {
            for x in 0..<8 {
                let i = (y * 8 + x) * 4
                bytes[i] = x < 4 ? 25 : 230
                bytes[i + 1] = 127
                bytes[i + 2] = 204
                bytes[i + 3] = 255
            }
        }
        return Image(width: 8, height: 8, premultipliedRGBA: bytes)!
    }

    private func quad() -> Mesh {
        Mesh(positions: [Vector3(-1, -1, 0), Vector3(1, -1, 0),
                         Vector3(1, 1, 0), Vector3(-1, 1, 0)],
             normals: [.unitZ, .unitZ, .unitZ, .unitZ],
             indices: [0, 1, 2, 0, 2, 3],
             uvs: [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
    }

    override func draw() {
        background(.black)
        camera(.orbiting(radius: 3))
        fill(.white)
        var mesh = quad()
        switch mode {
        case .mapless:
            directionalLight(.white, direction: Vector3(-1, 0, -0.5))
        case .split, .splitTurned:
            directionalLight(.white, direction: Vector3(-1, 0, -0.5))
            mesh = mesh.normalMapped(splitMap())
        case .flat:
            directionalLight(.white, direction: Vector3(0, -1, -0.5))
            mesh = mesh.normalMapped(solidMap(127, 127, 255))
        case .greenHigh:
            directionalLight(.white, direction: Vector3(0, -1, -0.5))
            mesh = mesh.normalMapped(solidMap(127, 230, 204))
        case .greenLow:
            directionalLight(.white, direction: Vector3(0, -1, -0.5))
            mesh = mesh.normalMapped(solidMap(127, 25, 204))
        case .scaleZero:
            directionalLight(.white, direction: Vector3(-1, 0, -0.5))
            mesh = mesh.textured(solidMap(255, 255, 255)).normalMapped(splitMap(), scale: 0)
        case .texturedOnly:
            directionalLight(.white, direction: Vector3(-1, 0, -0.5))
            mesh = mesh.textured(solidMap(255, 255, 255))
        }
        if mode == .splitTurned { rotateZ(.pi) }
        drawMesh(mesh)
    }
}
