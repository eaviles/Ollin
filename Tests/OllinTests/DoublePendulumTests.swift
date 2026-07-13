import Testing
import Foundation
@testable import Ollin

struct DoublePendulumTests {

    @Test func energyHoldsSteady() {
        // The exact dynamics conserve energy; the fixed substeps must hold it
        // to a hair across ten seconds of chaotic swinging.
        let pendulum = DoublePendulum()
        let initial = pendulum.energy
        let scale = max(abs(initial), 1)
        for _ in 0 ..< 600 {
            pendulum.step()
            #expect(abs(pendulum.energy - initial) / scale < 1e-4)
        }
    }

    @Test func runsAreDeterministic() {
        let a = DoublePendulum()
        let b = DoublePendulum()
        for _ in 0 ..< 300 { a.step(); b.step() }
        #expect(a.angle1 == b.angle1 && a.angle2 == b.angle2)
        #expect(a.velocity1 == b.velocity1 && a.velocity2 == b.velocity2)
    }

    @Test func aHairApartDiverges() {
        // The butterfly effect itself: a start offset by a ten-thousandth of
        // a radian ends somewhere completely different within half a minute.
        let a = DoublePendulum()
        let b = DoublePendulum(angle1: 2.1 + 1e-4)
        for _ in 0 ..< 1800 { a.step(); b.step() }
        #expect(abs(a.angle1 - b.angle1) + abs(a.angle2 - b.angle2) > 0.1)
    }

    @Test func bobsSitWhereTheAnglesSay() {
        let hanging = DoublePendulum(angle1: 0, angle2: 0)
        #expect(hanging.bob1.distance(to: Vector2(0, 200)) < 1e-12)
        #expect(hanging.bob2.distance(to: Vector2(0, 400)) < 1e-12)

        let sideways = DoublePendulum(length1: 100, length2: 50,
                                      angle1: .pi / 2, angle2: .pi / 2)
        #expect(sideways.bob1.distance(to: Vector2(100, 0)) < 1e-9)
        #expect(sideways.bob2.distance(to: Vector2(150, 0)) < 1e-9)
    }

    @Test func smallSwingsMatchTheTextbookPeriod() {
        // With a nearly massless second bob and a small angle, arm one is a
        // plain pendulum: after one period 2 pi sqrt(L / g) it is back where
        // it started.
        let pendulum = DoublePendulum(length1: 200, length2: 200,
                                      mass1: 1, mass2: 1e-9,
                                      angle1: 0.05, angle2: 0.05)
        let period = 2 * Double.pi * (200.0 / 980.0).squareRoot()
        let steps = 600
        for _ in 0 ..< steps { pendulum.step(period / Double(steps)) }
        #expect(abs(pendulum.angle1 - 0.05) < 0.002)
    }

    @Test func restStaysAtRest() {
        // Hanging straight down with no velocity is an equilibrium.
        let pendulum = DoublePendulum(angle1: 0, angle2: 0)
        for _ in 0 ..< 120 { pendulum.step() }
        #expect(abs(pendulum.angle1) < 1e-12 && abs(pendulum.angle2) < 1e-12)
    }
}
