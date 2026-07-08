import Testing
import Ollin
@testable import OllinVision

/// The synchronous still-image path: `waitFor` must run a one-shot detection
/// inline and hand back the result, including when the caller is the main
/// actor (the `setup()` scenario), where a closure that wrongly inherited
/// main-actor isolation would deadlock against the parked thread.
@Suite struct WaitForTests {

    /// A white image with a filled black disk centered at `(cx, cy)`.
    private static func diskImage(size: Int, cx: Double, cy: Double, r: Double) -> Image {
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

    @Test @MainActor func detectsInlineFromTheMainActor() throws {
        let image = Self.diskImage(size: 160, cx: 80, cy: 80, r: 40)
        let found = try waitFor(image) {
            try await ContourDetector.detect(in: $0, detectsDarkOnLight: true)
        }
        #expect(found.count >= 1)
    }

    @Test @MainActor func measuresAPairInline() throws {
        let a = Self.diskImage(size: 160, cx: 70, cy: 80, r: 30)
        let b = Self.diskImage(size: 160, cx: 90, cy: 80, r: 30)
        let field = try waitFor(a, b) {
            try await FlowTracker.flow(from: $0, to: $1, accuracy: .low)
        }
        #expect(field != nil)
    }
}
