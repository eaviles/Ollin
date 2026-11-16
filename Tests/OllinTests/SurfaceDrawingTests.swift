import CoreGraphics
import Foundation
import Testing
import simd
@testable import Ollin

// MARK: - The picture and the sketch that draws over it

/// A picture with something to get wrong at every pixel: smooth ramps that turn
/// any small shift into a different value, and hard-edged blocks that turn a
/// one-pixel slip into a different color.
private func testPicture(width: Int, height: Int) -> CGImage {
    var bytes = [UInt8](repeating: 255, count: width * height * 4)
    for y in 0..<height {
        for x in 0..<width {
            let i = (y * width + x) * 4
            let block = ((x / 16) + (y / 16)) % 3
            bytes[i] = UInt8((x * 255) / max(1, width - 1))
            bytes[i + 1] = UInt8((y * 255) / max(1, height - 1))
            bytes[i + 2] = block == 0 ? 40 : (block == 1 ? 130 : 220)
        }
    }
    let data = CFDataCreate(nil, bytes, bytes.count)!
    return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                   bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                   provider: CGDataProvider(data: data)!, decode: nil, shouldInterpolate: false,
                   intent: .defaultIntent)!
}

/// A flat four-cornered mesh, its corners given in order around it.
private func quad(_ a: Vector3, _ b: Vector3, _ c: Vector3, _ d: Vector3) -> Mesh {
    let normal = (b - a).cross(d - a).normalized
    return Mesh(positions: [a, b, c, d], normals: [Vector3](repeating: normal, count: 4),
                indices: [0, 1, 2, 0, 2, 3])
}

/// The picture drawn to fill the canvas, the camera that "took" it, and then
/// whatever a test draws in the room.
@MainActor
private final class OverPicture: Sketch {
    static let size = (width: 320, height: 240)

    let picture = Image(cgImage: testPicture(width: OverPicture.size.width,
                                             height: OverPicture.size.height))
    var lens = OverPicture.straight
    var room: (OverPicture) -> Void = { _ in }

    /// At the origin looking along -z with no roll: a point `(x, y, -z)` lands
    /// on column `160 + 256 x / z`, row `120 - 256 y / z`, so a move across the
    /// view by `z / 256` is one whole pixel.
    static let straight = Camera3D(
        eye: .zero, target: Vector3(0, 0, -1), up: .unitY, near: 0.01, far: 100,
        projection: .intrinsic(CameraIntrinsics(fx: 256, fy: 256, cx: 160, cy: 120,
                                                width: size.width, height: size.height)))

    /// Off to one side, rolled, through a lens whose center is off the middle
    /// and whose two focal lengths differ: nothing lines up by luck.
    static let askew = Camera3D(
        eye: Vector3(0.6, 1.4, 2.2), target: Vector3(-0.1, 0.9, 0), up: Vector3(0.09, 1, 0.02),
        near: 0.01, far: 100,
        projection: .intrinsic(CameraIntrinsics(fx: 262, fy: 265, cx: 163.5, cy: 117.75,
                                                width: size.width, height: size.height)))

    override var canvasSize: CanvasSize { .size(Self.size.width, Self.size.height) }

    override func draw() {
        background(.black)
        drawImage(picture, 0, 0, width, height)
        camera(lens)
        noStroke()
        fill(.white)
        room(self)
    }
}

/// How two frames differ: the largest step on any channel, and how many pixels
/// differ at all.
private func difference(_ a: CGImage, _ b: CGImage) -> (largest: Int, pixels: Int) {
    let pa = pixels(of: a), pb = pixels(of: b)
    var largest = 0, count = 0
    for i in stride(from: 0, to: min(pa.count, pb.count), by: 4) {
        var here = 0
        for c in 0..<3 { here = max(here, abs(Int(pa[i + c]) - Int(pb[i + c]))) }
        if here > 0 { count += 1 }
        largest = max(largest, here)
    }
    return (largest, count)
}

@MainActor
private func frame(lens: Camera3D = OverPicture.straight,
                   _ room: @escaping (OverPicture) -> Void = { _ in }) throws -> CGImage {
    let sketch = OverPicture()
    sketch.lens = lens
    sketch.room = room
    return try OllinApp.image(of: sketch)
}

