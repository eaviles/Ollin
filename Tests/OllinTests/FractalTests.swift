import Testing
@testable import Ollin

/// Pure-CPU checks on the fractal family: circle inversion is an involution
/// that fixes the rim, the inversion chaos game condenses deterministically,
/// the IFS chaos game lands on the attractor, and `fitted` places a cloud
/// without distorting it. No GPU.
@Suite struct FractalTests {
    // MARK: - Circle inversion

    /// Inversion fixes the rim and is its own inverse everywhere else.
    @Test func inversionIsAnInvolutionFixingTheRim() {
        let circle = Circle(center: Vector2(3, -2), radius: 5)
        let rim = Vector2(3 + 5, -2)
        let rimImage = inverted(rim, in: circle)
        #expect(abs(rimImage.x - rim.x) < 1e-12 && abs(rimImage.y - rim.y) < 1e-12)

        let point = Vector2(11, 4)
        let once = inverted(point, in: circle)
        let twice = inverted(once, in: circle)
        #expect(abs(twice.x - point.x) < 1e-9 && abs(twice.y - point.y) < 1e-9)

        // d · d' = r².
        let d = ((point.x - 3) * (point.x - 3) + (point.y + 2) * (point.y + 2)).squareRoot()
        let dPrime = ((once.x - 3) * (once.x - 3) + (once.y + 2) * (once.y + 2)).squareRoot()
        #expect(abs(d * dPrime - 25) < 1e-9)
    }

    /// The inversion chaos game returns the asked-for count, lands every
    /// point deterministically, and stays within the arrangement's reach
    /// (inside some circle, since accepted steps always pull inward).
    @Test func inversionLimitSetIsDeterministic() {
        let circles = (0 ..< 6).map { i -> Circle in
            let angle = Double(i) / 6 * 2 * .pi
            return Circle(center: Vector2(cos(angle) * 100, sin(angle) * 100),
                          radius: 50)
        }
        var rngA = SplitMix64(seed: 9)
        var rngB = SplitMix64(seed: 9)
        let a = inversionLimitSet(of: circles, count: 2_000, using: &rngA)
        let b = inversionLimitSet(of: circles, count: 2_000, using: &rngB)
        #expect(a.count == 2_000)
        #expect(a == b)
        for point in a.suffix(1_500) {
            let insideSome = circles.contains { circle in
                let dx = point.x - circle.center.x, dy = point.y - circle.center.y
                return dx * dx + dy * dy <= circle.radius * circle.radius + 1e-9
            }
            #expect(insideSome)
        }
    }

    /// Degenerate inversion inputs return empty instead of trapping.
    @Test func inversionDegeneratesReturnEmpty() {
        var rng = SplitMix64(seed: 1)
        #expect(inversionLimitSet(of: [], count: 10, using: &rng).isEmpty)
        let one = [Circle(center: Vector2(0, 0), radius: 10)]
        #expect(inversionLimitSet(of: one, count: 10, using: &rng).isEmpty)
        let two = [Circle(center: Vector2(-20, 0), radius: 10),
                   Circle(center: Vector2(20, 0), radius: 10)]
        #expect(inversionLimitSet(of: two, count: 0, using: &rng).isEmpty)
    }

    // MARK: - IFS

    /// A single contraction's chaos game converges to its fixed point.
    @Test func ifsOrbitFallsOntoTheAttractor() {
        // x' = x/2 + 1 has fixed point 2; y' = y/2 + 3 has fixed point 6.
        let system = IFS(maps: [IFS.Map(0.5, 0, 0, 0.5, 1, 3)])
        var rng = SplitMix64(seed: 4)
        let points = system.points(count: 50, settle: 60, using: &rng)
        #expect(points.count == 50)
        for point in points {
            #expect(abs(point.x - 2) < 1e-6)
            #expect(abs(point.y - 6) < 1e-6)
        }
    }

    /// The chaos game is deterministic for a fixed seed, and weights steer
    /// the visit distribution (a heavily weighted map gets most visits).
    @Test func ifsIsDeterministicAndWeighted() {
        let system = IFS(maps: [
            IFS.Map(0.5, 0, 0, 0.5, 0, 0, weight: 9),
            IFS.Map(0.5, 0, 0, 0.5, 10, 0, weight: 1),
        ])
        var rngA = SplitMix64(seed: 7)
        var rngB = SplitMix64(seed: 7)
        let a = system.points(count: 4_000, using: &rngA)
        let b = system.points(count: 4_000, using: &rngB)
        #expect(a == b)
        // Points that just took the heavy map (x' = x/2) land left of the
        // ones that took the light map (x' = x/2 + 10, so x >= 10).
        let lightVisits = a.filter { $0.x >= 10 }.count
        #expect(lightVisits > 0)
        #expect(Double(lightVisits) / Double(a.count) < 0.2)
    }

