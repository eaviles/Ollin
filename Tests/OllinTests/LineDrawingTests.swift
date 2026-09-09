@testable import Ollin
import Testing
import Foundation

/// Checks on `LineDrawing`, the hidden-line renderer that writes a scene down
/// as plottable paths.
///
/// The laws are what makes a drawing a drawing rather than a wireframe with
/// hope in it: a cube shows nine of its twelve edges and the three at the far
/// corner are gone; a wall takes out the middle of what stands behind it and
/// leaves the ends; a smooth ball is its silhouette alone, at the size the
/// camera says, while the same ball with no crease angle is the whole
/// tessellation; a surface that ends is drawn at its border; nothing behind the
/// camera is drawn, and something half behind it is cut at the camera rather
/// than smeared; and what is drawn comes back joined into few paths, since a
/// pen lifting between every edge is a worse drawing and a slower plot.
@Suite
struct LineDrawingTests {

    private let size = Vector2(400, 400)

    private func drawing(_ meshes: [Mesh], camera: Camera3D,
                         creaseAngle: Double = .pi / 6, spacing: Double = 2) -> [Contour] {
        LineDrawing(of: meshes, camera: camera, size: size,
                    creaseAngle: creaseAngle, spacing: spacing).paths
    }

    private func length(_ paths: [Contour]) -> Double {
        paths.reduce(0.0) { total, path in
            let points = path.points
            guard points.count > 1 else { return total }
            var sum = 0.0
            for index in 1..<points.count { sum += (points[index] - points[index - 1]).length }
            if path.isClosed, let first = points.first, let last = points.last {
                sum += (first - last).length
            }
            return total + sum
        }
    }

    /// Every point of every path, as a flat list.
    private func points(_ paths: [Contour]) -> [Vector2] { paths.flatMap(\.points) }

    /// How near the drawn line work comes to a place on the canvas, measured to
    /// the lines themselves rather than to the points they turn at.
    private func nearest(_ paths: [Contour], to place: Vector2) -> Double {
        var best = Double.infinity
        for path in paths {
            let points = path.points
            guard points.count > 1 else {
                if let only = points.first { best = min(best, (only - place).length) }
                continue
            }
            var pairs = (1..<points.count).map { (points[$0 - 1], points[$0]) }
            if path.isClosed, let first = points.first, let last = points.last {
                pairs.append((last, first))
            }
            for (a, b) in pairs {
                let along = b - a
                let square = along.dot(along)
                let t = square > 1e-12 ? min(max((place - a).dot(along) / square, 0), 1) : 0
                best = min(best, (place - (a + along * t)).length)
            }
        }
        return best
    }

    // MARK: - The cube

    @Test func aCubeShowsNineEdgesAndHidesThreeAtTheFarCorner() {
        // Straight down the diagonal, where three faces are seen and three are
        // turned away. The two corners on that diagonal land on the same place
        // on the canvas, so the edges are told apart by their middles: nine of
        // them are drawn and the three at the far corner are not.
        let camera = Camera3D(eye: Vector3(4, 4, 4), target: .zero,
                              projection: .orthographic(height: 6))
        let paths = drawing([.box(size: 2)], camera: camera)
        let far = Vector3(-1, -1, -1)
        var seen = 0, gone = 0
        for axis in 0..<3 {
            for a in [-1.0, 1.0] {
                for b in [-1.0, 1.0] {
                    // The middle of each of the twelve edges, by which axis it
                    // runs along and where the other two sit.
                    var middle = Vector3.zero
                    switch axis {
                    case 0: middle = Vector3(0, a, b)
                    case 1: middle = Vector3(a, 0, b)
                    default: middle = Vector3(a, b, 0)
                    }
                    let hidden = (middle - far).length < 1.01   // it touches the far corner
                    let at = LineDrawing.canvasPoint(of: middle, camera: camera, size: size)!
                    let distance = nearest(paths, to: at)
                    if hidden {
                        #expect(distance > 20, "the hidden edge at \(middle) is not drawn")
                        gone += 1
                    } else {
                        #expect(distance < 3, "the edge at \(middle) is drawn")
                        seen += 1
                    }
                }
            }
        }
        #expect(seen == 9 && gone == 3, "nine drawn and three not: \(seen) and \(gone)")
    }

    @Test func theCubeComesBackAsFewPathsNotTwelve() {
        let camera = Camera3D(eye: Vector3(4, 4, 4), target: .zero)
        let paths = drawing([.box(size: 2)], camera: camera)
        #expect(paths.count <= 3, "the visible edges join up: \(paths.count) paths")
        #expect(paths.contains { $0.isClosed }, "and the silhouette closes")
    }

    // MARK: - One thing behind another

