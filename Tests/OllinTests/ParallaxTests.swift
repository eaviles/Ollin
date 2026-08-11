import CoreGraphics
import Foundation
@testable import Ollin
import Testing

/// The height map's two consumers: parallax occlusion (per-pixel relief that
/// shifts what every map shows, geometry untouched) and CPU displacement
/// (`Mesh.displaced(by:scale:)`, the same image made true of the vertices).
/// The CPU half pins the attach rule, the shared white-at-the-surface datum,
/// the weld-aware move (a uv seam cannot tear), the normal recompute, and the
/// USD displacement round trip. The Metal-gated probes pin the march against
/// counterfactuals: content shifts toward the camera on both tangent axes
/// (the sign contract), the silhouette never moves (the technique's whole
/// envelope), a white map is the exact null on the same pipeline, and scale 0
/// routes down the plain textured path byte for byte.
@Suite
@MainActor
struct ParallaxTests {

    // MARK: - Authoring helpers

    private func solidMap(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Image {
        var bytes = [UInt8](repeating: 255, count: 8 * 8 * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            bytes[i] = r; bytes[i + 1] = g; bytes[i + 2] = b
        }
        return Image(width: 8, height: 8, premultipliedRGBA: bytes)!
    }

    /// A horizontal 0…255 gradient in every channel, for seam tests.
    private func gradientMap(size: Int = 32) -> Image {
        var bytes = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let v = UInt8(x * 255 / (size - 1))
                let i = (y * size + x) * 4
                bytes[i] = v; bytes[i + 1] = v; bytes[i + 2] = v
            }
        }
        return Image(width: size, height: size, premultipliedRGBA: bytes)!
    }

    // MARK: - The convenience

    @Test func parallaxMappedAttachesTheMapAndGeneratesTangents() throws {
        let height = solidMap(60, 60, 60)
        let mesh = Mesh.sphere(radius: 1, segments: 8, rings: 4).parallaxMapped(height, scale: 0.12)
        let m = try #require(mesh.material)
        #expect(m.heightTexture === height)
        #expect(abs(m.heightScale - 0.12) < 1e-12)
        #expect(mesh.tangents.count == mesh.positions.count,
                "parallaxMapped must set up the tangent basis the march projects through")
        // Composes with the rest of the set in either order.
        let dressed = mesh.textured(solidMap(200, 150, 100))
        #expect(dressed.material?.heightTexture === height)
        #expect(dressed.material?.texture != nil)
    }

    // MARK: - CPU displacement

    @Test func displacedKeepsWhiteAtTheAuthoredSurface() throws {
        // White is the surface itself (the parallax datum): displacing by an
        // all-white map moves nothing measurable at any scale.
        let sphere = Mesh.sphere(radius: 10, segments: 16, rings: 8)
        let moved = sphere.displaced(by: solidMap(255, 255, 255), scale: 50)
        for (a, b) in zip(sphere.positions, moved.positions) {
            #expect((a - b).length < 1e-9, "white must stay at the surface")
        }
    }

    @Test func displacedCarvesDarkRegionsInByScale() throws {
        // Black carves in by the full scale along the normal: a sphere's every
        // vertex pulls inward, radius 10 to radius 7.
        let sphere = Mesh.sphere(radius: 10, segments: 16, rings: 8)
        let carved = sphere.displaced(by: solidMap(0, 0, 0), scale: 3)
        for p in carved.positions {
            #expect(abs(p.length - 7) < 1e-3, "black must carve in by scale, got radius \(p.length)")
        }
        // And the recomputed normals still point outward on the shrunken sphere.
        for (p, n) in zip(carved.positions, carved.normals) where p.length > 1e-6 {
            #expect(p.normalized.dot(n) > 0.9, "normals must be recomputed outward")
        }
    }

    @Test func displacedMovesSeamVerticesTogether() throws {
        // A sphere's uv seam holds coincident vertices with different uvs; a
        // gradient map samples different heights on the two sides. The welded
        // move must keep every coincident pair coincident (no tearing).
        let sphere = Mesh.sphere(radius: 5, segments: 24, rings: 12)
        let moved = sphere.displaced(by: gradientMap(), scale: 2)
        var byPosition: [String: Vector3] = [:]
        for (i, p) in sphere.positions.enumerated() {
            let key = "\(Float(p.x))/\(Float(p.y))/\(Float(p.z))"
            if let seen = byPosition[key] {
                #expect((seen - moved.positions[i]).length < 1e-9,
                        "coincident vertices must move as one")
            } else {
                byPosition[key] = moved.positions[i]
            }
        }
    }

    @Test func displacedRegeneratesTangentsAndKeepsTheMaterial() throws {
        let normalMap = solidMap(127, 127, 255)
        let mesh = Mesh.sphere(radius: 4, segments: 12, rings: 6).normalMapped(normalMap)
        let before = mesh.tangents
        let moved = mesh.displaced(by: gradientMap(), scale: 1)
        #expect(moved.tangents.count == moved.positions.count,
                "a carried tangent basis must be regenerated for the new shape")
        #expect(moved.material?.normalTexture === normalMap, "the material rides along")
        #expect(before.count == mesh.positions.count)
    }

    @Test func displacedWithoutUVsComesBackUnchanged() throws {
        var bare = Mesh.sphere(radius: 2, segments: 8, rings: 4)
        bare.uvs = []
        let moved = bare.displaced(by: solidMap(0, 0, 0), scale: 1)
        #expect(moved.positions == bare.positions)
    }

    // MARK: - The USD round trip

    @Test func usdzRoundTripKeepsTheHeightMap() throws {
        var mesh = Mesh.plane(width: 2, depth: 2)
        var material = MeshMaterial(baseColor: .white, texture: solidMap(200, 150, 100))
        material.heightTexture = solidMap(90, 90, 90)
        material.heightScale = 0.12
        mesh.material = material
        var node = SceneNode(name: "panel")
        node.mesh = mesh

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-parallax-\(UUID().uuidString).usdz")
        #expect(Scene(nodes: [node]).write(to: url))
        defer { try? FileManager.default.removeItem(at: url) }
        let back = try #require(Scene(contentsOf: url))
        func firstMesh(_ nodes: [SceneNode]) -> Mesh? {
            for n in nodes {
                if let mesh = n.mesh { return mesh }
                if let hit = firstMesh(n.children) { return hit }
            }
            return nil
        }
        let m = try #require(firstMesh(back.nodes)?.material)
        let heightBack = try #require(m.heightTexture)
        let px = try #require(heightBack.premultipliedPixels())
        #expect(px[0] == 90, "the height map's channel must survive the trip, got \(px[0])")
        #expect(abs(m.heightScale - 0.12) < 1e-5,
                "heightScale must round-trip through the tap's channel scale")
        // And the read scene's mesh must carry the tangent basis the parallax
        // march needs (the reader generates it for a displacement connection).
        #expect(firstMesh(back.nodes)?.tangents.count == firstMesh(back.nodes)?.positions.count)
    }

    @Test func aHeightMappedPackagePassesTheSystemValidator() throws {
        let checker = URL(fileURLWithPath: "/usr/bin/usdchecker")
        guard FileManager.default.isExecutableFile(atPath: checker.path) else { return }

        var mesh = Mesh.plane(width: 2, depth: 2)
        var material = MeshMaterial(baseColor: .white, texture: solidMap(200, 150, 100))
        material.heightTexture = solidMap(90, 90, 90)
        material.heightScale = 0.08
        mesh.material = material
        var node = SceneNode(name: "panel")
        node.mesh = mesh

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-parallax-\(UUID().uuidString).usdz")
        #expect(Scene(nodes: [node]).write(to: url))
        defer { try? FileManager.default.removeItem(at: url) }

        let process = Process()
        process.executableURL = checker
        process.arguments = ["--arkit", url.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(),
                          as: UTF8.self)
        process.waitUntilExit()
        #expect(process.terminationStatus == 0,
                "usdchecker --arkit refused the height-mapped package:\n\(text)")
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

    /// The brightness-weighted centroid of pixels over a threshold.
    private func brightCentroid(of image: CGImage, threshold: Int = 140) -> (x: Double, y: Double)? {
        let bytes = imageBytes(image)
        var sx = 0.0, sy = 0.0, total = 0.0
        for y in 0..<image.height {
            for x in 0..<image.width {
                let i = (y * image.width + x) * 4
                let v = Int(bytes[i])
                if v > threshold {
                    sx += Double(x * v); sy += Double(y * v); total += Double(v)
                }
            }
        }
        guard total > 0 else { return nil }
        return (sx / total, sy / total)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func parallaxShiftsContentTowardTheCamera() throws {
        // A bright dot at the center of a quad, over an all-black height map
        // (the whole surface recessed by the full scale). Seen obliquely, the
        // recessed content must appear shifted *toward* the camera's side of
        // the quad on both tangent axes; the flat control holds it centered.
        // This is the sign contract for the tangent-frame projection: u
        // against the eye, v with the opposite sign (the bitangent points up
        // the image, v grows down it). A flipped component fails one axis.
        let flat = try #require(OllinApp.image(of: ParallaxProbe.make(.dotFlatSide), frame: 1))
        let shifted = try #require(OllinApp.image(of: ParallaxProbe.make(.dotDeepSide), frame: 1))
        let c0 = try #require(brightCentroid(of: flat))
        let c1 = try #require(brightCentroid(of: shifted))
        #expect(c1.x - c0.x > 4,
                "camera on +x: the recessed dot must shift toward it, got \(c0) vs \(c1)")

        let flatUp = try #require(OllinApp.image(of: ParallaxProbe.make(.dotFlatAbove), frame: 1))
        let shiftedUp = try #require(OllinApp.image(of: ParallaxProbe.make(.dotDeepAbove), frame: 1))
        let u0 = try #require(brightCentroid(of: flatUp))
        let u1 = try #require(brightCentroid(of: shiftedUp))
        #expect(u0.y - u1.y > 4,
                "camera above: the recessed dot must shift up the canvas, got \(u0) vs \(u1)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func parallaxNeverMovesTheSilhouette() throws {
        // The whole envelope in one probe: a strongly parallax-mapped sphere
        // and its flat control cover exactly the same pixels. Parallax shifts
        // shading only; the outline is the geometry's, and only
        // displaced(by:scale:) changes that.
        let mapped = try #require(OllinApp.image(of: ParallaxProbe.make(.sphereMapped), frame: 1))
        let control = try #require(OllinApp.image(of: ParallaxProbe.make(.sphereControl), frame: 1))
        let a = imageBytes(mapped), b = imageBytes(control)
        var maskDiffers = 0
        for i in stride(from: 0, to: min(a.count, b.count), by: 4) {
            // Background pixels are exact (nothing drew there); a pixel is
            // "covered" when it differs from the black background.
            let coveredA = a[i] > 8 || a[i + 1] > 8 || a[i + 2] > 8
            let coveredB = b[i] > 8 || b[i + 1] > 8 || b[i + 2] > 8
            if coveredA != coveredB { maskDiffers += 1 }
        }
        #expect(maskDiffers == 0, "the silhouette must not move, \(maskDiffers) pixels changed sides")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aWhiteHeightMapIsTheExactNull() throws {
        // White is the surface plane: the march exits at the entry sample and
        // hands the uv back unchanged, so the same pipeline with the gate up
        // renders byte-identically to the gate down. (Both probes carry a
        // white occlusion map so both ride the surface-mapped pipeline; only
        // the parallax gate differs.)
        let on = try #require(OllinApp.image(of: ParallaxProbe.make(.whiteHeight), frame: 1))
        let off = try #require(OllinApp.image(of: ParallaxProbe.make(.whiteHeightScaleZero), frame: 1))
        #expect(imageBytes(on) == imageBytes(off))
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func scaleZeroRoutesDownThePlainTexturedPath() throws {
        // heightScale 0 is the off switch: the drawer never raises the gate,
        // so the frame is byte-identical to the same mesh with no height map
        // attached at all (the plain textured pipeline).
        let off = try #require(OllinApp.image(of: ParallaxProbe.make(.scaleZero), frame: 1))
        let none = try #require(OllinApp.image(of: ParallaxProbe.make(.texturedOnly), frame: 1))
        #expect(imageBytes(off) == imageBytes(none))
    }
}