    /// Degenerate systems return empty instead of trapping.
    @Test func ifsDegeneratesReturnEmpty() {
        var rng = SplitMix64(seed: 3)
        #expect(IFS(maps: []).points(count: 10, using: &rng).isEmpty)
        let weightless = IFS(maps: [IFS.Map(0.5, 0, 0, 0.5, 0, 0, weight: 0)])
        #expect(weightless.points(count: 10, using: &rng).isEmpty)
    }

    // MARK: - Fractal flame

    /// The polar variations measure theta from the y axis: polar at (1, 0)
    /// maps to (1/2, r - 1) = (0.5, 0). Pins the atan2 argument order, the
    /// classic porting mistake.
    @Test func flameThetaConventionIsFromTheYAxis() {
        var rng = SplitMix64(seed: 1)
        let polar = FractalFlame.applyVariation(.polar, 1, 0, using: &rng)
        #expect(abs(polar.0 - 0.5) < 1e-12)
        #expect(abs(polar.1 - 0) < 1e-12)
        let linear = FractalFlame.applyVariation(.linear, 0.3, -0.7, using: &rng)
        #expect(linear.0 == 0.3 && linear.1 == -0.7)
    }

    /// The same flame, size, seed, and sample count develop the same bytes,
    /// whether taken in one gulp or in slices.
    @Test func flameRenderIsDeterministicAndSliceable() {
        var source = SplitMix64(seed: 21)
        let flame = FractalFlame.random(using: &source)

        let one = FractalFlame.Renderer(flame, width: 64, height: 64, seed: 5)
        one.accumulate(samples: 120_000)
        let two = FractalFlame.Renderer(flame, width: 64, height: 64, seed: 5)
        for _ in 0 ..< 4 { two.accumulate(samples: 30_000) }
        let imageOne = one.image()
        let imageTwo = two.image()
        #expect(imageOne.premultipliedPixels() == imageTwo.premultipliedPixels())

        // And it actually drew something.
        let bytes = imageOne.premultipliedPixels() ?? []
        let ink = bytes.enumerated().filter { $0.offset % 4 != 3 }.map { Int($0.element) }.reduce(0, +)
        #expect(ink > 0)
    }

    // MARK: - Kleinian limit sets

    /// The gasket traces come back as a dense closed curve near the unit
    /// scale, and the walk closes back onto its starting point.
    @Test func kleinianGasketTracesAClosedCurve() {
        let curve = kleinianLimitSet(.gasket, epsilon: 0.01)
        #expect(curve.isClosed)
        #expect(curve.points.count > 1_000)
        for point in curve.points {
            #expect(point.x.isFinite && point.y.isFinite)
            #expect((point.x * point.x + point.y * point.y).squareRoot() < 4)
        }
        let first = curve.points.first!
        let last = curve.points.last!
        let gap = ((first.x - last.x) * (first.x - last.x)
                 + (first.y - last.y) * (first.y - last.y)).squareRoot()
        #expect(gap < 0.05)
    }

    /// The walk is rng-free: the same traces always trace the same curve,
    /// and every preset produces a substantial one.
    @Test func kleinianIsDeterministicAcrossPresets() {
        let a = kleinianLimitSet(.lace, epsilon: 0.01)
        let b = kleinianLimitSet(.lace, epsilon: 0.01)
        #expect(a.points == b.points)
        for preset in KleinianPreset.allCases {
            let curve = kleinianLimitSet(preset, epsilon: 0.02, maxDepth: 40)
            #expect(curve.points.count > 300)
        }
    }

    // MARK: - fitted

    /// `fitted` scales uniformly (aspect preserved), centers in the frame,
    /// and fills the limiting axis exactly.
    @Test func fittedScalesUniformlyAndCenters() {
        let cloud = [Vector2(0, 0), Vector2(4, 0), Vector2(4, 2), Vector2(0, 2)]
        let frame = Rectangle(x: 100, y: 100, width: 200, height: 200)
        let placed = fitted(cloud, in: frame)
        var minX = placed[0].x, maxX = placed[0].x
        var minY = placed[0].y, maxY = placed[0].y
        for p in placed {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        #expect(abs((maxX - minX) - 200) < 1e-9)   // limiting axis fills
        #expect(abs((maxY - minY) - 100) < 1e-9)   // aspect 2:1 preserved
        #expect(abs((minX + maxX) / 2 - 200) < 1e-9)
        #expect(abs((minY + maxY) / 2 - 200) < 1e-9)
    }

    /// A degenerate cloud (one point, or all coincident) centers unscaled.
    @Test func fittedHandlesDegenerateClouds() {
        #expect(fitted([], in: Rectangle(x: 0, y: 0, width: 10, height: 10)).isEmpty)
        let single = fitted([Vector2(5, 5)],
                            in: Rectangle(x: 0, y: 0, width: 100, height: 60))
        #expect(single.count == 1)
        #expect(abs(single[0].x - 50) < 1e-12 && abs(single[0].y - 30) < 1e-12)
    }
}
