import Foundation
import Testing
@testable import Ollin

/// `smoothed(neighbors:weights:)`, the moving average that keeps one point for
/// each point in. The yardstick is a circle: averaging evenly spaced points on
/// a circle moves each one straight toward the center by a factor the kernel
/// alone decides (the kernel's cosine sum at the angle between neighbors), so
/// every window has an exact answer to meet. No GPU.
@Suite
struct MovingAverageSmoothingTests {

    static let center = Vector2(310, 205)

    /// `n` points on a circle of `radius`, a quarter step off the axes so no
    /// coordinate is zero.
    static func circle(_ n: Int, radius: Double = 100) -> Contour {
        Contour((0 ..< n).map { i in
            center + Vector2(angle: (Double(i) + 0.25) / Double(n) * .tau, length: radius)
        }, closed: true)
    }

    /// The factor a window of `2 * reach + 1` points shrinks a circle of `n`
    /// points by, from the kernel's cosine sum. The box's sum has a closed
    /// form; the bell's is summed out, from its own statement of the weights.
    static func shrinkage(reach: Int, weights: SmoothingWeights, points n: Int) -> Double {
        let step = Double.tau / Double(n)
        switch weights {
        case .box:
            let width = Double(2 * reach + 1)
            return sin(width * step / 2) / (width * sin(step / 2))
        case .gaussian:
            // A standard deviation of half the window: exp(-k² / (2 (w/2)²)) = exp(-2k²/w²).
            let w = Double(reach)
            var top = 0.0, bottom = 0.0
            for k in -reach ... reach {
                let g = exp(-2 * Double(k * k) / (w * w))
                top += g * cos(Double(k) * step)
                bottom += g
            }
            return top / bottom
        }
    }

    // MARK: - The circle

    /// Every point lands at the analytic radius, on its own spoke, for every
    /// window from one neighbor to twelve, under both weights.
    @Test(arguments: SmoothingWeights.allCases, 1 ... 12)
    func aCircleShrinksByTheKernelsFactor(weights: SmoothingWeights, reach: Int) {
        let n = 64, radius = 100.0
        let ring = Self.circle(n, radius: radius)
        let smooth = ring.smoothed(neighbors: reach, weights: weights)
        let want = radius * Self.shrinkage(reach: reach, weights: weights, points: n)
        #expect(smooth.points.count == n)
        for (before, after) in zip(ring.points, smooth.points) {
            let spoke = (before - Self.center).normalized
            let moved = after - Self.center
            #expect(abs(moved.length - want) < 1e-9)
            #expect(abs(moved.x * spoke.y - moved.y * spoke.x) < 1e-9)
        }
    }

