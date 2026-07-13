import Testing
import Foundation
@testable import Ollin

struct DampedSpringTests {

    // MARK: - The closed form

    @Test func criticalStepMatchesTheClosedForm() {
        // One update must land exactly on the analytic critically damped
        // solution x(t) = (x0 + (v0 + w*x0) t) e^(-w t) measured from the target.
        var spring = DampedSpring(value: 3.0, duration: 0.5)
        spring.target = 10.0
        spring.velocity = 2.0
        let omega = 2 * Double.pi / 0.5
        let dt = 0.037
        let x0 = 3.0 - 10.0, v0 = 2.0
        let expected = 10.0 + (x0 + (v0 + omega * x0) * dt) * exp(-omega * dt)
        spring.update(dt: dt)
        #expect(abs(spring.value - expected) < 1e-12)
    }

    @Test func stepsComposeExactly() {
        // The update is the exact solution, so many small steps equal one big
        // step: frame rate cannot change where a spring ends up.
        for bounce in [-0.5, 0.0, 0.35, 0.8] {
            var fine = DampedSpring(value: 0.0, duration: 0.4, bounce: bounce)
            var coarse = fine
            fine.target = 100; coarse.target = 100
            fine.kick(30); coarse.kick(30)
            for _ in 0 ..< 120 { fine.update(dt: 1.0 / 120.0) }
            for _ in 0 ..< 30 { coarse.update(dt: 1.0 / 30.0) }
            #expect(abs(fine.value - coarse.value) < 1e-9)
            #expect(abs(fine.velocity - coarse.velocity) < 1e-7)
        }
    }

    @Test func convergesToTheTarget() {
        for bounce in [-0.6, 0.0, 0.5] {
            var spring = DampedSpring(value: -40.0, duration: 0.3, bounce: bounce)
            spring.target = 25
            for _ in 0 ..< 600 { spring.update(dt: 1.0 / 60.0) }
            #expect(abs(spring.value - 25) < 1e-6)
            #expect(abs(spring.velocity) < 1e-4)
        }
    }

    // MARK: - Character

    @Test func criticalFromRestNeverOvershoots() {
        var spring = DampedSpring(value: 0.0, duration: 0.5)
        spring.target = 50
        var previous = 0.0
        for _ in 0 ..< 300 {
            spring.update(dt: 1.0 / 60.0)
            #expect(spring.value <= 50 + 1e-9)         // never crosses
            #expect(spring.value >= previous - 1e-9)   // approaches monotonically
            previous = spring.value
        }
    }

    @Test func bounceOvershoots() {
        var spring = DampedSpring(value: 0.0, duration: 0.5, bounce: 0.5)
        spring.target = 50
        var crossed = false
        for _ in 0 ..< 300 {
            spring.update(dt: 1.0 / 60.0)
            if spring.value > 50 { crossed = true }
        }
        #expect(crossed)
    }

    @Test func negativeBounceLagsBehindCritical() {
        var critical = DampedSpring(value: 0.0, duration: 0.5)
        var draggy = DampedSpring(value: 0.0, duration: 0.5, bounce: -0.6)
        critical.target = 50; draggy.target = 50
        for _ in 0 ..< 30 {          // half a second, mid-flight
            critical.update(dt: 1.0 / 60.0)
            draggy.update(dt: 1.0 / 60.0)
        }
        #expect(draggy.value < critical.value)
    }

    @Test func kickSpringsBack() {
        var spring = DampedSpring(value: 10.0, duration: 0.4)
        spring.kick(400)
        // A critically damped impulse peaks at velocity / (omega e): about
        // 9.4 here, so the throw must carry the value well past 15.
        var farthest = 10.0
        for _ in 0 ..< 600 {
            spring.update(dt: 1.0 / 60.0)
            farthest = max(farthest, spring.value)
        }
        #expect(farthest > 15)                 // the throw moved it
        #expect(abs(spring.value - 10) < 1e-6) // and it came home
    }

    @Test func knobsClampToSafeRanges() {
        var spring = DampedSpring(value: 0.0, duration: -3, bounce: 5)
        #expect(spring.duration >= 0.0001)
        #expect(spring.bounce == 1)
        spring.bounce = -4
        #expect(spring.bounce == -0.999)
        spring.target = 1
        for _ in 0 ..< 100 { spring.update(dt: 1.0 / 60.0) }
        #expect(spring.value.isFinite)
    }

    @Test func vectorSpringMatchesTwoScalarSprings() {
        var vector = DampedSpring(value: Vector2(1, -2), duration: 0.3, bounce: 0.4)
        var x = DampedSpring(value: 1.0, duration: 0.3, bounce: 0.4)
        var y = DampedSpring(value: -2.0, duration: 0.3, bounce: 0.4)
        vector.target = Vector2(10, 20); x.target = 10; y.target = 20
        for _ in 0 ..< 90 {
            vector.update(dt: 1.0 / 60.0)
            x.update(dt: 1.0 / 60.0)
            y.update(dt: 1.0 / 60.0)
        }
        #expect(abs(vector.value.x - x.value) < 1e-12)
        #expect(abs(vector.value.y - y.value) < 1e-12)
    }

    // MARK: - The wrapper

    @Test func sprungRetargetKeepsMomentum() {
        let sprung = Sprung(wrappedValue: 0.0, duration: 0.4)
        sprung.wrappedValue = 100
        for _ in 0 ..< 10 { sprung.advance(by: 1.0 / 60.0) }
        let midFlight = sprung.velocity
        #expect(midFlight > 0)
        sprung.wrappedValue = -100          // retarget mid-flight
        #expect(sprung.velocity == midFlight) // the velocity carries over
        #expect(sprung.target == -100)
        for _ in 0 ..< 600 { sprung.advance(by: 1.0 / 60.0) }
        #expect(abs(sprung.wrappedValue + 100) < 1e-6)
    }

    @Test func sprungSetJumpsWithoutMotion() {
        let sprung = Sprung(wrappedValue: 0.0, duration: 0.4)
        sprung.wrappedValue = 100
        for _ in 0 ..< 10 { sprung.advance(by: 1.0 / 60.0) }
        sprung.set(7)
        #expect(sprung.wrappedValue == 7)
        #expect(sprung.target == 7)
        sprung.advance(by: 1.0 / 60.0)
        #expect(sprung.wrappedValue == 7)   // at rest, nothing moves
    }
}
