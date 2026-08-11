import CoreGraphics
import Foundation
@testable import Ollin
import Testing

/// Detail maps: the finer second texture pair tiled across the base one
/// (`Mesh.detailMapped(_:normal:scale:strength:)`). The CPU half pins the
/// attach rule (tangents generated only when a detail normal needs them) and
/// the spatial exporter's honest strip. The Metal-gated probes pin the
/// contract against counterfactuals: the color map tiles at `detailScale`
/// (more tiles at a higher scale), a neutral 128-gray map is within a step of
/// the identity, a flat detail normal leaves the base relief untouched (the
/// reorientation's identity, which an overwrite blend fails), a tilted detail
/// composes *onto* the base tilt rather than replacing it, and strength 0
/// routes down the plain textured path byte for byte.
@Suite
@MainActor
struct DetailMapTests {

    // MARK: - Authoring helpers

    private func solidMap(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Image {
        var bytes = [UInt8](repeating: 255, count: 8 * 8 * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            bytes[i] = r; bytes[i + 1] = g; bytes[i + 2] = b
        }
        return Image(width: 8, height: 8, premultipliedRGBA: bytes)!
    }

    // MARK: - The convenience

    @Test func detailMappedAttachesThePair() throws {
        let color = solidMap(128, 128, 128)
        let normal = solidMap(127, 127, 255)
        let mesh = Mesh.sphere(radius: 1, segments: 8, rings: 4)
            .detailMapped(color, normal: normal, scale: 12, strength: 0.7)
        let m = try #require(mesh.material)
        #expect(m.detailTexture === color)
        #expect(m.detailNormalTexture === normal)
        #expect(abs(m.detailScale - 12) < 1e-12)
        #expect(abs(m.detailStrength - 0.7) < 1e-12)
        #expect(mesh.tangents.count == mesh.positions.count,
                "a detail normal map needs the tangent basis, generated on attach")
        // Composes with the rest of the set in either order.
        let dressed = mesh.textured(solidMap(200, 150, 100))
        #expect(dressed.material?.detailTexture === color)
        #expect(dressed.material?.texture != nil)
    }

