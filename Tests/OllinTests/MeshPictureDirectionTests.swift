@testable import Ollin
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

/// Which way round a picture reads on a mesh that carries uvs.
///
/// An image's `u` runs left to right and its `v` top to bottom. Seen from the
/// side a surface's normals face, a picture reads as the image does when the
/// surface carries `u` to the viewer's right while `v` runs down; carried the
/// other way round it reads as in a mirror, and lettering comes out backwards.
///
/// Two readings of the same fact are here. One needs no GPU: a triangle's
/// corners go round one way seen from outside and one way on the image, and
/// the two have to agree (`readingShare`). The other draws the mesh wearing a
/// ramp and reads the ramp off the frame, which is the one that would catch a
/// sampler or a shader turning the picture after the mesh got it right.
@Suite(.serialized)
@MainActor
struct MeshPictureDirectionTests {

    // MARK: The reading that needs no GPU

    /// The share of a mesh's textured area whose picture reads the right way
    /// round from the side its normals face: 1 when all of it does, 0 when it
    /// all reads as in a mirror.
    ///
    /// Seen from outside with y up, a front-facing triangle's corners go round
    /// counter-clockwise. On the image, where `v` runs down the page, the same
    /// corners go round counter-clockwise too when the picture reads right,
    /// and that is a negative area in (u, v), since those axes are a
    /// left-handed pair. A triangle of no size on either side is left out.
    static func readingShare(_ mesh: Mesh) -> Double {
        guard mesh.uvs.count == mesh.positions.count,
              mesh.normals.count == mesh.positions.count else { return .nan }
        var right = 0.0, total = 0.0
        var i = 0
        while i + 2 < mesh.indices.count {
            let a = Int(mesh.indices[i]), b = Int(mesh.indices[i + 1]), c = Int(mesh.indices[i + 2])
            i += 3
            let face = (mesh.positions[b] - mesh.positions[a])
                .cross(mesh.positions[c] - mesh.positions[a])
            let out = mesh.normals[a] + mesh.normals[b] + mesh.normals[c]
            let ta = mesh.uvs[a], tb = mesh.uvs[b], tc = mesh.uvs[c]
            let onImage = (tb.x - ta.x) * (tc.y - ta.y) - (tb.y - ta.y) * (tc.x - ta.x)
            let area = face.length
            guard area > 1e-12, abs(onImage) > 1e-12, abs(face.dot(out)) > 1e-12 else { continue }
            total += area
            let facing = face.dot(out) > 0 ? 1.0 : -1.0
            if facing * onImage < 0 { right += area }
        }
        return total > 0 ? right / total : .nan
    }

    private static let upward = Curve3D([Vector3(0, -1, 0), Vector3(0, 0, 0), Vector3(0, 1, 0)])

    /// Every built-in generator whose picture reads the right way round.
    @Test func aPictureReadsTheRightWayRoundFromOutside() {
        var field = Heightfield(columns: 9, rows: 7)
        for y in 0..<7 { for x in 0..<9 { field[x, y] = Double((x * 3 + y * 5) % 7) / 7 } }
        let stroke = GestureMark(points: (0...24).map { k in
            let t = Double(k) / 24
            return Vector2(100 + 400 * t, 300 + 60 * sin(t * 6))
        }, widths: [Double](repeating: 40, count: 25))
        let carriers: [(name: String, mesh: Mesh)] = [
            ("sphere", Mesh.sphere()),
            ("sphere, 24 by 12", Mesh.sphere(radius: 3, segments: 24, rings: 12)),
            ("sphere, 7 by 5", Mesh.sphere(radius: 1, segments: 7, rings: 5)),
            ("sphere, 3 by 2", Mesh.sphere(radius: 1, segments: 3, rings: 2)),
            ("plane", Mesh.plane(width: 2, depth: 2, segments: 3)),
            ("heightfield", field.mesh(width: 4, depth: 3, height: 1)),
            ("gesture tube", stroke.tube(sides: 12)),
        ]
        for entry in carriers {
            let share = Self.readingShare(entry.mesh)
            // The gesture's tube is a little under 1: where its path bends hard
            // the inside of the bend folds a few triangles over.
            #expect(share > 0.99, "\(entry.name) reads the right way round on \(share) of its area")
        }
    }

