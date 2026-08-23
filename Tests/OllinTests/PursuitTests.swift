@testable import Ollin
import Testing
import Foundation

/// Pure-CPU checks on the pursuit chase. Every one of these is a theorem about
/// the chase rather than a matter of taste, which is the point: a spiral that
/// is slightly the wrong spiral looks exactly as good as the right one.
///
/// The load-bearing pair is the shrink rule and the constant angle. The first
/// says the ring stays a regular polygon and gets smaller by an exact amount,
/// which can only be true if every runner moves off the positions everyone
/// held *before* the step. The second is the logarithmic spiral itself: the
/// angle between a runner's path and the line to the center never changes.
@Suite
struct PursuitTests {

    private typealias Runner = Pursuit.Runner

    /// The distance a runner covers before it arrives, from the published
    /// result for the ring: `radius / sin(chasing * pi / sides)`.
    private func lawfulDistance(radius: Double, sides: Int, chasing: Int = 1) -> Double {
        radius / sin(Double(chasing) * .pi / Double(sides))
    }

    private func radius(of chase: Pursuit, around center: Vector2) -> Double {
        chase.runners.reduce(0) { $0 + $1.position.distance(to: center) }
            / Double(chase.runners.count)
    }

    // MARK: - The ring

    @Test func theRingStaysARegularPolygon() {
        // If the runners moved one after another instead of together, each one
        // would chase a target that had already left, and the ring would go
        // lopsided within a few steps.
        let center = Vector2(500, 500)
        for sides in [3, 4, 5, 6, 9] {
            let chase = Pursuit.ring(sides: sides, center: center, radius: 400)
            chase.step(600)
            let radii = chase.runners.map { $0.position.distance(to: center) }
            let sideLengths = chase.runners.indices.map { index in
                chase.runners[index].position
                    .distance(to: chase.runners[(index + 1) % sides].position)
            }
            let radiusSpread = (radii.max()! - radii.min()!) / radii.max()!
            let sideSpread = (sideLengths.max()! - sideLengths.min()!) / sideLengths.max()!
            #expect(radiusSpread < 1e-9,
                    "a \(sides)-runner ring went out of round by \(radiusSpread)")
            #expect(sideSpread < 1e-9,
                    "a \(sides)-runner ring's sides spread by \(sideSpread)")
            #expect(radii[0] < 400, "and it did shrink")
        }
    }

    @Test func theRingShrinksByTheExactRule() {
        // r' * r' == r * r - 2 * step * r * sin(chasing * pi / sides) + step * step,
        // which falls out of moving one exact step along the chord.
        let center = Vector2.zero
        for (sides, chasing) in [(4, 1), (5, 1), (6, 2), (7, 3), (8, 4)] {
            let step = 0.5
            let chase = Pursuit.ring(sides: sides, center: center, radius: 200,
                                     chasing: chasing, stepSize: step)
            let closing = sin(Double(chasing) * .pi / Double(sides))
            for _ in 0 ..< 200 {
                let before = radius(of: chase, around: center)
                chase.step()
                let after = radius(of: chase, around: center)
                let want = (before * before - 2 * step * before * closing + step * step)
                    .squareRoot()
                #expect(abs(after - want) < 1e-9,
                        "\(sides) sides chasing \(chasing): \(after) against \(want)")
            }
        }
    }

    @Test func theTrailIsALogarithmicSpiral() {
        // The definition of an equiangular spiral: the angle between the path
        // and the line to the center is the same everywhere. Here it must be
        // exactly 90 degrees minus chasing * 180 / sides.
        let center = Vector2(300, 300)
        for (sides, chasing) in [(3, 1), (4, 1), (5, 2), (12, 1)] {
            let chase = Pursuit.ring(sides: sides, center: center, radius: 250,
                                     chasing: chasing, stepSize: 0.4)
            chase.step(400)
            let want = Double.pi / 2 - Double(chasing) * .pi / Double(sides)
            let trail = chase.runners[0].trail
            var worst = 0.0
            for index in 0 ..< trail.count - 1 {
                let along = (trail[index + 1] - trail[index]).normalized
                let inward = (center - trail[index]).normalized
                worst = Swift.max(worst, abs(abs(along.angle(to: inward)) - want))
            }
            #expect(worst < 1e-9,
                    "\(sides) sides chasing \(chasing) drifted \(worst) off \(want)")
        }
    }

    @Test func theRunnersCoverTheDistanceTheLawPredicts() {
        let center = Vector2(0, 0)
        for (sides, chasing) in [(3, 1), (4, 1), (5, 1), (6, 1), (8, 3), (10, 1)] {
            let radius = 400.0
            let chase = Pursuit.ring(sides: sides, center: center, radius: radius,
                                     chasing: chasing, stepSize: radius / 4000)
            chase.run()
            #expect(chase.isFinished, "\(sides) sides chasing \(chasing) never arrived")
            let want = lawfulDistance(radius: radius, sides: sides, chasing: chasing)
            let made = chase.runners[0].distanceTraveled
            #expect(abs(made - want) / want < 0.005,
                    "\(sides) sides chasing \(chasing) ran \(made), the law says \(want)")
        }
    }

    @Test func theSquareIsTheCaseEveryoneQuotes() {
        // Four dogs on a square each run exactly one side of it.
        let side = 300.0
        let chase = Pursuit.ring(sides: 4, center: .zero, radius: side / 2.0.squareRoot(),
                                 stepSize: 0.02)
        chase.run()
        #expect(abs(chase.runners[0].distanceTraveled - side) / side < 0.005,
                "ran \(chase.runners[0].distanceTraveled) where the side is \(side)")
    }

    @Test func aFixedStepStopsShortOfTheCenter() {
        // A runner covering a fixed distance per step overshoots a little every
        // time, so the ring can never reach the middle. Two exact bounds fall
        // out of the shrink rule, written as (r - d * sin) squared plus
        // d * d * cos squared:
        //
        //  - it never gets nearer the center than one stride times the cosine,
        //  - and since a runner lands on its target rather than running past
        //    it, the chase always ends at or inside the circle where the gap
        //    is one stride, which is stride / (2 * sin).
        let center = Vector2(0, 0)
        let step = 2.0
        for sides in [3, 5, 8] {
            let closing = sin(Double.pi / Double(sides))
            let nearestPossible = step * cos(Double.pi / Double(sides))
            let settling = step / (2 * closing)

            let settled = Pursuit.ring(sides: sides, center: center, radius: 300,
                                       stepSize: step)
            settled.catchDistance = 0        // floored at one stride, so it runs on
            var nearest = Double.infinity
            while !settled.isFinished && settled.stepsTaken < 20_000 {
                settled.step()
                nearest = Swift.min(nearest, radius(of: settled, around: center))
            }
            #expect(nearest >= nearestPossible - 1e-9,
                    "\(sides) sides came within \(nearest), nearer than \(nearestPossible)")
            let rested = radius(of: settled, around: center)
            #expect(rested <= settling + 1e-9,
                    "\(sides) sides ended at \(rested), outside \(settling)")

            // The default catch distance is twice the step, so an ordinary run
            // ends inside twice the settling radius, and no more than one
            // step's shrink inside it.
            let ordinary = Pursuit.ring(sides: sides, center: center, radius: 300,
                                        stepSize: step)
            ordinary.run()
            let ended = radius(of: ordinary, around: center)
            #expect(ended <= 2 * settling + 1e-9,
                    "\(sides) sides ended at \(ended), outside twice \(settling)")
            #expect(ended > 2 * settling - step * closing - 1e-9,
                    "\(sides) sides ended at \(ended), further in than one step")
        }
    }

    // MARK: - The straight-line chase

    /// A quarry crossing in front at `k` times the pursuer's speed, starting
    /// square-on at distance `gap`.
    private func straightLineChase(gap: Double, quarrySpeed k: Double,
                                   stepSize: Double = 0.05) -> Pursuit {
        Pursuit(runners: [.holding(Vector2(0, 1), from: .zero, speed: k),
                          .chasing(0, from: Vector2(gap, 0))],
                stepSize: stepSize)
    }

    @Test func aStraightLineChaseEndsWhereTheLawSays() {
        // The published result: the pursuer covers gap / (1 - k * k), and the
        // quarry is caught after running gap * k / (1 - k * k).
        for k in [0.25, 0.5, 0.75] {
            let gap = 300.0
            let chase = straightLineChase(gap: gap, quarrySpeed: k)
            chase.run()
            #expect(chase.isFinished, "a slower quarry is always caught")
            let wantPursuer = gap / (1 - k * k)
            let wantQuarry = gap * k / (1 - k * k)
            let ranPursuer = chase.runners[1].distanceTraveled
            let ranQuarry = chase.runners[0].distanceTraveled
            #expect(abs(ranPursuer - wantPursuer) / wantPursuer < 0.005,
                    "at k \(k) the pursuer ran \(ranPursuer), the law says \(wantPursuer)")
            #expect(abs(ranQuarry - wantQuarry) / wantQuarry < 0.005,
                    "at k \(k) the quarry ran \(ranQuarry), the law says \(wantQuarry)")
        }
    }

    @Test func aQuarryAsFastAsItsPursuerIsNeverCaught() {
        let gap = 300.0
        let chase = straightLineChase(gap: gap, quarrySpeed: 1)
        chase.run(limit: 200_000)
        #expect(!chase.isFinished, "an equal quarry stays ahead")
        // And the classic tail: the gap closes toward half what it started as,
        // from above, and then stops closing.
        let ended = chase.runners[0].position.distance(to: chase.runners[1].position)
        #expect(ended > gap / 2, "it never closes past half: \(ended)")
        #expect(ended < gap / 2 * 1.1, "and it does close to about half: \(ended)")
    }

    // MARK: - The rules a runner obeys

    @Test func aRunnerNeverTurnsMoreThanItsLimit() {
        let limit = 0.03
        let chase = Pursuit(runners: [.holding(Vector2(0, 1), from: .zero, speed: 0.6),
                                      // Facing away, so it has to come about.
                                      Runner(position: Vector2(200, 0), chases: 0,
                                             heading: Vector2(1, 0))],
                            stepSize: 0.5)
        chase.maxTurn = limit
        var heading = chase.runners[1].heading
        var turned = false
        for _ in 0 ..< 400 {
            chase.step()
            let now = chase.runners[1].heading
            let turn = abs(heading.angle(to: now))
            #expect(turn <= limit + 1e-12, "it turned \(turn) with a limit of \(limit)")
            if turn > 1e-9 { turned = true }
            heading = now
        }
        #expect(turned, "and it did come about rather than freeze")
    }

    @Test func aRunnerThatCannotTurnAtAllRunsStraight() {
        let chase = Pursuit(runners: [.holding(Vector2(0, 1), from: .zero),
                                      Runner(position: Vector2(100, 0), chases: 0,
                                             heading: Vector2(-1, 0))],
                            stepSize: 1)
        chase.maxTurn = 0
        chase.step(50)
        #expect(chase.runners[1].position.y == 0, "it held its line")
        #expect(chase.runners[1].position.x == 50)
    }

    @Test func aRunnerNeverRunsPastTheOneItCaught() {
        // A stride longer than the gap must land on the target, not beyond it.
        let chase = Pursuit(runners: [.holding(Vector2(0, 1), from: .zero, speed: 0),
                                      .chasing(0, from: Vector2(10, 0), speed: 40)],
                            stepSize: 1)
        chase.step(3)
        #expect(chase.runners[1].hasArrived)
        #expect(chase.runners[1].position == .zero, "it stopped on the quarry")
        #expect(chase.runners[1].distanceTraveled == 10, "having run the gap and no more")
        #expect(chase.stepsTaken == 1, "and the chase was over after one step")
    }

    @Test func aRunnerChasingNobodyHoldsItsHeading() {
        for who in [Runner(position: .zero, chases: nil, heading: Vector2(3, 4)),
                    // Chasing itself, and chasing somebody who is not there,
                    // both mean chasing nobody.
                    Runner(position: .zero, chases: 0, heading: Vector2(3, 4)),
                    Runner(position: .zero, chases: 7, heading: Vector2(3, 4))] {
            let chase = Pursuit(runners: [who, .chasing(0, from: Vector2(0, 500))],
                                stepSize: 1)
            chase.step(10)
            #expect(abs(chase.runners[0].position.x - 6) < 1e-9)
            #expect(abs(chase.runners[0].position.y - 8) < 1e-9,
                    "a unit heading, so ten steps is ten units along it")
        }
    }

    @Test func theWebKeepsTheChaseLinesAlongTheWay() {
        let chase = Pursuit.ring(sides: 5, center: .zero, radius: 100, stepSize: 1)
        #expect(chase.web.isEmpty, "nothing is kept until it is asked for")
        chase.recordEvery = 10
        chase.step(100)
        #expect(chase.web.count == 5 * 10, "the line-up you started with, and nine more")
        #expect(chase.web.allSatisfy { $0.points.count == 2 && !$0.isClosed })
        #expect(chase.links.count == 5, "one line per runner that follows another")
    }

    @Test func aChaseWithNobodyRunningIsOverBeforeItStarts() {
        let empty = Pursuit(runners: [], stepSize: 1)
        #expect(empty.isFinished)
        empty.run()
        #expect(empty.stepsTaken == 0)
        #expect(empty.trails.isEmpty)

        let loners = Pursuit(runners: [.holding(Vector2(1, 0), from: .zero)], stepSize: 1)
        #expect(loners.isFinished, "there is nobody left to arrive")
    }

    @Test func theTrailStartsWhereTheRunnerDid() {
        let chase = Pursuit.ring(sides: 4, center: Vector2(50, 50), radius: 30)
        let starts = chase.runners.map(\.position)
        chase.step(25)
        for (index, trail) in chase.trails.enumerated() {
            #expect(trail.points.first == starts[index])
            #expect(trail.points.count == 26, "one point per step, and the start")
            #expect(!trail.isClosed)
            #expect(trail.points.last == chase.runners[index].position)
        }
    }

    @Test func aRingAsksForAtLeastTwoRunnersAndASensibleTarget() {
        #expect(Pursuit.ring(sides: 1, center: .zero, radius: 10).runners.count == 2)
        // Chasing yourself is not a chase, so the target is clamped into range.
        let clamped = Pursuit.ring(sides: 5, center: .zero, radius: 10, chasing: 9)
        #expect(clamped.runners.allSatisfy { $0.chases != nil })
        #expect(zip(clamped.runners.indices, clamped.runners)
            .allSatisfy { $0.1.chases != $0.0 })
    }
}