/// What stands in the test room: a wall seen at a slant made of two large
/// triangles, a box, and a ball. Each is placed first and then drawn through
/// `look`, so a look that is a `painted` block paints it where it stands.
@MainActor
private func furnish(_ s: OverPicture, look: (() -> Void) -> Void = { $0() }) {
    look {
        s.drawMesh(quad(Vector3(-2.5, 0, -1.5), Vector3(1.5, 0, 0.6),
                        Vector3(1.5, 2.4, 0.6), Vector3(-2.5, 2.4, -1.5)))
    }
    s.withState {
        s.translate(-0.4, 0.9, 0.3)
        s.rotateY(0.5)
        look { s.drawBox(width: 0.5, height: 0.7, depth: 0.4) }
    }
    s.withState {
        s.translate(0.5, 1.2, 0.5)
        look { s.drawSphere(radius: 0.3) }
    }
}

// MARK: - The picture as paint

/// Invariants of drawing on a surface a camera's picture shows: the picture as
/// paint, the mesh that only hides, an image laid on four points of space, the
/// ray back through a real lens, and the surface value they stand on.
@Suite
@MainActor
struct SurfaceDrawingTests {

    @Test func aMeshPaintedWithThePictureAndLeftInPlaceChangesNoPixel() throws {
        let plain = try frame(lens: OverPicture.askew)
        let painted = try frame(lens: OverPicture.askew) { s in
            furnish(s) { body in s.painted(with: s.picture, from: s.lens, body) }
        }
        // The control: the same things drawn as plain white solids cover a
        // good part of the canvas, so "no change" is not an empty stage.
        let solid = try frame(lens: OverPicture.askew) { s in
            s.noLights()
            furnish(s)
        }
        #expect(difference(plain, solid).pixels > 320 * 240 / 3,
                "the room's meshes cover a third of the canvas at least")
        // Flat faces come out exactly: the wall of two large triangles seen at
        // a slant, and the box. A curved mesh's rim is the one place a pixel
        // can differ. A triangle there is seen nearly edge-on, a pixel it only
        // partly covers is shaded at its center, half a pixel past the
        // triangle's own edge, and that far along such a triangle the place in
        // the picture is read with less than a pixel's precision. Measured: 6
        // pixels of the ball, each within 2 levels.
        func paintedAlone(_ only: Int) throws -> (largest: Int, pixels: Int) {
            let one = try frame(lens: OverPicture.askew) { s in
                var index = 0
                furnish(s) { body in
                    if index == only { s.painted(with: s.picture, from: s.lens, body) }
                    index += 1
                }
            }
            return difference(plain, one)
        }
        let wall = try paintedAlone(0), box = try paintedAlone(1), ball = try paintedAlone(2)
        #expect(wall.pixels == 0, "the slanted wall: \(wall.pixels) pixels moved, by up to \(wall.largest)")
        #expect(box.pixels == 0, "the box: \(box.pixels) pixels moved, by up to \(box.largest)")
        #expect(ball.largest <= 2 && ball.pixels <= 24,
                "the ball: \(ball.pixels) pixels moved, by up to \(ball.largest) levels")
        let moved = difference(plain, painted)
        #expect(moved.largest <= 2 && moved.pixels <= 24,
                "all three: \(moved.pixels) pixels moved, by up to \(moved.largest) levels")
    }

    @Test func theFillTintsThePaintAndWhiteLeavesIt() throws {
        let plain = try frame(lens: OverPicture.askew)
        let tinted = try frame(lens: OverPicture.askew) { s in
            s.fill(Color(red: 1, green: 0.4, blue: 0.4))
            furnish(s) { body in s.painted(with: s.picture, from: s.lens, body) }
        }
        #expect(difference(plain, tinted).pixels > 320 * 240 / 3,
                "a fill that is not white shows on the painted meshes")
    }

    @Test func aPlacedMeshKeepsItsPixelsAndAMovedOneCarriesThem() throws {
        // A sheet square to the view, two units ahead: 0.125 across is 16 pixels.
        let sheet = quad(Vector3(-0.25, -0.125, -2), Vector3(0, -0.125, -2),
                         Vector3(0, 0.125, -2), Vector3(-0.25, 0.125, -2))
        let bare = try frame()
        let plain = Pixels(bare)

        // A transform before the block places the mesh: it takes the pixels of
        // where it ends up, so nothing moves.
        let placed = try frame { s in
            s.translate(0.125, 0, 0)
            s.painted(with: s.picture, from: s.lens) { s.drawMesh(sheet) }
        }
        #expect(difference(placed, bare).largest == 0,
                "a mesh placed before the block is painted where it stands")

        // A transform inside the block moves it afterwards: columns 128 to 160
        // of the picture now sit on columns 144 to 176.
        let carried = Pixels(try frame { s in
            s.painted(with: s.picture, from: s.lens) {
                s.translate(0.125, 0, 0)
                s.drawMesh(sheet)
            }
        })
        // The present pass dithers by pixel position and reaches one level, so
        // one color at two places can come out two levels apart and no more.
        var worst = 0, differing = 0
        for y in 105..<135 {
            for x in 145..<175 {
                for c in 0..<3 {
                    let step = abs(carried.channel(c, x, y) - plain.channel(c, x - 16, y))
                    worst = max(worst, step)
                    if step > 0 { differing += 1 }
                }
            }
        }
        #expect(worst <= 2, "the moved sheet shows the pixels it left, 16 columns over (worst \(worst))")
        // The control: the picture's ramp climbs a level every pixel and a
        // quarter, so a sheet still showing where it lands would be far off.
        var unmoved = 0
        for y in 105..<135 {
            for x in 145..<175 { unmoved = max(unmoved, abs(plain.channel(0, x, y) - plain.channel(0, x - 16, y))) }
        }
        #expect(unmoved >= 10, "16 columns apart the picture itself differs by \(unmoved) levels")
        // And nothing changed outside the place it moved to.
        var outside = 0
        for y in 0..<240 {
            for x in 0..<320 where !(143...177).contains(x) || !(103...137).contains(y) {
                for c in 0..<3 where carried.channel(c, x, y) != plain.channel(c, x, y) { outside += 1 }
            }
        }
        #expect(outside == 0, "the rest of the canvas is the picture still")
    }

    @Test func whatThePaintingCameraDidNotSeeIsNotDrawn() throws {
        // The picture is taken through a camera turned well away from the
        // sheet, so no point of the sheet has a pixel in it.
        let away = Camera3D(eye: .zero, target: Vector3(1, 0, 0.2), up: .unitY, near: 0.01, far: 100,
                            projection: .intrinsic(CameraIntrinsics(fx: 256, fy: 256, cx: 160, cy: 120,
                                                                    width: 320, height: 240)))
        let sheet = quad(Vector3(-0.5, -0.4, -2), Vector3(0.5, -0.4, -2),
                         Vector3(0.5, 0.4, -2), Vector3(-0.5, 0.4, -2))
        let unseen = try frame { s in
            s.painted(with: s.picture, from: away) { s.drawMesh(sheet) }
        }
        let bare = try frame()
        #expect(difference(unseen, bare).pixels == 0,
                "a mesh outside the painting camera's view leaves the canvas alone")

        // Half seen: the camera that took the picture looks at the sheet's
        // right half only, and only that half is drawn.
        let half = Camera3D(eye: .zero, target: Vector3(0.625, 0, -1), up: .unitY, near: 0.01, far: 100,
                            projection: .intrinsic(CameraIntrinsics(fx: 256, fy: 256, cx: 160, cy: 120,
                                                                    width: 320, height: 240)))
        let partly = Pixels(try frame { s in
            s.fill(Color(red: 0.2, green: 0.2, blue: 0.2))      // a tint, so drawn pixels show
            s.painted(with: s.picture, from: half) { s.drawMesh(sheet) }
        })
        let plain = Pixels(try frame())
        func changed(_ x: Int, _ y: Int) -> Bool {
            (0..<3).contains { partly.channel($0, x, y) != plain.channel($0, x, y) }
        }
        #expect(!changed(110, 120), "the sheet's left side was outside the painting camera's view")
        #expect(changed(215, 120), "its right side was inside it")
    }

    @Test func paintedMeshesShareOneRun() throws {
        let sketch = OverPicture()
        sketch.room = { s in
            s.painted(with: s.picture, from: s.lens) {
                for i in 0..<40 {
                    s.withState {
                        s.translate(Double(i % 8) * 0.2 - 0.7, Double(i / 8) * 0.2 - 0.4, -2)
                        s.drawBox(size: 0.1)
                    }
                }
            }
            s.occluding { s.drawBox(size: 0.1); s.drawSphere(radius: 0.1) }
            s.drawBox(size: 0.1)
        }
        sketch.setCanvasSize(width: 320, height: 240)
        try sketch.setup()
        sketch.performDraw()
        let meshes = sketch.drawer.batches.filter { $0.kind == .mesh3D }
        #expect(meshes.count == 3, "forty painted boxes, two hiding meshes, one lit box: three runs")
        #expect(meshes.first?.picture === sketch.picture)
        #expect(meshes.dropFirst().first?.meshOccluder == true)
        #expect(meshes.last?.picture == nil && meshes.last?.meshOccluder == false)
        let outside = meshes.prefix(2).filter { $0.meshOutsideLighting }.count
        #expect(outside == 2)
        #expect(meshes.last?.meshOutsideLighting == false)
    }

    // MARK: The mesh that only hides

    @Test func anOccludingMeshHidesWhatIsDrawnBehindItAndShowsNothing() throws {
        let wall = quad(Vector3(-0.6, -0.5, -2), Vector3(0.6, -0.5, -2),
                        Vector3(0.6, 0.5, -2), Vector3(-0.6, 0.5, -2))
        func ball(_ s: OverPicture, z: Double) {
            s.noLights()
            s.fill(Color(red: 1, green: 0, blue: 1))
            s.withState { s.translate(0, 0, z); s.drawSphere(radius: 0.25) }
        }
        let plain = try frame()
        let alone = try frame { s in s.occluding { s.drawMesh(wall) } }
        #expect(difference(plain, alone).pixels == 0, "an occluding mesh puts no color down")

        let shown = try frame { s in ball(s, z: -3) }
        #expect(difference(plain, shown).pixels > 1000, "the ball shows with nothing in front of it")

        let hidden = try frame { s in
            s.occluding { s.drawMesh(wall) }
            ball(s, z: -3)
        }
        #expect(difference(plain, hidden).pixels == 0,
                "behind the wall the ball is hidden and the picture shows through")

        let inFront = try frame { s in
            s.occluding { s.drawMesh(wall) }
            ball(s, z: -1.2)
        }
        let free = try frame { s in ball(s, z: -1.2) }
        #expect(difference(inFront, free).pixels == 0, "in front of the wall the ball is whole")

        let before = try frame { s in
            ball(s, z: -3)
            s.occluding { s.drawMesh(wall) }
        }
        #expect(difference(before, shown).pixels == 0,
                "what was drawn before the block is already on the canvas and stays")
    }

    @Test func paintedAndOccludingMeshesCastNoShadow() throws {
        // A lit floor under a sheet that would shade it. Painted from a camera
        // that never saw it, the sheet draws no pixel of its own, so any change
        // to the frame would be its shadow.
        let away = Camera3D(eye: .zero, target: Vector3(0, 1, 0.1), up: Vector3(0, 0, -1),
                            near: 0.01, far: 100,
                            projection: .intrinsic(CameraIntrinsics(fx: 256, fy: 256, cx: 160, cy: 120,
                                                                    width: 320, height: 240)))
        let roof = quad(Vector3(-1, -0.4, -3.5), Vector3(1, -0.4, -3.5),
                        Vector3(1, -0.4, -1.5), Vector3(-1, -0.4, -1.5))
        func floor(_ s: OverPicture) {
            s.ambientLight(Color(white: 0.3))
            s.directionalLight(.white, direction: Vector3(0, -1, 0), castsShadow: true)
            s.castShadows()
            s.fill(Color(white: 0.8))
            s.withState { s.translate(0, -0.9, -2.5); s.drawPlane(width: 4, depth: 4) }
        }
        let lit = try frame { s in floor(s) }
        let shaded = try frame { s in
            floor(s)
            s.drawMesh(roof)
        }
        #expect(difference(lit, shaded).pixels > 500, "the control: a lit sheet does shade the floor")
        let underPaint = try frame { s in
            floor(s)
            s.painted(with: s.picture, from: away) { s.drawMesh(roof) }
        }
        #expect(difference(lit, underPaint).pixels == 0, "a painted mesh casts no shadow")
        let underOccluder = try frame { s in
            floor(s)
            s.occluding { s.withState { s.translate(0, 0, 40); s.drawMesh(roof) } }
        }
        #expect(difference(lit, underOccluder).pixels == 0, "nor does one that only hides")
    }

    // MARK: An image on four points

    /// A sheet image that is black but for four saturated dots at known places.
    private static let dots: [(u: Double, v: Double, rgb: (UInt8, UInt8, UInt8))] = [
        (0.25, 0.25, (255, 0, 0)), (0.75, 0.25, (0, 255, 0)),
        (0.75, 0.75, (0, 0, 255)), (0.25, 0.75, (255, 255, 0)),
    ]

    private static func dotSheet(side: Int = 128) -> CGImage {
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        for i in stride(from: 3, to: bytes.count, by: 4) { bytes[i] = 255 }
        for dot in dots {
            let cx = dot.u * Double(side), cy = dot.v * Double(side)
            for y in 0..<side {
                for x in 0..<side
                where pow(Double(x) + 0.5 - cx, 2) + pow(Double(y) + 0.5 - cy, 2) < 36 {
                    let i = (y * side + x) * 4
                    bytes[i] = dot.rgb.0; bytes[i + 1] = dot.rgb.1; bytes[i + 2] = dot.rgb.2
                }
            }
        }
        let data = CFDataCreate(nil, bytes, bytes.count)!
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: side * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: data)!, decode: nil, shouldInterpolate: false,
                       intent: .defaultIntent)!
    }

    @Test func anImageLaidOnFourPointsLandsWhereAFlatSheetCarriesIt() throws {
        // Four points of one surface that are no parallelogram, seen at a
        // slant: the picture's own coordinates bend at the diagonal unless the
        // mapping is the sheet's.
        let surface = try #require(Plane3(origin: Vector3(0, 1, 0), right: Vector3(1, 0, -0.5),
                                          up: Vector3(0, 1, 0.15)))
        let flat = [Vector2(-0.9, 0.7), Vector2(0.7, 0.5), Vector2(0.9, -0.6), Vector2(-0.5, -0.35)]
        let corners = flat.map { surface.point(at: $0) }
        let sheet = Image(cgImage: Self.dotSheet())
        let lens = OverPicture.askew
        let sketch = OverPicture()
        sketch.lens = lens
        sketch.room = { s in
            s.background(.black)
            s.drawImage(sheet, topLeft: corners[0], topRight: corners[1],
                        bottomRight: corners[2], bottomLeft: corners[3])
        }
        let rendered = Pixels(try OllinApp.image(of: sketch))

        // The sheet's own mapping, from the textbook square-to-quadrilateral
        // form, written out here and sharing nothing with the drawer's.
        let (x0, y0) = (flat[0].x, flat[0].y), (x1, y1) = (flat[1].x, flat[1].y)
        let (x2, y2) = (flat[2].x, flat[2].y), (x3, y3) = (flat[3].x, flat[3].y)
        let dx1 = x1 - x2, dx2 = x3 - x2, sx = x0 - x1 + x2 - x3
        let dy1 = y1 - y2, dy2 = y3 - y2, sy = y0 - y1 + y2 - y3
        let det = dx1 * dy2 - dy1 * dx2
        let g = (sx * dy2 - sy * dx2) / det, h = (dx1 * sy - dy1 * sx) / det
        func onSurface(_ u: Double, _ v: Double) -> Vector2 {
            let w = g * u + h * v + 1
            return Vector2(((x1 - x0 + g * x1) * u + (x3 - x0 + h * x3) * v + x0) / w,
                           ((y1 - y0 + g * y1) * u + (y3 - y0 + h * y3) * v + y0) / w)
        }
        sketch.width = 320
        sketch.height = 240
        sketch.camera(lens)
        for dot in Self.dots {
            let expected = try #require(sketch.project(surface.point(at: onSurface(dot.u, dot.v))))
            var sumX = 0.0, sumY = 0.0, weight = 0.0
            for y in 0..<rendered.height {
                for x in 0..<rendered.width {
                    // How much of this dot's color the pixel holds, taken
                    // against the other two channels so an edge counts in part.
                    let r = rendered.channel(0, x, y), gr = rendered.channel(1, x, y)
                    let b = rendered.channel(2, x, y)
                    let wanted = [dot.rgb.0 > 0 ? r : 255 - r, dot.rgb.1 > 0 ? gr : 255 - gr,
                                  dot.rgb.2 > 0 ? b : 255 - b].min()!
                    let lit = max(r, gr, b)
                    guard lit > 40, wanted > 128 else { continue }
                    let w = Double(lit)
                    sumX += (Double(x) + 0.5) * w; sumY += (Double(y) + 0.5) * w; weight += w
                }
            }
            #expect(weight > 0, "the dot at \(dot.u), \(dot.v) is on the canvas")
            let found = Vector2(sumX / weight, sumY / weight)
            #expect(found.distance(to: expected) < 0.75,
                    "the dot at \(dot.u), \(dot.v) landed \(found.distance(to: expected)) pixels off")
        }
    }

    @Test func pointsThatCrossOverDrawNothing() throws {
        let sheet = Image(cgImage: Self.dotSheet(side: 32))
        let crossed = try frame { s in
            // Top right and bottom right changed places: a bow tie.
            s.drawImage(sheet, topLeft: Vector3(-0.5, 0.5, -2), topRight: Vector3(0.5, -0.5, -2),
                        bottomRight: Vector3(0.5, 0.5, -2), bottomLeft: Vector3(-0.5, -0.5, -2))
        }
        let bare = try frame()
        #expect(difference(crossed, bare).pixels == 0)
    }

    // MARK: The ray back through a real lens

    @Test func cameraRayInvertsProjectThroughARealLens() throws {
        // A canvas wider than the lens's picture and one taller, so both ways
        // the picture is fitted are read backward.
        for (width, height) in [(640.0, 300.0), (300.0, 640.0), (320.0, 240.0)] {
            let sketch = Sketch()
            sketch.width = width
            sketch.height = height
            sketch.camera(OverPicture.askew)
            for world in [Vector3(0, 1, 0), Vector3(-0.8, 0.4, -1), Vector3(0.7, 1.9, 0.5)] {
                let screen = try #require(sketch.project(world))
                let ray = try #require(sketch.cameraRay(through: screen))
                #expect(ray.origin.distance(to: OverPicture.askew.eye) < 1e-9)
                #expect(ray.distance(to: world) < 1e-5,
                        "on a \(Int(width)) by \(Int(height)) canvas the ray misses by \(ray.distance(to: world))")
            }
        }
    }

    @Test func aClickUnprojectsOntoASurface() throws {
        let sketch = Sketch()
        sketch.width = 320
        sketch.height = 240
        sketch.camera(OverPicture.askew)
        let wall = Plane3(origin: Vector3(0, 1, -0.5), normal: Vector3(0.2, 0, 1))
        let spot = wall.point(at: Vector2(0.35, -0.2))
        let click = try #require(sketch.project(spot))
        let found = try #require(sketch.unproject(click, onto: wall))
        #expect(found.distance(to: spot) < 1e-5)
        #expect(abs(wall.distance(to: found)) < 1e-9, "the point is on the surface")
        // A surface behind the camera is not under any click.
        let behind = Plane3(origin: Vector3(0.6, 1.4, 9), normal: Vector3(0, 0, -1))
        #expect(sketch.unproject(click, onto: behind) == nil)
    }

    @Test func withPlaneDrawsInTheSurfacesOwnCoordinates() throws {
        let wall = Plane3(origin: Vector3(0.2, 0.1, -2), normal: Vector3(0.3, 0, 1))
        let inScope = try frame { s in
            s.noLights()
            s.withPlane(wall) {
                s.translate(0.2, -0.1, 0.05)
                s.drawBox(size: 0.3)
            }
        }
        let byHand = try frame { s in
            s.noLights()
            s.transform(wall.matrix)
            s.translate(0.2, -0.1, 0.05)
            s.drawBox(size: 0.3)
        }
        let bare = try frame()
        #expect(difference(inScope, byHand).pixels == 0)
        #expect(difference(inScope, bare).pixels > 500, "and the box is on the canvas")
    }
}