    /// The bell shrinks a curve less than the box over the same window, at
    /// every width, and the figures the documentation quotes hold.
    @Test func theBellShrinksLessThanTheBox() {
        for reach in 1 ... 12 {
            #expect(Self.shrinkage(reach: reach, weights: .gaussian, points: 64)
                    > Self.shrinkage(reach: reach, weights: .box, points: 64))
        }
        let ring = Self.circle(64)
        func lost(_ weights: SmoothingWeights) -> Double {
            1 - (ring.smoothed(neighbors: 3, weights: weights).points[0] - Self.center).length / 100
        }
        #expect(abs(lost(.box) - 0.019) < 0.0005)
        #expect(abs(lost(.gaussian) - 0.0095) < 0.0005)
    }

    // MARK: - Points kept

    /// One point out per point in, in the same order. The ring's jitter is
    /// only radial, so point i of the input sits on spoke i, and point i of
    /// the result, an average of its window, must sit within the wedge of
    /// spokes that window covers.
    @Test(arguments: SmoothingWeights.allCases)
    func theCountAndTheOrderStay(weights: SmoothingWeights) {
        var rng = SplitMix64(seed: 3)
        let n = 90
        let ring = Contour((0 ..< n).map { i in
            Self.center + Vector2(angle: Double(i) / Double(n) * .tau,
                                  length: 100 + Double.random(in: -6 ... 6, using: &rng))
        }, closed: true)
        let smooth = ring.smoothed(neighbors: 4, weights: weights)
        #expect(smooth.points.count == n)
        #expect(smooth.isClosed)
        for i in 0 ..< n {
            // The point's angle measured from spoke i, in steps between spokes.
            let turn = (smooth.points[i] - Self.center).angle - Double(i) / Double(n) * .tau
            let steps = atan2(sin(turn), cos(turn)) / (.tau / Double(n))
            #expect(abs(steps) <= 4)
        }
        // And the jitter is mostly gone: the spread of the radii falls by more than half.
        func spread(_ c: Contour) -> Double {
            let r = c.points.map { ($0 - Self.center).length }
            let mean = r.reduce(0, +) / Double(r.count)
            return (r.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(r.count)).squareRoot()
        }
        #expect(spread(smooth) < 0.5 * spread(ring))
    }

    /// An open contour keeps its two end points exactly, whatever the window.
    @Test(arguments: SmoothingWeights.allCases)
    func anOpenContourKeepsItsEnds(weights: SmoothingWeights) {
        var rng = SplitMix64(seed: 5)
        let walk = Contour((0 ..< 40).map { i in
            Vector2(Double(i) * 7, Double.random(in: -20 ... 20, using: &rng))
        }, closed: false)
        for reach in [1, 3, 10, 39, 500] {
            let smooth = walk.smoothed(neighbors: reach, weights: weights)
            #expect(smooth.points.count == 40)
            #expect(!smooth.isClosed)
            #expect(smooth.points.first == walk.points.first)
            #expect(smooth.points.last == walk.points.last)
        }
    }

    /// The window reaches past an end by mirroring the curve through it, so an
    /// evenly spaced straight run stays where it is right up to its ends, where
    /// a window that stopped short or repeated the end point would pull the
    /// points beside the ends inward.
    @Test(arguments: SmoothingWeights.allCases)
    func aStraightEvenRunStaysPut(weights: SmoothingWeights) {
        let run = Contour((0 ..< 25).map { i in Vector2(12 + Double(i) * 6.5, 40 - Double(i) * 2.25) },
                          closed: false)
        let smooth = run.smoothed(neighbors: 5, weights: weights)
        for (a, b) in zip(run.points, smooth.points) {
            #expect(a.distance(to: b) < 1e-9)
        }
    }

    // MARK: - Edges of the range

    /// No window, or too few points to average, leaves the contour as it was.
    @Test func nothingToAverageLeavesItAlone() {
        let ring = Self.circle(12)
        #expect(ring.smoothed(neighbors: 0) == ring)
        #expect(ring.smoothed(neighbors: -3) == ring)
        let pair = Contour([Vector2(0, 0), Vector2(10, 4)], closed: false)
        #expect(pair.smoothed(neighbors: 4) == pair)
        let loop = Contour([Vector2(0, 0), Vector2(10, 4)], closed: true)
        #expect(loop.smoothed(neighbors: 4) == loop)
        #expect(Contour([], closed: true).smoothed(neighbors: 2).points.isEmpty)
    }

    /// Around a closed contour the window stops where it would meet itself, so
    /// asking for more neighbors than that gives the widest window there is.
    @Test(arguments: SmoothingWeights.allCases)
    func aClosedWindowStopsWhereItWouldMeetItself(weights: SmoothingWeights) {
        let ring = Self.circle(11)
        #expect(ring.smoothed(neighbors: 9, weights: weights) == ring.smoothed(neighbors: 5, weights: weights))
        #expect(ring.smoothed(neighbors: 4, weights: weights) != ring.smoothed(neighbors: 5, weights: weights))
    }

    /// A shape smooths every contour and keeps its winding rule.
    @Test func aShapeSmoothsEveryContour() {
        let outer = Self.circle(48, radius: 120), inner = Self.circle(24, radius: 50)
        let shape = Shape(contours: [outer, inner], winding: .nonZero)
        let smooth = shape.smoothed(neighbors: 2, weights: .box)
        #expect(smooth.winding == .nonZero)
        #expect(smooth.contours == [outer.smoothed(neighbors: 2, weights: .box),
                                    inner.smoothed(neighbors: 2, weights: .box)])
    }
}
