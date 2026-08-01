import Testing
@testable import Ollin

/// The placement rules behind `strokeBrush(_:)`. A snapshot pins what the stamps
/// look like; these pin where they go, which is the part a picture cannot check.
@Suite
struct BrushTests {

    private let line = [Vector2(0, 0), Vector2(300, 0)]

    private func place(_ brush: Brush, width: Double = 20,
                       along path: [Vector2]? = nil, closed: Bool = false) -> [Brush.Stamp] {
        Brush.stamps(along: path ?? line, closed: closed, brush: brush,
                     width: { _ in width }, opacity: { _ in 1 })
    }

    /// The same brush on the same path draws the same mark, every frame and every
    /// run. A brush rolls its own generator from the stamp's index rather than
    /// drawing on the sketch's `random`, so it also cannot shift a sketch's other
    /// randomness by being added to it.
    @Test func theSameBrushPlacesTheSameStamps() {
        let brush = Brush.spray(seed: 11)
        let a = place(brush), b = place(brush)
        #expect(a.count == b.count)
        for (x, y) in zip(a, b) {
            #expect(x.center == y.center)
            #expect(x.size == y.size)
            #expect(x.angle == y.angle)
            #expect(x.opacity == y.opacity)
        }
    }

    @Test func adifferentSeedPlacesADifferentMark() {
        let a = place(.spray(seed: 1)), b = place(.spray(seed: 2))
        #expect(a.count == b.count)                       // the walk is the same
        #expect(zip(a, b).contains { $0.center != $1.center })   // the throw is not
    }

    /// Spacing is measured in stamp sizes, not pixels, which is what lets one
    /// brush keep its texture at any weight: the same brush twice as heavy makes
    /// the same mark, twice as big, with half as many stamps over a fixed path.
    @Test func spacingScalesWithTheStampNotTheCanvas() {
        let brush = Brush(.circle, spacing: 0.5)
        let small = place(brush, width: 10).count
        let large = place(brush, width: 20).count
        #expect(abs(Double(small) - Double(large) * 2) <= 2,
                "\(small) stamps at half the weight against \(large) at full")
    }

    @Test func countMultipliesTheStampsAtEachStep() {
        let one = place(Brush(.circle, spacing: 0.5, count: 1)).count
        let three = place(Brush(.circle, spacing: 0.5, scatter: 1, count: 3)).count
        #expect(three == one * 3)
    }

    /// Every random knob is a fraction of the stamp's own size, so a brush stays
    /// in proportion when the weight changes.
    @Test func scatterIsAFractionOfTheStampSize() {
        let brush = Brush(.circle, spacing: 0.5, scatter: 1, seed: 3)
        for width in [8.0, 40.0] {
            let strayed = place(brush, width: width).map { abs($0.center.y) }.max() ?? 0
            #expect(strayed <= width, "strayed \(strayed) at width \(width)")
            #expect(strayed > width * 0.4, "barely strayed at width \(width)")
        }
    }

    @Test func stampsFollowTheHeadingOfThePath() {
        let diagonal = [Vector2(0, 0), Vector2(200, 200)]
        let stamps = place(Brush(.square, spacing: 0.5), along: diagonal)
        #expect(stamps.count > 4)
        for stamp in stamps { #expect(abs(stamp.angle - .pi / 4) < 1e-9) }
    }

    @Test func aFixedAngleIgnoresTheHeading() {
        let diagonal = [Vector2(0, 0), Vector2(200, 200)]
        let stamps = place(Brush(.square, spacing: 0.5, angle: .fixed(0.75)), along: diagonal)
        for stamp in stamps { #expect(abs(stamp.angle - 0.75) < 1e-9) }
    }

    /// Stamps are placed by distance along the path, so they stay evenly spread
    /// however unevenly the path's own points are spread. A recorded mark bunches
    /// its points where the hand slowed, and a brush must not bunch with them.
    @Test func stampsAreSpacedByDistanceNotByVertex() {
        let bunched = [Vector2(0, 0), Vector2(1, 0), Vector2(2, 0), Vector2(3, 0),
                       Vector2(300, 0)]
        let stamps = place(Brush(.circle, spacing: 0.5), along: bunched)
        let gaps = zip(stamps, stamps.dropFirst()).map { ($1.center - $0.center).length }
        #expect(gaps.count > 4)
        for gap in gaps { #expect(abs(gap - 10) < 1e-6, "gap \(gap) should be 0.5 of 20") }
    }

    /// A closed path comes back to its first point, so the last stamp sits near
    /// the start rather than leaving the loop open.
    @Test func aClosedPathIsWalkedAllTheWayRound() {
        let square = [Vector2(0, 0), Vector2(100, 0), Vector2(100, 100), Vector2(0, 100)]
        let open = place(Brush(.circle, spacing: 0.5), along: square, closed: false)
        let loop = place(Brush(.circle, spacing: 0.5), along: square, closed: true)
        #expect(loop.count > open.count)
        let last = try! #require(loop.last)
        #expect((last.center - Vector2(0, 0)).length < 20)
    }

    /// The width the caller reports is the stamp's size, which is where an
    /// ambient `strokeProfile` folds in: a taper shrinks the stamps toward both
    /// ends rather than thinning a ribbon.
    @Test func theWidthClosureSizesEachStamp() {
        let stamps = Brush.stamps(along: line, closed: false,
                                  brush: Brush(.circle, spacing: 0.5),
                                  width: { t in 4 + 36 * sin(t * .pi) },
                                  opacity: { _ in 1 })
        let first = try! #require(stamps.first)
        let widest = try! #require(stamps.max { $0.size < $1.size })
        #expect(first.size < 8)
        #expect(widest.size > 35)
        // Crowding follows the size, so a thinning mark does not go gappy.
        #expect(stamps.count > 15)
    }

    @Test func aVanishingProfilePlacesNothingRatherThanLoopingForever() {
        let stamps = Brush.stamps(along: line, closed: false,
                                  brush: Brush(.circle, spacing: 0.5),
                                  width: { _ in 0 }, opacity: { _ in 1 })
        #expect(stamps.isEmpty)
    }

    @Test func opacityJitterOnlyEverDarkensTowardTransparent() {
        let stamps = place(Brush(.circle, spacing: 0.5, opacityJitter: 1, seed: 6))
        for stamp in stamps { #expect(stamp.opacity > 0 && stamp.opacity <= 1) }
    }

    /// A spacing of zero would be an infinite number of stamps, so it is floored.
    @Test func zeroSpacingIsClampedInsteadOfHanging() {
        let stamps = place(Brush(.circle, spacing: 0))
        #expect(stamps.count > 0 && stamps.count < 2_000)
    }

    @Test func aSinglePointStillLeavesAMark() {
        let stamps = place(Brush(.circle, spacing: 0.5), along: [Vector2(10, 10)])
        #expect(stamps.count == 1)
        #expect(stamps[0].center == Vector2(10, 10))
    }
}
