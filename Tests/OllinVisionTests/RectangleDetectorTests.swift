import Testing
import Ollin
@testable import OllinVision

/// Rectangle detection is classical CV (no ML model), so it runs anywhere and is
/// fully checkable on a generated image — including the coordinate orientation:
/// a rectangle drawn in the top of the image must map to the top of the canvas.
@Suite struct RectangleDetectorTests {

    /// A white image with a black filled rectangle (top-left pixel coordinates).
    private func rectImage(width: Int, height: Int, x0: Int, y0: Int, x1: Int, y1: Int) -> Image {
        let image = Image(width: width, height: height, color: .white)
        let black = Color(white: 0)
        for y in y0...y1 { for x in x0...x1 { image[x, y] = black } }
        return image
    }

    @Test func detectsARectangleInTheTopHalf() async throws {
        // A black rectangle in the upper portion: center ≈ (200, 90) of a 400×300.
        let image = rectImage(width: 400, height: 300, x0: 120, y0: 40, x1: 280, y1: 140)
        let rects = try await RectangleDetector.detect(in: image, minConfidence: 0.0)
        #expect(!rects.isEmpty)
        guard let r = rects.first else { return }

        let canvas = Rectangle(x: 0, y: 0, width: 400, height: 300)
        let c = r.center(in: canvas)
        #expect(abs(c.x - 200) < 60)   // horizontally centered
        #expect(c.y < 150)             // top half (verifies the y-flip)
        #expect(abs(c.y - 90) < 60)
        #expect(r.corners(in: canvas).count == 4)
    }

    @Test func blankImageHasNoRectangles() async throws {
        let image = Image(width: 200, height: 200, color: .white)
        let rects = try await RectangleDetector.detect(in: image)
        #expect(rects.isEmpty)
    }
}
