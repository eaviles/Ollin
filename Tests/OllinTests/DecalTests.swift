import CoreGraphics
import Foundation
@testable import Ollin
import Testing

/// Projected decals (`drawDecal(_:at:...)`): a picture stamped onto the mesh
/// surfaces inside an oriented projection box. The CPU half pins the value
/// type (proportions kept, layer sharing, the per-frame cap and reset, the
/// opacity-zero early-out). The Metal-gated probes pin the projection against
/// counterfactuals: the stamp lands where the box is placed (left vs right),
/// the box's depth bounds it (a box hovering above the floor stamps nothing),
/// an edge-on wall fades it out instead of smearing, later decals composite
/// over earlier ones, and a plain solid mesh receives one too (the routed
/// pipeline serves every lit mesh).
@Suite
@MainActor
struct DecalTests {

    // MARK: - Authoring helpers

    private func solidImage(_ r: UInt8, _ g: UInt8, _ b: UInt8, alpha: UInt8 = 255,
                            width: Int = 8, height: Int = 8) -> Image {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let a = Double(alpha) / 255
        for i in stride(from: 0, to: bytes.count, by: 4) {
            bytes[i] = UInt8(Double(r) * a); bytes[i + 1] = UInt8(Double(g) * a)
            bytes[i + 2] = UInt8(Double(b) * a); bytes[i + 3] = alpha
        }
        return Image(width: width, height: height, premultipliedRGBA: bytes)!
    }

    // MARK: - The value type and the frame list

    @Test func aDecalKeepsItsSourceProportions() throws {
        let wide = try #require(Decal(solidImage(255, 0, 0, width: 200, height: 100)))
        #expect(abs(wide.aspect - 0.5) < 1e-12)
        let tall = try #require(Decal(solidImage(255, 0, 0, width: 50, height: 150)))
        #expect(abs(tall.aspect - 3) < 1e-12)
    }

    @Test func placementsShareLayersAndCapAtEight() throws {
        let sketch = Sketch()
        let red = try #require(Decal(solidImage(255, 0, 0)))
        let blue = try #require(Decal(solidImage(0, 0, 255)))
        for i in 0..<10 {
            sketch.drawer.placeDecal(i % 2 == 0 ? red : blue, at: Vector3(Double(i), 0, 0),
                                     direction: Vector3(0, -1, 0), width: 10, height: nil,
                                     depth: nil, roll: 0, opacity: 1)
        }
        #expect(sketch.drawer.placedDecals.count == 8, "the frame caps at eight placements")
        #expect(sketch.drawer.usedDecals.count == 2, "two distinct images share two layers")
        // The uniform mirrors the list behind its count.
        let u = sketch.drawer.decalsUniform()
        #expect(u.count == 8)
        // And the frame reset clears both, like the lights.
        sketch.drawer.beginFrame()
        #expect(sketch.drawer.placedDecals.isEmpty && sketch.drawer.usedDecals.isEmpty)
    }

    @Test func zeroOpacityAndDegenerateBoxesPlaceNothing() throws {
        let sketch = Sketch()
        let red = try #require(Decal(solidImage(255, 0, 0)))
        sketch.drawer.placeDecal(red, at: .zero, direction: Vector3(0, -1, 0),
                                 width: 10, height: nil, depth: nil, roll: 0, opacity: 0)
        sketch.drawer.placeDecal(red, at: .zero, direction: Vector3(0, -1, 0),
                                 width: 0, height: nil, depth: nil, roll: 0, opacity: 1)
        sketch.drawer.placeDecal(red, at: .zero, direction: .zero,
                                 width: 10, height: nil, depth: nil, roll: 0, opacity: 1)
        #expect(sketch.drawer.placedDecals.isEmpty,
                "opacity 0, a zero-size box, and a zero direction all place nothing")
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

    /// The centroid of clearly red pixels (the stamp), nil when none.
    private func redCentroid(of image: CGImage) -> (x: Double, y: Double, count: Int)? {
        let bytes = imageBytes(image)
        var sx = 0.0, sy = 0.0
        var count = 0
        for y in 0..<image.height {
            for x in 0..<image.width {
                let i = (y * image.width + x) * 4
                if Int(bytes[i]) > Int(bytes[i + 1]) + 60, Int(bytes[i]) > Int(bytes[i + 2]) + 60 {
                    sx += Double(x); sy += Double(y); count += 1
                }
            }
        }
        guard count > 0 else { return nil }
        return (sx / Double(count), sy / Double(count), count)
    }

    /// Count clearly blue pixels.
    private func bluePixels(of image: CGImage) -> Int {
        let bytes = imageBytes(image)
        var count = 0
        for i in stride(from: 0, to: bytes.count, by: 4) {
            if Int(bytes[i + 2]) > Int(bytes[i]) + 60, Int(bytes[i + 2]) > Int(bytes[i + 1]) + 60 {
                count += 1
            }
        }
        return count
    }