    @Test func aColorOnlyDetailNeedsNoTangents() throws {
        let mesh = Mesh.sphere(radius: 1, segments: 8, rings: 4)
            .detailMapped(solidMap(128, 128, 128))
        #expect(mesh.tangents.isEmpty,
                "the color half tiles through uvs alone; no basis should be generated")
    }

    @Test func theSpatialExporterNotesAndSkipsDetail() throws {
        let scene = OllinApp.spatialScene(of: DetailProbe.make(.exportStrip), frame: 0)
        func firstMesh(_ nodes: [SceneNode]) -> Mesh? {
            for n in nodes {
                if let mesh = n.mesh { return mesh }
                if let hit = firstMesh(n.children) { return hit }
            }
            return nil
        }
        let m = try #require(firstMesh(scene.nodes)?.material)
        #expect(m.detailTexture == nil && m.detailNormalTexture == nil,
                "neither file format has a detail slot; the pair must strip with a note")
        #expect(m.texture != nil, "the base texture itself still exports")
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

    /// Count the dark-to-light transitions along the canvas's middle row,
    /// over the quad's pixels only (the near-black background is skipped).
    /// The dark stripes land ~97 and the light ones ~209 after the
    /// gamma-correct multiply, so 150 splits them with a wide margin.
    private func stripeTransitions(of image: CGImage) -> Int {
        let bytes = imageBytes(image)
        let y = image.height / 2
        var wasDark: Bool?
        var transitions = 0
        for x in 0..<image.width {
            let i = (y * image.width + x) * 4
            if bytes[i] < 25, bytes[i + 1] < 25, bytes[i + 2] < 25 { continue }
            let dark = bytes[i] < 150
            if let previous = wasDark, previous != dark { transitions += 1 }
            wasDark = dark
        }
        return transitions
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theDetailColorTilesAtItsOwnScale() throws {
        // One dark stripe per detail tile: at scale 6 the middle row crosses
        // about twice as many stripe edges as at scale 3, and the undetailed
        // control crosses none. Pins both the tiling and the repeat sampler
        // (a clamping sampler would show one stripe and a smear).
        let none = try #require(OllinApp.image(of: DetailProbe.make(.plain), frame: 1))
        let coarse = try #require(OllinApp.image(of: DetailProbe.make(.stripesScale3), frame: 1))
        let fine = try #require(OllinApp.image(of: DetailProbe.make(.stripesScale6), frame: 1))
        let n0 = stripeTransitions(of: none)
        let n3 = stripeTransitions(of: coarse)
        let n6 = stripeTransitions(of: fine)
        #expect(n0 == 0, "the control has no stripes, got \(n0)")
        #expect(n3 >= 4, "scale 3 must tile visible stripes, got \(n3)")
        #expect(n6 >= n3 + 3, "a higher detail scale must tile more stripes: \(n3) vs \(n6)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aNeutralGrayDetailIsWithinAStepOfTheIdentity() throws {
        // 128 gray is the data-read neutral: the sample x 2 multiplies by
        // 1.004, under half an 8-bit step everywhere, so the detailed render
        // sits within the dither's neighborhood of the control.
        let detailed = try #require(OllinApp.image(of: DetailProbe.make(.neutralGray), frame: 1))
        let control = try #require(OllinApp.image(of: DetailProbe.make(.plain), frame: 1))
        let a = imageBytes(detailed), b = imageBytes(control)
        var worst = 0
        for i in 0..<min(a.count, b.count) {
            worst = max(worst, abs(Int(a[i]) - Int(b[i])))
        }
        #expect(worst <= 3, "a neutral detail map must be visually inert, worst step \(worst)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func strengthZeroRoutesDownThePlainPath() throws {
        // Strength 0 is the off switch: the drawer never raises the gates, so
        // the frame is byte-identical to the same mesh with no detail maps
        // attached at all (the plain textured pipeline).
        let off = try #require(OllinApp.image(of: DetailProbe.make(.strengthZero), frame: 1))
        let none = try #require(OllinApp.image(of: DetailProbe.make(.plain), frame: 1))
        #expect(imageBytes(off) == imageBytes(none))
    }

    /// The mean brightness over the quad's pixels.
    private func meanBrightness(of image: CGImage) -> Double {
        let bytes = imageBytes(image)
        var sum = 0.0, count = 0.0
        for i in stride(from: 0, to: bytes.count, by: 4) where bytes[i + 3] > 200 {
            sum += Double(bytes[i]); count += 1
        }
        return count > 0 ? sum / count : 0
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aFlatDetailNormalLeavesTheBaseReliefUntouched() throws {
        // The reorientation's identity: a flat (127,127,255) detail normal
        // must hand back the base normal map's own relief. An overwrite blend
        // fails this (it would flatten the base tilt); the probe compares
        // against the base-only render and allows only the dither's step.
        let flat = try #require(OllinApp.image(of: DetailProbe.make(.tiltedBaseFlatDetail), frame: 1))
        let baseOnly = try #require(OllinApp.image(of: DetailProbe.make(.tiltedBaseNoDetail), frame: 1))
        let a = imageBytes(flat), b = imageBytes(baseOnly)
        var worst = 0
        for i in 0..<min(a.count, b.count) {
            worst = max(worst, abs(Int(a[i]) - Int(b[i])))
        }
        #expect(worst <= 3, "a flat detail must leave the base relief alone, worst step \(worst)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aTiltedDetailComposesOntoTheBaseTilt() throws {
        // Light shines from the +x side. The base normal map tilts the quad's
        // normals toward the light (brighter than flat); a detail normal with
        // the same lean must tilt them *further* (brighter still), which is
        // what reorienting onto the base gives and what replacing the base
        // with the detail alone would not.
        let flat = meanBrightness(of: try #require(
            OllinApp.image(of: DetailProbe.make(.litFlat), frame: 1)))
        let base = meanBrightness(of: try #require(
            OllinApp.image(of: DetailProbe.make(.litBaseTilt), frame: 1)))
        let composed = meanBrightness(of: try #require(
            OllinApp.image(of: DetailProbe.make(.litBaseAndDetailTilt), frame: 1)))
        #expect(base > flat + 4, "the base tilt alone must brighten: \(flat) vs \(base)")
        #expect(composed > base + 4, "the detail must tilt further onto the base: \(base) vs \(composed)")
    }
}