    /// The meshes built along a path still carry a picture mirrored: a swept or
    /// lofted wall and a strip between two rails read the right way round on
    /// none of their area (measured 2026-11-23). Pinned until they are turned,
    /// so the day they are this fails and the three join the list above.
    @Test func theMeshesBuiltAlongAPathAreStillMirrored() {
        let rail = [Vector3(-1, 0, 0), Vector3(0, 0, 0.2), Vector3(1, 0, 0)]
        let carriers: [(name: String, mesh: Mesh)] = [
            ("sweep", Mesh.sweep(Profile.ellipse(radiusX: 0.4, radiusY: 0.4, segments: 16),
                                 along: Self.upward, capped: false)),
            ("loft", Mesh.loft([Profile.rectangle(width: 0.6, height: 0.6),
                                Profile.ellipse(radiusX: 0.2, radiusY: 0.2, segments: 16)],
                               along: Self.upward, capped: false)),
            ("strip", Mesh.strip(between: rail, and: rail.map { $0 + Vector3(0, 0.6, 0) })),
        ]
        for entry in carriers {
            withKnownIssue("a \(entry.name) carries its picture mirrored: 0 of its area reads right, 2026-11-23") {
                #expect(Self.readingShare(entry.mesh) > 0.99)
            }
        }
    }

    // MARK: Where the picture sits on a ball

    /// The point of a unit ball a uv stands for, as the reference gives it.
    static func ballPoint(_ uv: Vector2) -> Vector3 {
        let turn = 2 * Double.pi * uv.x, down = Double.pi * uv.y
        return Vector3(-sin(turn) * sin(down), cos(down), -cos(turn) * sin(down))
    }

    @Test func aBallCarriesThePicturesMiddleOnItsFront() {
        for (segments, rings) in [(32, 16), (64, 32), (24, 12), (7, 5), (6, 3), (3, 2)] {
            let radius = 2.5
            let ball = Mesh.sphere(radius: radius, segments: segments, rings: rings)
            #expect(ball.uvs.count == ball.positions.count)
            var worst = 0.0
            for (p, uv) in zip(ball.positions, ball.uvs) {
                #expect((0...1).contains(uv.x) && (0...1).contains(uv.y))
                worst = max(worst, (p - Self.ballPoint(uv) * radius).length)
            }
            #expect(worst < 1e-12, "\(segments) by \(rings): a vertex stands \(worst) from its uv's place")
        }
        // The four places a sketch turns a ball by: the middle on the front, a
        // quarter to either side, and the picture's two edges meeting at the back.
        #expect((Self.ballPoint(Vector2(0.5, 0.5)) - Vector3(0, 0, 1)).length < 1e-12)
        #expect((Self.ballPoint(Vector2(0.25, 0.5)) - Vector3(-1, 0, 0)).length < 1e-12)
        #expect((Self.ballPoint(Vector2(0.75, 0.5)) - Vector3(1, 0, 0)).length < 1e-12)
        #expect((Self.ballPoint(Vector2(0, 0.5)) - Vector3(0, 0, -1)).length < 1e-12)
        #expect((Self.ballPoint(Vector2(1, 0.5)) - Vector3(0, 0, -1)).length < 1e-12)
        #expect((Self.ballPoint(Vector2(0.3, 0)) - Vector3(0, 1, 0)).length < 1e-12)
    }

    /// A sketch written for a ball that carries its picture mirrored, starting
    /// on +x, can have that placement: with `u` mapped to `0.75 - u` under a
    /// tiling wrap, every point reads the picture at its angle round y from +x
    /// toward +z, as a share of a turn. The changelog names this map.
    @Test func theMirroredPlacementIsOneMapOfTheUVsAway() {
        let ball = Mesh.sphere(radius: 1, segments: 24, rings: 12)
        for (p, uv) in zip(ball.positions, ball.uvs) where abs(p.y) < 0.999 {
            let fromPlusX = atan2(p.z, p.x) / (2 * .pi)
            let mapped = 0.75 - uv.x
            let apart = (mapped - fromPlusX) - (mapped - fromPlusX).rounded()
            #expect(abs(apart) < 1e-9, "at \(p): the angle from +x is u = \(fromPlusX), the map gives \(mapped)")
        }
    }