    /// The centroid of clearly green pixels (the drawn marker), nil when none.
    private func greenCentroid(of image: CGImage) -> (x: Double, y: Double)? {
        let bytes = imageBytes(image)
        var sx = 0.0, sy = 0.0
        var count = 0
        for y in 0..<image.height {
            for x in 0..<image.width {
                let i = (y * image.width + x) * 4
                if Int(bytes[i + 1]) > Int(bytes[i]) + 60, Int(bytes[i + 1]) > Int(bytes[i + 2]) + 60 {
                    sx += Double(x); sy += Double(y); count += 1
                }
            }
        }
        guard count > 0 else { return nil }
        return (sx / Double(count), sy / Double(count))
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theStampLandsWhereTheBoxIsPlaced() throws {
        // A red sticker stamped down onto a gray floor, once left of center and
        // once right, each frame also drawing a small green sphere at the same
        // world position: the stamp must land where the renderer's own
        // projection puts that position (which catches a mirrored or shifted
        // world-to-box transform without hand-deriving camera conventions),
        // and the two stamps must sit apart.
        let left = try #require(OllinApp.image(of: DecalProbe.make(.stampLeft), frame: 1))
        let right = try #require(OllinApp.image(of: DecalProbe.make(.stampRight), frame: 1))
        let cl = try #require(redCentroid(of: left), "the left stamp must land")
        let cr = try #require(redCentroid(of: right), "the right stamp must land")
        let ml = try #require(greenCentroid(of: left), "the left marker must draw")
        let mr = try #require(greenCentroid(of: right), "the right marker must draw")
        // The marker sits just outside the box (or the stamp would cover it),
        // offset along world z only, so the x agreement is exact.
        #expect(abs(cl.x - ml.x) < 14,
                "the stamp must land at its world position: stamp \(cl) vs marker \(ml)")
        #expect(abs(cr.x - mr.x) < 14,
                "the stamp must land at its world position: stamp \(cr) vs marker \(mr)")
        #expect(abs(cr.x - cl.x) > 30, "the two stamps must sit apart: \(cl) vs \(cr)")
        #expect(cl.count > 40 && cr.count > 40, "the stamp must cover real area")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theBoxDepthBoundsTheStamp() throws {
        // The same placement with the box's depth range hovering above the
        // floor: the floor sits outside |z| <= 0.5, so nothing stamps.
        let hover = try #require(OllinApp.image(of: DecalProbe.make(.stampHovering), frame: 1))
        #expect(redCentroid(of: hover) == nil, "a box that doesn't reach the surface stamps nothing")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func anEdgeOnSurfaceFadesTheStampOut() throws {
        // A wall parallel to the projection axis sits edge-on to the stamp:
        // the facing fade must drop it to nothing rather than smear the
        // picture down the wall.
        let wall = try #require(OllinApp.image(of: DecalProbe.make(.stampOnEdgeOnWall), frame: 1))
        #expect(redCentroid(of: wall) == nil, "an edge-on surface must fade the stamp out")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func laterDecalsCompositeOverEarlierOnes() throws {
        // Red then blue at the same spot: blue wins where they overlap. The
        // reversed order hands it back to red.
        let blueOver = try #require(OllinApp.image(of: DecalProbe.make(.redThenBlue), frame: 1))
        let redOver = try #require(OllinApp.image(of: DecalProbe.make(.blueThenRed), frame: 1))
        #expect(bluePixels(of: blueOver) > 40, "the later blue must cover the red")
        #expect(redCentroid(of: blueOver) == nil, "no red may remain under the covering blue")
        #expect(redCentroid(of: redOver) != nil, "reversed, the red covers")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aPlainSolidMeshReceivesADecal() throws {
        // The floor here carries no texture and no maps at all: the routed
        // pipeline must still land the stamp on it.
        let solid = try #require(OllinApp.image(of: DecalProbe.make(.stampOnSolid), frame: 1))
        let c = try #require(redCentroid(of: solid), "a solid mesh must receive the stamp")
        #expect(c.count > 40)
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func transparencyStampsOnlyTheInk() throws {
        // A sticker with a transparent border: outside the ink the floor keeps
        // its own color, byte for byte, against the same frame stamped with a
        // fully transparent image (which paints nothing anywhere).
        let inked = try #require(OllinApp.image(of: DecalProbe.make(.transparentBorder), frame: 1))
        let clear = try #require(OllinApp.image(of: DecalProbe.make(.fullyTransparent), frame: 1))
        let c = try #require(redCentroid(of: inked), "the ink must stamp")
        #expect(c.count > 10)
        // The fully transparent stamp leaves the floor untouched everywhere.
        #expect(redCentroid(of: clear) == nil)
    }
}

