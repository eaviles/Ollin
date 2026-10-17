import Testing
import Ollin
@testable import OllinPhone

/// The fingers read as one pointer, the rule a sketch shown on the phone gets its
/// `mouseX` and `mouseIsPressed` from. Pure: no phone, no sketch, no main actor.
@Suite(.timeLimit(.minutes(1))) struct PhonePointerTests {

    private func finger(_ id: Int, _ x: Double, _ y: Double, force: Double? = nil) -> PhoneTouch {
        PhoneTouch(id: id, position: Vector2(x, y), force: force)
    }

    @Test func aTapPressesAndReleasesWhereItLanded() {
        var pointer = PhonePointer()
        #expect(pointer.take([finger(1, 0.5, -0.5)]) == [.press(Vector2(0.5, -0.5), force: nil)])
        #expect(pointer.take([]) == [.release(Vector2(0.5, -0.5))])
        #expect(pointer.holder == nil)
    }

    @Test func aDragMovesOnlyWhenSomethingChanged() {
        var pointer = PhonePointer()
        _ = pointer.take([finger(1, 0, 0)])
        #expect(pointer.take([finger(1, 0.25, 0)]) == [.move(Vector2(0.25, 0), force: nil)])
        #expect(pointer.take([finger(1, 0.25, 0)]).isEmpty)
        // A press getting harder is a move too: pressure is part of the pointer.
        #expect(pointer.take([finger(1, 0.25, 0, force: 0.6)]) == [.move(Vector2(0.25, 0), force: 0.6)])
    }

    @Test func aSecondFingerNeverMovesThePointer() {
        var pointer = PhonePointer()
        _ = pointer.take([finger(1, 0, 0)])
        #expect(pointer.take([finger(1, 0, 0), finger(2, 0.9, 0.9)]).isEmpty)
        #expect(pointer.holder == 1)
    }

    @Test func aRestingFingerDoesNotTakeOverWhenTheFirstLifts() {
        var pointer = PhonePointer()
        _ = pointer.take([finger(1, 0, 0)])
        _ = pointer.take([finger(1, 0, 0), finger(2, 0.9, 0.9)])
        // The holder lifts with the second still down: a release, and no jump.
        #expect(pointer.take([finger(2, 0.9, 0.9)]) == [.release(Vector2(0, 0))])
        #expect(pointer.take([finger(2, 0.8, 0.9)]).isEmpty)
        // Once the resting finger leaves too, the next landing takes the pointer.
        #expect(pointer.take([]).isEmpty)
        #expect(pointer.take([finger(3, -1, 1)]) == [.press(Vector2(-1, 1), force: nil)])
    }

    @Test func aFingerLandingAsTheHolderLeavesTakesItInOneReading() {
        var pointer = PhonePointer()
        _ = pointer.take([finger(1, 0, 0)])
        #expect(pointer.take([finger(2, 0.5, 0.5)])
                == [.release(Vector2(0, 0)), .press(Vector2(0.5, 0.5), force: nil)])
        #expect(pointer.holder == 2)
    }

    @Test func fingersPassedAtTheStartNeverPress() {
        // Arming while a hand rests on the glass must not press where it rests.
        var pointer = PhonePointer()
        pointer.pass([4])
        #expect(pointer.take([finger(4, 0, 0)]).isEmpty)
        #expect(pointer.take([finger(4, 0, 0), finger(5, 0.1, 0.1)]) == [.press(Vector2(0.1, 0.1), force: nil)])
    }

    // MARK: Two fingers as a pair

    private func pair(_ a: (Double, Double), _ b: (Double, Double)) -> PhonePointer.Pair {
        PhonePointer.Pair(first: Vector2(a.0, a.1), second: Vector2(b.0, b.1))
    }

    @Test func twoFingersThatMoveSayWhereBothWereAndAre() {
        var pointer = PhonePointer()
        _ = pointer.take([finger(1, -0.2, 0), finger(2, 0.2, 0)])
        // The first finger holds the pointer, so it moves it as well.
        #expect(pointer.take([finger(1, -0.4, 0), finger(2, 0.4, 0)])
                == [.move(Vector2(-0.4, 0), force: nil),
                    .pair(from: pair((-0.2, 0), (0.2, 0)), to: pair((-0.4, 0), (0.4, 0)))])
        #expect(pointer.take([finger(1, -0.4, 0), finger(2, 0.4, 0)]).isEmpty,
                "a pair that holds still says nothing")
    }

    @Test func aPairThatChangesFingersStartsOver() {
        var pointer = PhonePointer()
        _ = pointer.take([finger(1, 0, 0), finger(2, 0.5, 0)])
        // The second finger lifts as a third lands far away: no pinch across the swap.
        #expect(pointer.take([finger(1, 0, 0), finger(3, -0.9, 0.9)]).isEmpty)
        #expect(pointer.take([finger(1, 0, 0), finger(3, -0.8, 0.9)])
                == [.pair(from: pair((0, 0), (-0.9, 0.9)), to: pair((0, 0), (-0.8, 0.9)))])
        // Down to one finger and back to two is a new pair too.
        _ = pointer.take([finger(1, 0, 0)])
        #expect(pointer.take([finger(1, 0, 0), finger(4, 0.3, 0.3)]).isEmpty)
    }

    @Test func spreadingToTwiceTheDistanceIsAPinchOfTwo() throws {
        let canvas = Rectangle(x: 0, y: 0, width: 800, height: 600)
        let change = try #require(pair((-0.1, 0.2), (0.1, 0.2))
            .change(to: pair((-0.2, 0.2), (0.2, 0.2)), in: canvas))
        #expect(abs(change.scale - 2) < 1e-12 && abs(change.turn) < 1e-12)
    }

    @Test func aQuarterTurnClockwiseOnTheGlassIsAPositiveQuarterTurn() throws {
        // Up on the glass is up on the canvas, so the second finger going from
        // the right of the first to below it is clockwise on the screen, the
        // way `rotate(_:)` turns a positive angle.
        let canvas = Rectangle(x: 0, y: 0, width: 1000, height: 1000)
        let change = try #require(pair((0, 0), (0.5, 0)).change(to: pair((0, 0), (0, -0.5)), in: canvas))
        #expect(abs(change.turn - .pi / 2) < 1e-12 && abs(change.scale - 1) < 1e-12)
    }

    @Test func aTurnAcrossTheBackIsTheShorterWayRound() throws {
        // From just above the first finger's left to just below it is a small
        // counterclockwise turn, never most of a circle the other way.
        let canvas = Rectangle(x: 0, y: 0, width: 1000, height: 1000)
        let change = try #require(pair((0, 0), (-0.5, 0.01)).change(to: pair((0, 0), (-0.5, -0.01)), in: canvas))
        #expect(change.turn < 0 && change.turn > -0.05, "turn \(change.turn)")
    }

    @Test func twoFingersOnOneSpotHaveNoChange() {
        let canvas = Rectangle(x: 0, y: 0, width: 100, height: 100)
        #expect(pair((0.3, 0.3), (0.3, 0.3)).change(to: pair((0, 0), (0.5, 0)), in: canvas) == nil)
        #expect(pair((0, 0), (0.5, 0)).change(to: pair((0.1, 0.1), (0.1, 0.1)), in: canvas) == nil)
    }
}