/// The detail render probes: a camera-facing quad, one arrangement per mode.
private final class DetailProbe: Sketch {
    enum Mode {
        case plain, stripesScale3, stripesScale6, neutralGray, strengthZero
        case tiltedBaseFlatDetail, tiltedBaseNoDetail
        case litFlat, litBaseTilt, litBaseAndDetailTilt
        case exportStrip
    }
    var mode = Mode.plain

    static func make(_ mode: Mode) -> DetailProbe {
        let probe = DetailProbe()
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

    /// Half dark, half light down the image: one stripe pair per tile.
    private func stripeDetail() -> Image {
        let size = 32
        var bytes = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let v: UInt8 = x < size / 2 ? 40 : 216
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

    /// A normal map leaning every normal toward the map's +x (208 in red).
    private var tiltMap: Image { solid(208, 127, 255) }
    /// The flat tangent-space normal.
    private var flatNormalMap: Image { solid(127, 127, 255) }

    override func draw() {
        background(.black)
        fill(Color(white: 0.9))
        camera(.orbiting(radius: 3))
        switch mode {
        case .plain:
            directionalLight(.white, direction: Vector3(0, 0, -1))
            drawMesh(quad().textured(solid(180, 180, 180)))
        case .stripesScale3:
            directionalLight(.white, direction: Vector3(0, 0, -1))
            drawMesh(quad().textured(solid(180, 180, 180))
                .detailMapped(stripeDetail(), scale: 3))
        case .stripesScale6:
            directionalLight(.white, direction: Vector3(0, 0, -1))
            drawMesh(quad().textured(solid(180, 180, 180))
                .detailMapped(stripeDetail(), scale: 6))
        case .neutralGray:
            directionalLight(.white, direction: Vector3(0, 0, -1))
            drawMesh(quad().textured(solid(180, 180, 180))
                .detailMapped(solid(128, 128, 128), scale: 4))
        case .strengthZero:
            directionalLight(.white, direction: Vector3(0, 0, -1))
            drawMesh(quad().textured(solid(180, 180, 180))
                .detailMapped(stripeDetail(), scale: 4, strength: 0))
        case .tiltedBaseFlatDetail:
            directionalLight(.white, direction: Vector3(-1, 0, -1))
            drawMesh(quad().textured(solid(180, 180, 180))
                .normalMapped(tiltMap)
                .detailMapped(normal: flatNormalMap, scale: 5))
        case .tiltedBaseNoDetail:
            directionalLight(.white, direction: Vector3(-1, 0, -1))
            drawMesh(quad().textured(solid(180, 180, 180))
                .normalMapped(tiltMap))
        case .litFlat:
            directionalLight(.white, direction: Vector3(-1, 0, -0.4))
            drawMesh(quad().textured(solid(180, 180, 180)))
        case .litBaseTilt:
            directionalLight(.white, direction: Vector3(-1, 0, -0.4))
            drawMesh(quad().textured(solid(180, 180, 180))
                .normalMapped(tiltMap))
        case .litBaseAndDetailTilt:
            directionalLight(.white, direction: Vector3(-1, 0, -0.4))
            drawMesh(quad().textured(solid(180, 180, 180))
                .normalMapped(tiltMap)
                .detailMapped(normal: tiltMap, scale: 5))
        case .exportStrip:
            directionalLight(.white, direction: Vector3(0, 0, -1))
            drawMesh(quad().textured(solid(180, 180, 180))
                .detailMapped(stripeDetail(), normal: flatNormalMap, scale: 4))
        }
    }
}