/// The decal render probes: a floor (or wall) under a top-lit camera, one
/// arrangement per mode.
private final class DecalProbe: Sketch {
    enum Mode {
        case stampLeft, stampRight, stampHovering, stampOnEdgeOnWall
        case redThenBlue, blueThenRed
        case stampOnSolid, transparentBorder, fullyTransparent
    }
    var mode = Mode.stampLeft

    static func make(_ mode: Mode) -> DecalProbe {
        let probe = DecalProbe()
        probe.mode = mode
        return probe
    }

    override var canvasSize: CanvasSize { .square(256) }

    private var redSticker = Decal(DecalProbe.solidImage(255, 0, 0))!
    private var blueSticker = Decal(DecalProbe.solidImage(0, 0, 255))!

    private static func solidImage(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Image {
        var bytes = [UInt8](repeating: 255, count: 8 * 8 * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) {
            bytes[i] = r; bytes[i + 1] = g; bytes[i + 2] = b
        }
        return Image(width: 8, height: 8, premultipliedRGBA: bytes)!
    }

    /// A red disc on a fully transparent field.
    private static func discImage() -> Image {
        let size = 64
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let dx = Double(x) - 31.5, dy = Double(y) - 31.5
                guard dx * dx + dy * dy < 200 else { continue }
                let i = (y * size + x) * 4
                bytes[i] = 255; bytes[i + 3] = 255
            }
        }
        return Image(width: size, height: size, premultipliedRGBA: bytes)!
    }

    /// A fully transparent image.
    private static func clearImage() -> Image {
        Image(width: 8, height: 8,
              premultipliedRGBA: [UInt8](repeating: 0, count: 8 * 8 * 4))!
    }

    private func floor() -> Mesh {
        Mesh.plane(width: 4, depth: 4)
    }

    override func draw() {
        background(.black)
        fill(Color(white: 0.7))
        directionalLight(.white, direction: Vector3(0, -1, 0))
        if mode == .stampOnEdgeOnWall {
            // Face the wall, so a wrongly smeared stamp would be visible.
            camera(.orbiting(radius: 4, elevation: 0.15))
            directionalLight(.white, direction: Vector3(0, 0, -1))
        } else {
            camera(.orbiting(radius: 4, elevation: 1.3))
        }
        switch mode {
        case .stampLeft, .stampRight:
            let x = mode == .stampLeft ? -0.9 : 0.9
            drawMesh(floor().textured(Self.solidImage(150, 150, 150)))
            drawDecal(redSticker, at: Vector3(x, 0, 0), width: 0.7)
            // The marker sits outside the box's footprint (offset along z
            // only) or the stamp would cover it; the probe compares x alone.
            withState {
                fill(.green)
                translate(x, 0.15, 0.7)
                drawSphere(radius: 0.08)
            }
        case .stampHovering:
            drawMesh(floor().textured(Self.solidImage(150, 150, 150)))
            // The box is 1 wide and defaults its depth to 1, centered 2 above
            // the floor: the floor sits well outside its depth range.
            drawDecal(redSticker, at: Vector3(0, 2, 0), width: 1)
        case .stampOnEdgeOnWall:
            // A wall standing straight up (its normals along +z): projecting
            // straight down runs exactly edge-on to it.
            let wall = Mesh(positions: [Vector3(-1.5, -1.5, 0), Vector3(1.5, -1.5, 0),
                                        Vector3(1.5, 1.5, 0), Vector3(-1.5, 1.5, 0)],
                            normals: [.unitZ, .unitZ, .unitZ, .unitZ],
                            indices: [0, 1, 2, 0, 2, 3],
                            uvs: [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)])
            drawMesh(wall.textured(Self.solidImage(150, 150, 150)))
            drawDecal(redSticker, at: Vector3(0, 0, 0), width: 2, depth: 4)
        case .redThenBlue:
            drawMesh(floor().textured(Self.solidImage(150, 150, 150)))
            drawDecal(redSticker, at: Vector3(0, 0, 0), width: 1)
            drawDecal(blueSticker, at: Vector3(0, 0, 0), width: 1.4)
        case .blueThenRed:
            drawMesh(floor().textured(Self.solidImage(150, 150, 150)))
            drawDecal(blueSticker, at: Vector3(0, 0, 0), width: 1.4)
            drawDecal(redSticker, at: Vector3(0, 0, 0), width: 1)
        case .stampOnSolid:
            drawMesh(floor())
            drawDecal(redSticker, at: Vector3(0, 0, 0), width: 1.2)
        case .transparentBorder:
            drawMesh(floor().textured(Self.solidImage(150, 150, 150)))
            drawDecal(Decal(Self.discImage())!, at: Vector3(0, 0, 0), width: 1.2)
        case .fullyTransparent:
            drawMesh(floor().textured(Self.solidImage(150, 150, 150)))
            drawDecal(Decal(Self.clearImage())!, at: Vector3(0, 0, 0), width: 1.2)
        }
    }
}
