import Foundation
import Testing
import Ollin
@testable import OllinLaser

/// The rules that stand between a sketch and the beam, each measured on a
/// stream that breaks it, and each shown able to fail: the brightness ceiling,
/// the stopped-beam guard, and what the guard must not touch.
@Suite
struct LaserSafetyTests {

    // MARK: Brightness

    @Test func theCeilingDimsEveryChannel() {
        var safety = LaserSafety()
        safety.maximumBrightness = 0.25
        let guarded = safety.guarded([LaserPoint(Vector2(0, 0), color: Color(red: 1, green: 0.8, blue: 0.4))])
        #expect(abs(guarded[0].color.red - 0.25) < 1e-9)
        #expect(abs(guarded[0].color.green - 0.2) < 1e-9)
        #expect(abs(guarded[0].color.blue - 0.1) < 1e-9)
    }

    @Test func aFullCeilingLeavesTheColorAlone() {
        var safety = LaserSafety()
        safety.maximumBrightness = 1
        let color = Color(red: 0.3, green: 0.6, blue: 0.9)
        #expect(safety.guarded([LaserPoint(.zero, color: color)])[0].color == color)
    }

    // MARK: A beam that stops

    @Test func aBeamThatStopsMovingIsBlanked() {
        var safety = LaserSafety()
        safety.stationaryLimit = 10
        // The worst frame there is: one lit point, played over and over.
        let held = Array(repeating: LaserPoint(Vector2(0.2, 0.2), color: .white), count: 50)
        let guarded = safety.guarded(held)
        #expect(guarded.prefix(10).allSatisfy { !$0.isBlanked })
        #expect(guarded.dropFirst(10).allSatisfy { $0.isBlanked })
    }

    @Test func aTinyShapeCountsAsStoppedToo() {
        var safety = LaserSafety()
        safety.stationaryLimit = 8
        safety.stationaryRadius = 0.01
        // A circle far smaller than the guard's radius is a spot, whatever the
        // sketch calls it.
        let points = (0..<40).map { i -> LaserPoint in
            let a = Double(i) / 40 * 2 * .pi
            return LaserPoint(Vector2(cos(a), sin(a)) * 0.002, color: .white)
        }
        #expect(safety.guarded(points).contains { $0.isBlanked })
    }

    @Test func movingOnStartsTheCountAgain() {
        var safety = LaserSafety()
        safety.stationaryLimit = 4
        safety.stationaryRadius = 0.01
        // A line drawn in steps well past the radius never trips the guard,
        // however long it is.
        let line = (0..<200).map { LaserPoint(Vector2(-1 + Double($0) * 0.01, 0), color: .white) }
        #expect(safety.guarded(line).allSatisfy { !$0.isBlanked })
    }

    @Test func aCornerDwellSurvivesTheGuard() {
        // The optimizer holds points at a corner on purpose. The default limit
        // sits well above that dwell, so the corners stay lit.
        var optimizer = LaserOptimizer()
        optimizer.cornerDwell = 6
        let stream = LaserOptimizer.guardedSquare(optimizer, LaserSafety())
        let corner = Vector2(0.5, 0.5)
        #expect(stream.points.contains { close($0.position, corner, tolerance: 1e-9) && !$0.isBlanked })
    }

    @Test func aLimitBelowTheDwellBlanksTheCorner() {
        // The counterfactual: the same corner, guarded by a limit that no dwell
        // could clear. If this stays lit, the guard is doing nothing at all.
        var optimizer = LaserOptimizer()
        optimizer.cornerDwell = 6
        var safety = LaserSafety()
        safety.stationaryLimit = 2
        let stream = LaserOptimizer.guardedSquare(optimizer, safety)
        let corner = Vector2(0.5, 0.5)
        let atCorner = stream.points.filter { close($0.position, corner, tolerance: 1e-9) }
        #expect(atCorner.contains { $0.isBlanked })
    }

    // MARK: What it must not touch

    @Test func blankedPointsAreLeftDark() {
        var safety = LaserSafety()
        safety.maximumBrightness = 1
        let travel = (0..<20).map { LaserPoint(blankedAt: Vector2(Double($0) * 0.05, 0)) }
        let guarded = safety.guarded(travel)
        #expect(guarded.allSatisfy { $0.isBlanked && $0.color == .black })
    }

    @Test func aDarkStretchDoesNotCountTowardsTheLimit() {
        var safety = LaserSafety()
        safety.stationaryLimit = 6
        // Lit, dark, lit at the same spot: the dark run resets the count, so
        // neither lit run reaches the limit.
        var points = Array(repeating: LaserPoint(Vector2(0.1, 0.1), color: .white), count: 5)
        points += Array(repeating: LaserPoint(blankedAt: Vector2(0.1, 0.1)), count: 3)
        points += Array(repeating: LaserPoint(Vector2(0.1, 0.1), color: .white), count: 5)
        let guarded = safety.guarded(points)
        #expect(guarded.filter { !$0.isBlanked }.count == 10)
    }

    @Test func theUnguardedRulesChangeNothing() {
        let points = Array(repeating: LaserPoint(Vector2(0.5, 0.5), color: .white), count: 500)
        #expect(LaserSafety.unguarded.guarded(points) == points)
    }

    @Test func theBlankHoldIsAllDarkAndSomewhere() {
        let hold = LaserSafety.blankHold(count: 12)
        #expect(hold.count == 12)
        #expect(hold.allSatisfy { $0.isBlanked && $0.position == .zero })
    }

    @Test func theGuardKeepsTheStreamsOwnFacts() {
        let stream = LaserSafety().guarded(LaserOptimizer().stream(square()))
        #expect(stream.canvas == unitCanvas)
        #expect(stream.pathCount == 1)
        #expect(stream.drawnLength > 0)
    }
}

extension LaserOptimizer {
    /// The square, optimized and guarded: the fixture the corner rules use.
    static func guardedSquare(_ optimizer: LaserOptimizer, _ safety: LaserSafety) -> LaserStream {
        var optimizer = optimizer
        optimizer.reordersPaths = false
        return safety.guarded(optimizer.stream(square()))
    }
}