    /// The twin the ball's solid is held against: the same grid built with its
    /// columns starting on +x and going round by +z, quad after quad in column
    /// order. (Built that way a ball carries a picture mirrored, which is why
    /// the generator's columns run the other way.)
    static func ballFromPlusX(radius: Double, segments: Int, rings: Int) -> [[Vector3]] {
        let segs = max(segments, 3), rng = max(rings, 2)
        var points: [Vector3] = []
        for i in 0...rng {
            let theta = Double(i) / Double(rng) * .pi
            for j in 0...segs {
                let phi = Double(j) / Double(segs) * 2 * .pi
                points.append(Vector3(sin(theta) * cos(phi), cos(theta), sin(theta) * sin(phi)) * radius)
            }
        }
        var triangles: [[Vector3]] = []
        let stride = segs + 1
        for i in 0..<rng {
            for j in 0..<segs {
                let a = i * stride + j, b = (i + 1) * stride + j
                triangles.append([points[a], points[a + 1], points[b + 1]])
                triangles.append([points[a], points[b + 1], points[b]])
            }
        }
        return triangles
    }

    static func triangles(of mesh: Mesh) -> [[Vector3]] {
        stride(from: 0, to: mesh.indices.count - 2, by: 3).map { k in
            (0..<3).map { mesh.positions[Int(mesh.indices[k + $0])] }
        }
    }

    /// Where the picture's join sits is no part of the solid. A ball whose
    /// segment count is a multiple of four, the default among them, is the
    /// twin triangle for triangle: the same triangles, in the same order, with
    /// their corners in the same order. The order matters because a see-through
    /// ball blends its faces as they are listed.
    @Test func aBallOfFourfoldSegmentsIsTheTwinTriangleForTriangle() {
        for (segments, rings) in [(32, 16), (64, 32), (96, 48), (24, 12), (8, 4), (4, 2)] {
            let now = Self.triangles(of: Mesh.sphere(radius: 1.5, segments: segments, rings: rings))
            let twin = Self.ballFromPlusX(radius: 1.5, segments: segments, rings: rings)
            #expect(now.count == twin.count)
            var worst = 0.0
            for (a, b) in zip(now, twin) {
                for corner in 0..<3 { worst = max(worst, (a[corner] - b[corner]).length) }
            }
            #expect(worst < 1e-12, "\(segments) by \(rings): a corner moved by \(worst)")
        }
    }

    /// At any other count the join still needs a column of points at the back,
    /// so the ball is the twin turned a quarter turn about y: the same
    /// triangles, each carried from (x, y, z) to (z, y, -x).
    @Test func aBallOfAnyOtherCountIsTheTwinAQuarterTurnRound() {
        func key(_ t: [Vector3]) -> [Int] {
            let center = (t[0] + t[1] + t[2]) / 3
            return [center.x, center.y, center.z].map { Int(($0 * 1e9).rounded()) }
        }
        for (segments, rings) in [(5, 3), (6, 3), (7, 5), (10, 5), (30, 15)] {
            let now = Self.triangles(of: Mesh.sphere(radius: 1, segments: segments, rings: rings))
            let turned = Self.ballFromPlusX(radius: 1, segments: segments, rings: rings)
                .map { $0.map { Vector3($0.z, $0.y, -$0.x) } }
            // The degenerate triangles at a pole have no center of their own to
            // tell them apart by, so the comparison is over the ones with area.
            func solid(_ list: [[Vector3]]) -> Set<[Int]> {
                Set(list.filter { ($0[1] - $0[0]).cross($0[2] - $0[0]).length > 1e-9 }.map(key))
            }
            #expect(solid(now) == solid(turned), "\(segments) by \(rings)")
            // And every triangle still faces out of the ball.
            for t in now where (t[1] - t[0]).cross(t[2] - t[0]).length > 1e-9 {
                #expect((t[1] - t[0]).cross(t[2] - t[0]).dot(t[0] + t[1] + t[2]) > 0)
            }
        }
    }

    // MARK: The reading off a frame

    /// Red rising left to right and green rising top to bottom, with a white
    /// stripe down one column of the picture, so a frame says both which way
    /// round the picture went on and where that column landed.
    static func ramp(stripeAt u: Double? = nil) -> Image {
        let w = 256, h = 128
        var image = Image(width: w, height: h, color: .black)
        for y in 0..<h {
            for x in 0..<w {
                let onStripe = u.map { abs((Double(x) + 0.5) / Double(w) - $0) < 0.012 } ?? false
                image[x, y] = onStripe ? .white
                    : Color(red: (Double(x) + 0.5) / Double(w), green: (Double(y) + 0.5) / Double(h), blue: 0)
            }
        }
        return image
    }

    final class BallProbe: Sketch {
        var picture = MeshPictureDirectionTests.ramp()
        var segments = 32
        var turn = 0.0
        override var canvasSize: CanvasSize { .square(240) }