// MARK: - The surface value

@Suite
struct Plane3Tests {

    private func isFrame(_ plane: Plane3) -> Bool {
        abs(plane.right.length - 1) < 1e-12 && abs(plane.up.length - 1) < 1e-12
            && abs(plane.normal.length - 1) < 1e-12
            && abs(plane.right.dot(plane.up)) < 1e-12
            && abs(plane.right.dot(plane.normal)) < 1e-12
            && abs(plane.up.dot(plane.normal)) < 1e-12
    }

    @Test func aWallReadsRightAndUpForSomeoneFacingIt() {
        let wall = Plane3(origin: Vector3(0, 1, -2), normal: .unitZ)
        #expect(isFrame(wall))
        #expect(wall.up.distance(to: .unitY) < 1e-12, "y climbs the wall")
        #expect(wall.right.distance(to: .unitX) < 1e-12, "x runs to the right of someone facing it")
        #expect(wall.normal.distance(to: .unitZ) < 1e-12)
        // A wall turned any way keeps its up along the room's up.
        let turned = Plane3(origin: .zero, normal: Vector3(0.7, 0, -0.4))
        #expect(isFrame(turned))
        #expect(turned.up.distance(to: .unitY) < 1e-12)
        #expect(turned.normal.distance(to: Vector3(0.7, 0, -0.4).normalized) < 1e-12)
    }

