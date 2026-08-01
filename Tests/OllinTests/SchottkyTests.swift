import Testing
@testable import Ollin

/// Pure-CPU checks on the Schottky circle orbit: the pairing map really pairs
/// its circles and turns the plane inside out, a Möbius image of a circle is a
/// circle, the orbit nests and prunes, and the walk uses no randomness. No GPU.
@Suite struct SchottkyTests {
    // MARK: - The pairing map

    /// A pairing carries its source circle exactly onto its target, and does so
    /// for any twist, since the twist only turns the image about the target
    /// center.
    @Test(arguments: [0.0, 0.4, 1.3, -2.2])
    func pairingCarriesSourceOntoTarget(twist: Double) {
        let from = Circle(center: Vector2(-40, 15), radius: 22)
        let to = Circle(center: Vector2(70, -30), radius: 13)
        let map = MobiusMap.pairing(from: from, to: to, twist: twist)

        guard let image = map.image(of: from) else {
            Issue.record("the pairing produced no circle image"); return
        }
        #expect(abs(image.radius - to.radius) < 1e-9)
        #expect(abs(image.center.x - to.center.x) < 1e-9)
        #expect(abs(image.center.y - to.center.y) < 1e-9)
    }

    /// The map is inside-out: a point well outside the source lands inside the
    /// target, which is the property that makes the orbit nest.
    @Test func pairingCarriesOutsideToInside() {
        let from = Circle(center: Vector2(-40, 0), radius: 20)
        let to = Circle(center: Vector2(60, 0), radius: 20)
        let map = MobiusMap.pairing(from: from, to: to, twist: 0.3)

        for point in [Vector2(-40, 200), Vector2(300, -120), Vector2(0, 0)] {
            let z = ComplexValue(re: point.x, im: point.y)
            let image = map.apply(z)
            let distance = ((image.re - to.center.x) * (image.re - to.center.x)
                            + (image.im - to.center.y) * (image.im - to.center.y)).squareRoot()
            #expect(distance < to.radius, "\(point) should land inside the target")
        }
    }

    /// Two tangent circles paired at zero twist hold their tangency point
    /// fixed, which is what makes the generator parabolic. That is the whole
    /// reason the default arrangement stays dense, so it is worth pinning.
    @Test func zeroTwistOnTangentCirclesIsParabolic() {
        let radius = 30.0
        let from = Circle(center: Vector2(10, -radius), radius: radius)
        let to = Circle(center: Vector2(10, radius), radius: radius)
        let tangency = ComplexValue(re: 10, im: 0)

        let map = MobiusMap.pairing(from: from, to: to, twist: 0)
        let image = map.apply(tangency)
        #expect(abs(image.re - tangency.re) < 1e-9)
        #expect(abs(image.im - tangency.im) < 1e-9)

        // The fixed point is what twist gives up: turn it and the point moves.
        let turned = MobiusMap.pairing(from: from, to: to, twist: 0.5).apply(tangency)
        #expect(abs(turned.re - tangency.re) + abs(turned.im - tangency.im) > 1)
    }

    /// A Möbius map carries circles to circles, so composing then imaging
    /// agrees with imaging twice.
    @Test func circleImagesCompose() {
        let a = MobiusMap.pairing(from: Circle(center: Vector2(-30, 0), radius: 18),
                                  to: Circle(center: Vector2(30, 5), radius: 21),
                                  twist: 0.25)
        let b = MobiusMap.pairing(from: Circle(center: Vector2(0, -25), radius: 12),
                                  to: Circle(center: Vector2(4, 33), radius: 15),
                                  twist: -0.7)
        let probe = Circle(center: Vector2(9, -4), radius: 6)

        guard let once = a.image(of: probe), let stepwise = b.image(of: once),
              let composed = (b * a).normalized.image(of: probe) else {
            Issue.record("a circle image degenerated to a line"); return
        }
        #expect(abs(stepwise.center.x - composed.center.x) < 1e-6)
        #expect(abs(stepwise.center.y - composed.center.y) < 1e-6)
        #expect(abs(stepwise.radius - composed.radius) < 1e-6)
    }

    // MARK: - The orbit

    /// The orbit opens with the pairing circles themselves, and every circle
    /// after them is strictly smaller than the arrangement, since each word
    /// drops its input into a target disc.
    @Test func orbitStartsWithThePairingCirclesAndShrinks() {
        let box = Rectangle(corner: Vector2(0, 0), width: 600, height: 600)
        let pairings = schottkyCuspedPairs(in: box)
        let circles = schottkyCircles(pairing: pairings, minRadius: 4, maxDepth: 20)

        #expect(circles.count > 4)
        let base = Set(pairings.flatMap { [$0.to, $0.from] })
        #expect(Set(circles.prefix(4)) == base)

        let largest = base.map(\.radius).max()!
        for circle in circles.dropFirst(4) {
            #expect(circle.radius <= largest + 1e-9)
        }
    }

