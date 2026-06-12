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
}