    @Test func aFloorTakesItsUpFromTheRoomsDepth() {
        let floor = Plane3(origin: .zero, normal: .unitY)
        #expect(isFrame(floor))
        #expect(floor.right.distance(to: .unitX) < 1e-12, "x is still the room's x")
        #expect(floor.up.distance(to: Vector3(0, 0, -1)) < 1e-12)
        let ceiling = Plane3(origin: .zero, normal: Vector3(0, -1, 0))
        #expect(isFrame(ceiling))
        #expect(ceiling.normal.distance(to: Vector3(0, -1, 0)) < 1e-12)
        // A normal with no length still gives a surface to draw on.
        #expect(isFrame(Plane3(origin: .zero, normal: .zero)))
    }

    @Test func placesGoOutAndComeBack() {
        let plane = Plane3(origin: Vector3(1, 2, 3), normal: Vector3(0.3, 0.2, 1), up: Vector3(0.1, 1, 0))
        #expect(isFrame(plane))
        let place = Vector2(0.4, -1.3)
        let lifted = plane.point(at: place, lift: 0.25)
        #expect(plane.coordinates(of: lifted).distance(to: place) < 1e-12,
                "a lifted point falls back on the place under it")
        #expect(abs(plane.distance(to: lifted) - 0.25) < 1e-12)
        #expect(abs(plane.distance(to: plane.point(at: place))) < 1e-12)
        // The matrix says the same thing in single precision.
        let m = plane.matrix * SIMD4<Float>(0.4, -1.3, 0.25, 1)
        #expect(Vector3(Double(m.x), Double(m.y), Double(m.z)).distance(to: lifted) < 1e-5)
    }

    @Test func aRayMeetsItFromEitherSideAndNeverFromBehindItsOrigin() throws {
        let plane = Plane3(origin: Vector3(0, 0, -2), normal: .unitZ)
        let front = Ray3(origin: .zero, direction: Vector3(0.1, 0.2, -1))
        let hit = try #require(plane.intersection(with: front))
        #expect(abs(hit.z + 2) < 1e-12)
        #expect(hit.distance(to: Vector3(0.2, 0.4, -2)) < 1e-12)
        #expect(abs((front.hit(plane) ?? 0) - hit.length) < 1e-12)
        let back = Ray3(origin: Vector3(0, 0, -5), direction: .unitZ)
        #expect(plane.intersection(with: back) != nil, "the back of a surface is met too")
        #expect(plane.intersection(with: Ray3(origin: .zero, direction: .unitZ)) == nil,
                "a ray pointing away never meets it")
        #expect(plane.intersection(with: Ray3(origin: .zero, direction: .unitX)) == nil,
                "nor one running along it")
    }

    @Test func aSurfaceIsFittedThroughPoints() throws {
        let truth = Plane3(origin: Vector3(0.5, 1.2, -1.8), normal: Vector3(0.4, 0.1, 1))
        // Three points: the surface through all of them.
        let three = [Vector2(0, 0), Vector2(1, 0.2), Vector2(0.3, 0.9)].map { truth.point(at: $0) }
        let exact = try #require(Plane3(through: three, facing: truth.point(at: .zero, lift: 3)))
        #expect(exact.normal.distance(to: truth.normal) < 1e-9)
        for point in three { #expect(abs(exact.distance(to: point)) < 1e-9) }

        // Many points a little off the surface: the fit lies within the
        // scatter, and `facing` picks the front.
        var generator = SystemRandomNumberGenerator()
        var cloud: [Vector3] = []
        for _ in 0..<200 {
            let at = Vector2(Double.random(in: -1...1, using: &generator),
                             Double.random(in: -0.7...0.7, using: &generator))
            cloud.append(truth.point(at: at, lift: Double.random(in: -0.004...0.004, using: &generator)))
        }
        let fitted = try #require(Plane3(through: cloud, facing: truth.point(at: .zero, lift: 3)))
        #expect(fitted.normal.dot(truth.normal) > 0.9999, "the fit faces the way the surface does")
        #expect(abs(truth.distance(to: fitted.origin)) < 0.002)
        let behind = try #require(Plane3(through: cloud, facing: truth.point(at: .zero, lift: -3)))
        #expect(behind.normal.dot(truth.normal) < -0.9999, "handed a point behind, it faces that way")

        // With no side named, the front is where the points run counter-clockwise.
        let around = [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
        let wound = try #require(Plane3(through: around.map { truth.point(at: $0) }))
        #expect(wound.normal.dot(truth.normal) > 0.9999)
        let unwound = try #require(Plane3(through: around.reversed().map { truth.point(at: $0) }))
        #expect(unwound.normal.dot(truth.normal) < -0.9999)

        // Points that name no surface.
        #expect(Plane3(through: [.zero, .unitX]) == nil, "two points")
        #expect(Plane3(through: [.zero, .unitX, .unitX * 2, .unitX * 5]) == nil, "points along a line")
        #expect(Plane3(through: [.unitY, .unitY, .unitY]) == nil, "one place three times")
        // Three points square to an axis, where two of the scatter's rows are empty.
        let level = try #require(Plane3(through: [Vector3(0, 2, 0), Vector3(1, 2, 0), Vector3(0, 2, -1)]))
        #expect(abs(abs(level.normal.y) - 1) < 1e-9)
    }

    @Test func movedTurnedAndFlippedAreTheSameSurface() {
        let plane = Plane3(origin: Vector3(0, 1, -2), normal: Vector3(0.2, 0, 1))
        let moved = plane.moved(by: Vector2(0.5, -0.25), lift: 0.1)
        #expect(moved.origin.distance(to: plane.point(at: Vector2(0.5, -0.25), lift: 0.1)) < 1e-12)
        #expect(moved.right.distance(to: plane.right) < 1e-12 && moved.up.distance(to: plane.up) < 1e-12)

        let turned = plane.turned(by: .pi / 2)
        #expect(isFrame(turned))
        #expect(turned.right.distance(to: plane.up) < 1e-12, "a quarter turn puts x where y was")
        #expect(turned.normal.distance(to: plane.normal) < 1e-12)

        let flipped = plane.flipped
        #expect(isFrame(flipped))
        #expect(flipped.normal.distance(to: -plane.normal) < 1e-12)
        #expect(flipped.up.distance(to: plane.up) < 1e-12, "up is still up from behind")

        #expect(Plane3(origin: .zero, right: .unitX, up: .unitX * 3) == nil,
                "two directions along one line name no surface")
        #expect(Plane3(origin: .zero, right: .zero, up: .unitY) == nil)
    }
}
