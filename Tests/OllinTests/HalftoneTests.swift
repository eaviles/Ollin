import Testing
@testable import Ollin

/// Pure-CPU checks on the vector halftone: the dot geometry inverts the
/// screen's covered-area model exactly, uniform tone screens to uniform
/// area-exact dots at any angle, the printable-dot cutoff and the inverted
/// mapping behave, and the whole pass is deterministic. No GPU.
@Suite @MainActor
struct HalftoneTests {
    private let bounds = Rectangle(x: 0, y: 0, width: 240, height: 240)

    private func flatImage(white: Double, alpha: Double = 1, side: Int = 48) -> Image {
        let image = Image(width: side, height: side, color: .clear)
        for y in 0 ..< side {
            for x in 0 ..< side {
                image[x, y] = Color(red: white, green: white, blue: white, alpha: alpha)
            }
        }
        return image
    }

    /// The dot radius is the exact inverse of the covered-area model on both
    /// branches: free circle and edge-clipped.
    @Test func dotRadiusInvertsCoveredFraction() {
        for step in 1 ..< 40 {
            let coverage = Double(step) / 40
            let rho = halftoneDotRadius(coverage: coverage)
            #expect(abs(halftoneCoveredFraction(rho) - coverage) < 1e-9)
        }
        #expect(halftoneDotRadius(coverage: 0) == 0)
        #expect(abs(halftoneDotRadius(coverage: 1) - 2.0.squareRoot()) < 1e-12)
    }

    /// A uniform mid-gray screens to dots that together cover the same area
    /// fraction the tone asks for, even on a rotated screen: the area-exact
    /// promise, integrated over all interior cells.
    @Test func uniformToneScreensAreaExactly() {
        let white = 0.5
        let expected = 1 - Color.srgbToLinear(white)
        let pitch = 12.0
        let dots = halftoneDots(of: flatImage(white: white), pitch: pitch,
                                angle: 0.37, bounds: bounds, inverted: false)
        #expect(!dots.isEmpty)
        // Interior dots only: cells clipped by the image edge carry partial
        // pixel counts, so stay one cell away from the boundary.
        let margin = pitch * 1.5
        let interior = dots.filter {
            $0.center.x > margin && $0.center.x < 240 - margin &&
            $0.center.y > margin && $0.center.y < 240 - margin
        }
        for dot in interior {
            #expect(abs(dot.coverage - expected) < 0.02)
            let fraction = halftoneCoveredFraction(dot.radius / (pitch / 2))
            #expect(abs(fraction - dot.coverage) < 1e-9)
        }
    }

    /// Bare paper stays bare (below the printable minimum there is no dot)
    /// and solid ink floods the cell (the corner-reaching radius).
    @Test func printableDotCutoffAndSolidCap() {
        let bare = halftoneDots(of: flatImage(white: 1), pitch: 12,
                                angle: .pi / 4, bounds: bounds, inverted: false)
        #expect(bare.isEmpty)

        let solid = halftoneDots(of: flatImage(white: 0), pitch: 12,
                                 angle: .pi / 4, bounds: bounds, inverted: false)
        #expect(!solid.isEmpty)
        for dot in solid {
            #expect(dot.coverage == 1)
            #expect(abs(dot.radius - 12 / 2.0.squareRoot()) < 1e-9)
        }
    }

    /// `inverted` sizes dots by brightness instead of darkness: the two
    /// readings of the same tone are complementary.
    @Test func invertedMappingComplements() throws {
        let white = 0.5
        let plain = halftoneDots(of: flatImage(white: white), pitch: 12,
                                 angle: 0, bounds: bounds, inverted: false)
        let flipped = halftoneDots(of: flatImage(white: white), pitch: 12,
                                   angle: 0, bounds: bounds, inverted: true)
        let dot = try #require(plain.first { $0.column == 0 && $0.row == 0 })
        let mirrored = try #require(flipped.first { $0.column == 0 && $0.row == 0 })
        #expect(abs(dot.coverage + mirrored.coverage - 1) < 1e-9)
    }

    /// Transparency carries no ink: a fully transparent image screens to
    /// nothing, and half-alpha tone carries half the ink.
    @Test func alphaScalesInk() throws {
        let clear = halftoneDots(of: flatImage(white: 0, alpha: 0), pitch: 12,
                                 angle: 0, bounds: bounds, inverted: false)
        #expect(clear.isEmpty)

        let half = halftoneDots(of: flatImage(white: 0, alpha: 0.5), pitch: 12,
                                angle: 0, bounds: bounds, inverted: false)
        let full = halftoneDots(of: flatImage(white: 0), pitch: 12,
                                angle: 0, bounds: bounds, inverted: false)
        let halfDot = try #require(half.first { $0.column == 0 && $0.row == 0 })
        let fullDot = try #require(full.first { $0.column == 0 && $0.row == 0 })
        #expect(abs(halfDot.coverage - fullDot.coverage / 2) < 0.01)
    }

    /// Every dot's center lands inside the image's fitted rectangle, and the
    /// image keeps its aspect inside a wider bounds.
    @Test func dotsStayInsideTheFittedRect() {
        let wide = Rectangle(x: 0, y: 0, width: 400, height: 200)
        let fitted = Rectangle(fitting: Vector2(48, 48), in: wide)
        let dots = halftoneDots(of: flatImage(white: 0.3), pitch: 10,
                                angle: 0.7, bounds: wide, inverted: false)
        #expect(!dots.isEmpty)
        for dot in dots { #expect(fitted.contains(dot.center)) }
    }

    /// The same call twice returns the same dots: the screen is a pure
    /// function of (image, pitch, angle, bounds).
    @Test func screenIsDeterministic() {
        let image = flatImage(white: 0.4)
        for y in 0 ..< 48 {
            for x in 0 ..< 48 where (x + y) % 5 == 0 {
                image[x, y] = Color(red: 0.9, green: 0.2, blue: 0.4, alpha: 1)
            }
        }
        let a = halftoneDots(of: image, pitch: 7, angle: 0.5,
                             bounds: bounds, inverted: false)
        let b = halftoneDots(of: image, pitch: 7, angle: 0.5,
                             bounds: bounds, inverted: false)
        #expect(a.count == b.count)
        for (left, right) in zip(a, b) {
            #expect(left.center == right.center)
            #expect(left.radius == right.radius)
            #expect(left.coverage == right.coverage)
        }
    }

    /// Degenerate bounds return empty instead of trapping, and a tiny pitch
    /// is floored rather than exploding the dot count.
    @Test func degenerateInputsStaySafe() {
        let flat = flatImage(white: 0)
        let zeroBounds = Rectangle(x: 0, y: 0, width: 0, height: 0)
        #expect(halftoneDots(of: flat, pitch: 12, angle: 0,
                             bounds: zeroBounds, inverted: false).isEmpty)

        let fine = halftoneDots(of: flat, pitch: 0.01, angle: 0,
                                bounds: bounds, inverted: false)
        let floored = halftoneDots(of: flat, pitch: 2, angle: 0,
                                   bounds: bounds, inverted: false)
        #expect(fine.count == floored.count)
    }
}
