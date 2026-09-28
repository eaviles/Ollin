import CoreGraphics
import Testing
@testable import Ollin

/// The corner pin: a layer laid onto four points through the square-to-
/// quadrilateral map the installation projection uses. The unit square pinned
/// to itself has to change no byte; the four corners and the edge midpoints
/// have to land on their points within a pixel, with the layer inside them and
/// nothing outside; a mark drawn into the layer has to come out where the map
/// sends it; and four points with no area between them have to show nothing.
@Suite
@MainActor
struct CornerPinTests {

    /// Four points with a real perspective in them: two edges converge.
    static let quad = (topLeft: Vector2(0.12, 0.18), topRight: Vector2(0.86, 0.08),
                       bottomRight: Vector2(0.92, 0.9), bottomLeft: Vector2(0.2, 0.78))

    static func pinned(_ q: (topLeft: Vector2, topRight: Vector2, bottomRight: Vector2, bottomLeft: Vector2)) -> Filter {
        .cornerPin(topLeft: q.topLeft, topRight: q.topRight, bottomRight: q.bottomRight, bottomLeft: q.bottomLeft)
    }

    // MARK: Identity

    @Test(.enabled(if: Snapshot.hasMetal))
    func theSquarePinnedToItselfChangesNoByte() throws {
        let plain = try #require(OllinApp.image(of: MarkProbe.make(nil), frame: 1))
        let pinned = try #require(OllinApp.image(of: MarkProbe.make(.cornerPin()), frame: 1))
        #expect(maxDifference(plain, pinned) == 0)
        // The gate can fail: a moved corner moves bytes.
        let moved = try #require(OllinApp.image(
            of: MarkProbe.make(.cornerPin(bottomRight: Vector2(0.7, 0.8))), frame: 1))
        #expect(maxDifference(plain, moved) > 100)
    }

    // MARK: Where the layer lands

    /// Just inside each corner and each edge midpoint the layer is there, and
    /// just outside it is not, so the outline lands within a pixel of the four
    /// points and the straight edges between them.
    @Test(.enabled(if: Snapshot.hasMetal))
    func theCornersAndEdgesLandOnTheirPoints() throws {
        let q = Self.quad
        let image = try #require(OllinApp.image(of: MarkProbe.make(Self.pinned(q)), frame: 1))
        let px = pixels(of: image)
        let map = try #require(Homography(unitSquareTo: q.topLeft, q.topRight, q.bottomRight, q.bottomLeft))
        let inside = Vector2(0.5, 0.5)
        // The square's corners and edge midpoints, and where the map sends them.
        let squarePoints = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1),
                            Vector2(0.5, 0), Vector2(1, 0.5), Vector2(0.5, 1), Vector2(0, 0.5)]
        for s in squarePoints {
            // Step along the map's own image of the line toward the middle, so
            // the step is inside whatever the corner's angle is.
            let landed = map.map(s) * 200
            let toward = (map.map(s + (inside - s) * 0.05) * 200 - landed).normalized
            let inPoint = landed + toward * 1.5
            let outPoint = landed - toward * 2
            #expect(brightness(px, at: inPoint) > 200,
                    "\(s) landed at \(landed): 1.5 px inside reads \(brightness(px, at: inPoint))")
            // The present pass dithers, so a black pixel reads 0 or 1.
            #expect(brightness(px, at: outPoint) <= 1,
                    "\(s) landed at \(landed): 2 px outside reads \(brightness(px, at: outPoint))")
        }
    }

    /// The mark drawn a quarter of the way into the layer comes out centered
    /// where the map sends that point, within a pixel: the inside follows the
    /// corners, not only the outline.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aMarkInsideFollowsTheMap() throws {
        let q = Self.quad
        let image = try #require(OllinApp.image(of: MarkProbe.make(Self.pinned(q)), frame: 1))
        let map = try #require(Homography(unitSquareTo: q.topLeft, q.topRight, q.bottomRight, q.bottomLeft))
        let predicted = map.map(MarkProbe.mark) * 200
        let found = try #require(redCentroid(pixels(of: image), near: predicted, within: 12))
        #expect((found - predicted).length < 1.0, "the mark landed at \(found), the map says \(predicted)")
    }

    /// Three points in a line, and two on top of each other: nothing to draw.
    @Test(.enabled(if: Snapshot.hasMetal))
    func aPinWithNoAreaShowsNothing() throws {
        let flat = Filter.cornerPin(topLeft: Vector2(0, 0), topRight: Vector2(0.5, 0),
                                    bottomRight: Vector2(1, 0), bottomLeft: Vector2(0, 1))
        let doubled = Filter.cornerPin(topLeft: Vector2(0.2, 0.2), topRight: Vector2(0.2, 0.2),
                                       bottomRight: Vector2(0.8, 0.8), bottomLeft: Vector2(0.2, 0.8))
        for filter in [flat, doubled] {
            let px = pixels(of: try #require(OllinApp.image(of: MarkProbe.make(filter), frame: 1)))
            // The present pass dithers, so a black pixel reads 0 or 1.
            var lit = 0
            for i in stride(from: 0, to: px.bytes.count, by: 4) where px.bytes[i + 1] > 1 { lit += 1 }
            #expect(lit == 0, "\(lit) pixels lit under a pin with no area")
        }
    }

    // MARK: Pixels

    private func pixels(of image: CGImage) -> (bytes: [UInt8], width: Int, height: Int) {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedLast.rawValue
        if let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8,
                               bytesPerRow: w * 4, space: space, bitmapInfo: info) {
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        return (data, w, h)
    }

    /// The green channel at a canvas point (the layer is white, the mark red, the ground black).
    private func brightness(_ px: (bytes: [UInt8], width: Int, height: Int), at p: Vector2) -> Int {
        let x = min(max(Int(p.x.rounded(.down)), 0), px.width - 1)
        let y = min(max(Int(p.y.rounded(.down)), 0), px.height - 1)
        return Int(px.bytes[(y * px.width + x) * 4 + 1])
    }

    /// The centroid of the red-over-green excess near `point`: the mark, not the white around it.
    private func redCentroid(_ px: (bytes: [UInt8], width: Int, height: Int),
                             near point: Vector2, within radius: Int) -> Vector2? {
        var sum = Vector2(0, 0), weight = 0.0
        let cx = Int(point.x.rounded()), cy = Int(point.y.rounded())
        for y in max(0, cy - radius) ... min(px.height - 1, cy + radius) {
            for x in max(0, cx - radius) ... min(px.width - 1, cx + radius) {
                let i = (y * px.width + x) * 4
                let w = Double(max(0, Int(px.bytes[i]) - Int(px.bytes[i + 1])))
                sum = sum + Vector2(Double(x) + 0.5, Double(y) + 0.5) * w
                weight += w
            }
        }
        return weight > 0 ? sum / weight : nil
    }

    private func maxDifference(_ a: CGImage, _ b: CGImage) -> Int {
        let pa = pixels(of: a), pb = pixels(of: b)
        var worst = 0
        for i in 0 ..< min(pa.bytes.count, pb.bytes.count) {
            worst = max(worst, abs(Int(pa.bytes[i]) - Int(pb.bytes[i])))
        }
        return worst
    }
}

/// A white opaque layer with one red mark a quarter of the way in, laid over black.
private final class MarkProbe: Sketch {
    var filter: Filter?
    static func make(_ filter: Filter?) -> MarkProbe {
        let s = MarkProbe(); s.filter = filter; return s
    }
    /// The mark's center, in fractions of the layer.
    static let mark = Vector2(0.25, 0.25)
    override var canvasSize: CanvasSize { .square(200) }
    override func draw() {
        background(.black)
        let layer = makeRenderTarget()
        withTarget(layer) {
            background(.white)
            noStroke(); fill(Color(red: 1, green: 0, blue: 0))
            drawCircle(Self.mark.x * 200, Self.mark.y * 200, 6)
        }
        drawImage((filter.map { layer.filtered($0) } ?? layer).image, 0, 0)
    }
}
