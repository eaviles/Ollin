import Testing
import Ollin
@testable import OllinVision

/// The normalized↔canvas mapping is pure math, so it runs everywhere (no camera,
/// no GPU, no model). These pin the y-flip, the mirror, and the letterbox fit.
@Suite struct VisionMappingTests {

    let rect = Rectangle(x: 0, y: 0, width: 100, height: 100)

    @Test func lowerLeftOriginFlipsToTopLeft() {
        // Normalized (0,0) is the lower-left; on a top-left canvas that's (0, h).
        let bottomLeft = VisionSpace.point(0, 0, in: rect)
        #expect(bottomLeft.x == 0)
        #expect(bottomLeft.y == 100)

        // Normalized (0,1) (upper-left) maps to the canvas origin.
        let topLeft = VisionSpace.point(0, 1, in: rect)
        #expect(topLeft.x == 0)
        #expect(topLeft.y == 0)

        // Center stays the center.
        let center = VisionSpace.point(0.5, 0.5, in: rect)
        #expect(center.x == 50)
        #expect(center.y == 50)
    }

    @Test func mirrorFlipsX() {
        let p = VisionSpace.point(0, 0, in: rect, mirrored: true)
        #expect(p.x == 100)   // x mirrored
        #expect(p.y == 100)   // y still flipped
    }

    @Test func mappingHonorsRectOffsetAndSize() {
        let offset = Rectangle(x: 200, y: 50, width: 400, height: 200)
        let p = VisionSpace.point(0.5, 0.5, in: offset)
        #expect(p.x == 400)   // 200 + 0.5*400
        #expect(p.y == 150)   // 50  + 0.5*200
    }

    @Test func rectangleMapsToFullTargetForUnitRect() {
        let unit = Rectangle(x: 0, y: 0, width: 1, height: 1)
        let mapped = VisionSpace.rectangle(unit, in: rect)
        #expect(mapped.x == 0)
        #expect(mapped.y == 0)
        #expect(mapped.width == 100)
        #expect(mapped.height == 100)
    }

    @Test func fittedRectLetterboxesWideImage() {
        // A 200×100 image fit into a 100×100 box: scale 0.5 → 100×50, centered.
        let fitted = VisionSpace.fittedRect(imageSize: Vector2(200, 100), in: rect)
        #expect(fitted.width == 100)
        #expect(fitted.height == 50)
        #expect(fitted.x == 0)
        #expect(fitted.y == 25)
    }

    @Test func normalizedPointInvertsPoint() {
        let offset = Rectangle(x: 200, y: 50, width: 400, height: 200)
        for mirrored in [false, true] {
            for n in [Vector2(0, 0), Vector2(0.5, 0.5), Vector2(0.25, 0.8), Vector2(1, 1)] {
                let canvas = VisionSpace.point(n, in: offset, mirrored: mirrored)
                let back = VisionSpace.normalizedPoint(canvas, in: offset, mirrored: mirrored)
                #expect(abs(back.x - n.x) < 1e-9)
                #expect(abs(back.y - n.y) < 1e-9)
            }
        }
    }

    @Test func normalizedRectangleInvertsRectangle() {
        let offset = Rectangle(x: 200, y: 50, width: 400, height: 200)
        let n = Rectangle(x: 0.2, y: 0.3, width: 0.4, height: 0.25)
        for mirrored in [false, true] {
            let canvas = VisionSpace.rectangle(n, in: offset, mirrored: mirrored)
            let back = VisionSpace.normalizedRectangle(canvas, in: offset, mirrored: mirrored)
            #expect(abs(back.x - n.x) < 1e-9)
            #expect(abs(back.y - n.y) < 1e-9)
            #expect(abs(back.width - n.width) < 1e-9)
            #expect(abs(back.height - n.height) < 1e-9)
        }
    }
}
