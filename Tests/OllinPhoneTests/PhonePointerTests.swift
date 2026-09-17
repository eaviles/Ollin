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
}
