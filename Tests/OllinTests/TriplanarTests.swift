import CoreGraphics
import Foundation
@testable import Ollin
import Testing

/// Triplanar projection: the base texture (and normal map) read by world
/// position along the three axes, blended by the surface normal, for meshes
/// with no uvs at all. The CPU tests pin the attach rule (no uvs, no tangents
/// needed) and the off switch; the Metal-gated probes pin the projection
/// against counterfactuals: a no-uv mesh really wears the picture, each axis
/// frame reads upright and unmirrored from either side (the u sign flip),
/// the top projection follows the same frame, the 45-degree seam *mixes* the
/// two projections instead of hard-picking one, the projected normal map
/// pushes the lighting in the frame's own directions with no tangent basis,
/// and the projection is anchored to the world, not the mesh (the documented
/// envelope, stated as a test). Byte-identity for uv-mapped meshes is the
/// snapshot suite's job (surface-maps / parallax-relief / normal-maps hold
/// unrecorded).
@Suite
@MainActor
struct TriplanarTests {

    // MARK: - The convenience

    @Test func triplanarTexturedAttachesTheProjection() throws {
        let tex = TriplanarProbe.solid(200, 150, 100)
        let bumps = TriplanarProbe.solid(127, 127, 255)
        var bare = Mesh.sphere(radius: 1, segments: 8, rings: 4)
        bare.uvs = []
        let mesh = bare.triplanarTextured(tex, normal: bumps, scale: 90, normalScale: 0.8)
        let m = try #require(mesh.material)
        #expect(m.texture === tex)
        #expect(m.normalTexture === bumps)
        #expect(abs(m.triplanarScale - 90) < 1e-12)
        #expect(abs(m.normalScale - 0.8) < 1e-12)
        #expect(mesh.tangents.isEmpty,
                "the projection carries its own frames; no tangent basis is generated")
        #expect(mesh.uvs.isEmpty, "and no uvs are needed or invented")
    }

    // MARK: - Render probes

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

    /// The centroid of pixels whose dominant channel is `channel` (0 r, 1 g,
    /// 2 b), counting only clearly-colored pixels.
    private func channelCentroid(of image: CGImage, channel: Int) -> (x: Double, y: Double)? {
        let bytes = imageBytes(image)
        var sx = 0.0, sy = 0.0, total = 0.0
        for y in 0..<image.height {
            for x in 0..<image.width {
                let i = (y * image.width + x) * 4
                let rgb = [Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2])]
                let top = rgb[channel]
                guard top > 100 else { continue }
                let others = rgb.enumerated().filter { $0.offset != channel }.map(\.element)
                if others.allSatisfy({ top > $0 + 60 }) {
                    sx += Double(x); sy += Double(y); total += 1
                }
            }
        }
        guard total > 20 else { return nil }
        return (sx / total, sy / total)
    }

    /// Mean brightness of the block centered at the canvas center.
    private func centerMean(of image: CGImage, half: Int = 24) -> Double {
        let bytes = imageBytes(image)
        let cx = image.width / 2, cy = image.height / 2
        var sum = 0.0, n = 0.0
        for y in (cy - half)..<(cy + half) {
            for x in (cx - half)..<(cx + half) {
                let i = (y * image.width + x) * 4
                sum += Double(Int(bytes[i]) + Int(bytes[i + 1]) + Int(bytes[i + 2])) / 3
                n += 1
            }
        }
        return sum / n
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aMeshWithNoUVsWearsThePicture() throws {
        // The point of the feature: a marched metaball skin (no uvs, no
        // tangents) shows the texture's colors; the scale-0 control draws the
        // plain solid surface, so it shows neither.
        let on = try #require(OllinApp.image(of: TriplanarProbe.make(.blob), frame: 1))
        let off = try #require(OllinApp.image(of: TriplanarProbe.make(.blobScaleZero), frame: 1))
        #expect(channelCentroid(of: on, channel: 0) != nil, "the red half must arrive")
        #expect(channelCentroid(of: on, channel: 1) != nil, "the green half must arrive")
        #expect(channelCentroid(of: off, channel: 0) == nil, "the control stays plain")
        #expect(channelCentroid(of: off, channel: 1) == nil)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func scaleZeroIsTheOffSwitch() throws {
        // triplanarScale 0 means uv mapping as usual; with no uvs either, the
        // mesh draws on the plain solid path, byte-identical to the same mesh
        // with no material at all.
        let off = try #require(OllinApp.image(of: TriplanarProbe.make(.blobScaleZero), frame: 1))
        let none = try #require(OllinApp.image(of: TriplanarProbe.make(.blobBare), frame: 1))
        #expect(imageBytes(off) == imageBytes(none))
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theProjectionReadsUprightAndUnmirroredFromBothSides() throws {
        // A quadrant texture (red top-left, green top-right, blue bottom-left)
        // on a z-facing wall covered by exactly one tile. From the front the
        // image reads as authored; from the *back* the u sign flips with the
        // face, so it still reads unmirrored: red stays screen-left of green,
        // red stays above blue. A dropped sign flip mirrors the back view and
        // fails it.
        for mode in [TriplanarProbe.Mode.wallFront, .wallBack] {
            let shot = try #require(OllinApp.image(of: TriplanarProbe.make(mode), frame: 1))
            let red = try #require(channelCentroid(of: shot, channel: 0), "\(mode)")
            let green = try #require(channelCentroid(of: shot, channel: 1), "\(mode)")
            let blue = try #require(channelCentroid(of: shot, channel: 2), "\(mode)")
            #expect(green.x - red.x > 8, "\(mode): red must sit screen-left of green")
            #expect(blue.y - red.y > 8, "\(mode): red must sit screen-above blue")
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theTopProjectionFollowsTheSameFrame() throws {
        // The same quadrant texture on a floor seen from above: u runs +x,
        // v runs +z (image north is -z), so from a camera on the +z side
        // looking down, the image reads upright: red far-left, green
        // far-right, blue near-left.
        let shot = try #require(OllinApp.image(of: TriplanarProbe.make(.floorAbove), frame: 1))
        let red = try #require(channelCentroid(of: shot, channel: 0))
        let green = try #require(channelCentroid(of: shot, channel: 1))
        let blue = try #require(channelCentroid(of: shot, channel: 2))
        #expect(green.x - red.x > 8, "u must run with +x on the top projection")
        #expect(blue.y - red.y > 8, "v must run with +z (the far side is image top)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theSeamMixesTheTwoProjectionsInsteadOfPickingOne() throws {
        // On a sphere's 45-degree meridian the x and z projections carry equal
        // weight, and the texture is arranged so one reads red there and the
        // other green: every center pixel must hold *both* channels (the
        // blend), not one or the other (a hard pick). The control camera faces
        // +z, where the weight is all z's and pixels stay pure.
        let seam = try #require(OllinApp.image(of: TriplanarProbe.make(.sphereSeam), frame: 1))
        let bytes = imageBytes(seam)
        let w = seam.width
        var minMix = 255
        for y in (seam.height / 2 - 8)..<(seam.height / 2 + 8) {
            for x in (w / 2 - 8)..<(w / 2 + 8) {
                let i = (y * w + x) * 4
                minMix = min(minMix, min(Int(bytes[i]), Int(bytes[i + 1])))
            }
        }
        #expect(minMix > 60,
                "every seam pixel must mix red and green; a hard axis pick reads \(minMix)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theNormalMapPushesTheLightingAlongTheFrameAxes() throws {
        // A flat wall, no uvs and no tangents anywhere: the projected normal
        // map alone bends the shading. A map tilted toward image-right reads
        // brighter under light arriving from +x than its image-left twin (the
        // u axis), and a green-up map reads brighter under light from above
        // than its green-down twin (the green-up convention on the projected
        // frame). Each sign carries one comparison.
        let right = try #require(OllinApp.image(of: TriplanarProbe.make(.bumpRight), frame: 1))
        let left = try #require(OllinApp.image(of: TriplanarProbe.make(.bumpLeft), frame: 1))
        #expect(centerMean(of: right) - centerMean(of: left) > 20,
                "an image-right tilt must catch the +x light, got \(centerMean(of: right)) vs \(centerMean(of: left))")

        let up = try #require(OllinApp.image(of: TriplanarProbe.make(.bumpUp), frame: 1))
        let down = try #require(OllinApp.image(of: TriplanarProbe.make(.bumpDown), frame: 1))
        #expect(centerMean(of: up) - centerMean(of: down) > 20,
                "green must mean image-up on the projected frame, got \(centerMean(of: up)) vs \(centerMean(of: down))")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theProjectionIsAnchoredToTheWorldNotTheMesh() throws {
        // The documented envelope, stated: the pattern belongs to the world,
        // so a translated mesh slides through it. Where both renders cover a
        // pixel with the same flat quadrant, the color is identical even
        // though the mesh underneath moved half a tile.
        let still = try #require(OllinApp.image(of: TriplanarProbe.make(.anchorStill), frame: 1))
        let moved = try #require(OllinApp.image(of: TriplanarProbe.make(.anchorMoved), frame: 1))
        let a = imageBytes(still), b = imageBytes(moved)
        let w = still.width
        // A block inside the red quadrant, away from every boundary.
        var differing = 0
        for y in (still.height / 4 - 10)..<(still.height / 4 + 10) {
            for x in (w / 4 - 10)..<(w / 4 + 10) {
                let i = (y * w + x) * 4
                if a[i] != b[i] || a[i + 1] != b[i + 1] || a[i + 2] != b[i + 2] { differing += 1 }
            }
        }
        #expect(differing == 0,
                "the pattern must hold its world position under a moved mesh, \(differing) pixels moved with it")
    }

    @Test func theSpatialExporterNotesAndSkipsTheProjection() throws {
        // Neither file format has a triplanar slot, so the recorder strips the
        // projected maps (saying so once) and the surface exports in its plain
        // color rather than wearing a uv texture it never mapped through.
        let scene = OllinApp.spatialScene(of: TriplanarProbe.make(.blob), frame: 1)
        func firstMesh(_ nodes: [SceneNode]) -> Mesh? {
            for n in nodes {
                if let mesh = n.mesh { return mesh }
                if let hit = firstMesh(n.children) { return hit }
            }
            return nil
        }
        let mesh = try #require(firstMesh(scene.nodes))
        #expect(mesh.material?.texture == nil, "the projected base map must stay behind")
        #expect(mesh.material?.normalTexture == nil)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func twoRendersAreByteIdentical() throws {
        let a = try #require(OllinApp.image(of: TriplanarProbe.make(.blob), frame: 1))
        let b = try #require(OllinApp.image(of: TriplanarProbe.make(.blob), frame: 1))
        #expect(imageBytes(a) == imageBytes(b))
    }
}

/// The triplanar render probes: a metaball blob, a one-tile wall or floor, a
/// seam-facing sphere, or the world-anchor pair, one arrangement per mode.
private final class TriplanarProbe: Sketch {
    enum Mode {
        case blob, blobScaleZero, blobBare
        case wallFront, wallBack, floorAbove
        case sphereSeam
        case bumpRight, bumpLeft, bumpUp, bumpDown
        case anchorStill, anchorMoved
    }
    var mode = Mode.blob

    static func make(_ mode: Mode) -> TriplanarProbe {
        let probe = TriplanarProbe()
        probe.mode = mode
        return probe
    }

    override var canvasSize: CanvasSize { .square(256) }

    static func solid(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Image {
        var bytes = [UInt8](repeating: 255, count: 8 * 8 * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            bytes[i] = r; bytes[i + 1] = g; bytes[i + 2] = b
        }
        return Image(width: 8, height: 8, premultipliedRGBA: bytes)!
    }

    /// Quadrants: red top-left, green top-right, blue bottom-left, gray
    /// bottom-right.
    private func quadrants() -> Image {
        let size = 64
        var bytes = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let i = (y * size + x) * 4
                let rightHalf = x >= size / 2, bottomHalf = y >= size / 2
                let c: (UInt8, UInt8, UInt8) = bottomHalf
                    ? (rightHalf ? (128, 128, 128) : (0, 0, 255))
                    : (rightHalf ? (0, 255, 0) : (255, 0, 0))
                bytes[i] = c.0; bytes[i + 1] = c.1; bytes[i + 2] = c.2
            }
        }
        return Image(width: size, height: size, premultipliedRGBA: bytes)!
    }

    /// Left half red, right half green, full height (the seam probe's split).
    private func halves() -> Image {
        let size = 64
        var bytes = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let i = (y * size + x) * 4
                if x >= size / 2 { bytes[i] = 0; bytes[i + 1] = 255; bytes[i + 2] = 0 }
                else { bytes[i] = 255; bytes[i + 1] = 0; bytes[i + 2] = 0 }
            }
        }
        return Image(width: size, height: size, premultipliedRGBA: bytes)!
    }

    /// A z-facing wall covered by exactly one tile at scale 2: x, y in
    /// (0.1, 1.9), so u and v stay inside (0, 1) with no wrap seam. The
    /// `facing` sign picks which way its normal points (a closed mesh's
    /// visible faces always point at the viewer, which is the side the
    /// projection's u flip keys on).
    private func wall(facing: Double = 1) -> Mesh {
        Mesh(positions: [Vector3(0.1, 0.1, 0), Vector3(1.9, 0.1, 0),
                         Vector3(1.9, 1.9, 0), Vector3(0.1, 1.9, 0)],
             normals: [Vector3](repeating: Vector3(0, 0, facing), count: 4),
             indices: [0, 1, 2, 0, 2, 3])
    }

    /// The same one-tile patch lying flat (+y up), x, z in (0.1, 1.9).
    private func floor() -> Mesh {
        Mesh(positions: [Vector3(0.1, 0, 1.9), Vector3(1.9, 0, 1.9),
                         Vector3(1.9, 0, 0.1), Vector3(0.1, 0, 0.1)],
             normals: [.unitY, .unitY, .unitY, .unitY],
             indices: [0, 1, 2, 0, 2, 3])
    }

    /// A wide z-facing sheet for the world-anchor pair.
    private func sheet() -> Mesh {
        Mesh(positions: [Vector3(-3, -3, 0), Vector3(3, -3, 0),
                         Vector3(3, 3, 0), Vector3(-3, 3, 0)],
             normals: [.unitZ, .unitZ, .unitZ, .unitZ],
             indices: [0, 1, 2, 0, 2, 3])
    }

    override func draw() {
        background(.black)
        fill(.white)
        switch mode {
        case .blob, .blobScaleZero, .blobBare:
            camera(.orbiting(target: .zero, radius: 5, azimuth: 0.4, elevation: 0.2))
            ambientLight(.white)
            var balls = Metaballs()
            balls.add(at: Vector3(-0.5, 0, 0), radius: 0.9)
            balls.add(at: Vector3(0.7, 0.3, 0.2), radius: 0.7)
            let skin = balls.mesh(resolution: 40)
            switch mode {
            case .blob: drawMesh(skin.triplanarTextured(halves(), scale: 1.2))
            case .blobScaleZero: drawMesh(skin.triplanarTextured(halves(), scale: 0))
            default: drawMesh(skin)
            }
        case .wallFront, .wallBack:
            let front = mode == .wallFront
            camera(.orbiting(target: Vector3(1, 1, 0), radius: 4, azimuth: front ? 0 : .pi))
            ambientLight(.white)
            drawMesh(wall(facing: front ? 1 : -1).triplanarTextured(quadrants(), scale: 2))
        case .floorAbove:
            camera(.orbiting(target: Vector3(1, 0, 1), radius: 4, elevation: 1.3))
            ambientLight(.white)
            drawMesh(floor().triplanarTextured(quadrants(), scale: 2))
        case .sphereSeam:
            // Facing the 45-degree meridian: the x and z projections weigh
            // equally there, and at scale 2 one reads the texture's green half
            // while the other reads its red half.
            camera(.orbiting(target: .zero, radius: 4, azimuth: .pi / 4))
            ambientLight(.white)
            var sphere = Mesh.sphere(radius: 1, segments: 64, rings: 32)
            sphere.uvs = []
            drawMesh(sphere.triplanarTextured(halves(), scale: 2))
        case .bumpRight, .bumpLeft, .bumpUp, .bumpDown:
            camera(.orbiting(target: Vector3(1, 1, 0), radius: 4))
            let direction = (mode == .bumpRight || mode == .bumpLeft)
                ? Vector3(-0.7, 0, -0.7) : Vector3(0, -0.7, -0.7)
            directionalLight(.white, direction: direction)
            let map: Image
            switch mode {
            case .bumpRight: map = Self.solid(255, 127, 255)
            case .bumpLeft: map = Self.solid(0, 127, 255)
            case .bumpUp: map = Self.solid(127, 255, 255)
            default: map = Self.solid(127, 0, 255)
            }
            drawMesh(wall().triplanarTextured(Self.solid(230, 230, 230), normal: map, scale: 2))
        case .anchorStill, .anchorMoved:
            camera(.orbiting(target: .zero, radius: 5))
            ambientLight(.white)
            withState {
                if mode == .anchorMoved { translate(1, 0, 0) }
                drawMesh(sheet().triplanarTextured(quadrants(), scale: 2))
            }
        }
    }
}
