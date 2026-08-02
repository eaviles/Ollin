import CoreGraphics
import Foundation
@testable import Ollin
import Testing

/// Per-vertex mesh color. The CPU half checks the transforms: `colored(by:)`
/// reads position and normal, `colored(from:)` takes the nearest sample's
/// color, the reconstruction overload carries a cloud's colors (and skips the
/// transfer for an all-white cloud), and `keepingLargestComponent` keeps the
/// surviving piece's colors aligned. The Metal-gated probes pin the draw
/// contract: vertex colors multiply the fill (white fill shows them untouched,
/// a gray fill dims them), and per-vertex variation actually reaches the GPU.
@Suite
@MainActor
struct MeshColorTests {

    // MARK: Support

    /// The camera-facing unit quad the render probes draw: two triangles in the
    /// x-y plane, seen from the default orbit on +z.
    private static func quad() -> Mesh {
        Mesh(positions: [Vector3(-1, -1, 0), Vector3(1, -1, 0),
                         Vector3(1, 1, 0), Vector3(-1, 1, 0)],
             normals: [.unitZ, .unitZ, .unitZ, .unitZ],
             indices: [0, 1, 2, 0, 2, 3])
    }

    private func spherePoints(_ count: Int, radius: Double = 1) -> [Vector3] {
        let golden = Double.pi * (3 - 5.0.squareRoot())
        return (0 ..< count).map { i in
            let y = 1 - 2 * (Double(i) + 0.5) / Double(count)
            let ring = (1 - y * y).squareRoot()
            let angle = golden * Double(i)
            return Vector3(cos(angle) * ring, y, sin(angle) * ring) * radius
        }
    }

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

    // MARK: The transforms

    @Test func coloredByReadsPositionAndNormal() {
        let painted = Self.quad().colored { p, n in
            #expect(n == .unitZ)
            return p.x > 0 ? .red : .blue
        }
        #expect(painted.colors == [.blue, .red, .red, .blue])
        // The original is untouched (a value transform).
        #expect(Self.quad().colors.isEmpty)
    }

    @Test func coloredFromTakesTheNearestSampleColor() {
        let cloud = PointCloud(positions: [Vector3(0, 0, 0), Vector3(10, 0, 0)],
                               colors: [.red, .blue])
        let mesh = Mesh(positions: [Vector3(1, 0.2, 0), Vector3(9, -0.2, 0),
                                    Vector3(4, 0, 0)], indices: [0, 1, 2])
        let painted = mesh.colored(from: cloud)
        #expect(painted.colors == [.red, .blue, .red])
        // An empty cloud changes nothing.
        #expect(mesh.colored(from: PointCloud()).colors.isEmpty)
    }

    @Test func reconstructionCarriesCloudColors() {
        let cloud = PointCloud(points: spherePoints(1600).map {
            .init(position: $0, color: $0.y > 0 ? .red : .blue)
        })
        let mesh = reconstructSurface(of: cloud, resolution: 40, maxGap: .infinity)
        #expect(mesh.colors.count == mesh.positions.count)
        for (v, c) in zip(mesh.positions, mesh.colors) {
            if v.y > 0.3 { #expect(c == .red, "top vertex \(v) took \(c)") }
            if v.y < -0.3 { #expect(c == .blue, "bottom vertex \(v) took \(c)") }
        }
    }

    @Test func anAllWhiteCloudAddsNoColors() {
        let cloud = PointCloud(positions: spherePoints(900))
        let mesh = reconstructSurface(of: cloud, resolution: 32, maxGap: .infinity)
        #expect(!mesh.positions.isEmpty)
        #expect(mesh.colors.isEmpty)
    }

    @Test func keepingLargestComponentKeepsColorsAligned() {
        var points = spherePoints(1400)
        var colors = [Color](repeating: .red, count: 1400)
        points += spherePoints(300, radius: 0.4).map { $0 + Vector3(5, 0, 0) }
        colors += [Color](repeating: .blue, count: 300)
        let cloud = PointCloud(positions: points, colors: colors)
        let mesh = reconstructSurface(of: cloud, resolution: 64, maxGap: .infinity,
                                      keepingLargestComponent: true)
        #expect(!mesh.positions.isEmpty)
        #expect(mesh.colors.count == mesh.positions.count)
        #expect(mesh.colors.allSatisfy { $0 == .red }, "the dropped piece's colors leaked")
    }

    // MARK: The draw contract

    @Test(.enabled(if: Snapshot.hasMetal))
    func vertexColorsShowUntouchedOverAWhiteFill() throws {
        let image = try #require(OllinApp.image(of: VertexColorProbe.make(.redOnWhite), frame: 1))
        let c = pixel(of: image, x: 128, y: 128)
        #expect(c.r >= 230 && c.g <= 15 && c.b <= 15, "expected pure red, got \(c)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func theFillMultipliesAsAWholeMeshTint() throws {
        let image = try #require(OllinApp.image(of: VertexColorProbe.make(.redOnGray), frame: 1))
        let c = pixel(of: image, x: 128, y: 128)
        #expect(c.r >= 115 && c.r <= 140 && c.g <= 15 && c.b <= 15,
                "expected half red, got \(c)")
    }

    @Test(.enabled(if: Snapshot.hasMetal))
    func perVertexVariationReachesTheSurface() throws {
        let image = try #require(OllinApp.image(of: VertexColorProbe.make(.split), frame: 1))
        let left = pixel(of: image, x: 64, y: 128)
        let right = pixel(of: image, x: 192, y: 128)
        #expect(left.r > 150 && left.b < 100, "left half not red: \(left)")
        #expect(right.b > 150 && right.r < 100, "right half not blue: \(right)")
    }
}

/// The render probe: an unlit camera-facing quad whose vertex colors and fill
/// are chosen per mode, at a small canvas for speed.
private final class VertexColorProbe: Sketch {
    enum Mode { case redOnWhite, redOnGray, split }
    var mode = Mode.redOnWhite

    static func make(_ mode: Mode) -> VertexColorProbe {
        let probe = VertexColorProbe()
        probe.mode = mode
        return probe
    }

    override var canvasSize: CanvasSize { .square(256) }

    override func draw() {
        background(.black)
        camera(.orbiting(radius: 3))
        noLights()
        var quad = Mesh(positions: [Vector3(-1, -1, 0), Vector3(1, -1, 0),
                                    Vector3(1, 1, 0), Vector3(-1, 1, 0)],
                        normals: [.unitZ, .unitZ, .unitZ, .unitZ],
                        indices: [0, 1, 2, 0, 2, 3])
        switch mode {
        case .redOnWhite:
            quad.colors = [.red, .red, .red, .red]
            fill(.white)
        case .redOnGray:
            quad.colors = [.red, .red, .red, .red]
            fill(Color(white: 0.5))
        case .split:
            quad.colors = [.red, .blue, .blue, .red]
            fill(.white)
        }
        drawMesh(quad)
    }
}
