import Testing
import Ollin
@testable import OllinVision

/// Contour detection on procedurally-generated images — no camera, no bundled
/// asset, so it runs in CI. The disk test also pins the coordinate orientation
/// numerically: a dark disk authored in the *top* of the image must map into the
/// *top* of the canvas, which only holds if the y-flip is right.
@Suite struct ContourDetectorTests {

    /// A white image with a filled black disk centered at `(cx, cy)` (top-left
    /// pixel coordinates).
    private func diskImage(size: Int, cx: Double, cy: Double, r: Double) -> Image {
        let image = Image(width: size, height: size, color: .white)
        let black = Color(white: 0)
        for y in 0..<size {
            for x in 0..<size {
                let dx = Double(x) - cx, dy = Double(y) - cy
                if dx * dx + dy * dy < r * r { image[x, y] = black }
            }
        }
        return image
    }

    @Test func tracesADarkDiskInTheTopHalf() async throws {
        // Disk in the upper portion of a 200×200 image (cy = 50).
        let image = diskImage(size: 200, cx: 100, cy: 50, r: 30)
        let found = try await ContourDetector.detect(in: image, detectsDarkOnLight: true)
        #expect(found.count >= 1)

        // Map into a 100×100 canvas; the disk should land in the top half and be
        // roughly centered horizontally. A wrong y-flip would put it in the bottom.
        let rect = Rectangle(x: 0, y: 0, width: 100, height: 100)
        let points = found.contours(in: rect).flatMap { $0.points }
        #expect(!points.isEmpty)
        let avgX = points.map(\.x).reduce(0, +) / Double(points.count)
        let avgY = points.map(\.y).reduce(0, +) / Double(points.count)
        #expect(avgY < 50)            // top half (verifies the flip)
        #expect(avgX > 30 && avgX < 70)   // horizontally centered
    }

    @Test func shapesAreProducedForADisk() async throws {
        let image = diskImage(size: 160, cx: 80, cy: 80, r: 40)
        let found = try await ContourDetector.detect(in: image)
        let shapes = found.shapes(in: Rectangle(x: 0, y: 0, width: 100, height: 100))
        #expect(!shapes.isEmpty)
        #expect(shapes.first?.contours.first.map { $0.points.count >= 3 } ?? false)
    }

    @Test func blankImageDetectsCleanly() async throws {
        let image = Image(width: 64, height: 64, color: .white)
        let found = try await ContourDetector.detect(in: image)
        #expect(found.count >= 0)   // no trap, empty or near-empty is fine
    }
}
