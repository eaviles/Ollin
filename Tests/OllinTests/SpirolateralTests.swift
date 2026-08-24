import Foundation
import Ollin
import Testing

/// Laws for the spirolateral. The walk is a run of growing steps repeated until
/// it comes home, so the laws are about when it comes home, and about the turn
/// that carries one run onto the next.
@Suite
struct SpirolateralTests {
    /// The classic figure, corner by corner, worked out by hand. Steps of 1, 2, 3,
    /// 4 with a quarter turn after each, on a canvas where y grows downward.
    @Test func oneRunGoesWhereTheRuleSaysItDoes() {
        let figure = Spirolateral(order: 4, step: 10)
        let expected = [Vector2(0, 0), Vector2(10, 0), Vector2(10, 20), Vector2(-20, 20),
                        Vector2(-20, -20)]
        #expect(figure.points.count == expected.count)
        for (walked, want) in zip(figure.points, expected) {
            #expect(walked.distance(to: want) < 1e-9, "\(walked) is not \(want)")
        }
    }

    /// The closing count, against the count the turn dictates: a run turns the
    /// walker through `order` turns of `tau / k`, so the runs close as soon as a
    /// whole number of them makes a whole number of laps, which is `k / gcd`. When
    /// `k` divides `order` the run leaves the walker facing the way it set off, so
    /// no number of runs ever closes it.
    @Test func theClosingCountIsTheOneTheTurnDictates() {
        for k in 2 ... 12 {
            for order in 1 ... 24 {
                let figure = Spirolateral(order: order, turn: .tau / Double(k), step: 3)
                if order % k == 0 {
                    #expect(figure.closingRepeats == nil,
                            "order \(order) at a turn of tau/\(k) should never close")
                    #expect(figure.center == nil)
                } else {
                    #expect(figure.closingRepeats == k / gcd(order, k),
                            "order \(order) at a turn of tau/\(k)")
                    #expect(figure.closes)
                }
            }
        }
    }

    /// A quarter turn is the classic, and there the rule reads: every order closes
    /// except the multiples of four.
    @Test func aQuarterTurnClosesEveryOrderButTheMultiplesOfFour() {
        for order in 1 ... 20 {
            let figure = Spirolateral(order: order, step: 5)
            #expect(figure.closes == (order % 4 != 0), "order \(order)")
        }
        #expect(Spirolateral(order: 7, step: 5).repeats == 4)
        #expect(Spirolateral(order: 6, step: 5).repeats == 2)
        #expect(Spirolateral(order: 8, step: 5).repeats == 1)
    }

    /// A walk that says it comes home has to come home. Measured on the walk
    /// itself: the steps are re-walked here, from the rule rather than from the
    /// value, and they have to sum to nothing and turn a whole number of laps.
    @Test func aClosedWalkComesHome() {
        for order in [1, 2, 3, 5, 6, 7, 9, 10, 11] {
            let figure = Spirolateral(order: order, step: 4)
            var position = Vector2.zero
            var turns = 0
            for _ in 0 ..< figure.repeats {
                for i in 1 ... order {
                    position += Vector2(angle: Double(turns) * (.pi / 2), length: 4 * Double(i))
                    turns += 1
                }
            }
            #expect(position.length < 1e-9, "order \(order) stopped at \(position)")
            #expect(turns % 4 == 0, "order \(order) stopped facing a different way")
        }
    }

    /// The figure is one run turned about `center`, once per repeat. This is the
    /// law the whole shape rests on, and it names the corner it checks.
    @Test func everyRunIsTheFirstRunTurnedAboutTheCenter() {
        for order in [3, 5, 6, 7, 11] {
            let figure = Spirolateral(order: order, step: 7)
            guard let center = figure.center else { Issue.record("no center"); continue }
            for runIndex in 0 ..< figure.repeats {
                for i in 0 ..< order {
                    let turned = figure.points[i].rotated(by: Double(runIndex) * figure.netTurn,
                                                          around: center)
                    let walked = figure.points[runIndex * order + i]
                    #expect(walked.distance(to: turned) < 1e-9,
                            "order \(order), run \(runIndex), corner \(i): \(walked) is not \(turned)")
                }
            }
        }
    }

    /// A figure with that turn about a point is balanced about it, so the middle of
    /// its corners is the point itself. Independent of the walk: it only asks that
    /// the corners are spread evenly around the turn.
    @Test func theCornersBalanceOnTheCenter() {
        for order in [3, 5, 6, 7, 9, 11] {
            let figure = Spirolateral(order: order, step: 6)
            guard let center = figure.center else { continue }
            let middle = figure.points.reduce(Vector2.zero, +) / Double(figure.points.count)
            #expect(middle.distance(to: center) < 1e-9, "order \(order)")
        }
    }

    /// The pen travels one triangular number of steps per run, and the drawn
    /// outline has to be exactly that long.
    @Test func theOutlineIsAsLongAsTheStepsItIsMadeOf() {
        for order in [2, 3, 5, 7, 10] {
            let figure = Spirolateral(order: order, step: 2.5)
            #expect(abs(figure.length - Double(figure.repeats) * 2.5
                    * Double(order * (order + 1)) / 2) < 1e-9)
            var measured = 0.0
            for i in 0 ..< figure.points.count {
                let next = figure.points[(i + 1) % figure.points.count]
                if !figure.closes, i == figure.points.count - 1 { break }
                measured += figure.points[i].distance(to: next)
            }
            #expect(abs(measured - figure.length) < 1e-6, "order \(order)")
        }
    }

    /// Turning the other way on one step changes the count, because it changes how
    /// far a run turns the walker. Order 6 closes in two runs; reverse its first
    /// turn and the run comes back facing the way it set off, so it never closes.
    @Test func reversingATurnChangesWhetherItClosesAtAll() {
        let plain = Spirolateral(order: 6, step: 5)
        #expect(plain.closingRepeats == 2)
        let reversed = Spirolateral(order: 6, step: 5, reversed: [1])
        #expect(reversed.closingRepeats == nil)
        #expect(reversed.center == nil)
        #expect(abs(reversed.netTurn - .tau) < 1e-9)

        // And a reversal that leaves the net turn alone leaves the count alone,
        // while still drawing a different figure.
        let other = Spirolateral(order: 7, step: 5, reversed: [2, 5])
        #expect(other.closingRepeats == Spirolateral(order: 7, step: 5, reversed: [3, 6]).closingRepeats)
        #expect(other.points != Spirolateral(order: 7, step: 5, reversed: [3, 6]).points)
    }

    /// Asking for a count is allowed to overshoot the closing one, and the walk is
    /// then that many runs long, closed only when it lands on a whole number of
    /// them.
    @Test func anAskedForCountIsHonored() {
        let twice = Spirolateral(order: 7, step: 5, repeats: 8)
        #expect(twice.repeats == 8)
        #expect(twice.closes)
        #expect(twice.points.count == 56)

        let short = Spirolateral(order: 7, step: 5, repeats: 3)
        #expect(short.repeats == 3)
        #expect(!short.closes)
        // An open walk keeps the corner it stopped at.
        #expect(short.points.count == 22)
    }

    /// A walk that never closes is drawn as one run, open, and holds the corner it
    /// stopped at.
    @Test func aDriftingWalkIsDrawnOpen() {
        let figure = Spirolateral(order: 8, step: 3)
        #expect(!figure.closes)
        #expect(figure.repeats == 1)
        #expect(figure.points.count == 9)
        #expect(!figure.contour.isClosed)
        #expect(figure.runDisplacement.length > 1e-6)
    }

    /// Nothing to walk, nothing drawn.
    @Test func anEmptyWalkMakesNoPoints() {
        #expect(Spirolateral(order: 0, step: 5).points.isEmpty)
        #expect(Spirolateral(order: -3, step: 5).points.isEmpty)
        #expect(Spirolateral(order: 5, step: 0).points.isEmpty)
    }

    private func gcd(_ a: Int, _ b: Int) -> Int {
        var a = abs(a), b = abs(b)
        while b != 0 { (a, b) = (b, a % b) }
        return a
    }
}
