import Testing
import Foundation
@testable import Ollin

struct AttractorsTests {

    // MARK: - StrangeAttractor (continuous, RK4)

    @Test func orbitReturnsTheRequestedCount() {
        #expect(StrangeAttractor.lorenz().orbit(count: 0).isEmpty)
        #expect(StrangeAttractor.lorenz().orbit(count: 2500).count == 2500)
    }

    @Test func orbitsAreDeterministic() {
        let a = StrangeAttractor.lorenz().orbit(count: 3000, settle: 200)
        let b = StrangeAttractor.lorenz().orbit(count: 3000, settle: 200)
        #expect(a == b)
    }

    @Test func settleShiftsTheOrbitForward() {
        // Dropping `settle` warmup steps is the same path as integrating from the
        // start and skipping the first `settle` points.
        let full = StrangeAttractor.lorenz().orbit(count: 250)
        let settled = StrangeAttractor.lorenz().orbit(count: 200, settle: 50)
        #expect(settled.first == full[50])
        #expect(settled.last == full[249])
    }

    @Test func lorenzStaysBounded() {
        // On the attractor the orbit never escapes a modest box; a divergent
        // integrator would blow past it.
        for p in StrangeAttractor.lorenz().orbit(count: 20_000, settle: 1000) {
            #expect(abs(p.x) < 60 && abs(p.y) < 80 && p.z > -5 && p.z < 110)
            #expect(p.x.isFinite && p.y.isFinite && p.z.isFinite)
        }
    }

    @Test func rungeKuttaIsExactOnAConstantField() {
        // A constant velocity integrates linearly, which RK4 reproduces exactly:
        // the path is start + n·step along x. The first point is the start itself.
        let line = StrangeAttractor(start: .zero, step: 0.01) { _ in Vector3(1, 0, 0) }
        let path = line.orbit(count: 101)
        #expect(abs(path[0].x) < 1e-12)
        #expect(abs(path[100].x - 1.0) < 1e-9)
    }

    @Test func rungeKuttaConservesACircularOrbit() {
        // A rotation field traces a circle; RK4 holds the radius across many steps.
        let circle = StrangeAttractor(start: Vector3(1, 0, 0), step: 0.01) { p in
            Vector3(-p.y, p.x, 0)
        }
        for p in circle.orbit(count: 2000) {
            #expect(abs((p.x * p.x + p.y * p.y).squareRoot() - 1) < 1e-2)
        }
    }

    // MARK: - ChaoticMap (discrete)

    @Test func mapOrbitReturnsTheRequestedCount() {
        #expect(ChaoticMap.clifford().orbit(count: 0).isEmpty)
        #expect(ChaoticMap.clifford().orbit(count: 5000).count == 5000)
    }

    @Test func mapOrbitsAreDeterministic() {
        #expect(ChaoticMap.deJong().orbit(count: 4000) == ChaoticMap.deJong().orbit(count: 4000))
    }

    @Test func cliffordAndDeJongStayBounded() {
        // Both trigonometric maps live within roughly [-2, 2] on each axis.
        for map in [ChaoticMap.clifford(), ChaoticMap.deJong()] {
            for p in map.orbit(count: 10_000, settle: 100) {
                #expect(abs(p.x) <= 2.001 && abs(p.y) <= 2.001)
            }
        }
    }

    @Test func henonMatchesItsFirstIterates() {
        // The Hénon map (a=1.4, b=0.3) from the origin steps to known points.
        let henon = ChaoticMap(start: .zero, next: ChaoticMap.henon().next)
        let path = henon.orbit(count: 3)
        #expect(path[0] == Vector2(0, 0))
        #expect(path[1] == Vector2(1, 0))
        let third = path[2]
        #expect(abs(third.x + 0.4) < 1e-12 && abs(third.y - 0.3) < 1e-12)
    }
}