        override func draw() {
            background(.black)
            // Straight on from the front, the ball filling most of the frame.
            ortho(eye: Vector3(0, 0, 10), target: .zero, up: .unitY, height: 2.4)
            ambientLight(.white)
            fill(.white)
            rotateY(turn)
            drawMesh(Mesh.sphere(radius: 1, segments: segments, rings: 16).textured(picture))
        }
    }

    private func render(_ sketch: Sketch) throws -> Pixels {
        Pixels(try OllinApp.image(of: sketch, frame: 1))
    }

    /// The mean of one channel over a small patch centered at a fraction of the frame.
    private func patch(_ p: Pixels, _ fx: Double, _ fy: Double, channel: Int) -> Double {
        let cx = Int(Double(p.width) * fx), cy = Int(Double(p.height) * fy)
        var sum = 0, count = 0
        for y in (cy - 3)...(cy + 3) {
            for x in (cx - 3)...(cx + 3) {
                sum += Int(p.bytes[(y * p.width + x) * 4 + channel]); count += 1
            }
        }
        return Double(sum) / Double(count)
    }

    /// The column a white stripe stands at along the frame's middle row: the
    /// mean of the columns whose blue is lit (the ramp has no blue of its own).
    private func stripeColumn(_ p: Pixels) -> Double {
        let row = p.height / 2
        var sum = 0.0, weight = 0.0
        for x in 0..<p.width {
            let blue = Double(p.bytes[(row * p.width + x) * 4 + 2])
            if blue > 128 { sum += Double(x) * blue; weight += blue }
        }
        return weight > 0 ? sum / weight : .nan
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aBallShowsItsPictureLeftToRight() throws {
        for segments in [32, 7] {
            let probe = BallProbe()
            probe.segments = segments
            let frame = try render(probe)
            let left = patch(frame, 0.32, 0.5, channel: 0), middle = patch(frame, 0.5, 0.5, channel: 0)
            let right = patch(frame, 0.68, 0.5, channel: 0)
            #expect(left + 12 < middle && middle + 12 < right,
                    "\(segments) segments: red should rise left to right across the ball: \(left), \(middle), \(right)")
            let top = patch(frame, 0.5, 0.3, channel: 1), bottom = patch(frame, 0.5, 0.7, channel: 1)
            #expect(top + 30 < bottom, "green should rise from the top of the ball down: \(top), \(bottom)")
        }
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func aBallShowsThePicturesMiddleInFront() throws {
        // The stripe down the picture's middle lands on the frame's middle
        // column; the same stripe at a quarter lands halfway to the left limb
        // and does not reach the middle.
        let middle = BallProbe()
        middle.picture = Self.ramp(stripeAt: 0.5)
        let front = try render(middle)
        #expect(patch(front, 0.5, 0.5, channel: 2) > 200, "the middle stripe should cross the frame's middle")

        let quarter = BallProbe()
        quarter.picture = Self.ramp(stripeAt: 0.375)
        let side = try render(quarter)
        #expect(patch(side, 0.5, 0.5, channel: 2) < 30)
        // u = 0.375 is 45 degrees left of the front, so sin 45 of the radius to
        // the left of the middle: the radius is 100 pixels, 120 - 70.7 = 49.
        let column = stripeColumn(side)
        #expect(abs(column - 49.3) <= 2, "the stripe at u = 0.375 should stand at column 49, not \(column)")
    }

    /// The turn the reference names: `rotateY(.pi / 2)` brings the quarter that
    /// was on the left to the front.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aQuarterTurnBringsTheLeftQuarterForward() throws {
        let probe = BallProbe()
        probe.picture = Self.ramp(stripeAt: 0.25)
        probe.turn = .pi / 2
        let frame = try render(probe)
        #expect(abs(stripeColumn(frame) - 120) <= 2,
                "the stripe at u = 0.25 should stand at the frame's middle, not \(stripeColumn(frame))")
    }

    // MARK: The surroundings, seen from inside

    final class SkyProbe: Sketch {
        var url: URL!
        override var canvasSize: CanvasSize { .square(240) }

        override func draw() {
            background(.black)
            // A sketch's usual place: on +z, looking back at the origin.
            camera(.orbiting(radius: 4, fieldOfView: .pi / 3))
            environment(.hdri(url: url).backgroundBlurred(0))
            // The backdrop is drawn with the scene, so the scene needs something
            // in it: a bead under the frame's lower edge, out of every patch read.
            withState {
                translate(0, -2.1, 0)
                fill(.white)
                drawSphere(radius: 0.05)
            }
        }
    }

    private func write(_ image: Image, named name: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        let cg = image.currentCGImage()
        let dest = try #require(CGImageDestinationCreateWithURL(
            url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, cg, nil)
        #expect(CGImageDestinationFinalize(dest))
        return url
    }

    /// The surroundings are a picture seen from inside, with a lookup of their
    /// own that the ball's coordinates have no part in: from a sketch's usual
    /// place the backdrop reads left to right, and the column of the picture
    /// straight ahead is its first quarter (the picture's middle stands on +x,
    /// to the right).
    @Test(.enabled(if: Snapshot.hasMetal))
    func theSurroundingsReadLeftToRightFromInside() throws {
        let probe = SkyProbe()
        probe.url = try write(Self.ramp(), named: "ollin-picture-direction-sky.png")
        let frame = try render(probe)
        let left = patch(frame, 0.2, 0.5, channel: 0), middle = patch(frame, 0.5, 0.5, channel: 0)
        let right = patch(frame, 0.8, 0.5, channel: 0)
        #expect(left + 8 < middle && middle + 8 < right,
                "red should rise left to right across the backdrop: \(left), \(middle), \(right)")

        let striped = SkyProbe()
        striped.url = try write(Self.ramp(stripeAt: 0.25), named: "ollin-picture-direction-sky-stripe.png")
        let ahead = try render(striped)
        let column = stripeColumn(ahead)
        #expect(abs(column - 120) <= 4, "the picture's first quarter should stand straight ahead, not at column \(column)")
    }

    // MARK: A normal map follows the picture

    /// A normal map that leans everywhere one way: toward the picture's right
    /// (+u), or toward its top (the green channel, which points up the image).
    static func leaning(up: Bool) -> Image {
        // (0.6, 0, 0.8) or (0, 0.6, 0.8) in tangent space, written as a color.
        Image(width: 8, height: 8, color: up ? Color(red: 0.5, green: 0.8, blue: 0.9)
                                             : Color(red: 0.8, green: 0.5, blue: 0.9))
    }

    final class ReliefProbe: Sketch {
        /// Where the one light comes from, as the viewer sees it.
        var lightFrom = Vector3(1, 0, 0)
        var leansUp = false
        override var canvasSize: CanvasSize { .square(240) }

        override func draw() {
            background(.black)
            ortho(eye: Vector3(0, 0, 10), target: .zero, up: .unitY, height: 2.4)
            // One light, traveling in from one side and a little toward the ball.
            directionalLight(.white, direction: Vector3(-lightFrom.x, -lightFrom.y, -0.6))
            fill(.white)
            material(.dielectric(roughness: 1))
            drawMesh(Mesh.sphere(radius: 1, segments: 48, rings: 24)
                .normalMapped(MeshPictureDirectionTests.leaning(up: leansUp)))
        }
    }

    private func frontBrightness(leansUp: Bool, lightFrom: Vector3) throws -> Double {
        let probe = ReliefProbe()
        probe.leansUp = leansUp
        probe.lightFrom = lightFrom
        return patch(try render(probe), 0.5, 0.5, channel: 0)
    }

    /// The basis a normal map is read in comes from the mesh's uvs, so it goes
    /// the way the picture does: relief that leans toward the picture's right
    /// leans toward the viewer's right, and the front of the ball takes more of
    /// a light from the right than of the same light from the left. Relief that
    /// leans up the picture leans up the ball, which is the half of the basis
    /// its handedness decides.
    @Test(.enabled(if: Snapshot.hasMetal))
    func reliefLeansTheWayThePictureReads() throws {
        let fromRight = try frontBrightness(leansUp: false, lightFrom: Vector3(1, 0, 0))
        let fromLeft = try frontBrightness(leansUp: false, lightFrom: Vector3(-1, 0, 0))
        #expect(fromRight > fromLeft + 40,
                "leaning right, the front should be brighter lit from the right (\(fromRight)) than from the left (\(fromLeft))")
        let fromAbove = try frontBrightness(leansUp: true, lightFrom: Vector3(0, 1, 0))
        let fromBelow = try frontBrightness(leansUp: true, lightFrom: Vector3(0, -1, 0))
        #expect(fromAbove > fromBelow + 40,
                "leaning up, the front should be brighter lit from above (\(fromAbove)) than from below (\(fromBelow))")
        // The basis is right-handed where the picture is not mirrored.
        let ball = Mesh.sphere(radius: 1, segments: 16, rings: 8).generatingTangents()
        #expect(ball.tangents.count == ball.positions.count)
        #expect(ball.tangents.allSatisfy { $0.handedness == 1 })
    }
}
