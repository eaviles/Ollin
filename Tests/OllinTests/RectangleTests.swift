import Testing
@testable import Ollin

struct RectangleTests {

    @Test func fittingLetterboxesAWideImage() {
        let container = Rectangle(x: 0, y: 0, width: 100, height: 100)
        let fitted = Rectangle(fitting: Vector2(200, 100), in: container)
        #expect(fitted == Rectangle(x: 0, y: 25, width: 100, height: 50))
    }

    @Test func fittingPillarboxesATallImage() {
        let container = Rectangle(x: 10, y: 20, width: 100, height: 60)
        let fitted = Rectangle(fitting: Vector2(50, 100), in: container)
        #expect(abs(fitted.width - 30) < 1e-9)
        #expect(abs(fitted.height - 60) < 1e-9)
        #expect(fitted.center == container.center)
    }

    @Test func fittingMatchingAspectFillsTheContainer() {
        let container = Rectangle(x: 5, y: 5, width: 160, height: 90)
        let fitted = Rectangle(fitting: Vector2(1920, 1080), in: container)
        #expect(fitted == container)
    }

    @Test func fittingDegenerateSizeYieldsTheContainer() {
        let container = Rectangle(x: 0, y: 0, width: 100, height: 100)
        #expect(Rectangle(fitting: Vector2(0, 100), in: container) == container)
        #expect(Rectangle(fitting: Vector2(100, 0), in: container) == container)
    }

    @Test func pointAtNormalizedCoordinates() {
        let rect = Rectangle(x: 10, y: 20, width: 200, height: 100)
        #expect(rect.point(u: 0, v: 0) == rect.topLeft)
        #expect(rect.point(u: 1, v: 1) == rect.bottomRight)
        #expect(rect.point(u: 0.5, v: 0.5) == rect.center)
        #expect(rect.point(u: -0.5, v: 2) == Vector2(-90, 220))   // not clamped
    }

    @Test func uvInvertsPoint() {
        let rect = Rectangle(x: 10, y: 20, width: 200, height: 100)
        #expect(rect.uv(of: rect.point(u: 0.25, v: 0.75)) == Vector2(0.25, 0.75))
        #expect(rect.uv(of: rect.center) == Vector2(0.5, 0.5))
        // A degenerate axis reads 0 instead of dividing by zero.
        let flat = Rectangle(x: 0, y: 0, width: 100, height: 0)
        #expect(flat.uv(of: Vector2(50, 5)) == Vector2(0.5, 0))
    }

    @Test func sketchUVMapsTheCanvas() async {
        await MainActor.run {
            let sketch = Sketch()
            sketch.setCanvasSize(width: 400, height: 200)
            #expect(sketch.uv(0.5, 0.5) == sketch.center)
            #expect(sketch.uv(1, 1) == Vector2(400, 200))
            #expect(sketch.uv(0.25, 0) == Vector2(100, 0))
        }
    }
}