    @Test func aWallTakesOutTheMiddleOfWhatIsBehindIt() {
        // A tall wall in front of a wide bar: the bar's ends stick out either
        // side and its middle is gone.
        let camera = Camera3D(eye: Vector3(0, 0, 8), target: .zero,
                              projection: .orthographic(height: 8))
        let bar = Mesh.box(width: 6, height: 0.6, depth: 0.6)
        let wall = Mesh.box(width: 1.6, height: 4, depth: 0.6)
            .transformed(by: MeshInstance(position: Vector3(0, 0, 2)))
        let alone = drawing([bar], camera: camera)
        let behind = drawing([bar, wall], camera: camera)
        let middle = Vector2(size.x / 2, size.y / 2)
        #expect(nearest(alone, to: middle) < 20, "on its own the bar crosses the middle")
        #expect(nearest(behind, to: middle) > 35,
                "behind the wall its middle is gone: \(nearest(behind, to: middle))")
        // The ends are still there, on both sides.
        for x in [size.x * 0.16, size.x * 0.84] {
            #expect(nearest(behind, to: Vector2(x, size.y / 2)) < 20,
                    "the end at \(x) is still drawn")
        }
    }

    // MARK: - A smooth surface

    @Test func aBallIsItsSilhouetteAtTheSizeTheCameraSays() {
        // An orthographic camera makes the answer exact: a ball of radius 1 in a
        // frame 4 units tall covers a quarter of a 400-point canvas.
        let camera = Camera3D(eye: Vector3(0, 0, 6), target: .zero,
                              projection: .orthographic(height: 4))
        let paths = drawing([.sphere(radius: 1, segments: 64, rings: 32)], camera: camera)
        let middle = Vector2(size.x / 2, size.y / 2)
        let radii = points(paths).map { ($0 - middle).length }
        let expected = size.y / 4
        // The silhouette of a tessellated ball is a polygon inside the circle,
        // so it comes up a hair short of the radius rather than over it.
        #expect(radii.min()! > expected * 0.99, "nothing inside the silhouette: \(radii.min()!)")
        #expect(radii.max()! < expected * 1.01, "nor outside it: \(radii.max()!)")
        // And it is the outline, once round: the drawn length is the circle's
        // own, give or take what the ring of edges crossing it adds.
        let circumference = 2 * .pi * expected
        #expect(abs(length(paths) - circumference) < circumference * 0.15,
                "once round the circle: \(length(paths)) against \(circumference)")
    }

    @Test func noCreaseAngleKeepsTheWholeTessellation() {
        let camera = Camera3D(eye: Vector3(0, 0, 6), target: .zero,
                              projection: .orthographic(height: 4))
        let ball = Mesh.sphere(radius: 1, segments: 24, rings: 12)
        let silhouette = length(drawing([ball], camera: camera))
        let everything = length(drawing([ball], camera: camera, creaseAngle: 0))
        #expect(everything > silhouette * 4,
                "a wireframe is far more line than a drawing: \(everything) against \(silhouette)")
    }

    @Test func aSurfaceThatEndsIsDrawnAtItsBorder() {
        // A flat plane cut into segments: its four borders are drawn and the
        // seams inside it, which bend by nothing at all, are not.
        let camera = Camera3D(eye: Vector3(0, 6, 0.001), target: .zero,
                              projection: .orthographic(height: 4))
        let plane = Mesh.plane(width: 2, depth: 2, segments: 8)
        let paths = drawing([plane], camera: camera)
        let border = 4 * (size.y / 2)
        #expect(abs(length(paths) - border) < border * 0.05,
                "the border and nothing else: \(length(paths)) against \(border)")
    }

    // MARK: - The camera

    @Test func nothingBehindTheCameraIsDrawn() {
        let camera = Camera3D(eye: Vector3(0, 0, 5), target: .zero)
        let behind = Mesh.box(size: 2).transformed(by: MeshInstance(position: Vector3(0, 0, 12)))
        #expect(drawing([behind], camera: camera).isEmpty, "a box behind the eye draws nothing")
    }

    @Test func somethingHalfBehindTheCameraIsCutAtIt() {
        // A long bar running from behind the camera to well in front of it. The
        // far end is drawn where it belongs, the near half is cut at the plane
        // the camera stands on, and nothing comes back as a number that is not
        // a number, which is what an edge dragged around behind the eye gives.
        let camera = Camera3D(eye: .zero, target: Vector3(0, 0, -1))
        let bar = Mesh.box(width: 0.4, height: 0.4, depth: 20)
        let paths = drawing([bar], camera: camera)
        #expect(!paths.isEmpty, "the part in front is drawn")
        let all = points(paths)
        #expect(all.allSatisfy { $0.x.isFinite && $0.y.isFinite }, "and nothing is nonsense")
        let farCorner = LineDrawing.canvasPoint(of: Vector3(0.2, 0.2, -10),
                                                camera: camera, size: size)!
        #expect(nearest(paths, to: farCorner) < 3, "the far end is where it belongs")
    }

    @Test func theHiddenStretchesAreKeptForTheDashedLine() {
        // The three edges of a cube that its own faces cover come back as the
        // hidden set, so a drawing can dash them; the two sets together are the
        // whole of every edge that was worth drawing.
        let camera = Camera3D(eye: Vector3(4, 4, 4), target: .zero,
                              projection: .orthographic(height: 6))
        let full = LineDrawing(of: [.box(size: 2)], camera: camera, size: size)
        let far = LineDrawing.canvasPoint(of: Vector3(-1, -1, -1), camera: camera, size: size)!
        #expect(!full.hidden.isEmpty, "the covered stretches are there")
        #expect(nearest(full.hidden, to: far) < 3, "and they meet at the far corner")
        // Nine edges seen, three covered, all of one length under this camera.
        #expect(abs(length(full.paths) / 3 - length(full.hidden)) < length(full.hidden) * 0.05,
                "three hidden against nine seen: \(length(full.hidden)) and \(length(full.paths))")
    }

    @Test func anEmptySceneDrawsNothing() {
        let camera = Camera3D(eye: Vector3(0, 0, 5), target: .zero)
        #expect(drawing([], camera: camera).isEmpty)
        #expect(drawing([Mesh(positions: [], indices: [])], camera: camera).isEmpty)
    }
}
