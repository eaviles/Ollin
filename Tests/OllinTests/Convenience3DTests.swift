import CoreGraphics
import Foundation
import Testing
@testable import Ollin

/// Laws for the 3D-and-layout convenience tier: `cameraRay` as the exact
/// inverse of `project`, the `moveAxis` key read, the ground slab and
/// world-anchored label as byte-identical sugar, the point-cloud measurements,
/// the height-field coloring, the frustum mesh, the sheet layout, and the
/// sketch-adjacent resource walk.
@Suite
@MainActor
struct Convenience3DTests {

    // MARK: cameraRay

    @Test func cameraRayInvertsProjectInPerspective() throws {
        let sketch = Sketch()
        sketch.width = 640
        sketch.height = 400
        sketch.perspective(eye: Vector3(3, 2, 6), target: Vector3(0, 0.5, 0))
        for world in [Vector3(0, 0, 0), Vector3(1, 0.5, -2), Vector3(-1.5, 2, 1)] {
            let screen = try #require(sketch.project(world))
            let ray = try #require(sketch.cameraRay(through: screen))
            #expect(abs(ray.direction.length - 1) < 1e-9, "the direction is unit length")
            let toPoint = world - ray.origin
            let along = toPoint.dot(ray.direction)
            #expect(along > 0, "the point sits in front of the camera")
            let closest = ray.origin + ray.direction * along
            #expect(closest.distance(to: world) < 1e-6,
                    "the ray through a projected point passes back through the point")
        }
    }

    @Test func cameraRayInvertsProjectInOrthographic() throws {
        let sketch = Sketch()
        sketch.width = 500
        sketch.height = 500
        sketch.ortho(eye: Vector3(0, 3, 8), target: .zero, height: 6)
        let a = try #require(sketch.cameraRay(through: Vector2(100, 250)))
        let b = try #require(sketch.cameraRay(through: Vector2(400, 250)))
        #expect(a.direction.distance(to: b.direction) < 1e-9,
                "orthographic rays are parallel")
        #expect(a.origin.distance(to: b.origin) > 1e-6,
                "and start from different places on the view plane")
        let world = Vector3(0.8, 0.3, -1)
        let screen = try #require(sketch.project(world))
        let ray = try #require(sketch.cameraRay(through: screen))
        let along = (world - ray.origin).dot(ray.direction)
        let closest = ray.origin + ray.direction * along
        #expect(closest.distance(to: world) < 1e-6)
    }

    @Test func cameraRayNeedsACamera() {
        let sketch = Sketch()
        sketch.width = 100
        sketch.height = 100
        #expect(sketch.cameraRay(through: Vector2(50, 50)) == nil)
    }

    // MARK: moveAxis

    @Test func moveAxisReadsTheHeldKeys() {
        let sketch = Sketch()
        #expect(sketch.moveAxis == .zero)
        sketch.ingest(.key(character: "w", code: nil, pressed: true))
        sketch.ingest(.key(character: "d", code: nil, pressed: true))
        #expect(sketch.moveAxis == Vector2(1, -1), "up is negative y, canvas orientation")
        sketch.ingest(.key(character: nil, code: .leftArrow, pressed: true))
        #expect(sketch.moveAxis == Vector2(0, -1), "opposite directions cancel")
        sketch.ingest(.key(character: "w", code: nil, pressed: false))
        sketch.ingest(.key(character: "d", code: nil, pressed: false))
        sketch.ingest(.key(character: nil, code: .leftArrow, pressed: false))
        #expect(sketch.moveAxis == .zero)
    }

    // MARK: Rendered A/B: the 3D sugar equals the block it replaces

    private func bytes(of image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var out = [UInt8](repeating: 0, count: w * h * 4)
        out.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: w, height: h,
                                bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            ctx?.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return out
    }

    private final class Ground: Sketch {
        var oneCall = true
        override var canvasSize: CanvasSize { .square(256) }
        override func setup() { noLoop() }
        override func draw() {
            background(Color(hex: 0x10131A))
            perspective(eye: Vector3(6, 5, 9), target: Vector3(0, 0.5, 0))
            lights()
            fill(.coral)
            if oneCall {
                drawGround(size: 12, color: Color(hex: 0x2E3440),
                           material: .dielectric(roughness: 0.85))
            } else {
                withState {
                    fill(Color(hex: 0x2E3440))
                    material(.dielectric(roughness: 0.85))
                    translate(0, -0.06, 0)
                    drawBox(width: 12, height: 0.12, depth: 12)
                }
            }
            // Drawn with the standing state: a leak from the ground shows here.
            withState(at: Vector3(0, 0.6, 0)) { drawBox(size: 1.2) }
        }
    }

    @Test func groundEqualsTheSpelledOutSlab() throws {
        let one = Ground()
        let block = Ground(); block.oneCall = false
        #expect(bytes(of: try #require(OllinApp.image(of: one)))
             == bytes(of: try #require(OllinApp.image(of: block))))
    }

    private final class WorldLabel: Sketch {
        var oneCall = true
        override var canvasSize: CanvasSize { .square(256) }
        override func setup() { noLoop() }
        override func draw() {
            background(.black)
            perspective(eye: Vector3(0, 2, 6), target: .zero)
            lights()
            fill(.steelBlue)
            drawBox(size: 1)
            let anchor = Vector3(0, 0.9, 0)
            if oneCall {
                drawText("crate", at: anchor, size: 22, color: .white, align: .center, .bottom)
            } else if let p = project(anchor) {
                drawText("crate", p.x, p.y, size: 22, color: .white, align: .center, .bottom)
            }
        }
    }

    @Test func worldLabelEqualsProjectPlusText() throws {
        let one = WorldLabel()
        let manual = WorldLabel(); manual.oneCall = false
        #expect(bytes(of: try #require(OllinApp.image(of: one)))
             == bytes(of: try #require(OllinApp.image(of: manual))))
    }

    // MARK: Point-cloud measurements

    @Test func centroidAndSpreadAreTheMoments() {
        var cloud = PointCloud()
        #expect(cloud.centroid == nil)
        #expect(cloud.spreadRadius == 0)
        cloud.add(Vector3(1, 0, 0))
        cloud.add(Vector3(-1, 0, 0))
        cloud.add(Vector3(0, 2, 0))
        cloud.add(Vector3(0, -2, 0))
        let center = cloud.centroid
        #expect(center == Vector3.zero)
        // Mean squared distance is (1 + 1 + 4 + 4) / 4 = 2.5.
        #expect(abs(cloud.spreadRadius - 2.5.squareRoot()) < 1e-12)
    }

    // MARK: Height-field coloring

    @Test func heightfieldImagePaintsEachSampleThroughTheRamp() throws {
        let field = Heightfield(columns: 2, rows: 2, values: [0, 1, 0.5, 0.25])
        let ramp = Ramp([.black, .white])
        let image = try #require(field.image(ramp))
        #expect(image.width == 2 && image.height == 2)
        // Each pixel is the ramp's own color at that sample (the ramp mixes in
        // OKLab, so the midpoint is not a plain 0.5 gray), with one 8-bit
        // rounding step of slack per channel.
        for (i, value) in field.values.enumerated() {
            let want = ramp.color(at: value)
            let got = image[i % 2, i / 2]
            #expect(abs(got.red - want.red) < 0.01, "sample \(i)")
            #expect(abs(got.green - want.green) < 0.01, "sample \(i)")
            #expect(abs(got.blue - want.blue) < 0.01, "sample \(i)")
        }
    }

    @Test func heightfieldImageHonorsItsRange() throws {
        let field = Heightfield(columns: 2, rows: 2, values: [100, 200, 100, 200])
        let image = try #require(field.image(Ramp([.black, .white]), in: 100...200))
        #expect(abs(image[0, 0].red - 0) < 0.01)
        #expect(abs(image[1, 0].red - 1) < 0.01)
    }

    @Test func coloredMeshWearsTheColoring() {
        let field = Heightfield(columns: 3, rows: 3) { u, v in u * v }
        let mesh = field.coloredMesh(width: 10, depth: 10, height: 2, Ramp([.navy, .gold]))
        #expect(mesh.material?.texture != nil, "the ramp coloring rides as the texture")
        #expect(mesh.positions.count == field.values.count)
    }

    // MARK: The frustum mesh

    @Test func frustumRingsSitAtTheirRadii() {
        let mesh = Mesh.frustum(topRadius: 0.3, bottomRadius: 0.8, height: 2, segments: 16)
        for (p, n) in zip(mesh.positions, mesh.normals) {
            let radial = (p.x * p.x + p.z * p.z).squareRoot()
            if abs(p.y - 1) < 1e-9 {
                #expect(radial < 0.3 + 1e-9)
            } else if abs(p.y + 1) < 1e-9 {
                #expect(radial < 0.8 + 1e-9)
            } else {
                Issue.record("a vertex off both rings at y = \(p.y)")
            }
            #expect(abs(n.length - 1) < 1e-6, "normals are unit length")
        }
    }

    @Test func equalRadiiMakeACylinderWall() {
        let mesh = Mesh.frustum(topRadius: 0.5, bottomRadius: 0.5, height: 1, segments: 8)
        // Wall normals are horizontal when there is no taper; caps are the
        // vertical ones.
        let horizontal = mesh.normals.filter { abs($0.y) < 1e-9 }.count
        let vertical = mesh.normals.filter { abs(abs($0.y) - 1) < 1e-9 }.count
        #expect(horizontal + vertical == mesh.normals.count)
        #expect(horizontal > 0 && vertical > 0)
    }

    @Test func aZeroRadiusDropsItsCap() {
        let cone = Mesh.frustum(topRadius: 0, bottomRadius: 0.5, height: 1, segments: 8)
        #expect(!cone.normals.contains { abs($0.y - 1) < 1e-9 },
                "no top cap on a point")
        #expect(cone.normals.contains { abs($0.y + 1) < 1e-9 },
                "the wide end still caps")
    }

    // MARK: The sheet layout

    @Test func drawSheetLaysANearSquareGrid() {
        let sketch = Sketch()
        sketch.width = 900
        sketch.height = 900
        var cells: [Rectangle] = []
        let items = (0..<5).map { ("tile \($0)", $0) }
        sketch.drawSheet(items) { _, cell in cells.append(cell) }
        #expect(cells.count == 5)
        // Five items go 3 across, 2 down; every cell one size; the gutter 1%.
        let gutter = 9.0
        let cellW = (900 - gutter * 4) / 3
        #expect(abs(cells[0].x - gutter) < 1e-9)
        #expect(abs(cells[0].width - cellW) < 1e-9)
        #expect(abs(cells[1].x - (gutter * 2 + cellW)) < 1e-9)
        #expect(abs(cells[3].y - cells[0].y - cells[0].height - gutter) < 1e-9,
                "the second row starts one cell and one gutter down")
        for cell in cells.dropFirst() {
            #expect(abs(cell.width - cells[0].width) < 1e-9)
            #expect(abs(cell.height - cells[0].height) < 1e-9)
        }
    }

    @Test func drawSheetHonorsAColumnCount() {
        let sketch = Sketch()
        sketch.width = 800
        sketch.height = 400
        var cells: [Rectangle] = []
        sketch.drawSheet([("a", 0), ("b", 1), ("c", 2)], columns: 3, gutter: 10) { _, cell in
            cells.append(cell)
        }
        #expect(cells.count == 3)
        #expect(abs(cells[2].x + cells[2].width - (800 - 10)) < 1e-9,
                "the last column ends one gutter from the right edge")
    }

    // MARK: The sketch-adjacent resource walk

    @Test func sketchResourceWalksUpToTheNearestFolder() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-resource-\(UUID().uuidString)")
        let deep = root.appendingPathComponent("a/b/c")
        let models = root.appendingPathComponent("a/Models")
        try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: models, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let sketchFile = deep.appendingPathComponent("Sketch.swift").path
        let found = try #require(sketchResource("net.bin", from: sketchFile))
        #expect(found == models.appendingPathComponent("net.bin").path)
        #expect(sketchResource("x", in: "NoSuchFolder", from: sketchFile) == nil)
    }
}