/// The parallax render probes: a camera-facing quad or a sphere, one
/// arrangement per mode.
private final class ParallaxProbe: Sketch {
    enum Mode {
        case dotFlatSide, dotDeepSide, dotFlatAbove, dotDeepAbove
        case sphereMapped, sphereControl
        case whiteHeight, whiteHeightScaleZero
        case scaleZero, texturedOnly
    }
    var mode = Mode.dotFlatSide

    static func make(_ mode: Mode) -> ParallaxProbe {
        let probe = ParallaxProbe()
        probe.mode = mode
        return probe
    }

    override var canvasSize: CanvasSize { .square(256) }

    private func solid(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Image {
        var bytes = [UInt8](repeating: 255, count: 8 * 8 * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            bytes[i] = r; bytes[i + 1] = g; bytes[i + 2] = b
        }
        return Image(width: 8, height: 8, premultipliedRGBA: bytes)!
    }

    /// A bright dot centered on a dark field.
    private func dotTexture() -> Image {
        let size = 64
        var bytes = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let dx = Double(x) - 31.5, dy = Double(y) - 31.5
                let inside = dx * dx + dy * dy < 36
                let v: UInt8 = inside ? 255 : 20
                let i = (y * size + x) * 4
                bytes[i] = v; bytes[i + 1] = v; bytes[i + 2] = v
            }
        }
        return Image(width: size, height: size, premultipliedRGBA: bytes)!
    }

    /// Concentric height rings, for the silhouette probe's strong relief.
    private func ringHeight() -> Image {
        let size = 64
        var bytes = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let dx = Double(x) - 31.5, dy = Double(y) - 31.5
                let r = (dx * dx + dy * dy).squareRoot()
                let v = UInt8(127.5 + 127.5 * cos(r * 0.6))
                let i = (y * size + x) * 4
                bytes[i] = v; bytes[i + 1] = v; bytes[i + 2] = v
            }
        }
        return Image(width: size, height: size, premultipliedRGBA: bytes)!
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
        fill(Color(white: 0.9))
        directionalLight(.white, direction: Vector3(0, 0, -1))
        switch mode {
        case .dotFlatSide, .dotDeepSide:
            camera(.orbiting(radius: 3, azimuth: 0.6))
            var mesh = quad().textured(dotTexture())
            if mode == .dotDeepSide {
                mesh = mesh.parallaxMapped(solid(0, 0, 0), scale: 0.2)
            }
            drawMesh(mesh)
        case .dotFlatAbove, .dotDeepAbove:
            camera(.orbiting(radius: 3, elevation: 0.6))
            var mesh = quad().textured(dotTexture())
            if mode == .dotDeepAbove {
                mesh = mesh.parallaxMapped(solid(0, 0, 0), scale: 0.2)
            }
            drawMesh(mesh)
        case .sphereMapped, .sphereControl:
            camera(.orbiting(radius: 4, azimuth: 0.4))
            var mesh = Mesh.sphere(radius: 1.2, segments: 32, rings: 16)
                .textured(dotTexture())
            if mode == .sphereMapped {
                mesh = mesh.parallaxMapped(ringHeight(), scale: 0.25)
            }
            drawMesh(mesh)
        case .whiteHeight, .whiteHeightScaleZero:
            camera(.orbiting(radius: 3, azimuth: 0.5))
            let scale = mode == .whiteHeight ? 0.3 : 0.0
            let mesh = quad().textured(dotTexture())
                .surfaceMapped(occlusion: solid(255, 255, 255))
                .parallaxMapped(solid(255, 255, 255), scale: scale)
            drawMesh(mesh)
        case .scaleZero:
            camera(.orbiting(radius: 3, azimuth: 0.5))
            drawMesh(quad().textured(dotTexture()).parallaxMapped(solid(0, 0, 0), scale: 0))
        case .texturedOnly:
            camera(.orbiting(radius: 3, azimuth: 0.5))
            drawMesh(quad().textured(dotTexture()))
        }
    }
}