    /// Raising `minRadius` prunes strictly: a coarser walk is a subset of a
    /// finer one, and every circle it keeps clears the floor except the
    /// pairing circles the walk opens with.
    @Test func minimumRadiusPrunesTheWalk() {
        let box = Rectangle(corner: Vector2(0, 0), width: 500, height: 500)
        let pairings = schottkyCuspedPairs(in: box, lean: 0.4)

        let coarse = schottkyCircles(pairing: pairings, minRadius: 20, maxDepth: 30)
        let fine = schottkyCircles(pairing: pairings, minRadius: 2, maxDepth: 30)
        #expect(coarse.count < fine.count)
        #expect(Set(coarse).isSubset(of: Set(fine)))
    }

    /// The walk uses no randomness, so the same arrangement always returns the
    /// same circles in the same order.
    @Test func orbitIsDeterministic() {
        let box = Rectangle(corner: Vector2(10, -5), width: 400, height: 400)
        let pairings = schottkyCuspedPairs(in: box, spread: 1.08, lean: 0.3, twist: 0.2)
        let a = schottkyCircles(pairing: pairings, minRadius: 1.5, maxDepth: 40)
        let b = schottkyCircles(pairing: pairings, minRadius: 1.5, maxDepth: 40)
        #expect(a == b)
        #expect(a.count > 100)
    }

    /// Limit-set points are the centers of the circles the walk stopped at, so
    /// each one is covered by some circle in the orbit and there is one per
    /// pruned branch.
    @Test func limitSetPointsSitInsideTheOrbit() {
        let box = Rectangle(corner: Vector2(0, 0), width: 400, height: 400)
        let pairings = schottkyCuspedPairs(in: box)
        let points = schottkyLimitSet(pairing: pairings, minRadius: 3, maxDepth: 30)
        let circles = schottkyCircles(pairing: pairings, minRadius: 3, maxDepth: 30)

        #expect(!points.isEmpty)
        #expect(points.count < circles.count)
        for point in points.prefix(200) {
            #expect(circles.contains { $0.contains(point) })
        }
    }

    // MARK: - Degenerate input

    /// Nothing to pair, no floor to stop at, or a zero-radius circle: an empty
    /// result rather than a trap or a runaway walk.
    @Test func degenerateInputReturnsEmpty() {
        let box = Rectangle(corner: Vector2(0, 0), width: 300, height: 300)
        #expect(schottkyCircles(pairing: []).isEmpty)
        #expect(schottkyLimitSet(pairing: []).isEmpty)
        #expect(schottkyCircles(pairing: schottkyCuspedPairs(in: box),
                                minRadius: 0).isEmpty)
        let flat = [SchottkyPairing(from: Circle(center: .zero, radius: 0),
                                    to: Circle(center: Vector2(10, 0), radius: 5))]
        #expect(schottkyCircles(pairing: flat).isEmpty)
    }

    /// `spread` below 1 would overlap the pairs and break discreteness, and
    /// `lean` past a quarter turn would collide them, so both are clamped.
    @Test func builderClampsOutOfRangeParameters() {
        let box = Rectangle(corner: Vector2(0, 0), width: 400, height: 400)
        #expect(schottkyCuspedPairs(in: box, spread: 0.2) == schottkyCuspedPairs(in: box, spread: 1))
        #expect(schottkyCuspedPairs(in: box, lean: 9) == schottkyCuspedPairs(in: box, lean: 1.4))
    }

    /// Every preset yields a usable arrangement.
    @Test func everyPresetProducesAnOrbit() {
        let box = Rectangle(corner: Vector2(0, 0), width: 500, height: 500)
        for preset in SchottkyPreset.allCases {
            let circles = schottkyCircles(preset, in: box, minRadius: 2, maxDepth: 30)
            #expect(circles.count > 8, "\(preset) produced \(circles.count) circles")
            #expect(circles.allSatisfy { $0.radius > 0 && $0.center.x.isFinite })
        }
    }

    /// A necklace pairs circles across the ring, so its generators contract
    /// hard and its limit set is thin; the cusped family, whose pairs touch,
    /// keeps producing large circles far longer. That contrast is the reason
    /// both families ship, so pin the direction of it.
    @Test func touchingPairsOutproduceCrossRingPairs() {
        let box = Rectangle(corner: Vector2(0, 0), width: 600, height: 600)
        let cusped = schottkyCircles(pairing: schottkyCuspedPairs(in: box),
                                     minRadius: 1, maxDepth: 60)
        let necklace = schottkyCircles(pairing: schottkyNecklace(pairs: 2, in: box,
                                                                 tightness: 0.9),
                                       minRadius: 1, maxDepth: 60)
        #expect(cusped.count > necklace.count * 2)
    }
}
