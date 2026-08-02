import Testing
import Foundation
@testable import Ollin

struct BifurcationTests {

    // MARK: - Orbits

    @Test func orbitReturnsTheRequestedCount() {
        let map = IteratedMap.logistic()
        #expect(map.orbit(at: 3.7, count: 0).isEmpty)
        #expect(map.orbit(at: 3.7, count: 500).count == 500)
    }

    @Test func settleShiftsTheOrbitForward() {
        let map = IteratedMap.logistic()
        let full = map.orbit(at: 3.7, count: 250)
        let settled = map.orbit(at: 3.7, count: 200, settle: 50)
        #expect(settled.first == full[50])
        #expect(settled.last == full[249])
    }

    @Test func fixedPointBelowTheFirstFork() {
        // Below r = 3 the logistic orbit settles to the fixed point 1 - 1/r.
        for x in IteratedMap.logistic().orbit(at: 2.5, count: 50, settle: 2000) {
            #expect(abs(x - 0.6) < 1e-9)
        }
    }

    @Test func periodDoublingWindows() {
        // The classic cascade: a 2-cycle at r = 3.2, a 4-cycle at r = 3.5, and
        // the period-3 window past 1 + sqrt(8) = 3.8284 (r = 3.83 is inside).
        let map = IteratedMap.logistic()
        func distinct(at r: Double) -> Set<Int> {
            Set(map.orbit(at: r, count: 48, settle: 4000).map { Int(($0 * 1e6).rounded()) })
        }
        #expect(distinct(at: 3.2).count == 2)
        #expect(distinct(at: 3.5).count == 4)
        #expect(distinct(at: 3.83).count == 3)

        // The r = 3.2 pair matches the closed form (r+1 +- sqrt((r-3)(r+1))) / 2r.
        let cycle = map.orbit(at: 3.2, count: 2, settle: 4001).sorted()
        let root = ((3.2 - 3) * (3.2 + 1)).squareRoot()
        #expect(abs(cycle[0] - (3.2 + 1 - root) / 6.4) < 1e-6)
        #expect(abs(cycle[1] - (3.2 + 1 + root) / 6.4) < 1e-6)
    }

    @Test func gaussOrbitStaysInItsDeclaredRange() {
        let map = IteratedMap.gauss()
        for r in [-0.9, -0.5, 0.0, 0.4, 0.9] {
            for x in map.orbit(at: r, count: 500, settle: 500) {
                #expect(map.valueRange.contains(x))
            }
        }
    }

    // MARK: - Lyapunov exponents

    @Test func tentExponentIsExactlyLogR() {
        // |f'| = r everywhere but the kink, so the average of ln|f'| is ln r
        // with no estimation error at all.
        let map = IteratedMap.tent()
        #expect(abs(map.lyapunovExponent(at: 1.5) - log(1.5)) < 1e-12)
        #expect(abs(map.lyapunovExponent(at: 2.0) - log(2.0)) < 1e-12)
    }

    @Test func logisticExponentHitsTheKnownValues() {
        let map = IteratedMap.logistic()
        // Exactly ln 2 at r = 4 (the tent-map conjugacy); the estimate
        // converges statistically, hence the loose tolerance.
        #expect(abs(map.lyapunovExponent(at: 4, iterations: 200_000) - log(2.0)) < 0.02)
        // Negative in a stable window, positive in chaos.
        #expect(map.lyapunovExponent(at: 3.2) < -0.1)
        #expect(map.lyapunovExponent(at: 3.9) > 0.1)
    }

    @Test func centralDifferenceFallbackMatchesTheAnalyticDerivative() {
        let analytic = IteratedMap.logistic()
        var numeric = analytic
        numeric.derivative = nil
        let a = analytic.lyapunovExponent(at: 3.7, iterations: 5000)
        let b = numeric.lyapunovExponent(at: 3.7, iterations: 5000)
        #expect(abs(a - b) < 1e-5)
    }

    // MARK: - Cobweb and graph

    @Test func cobwebAlternatesCurveAndDiagonal() {
        let map = IteratedMap.logistic()
        let r = 3.4
        let web = map.cobweb(at: r, steps: 20)
        #expect(web.count == 41)
        #expect(web[0] == Vector2(map.start, map.valueRange.lowerBound))
        for i in stride(from: 1, to: web.count, by: 2) {
            // Odd points sit on the curve, and share x with the previous point.
            #expect(abs(web[i].y - map.next(web[i].x, r)) < 1e-12)
            #expect(web[i].x == web[i - 1].x)
        }
        for i in stride(from: 2, to: web.count, by: 2) {
            // Even points sit on the diagonal, at the previous point's height.
            #expect(web[i].x == web[i].y)
            #expect(web[i].y == web[i - 1].y)
        }
    }

    @Test func cobwebHonorsAnExplicitStart() {
        let web = IteratedMap.logistic().cobweb(at: 3.4, steps: 3, from: 0.123)
        #expect(web[0].x == 0.123)
    }

    @Test func graphSamplesTheRuleAcrossTheValueRange() {
        let map = IteratedMap.sine()
        let curve = map.graph(at: 0.8, samples: 65)
        #expect(curve.count == 65)
        #expect(curve.first?.x == 0 && curve.last?.x == 1)
        for p in curve {
            #expect(abs(p.y - map.next(p.x, 0.8)) < 1e-12)
        }
    }

    // MARK: - Bifurcation sweeps

    @Test func bifurcationSamplesColumnCenters() {
        let map = IteratedMap.logistic()
        let points = map.bifurcation(over: 3.0...4.0, columns: 10, perColumn: 5, settle: 100)
        #expect(points.count == 50)
        // The first column sits half a step in, never on the range's endpoint.
        #expect(abs(points[0].x - 3.05) < 1e-12)
        #expect(abs(points[45].x - 3.95) < 1e-12)
        // Values stay in the unit interval, and the sweep reproduces exactly.
        for p in points { #expect(p.y >= 0 && p.y <= 1) }
        #expect(points == map.bifurcation(over: 3.0...4.0, columns: 10, perColumn: 5, settle: 100))
    }

    @Test func bifurcationImageIsDeterministicInkOnWhite() throws {
        let map = IteratedMap.logistic()
        let image = try #require(map.bifurcationImage(width: 160, height: 120,
                                                      samplesPerColumn: 400, settle: 400))
        #expect(image.width == 160 && image.height == 120)

        // The stable-line column near r = 2.5 prints dark at the fixed point
        // 1 - 1/r (row = (1 - x) * height), and stays paper-white above it.
        let r = 2.4 + 1.6 * 9.5 / 160.0
        let row = Int((1.0 - (1.0 - 1.0 / r)) * 120.0)
        let ink = image[9, row]
        let paper = image[9, 10]
        #expect(ink.red < 0.5 && ink.alpha == 1)
        #expect(paper.red == 1 && paper.green == 1 && paper.blue == 1)

        // Bitwise reproducible.
        let again = try #require(map.bifurcationImage(width: 160, height: 120,
                                                      samplesPerColumn: 400, settle: 400))
        let pixels = try #require(image.premultipliedPixels())
        #expect(pixels == again.premultipliedPixels())
    }
}
