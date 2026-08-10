import Testing
import Foundation
import GameController
import Ollin
@testable import OllinController

/// What a sketch reads off a controller, checked against a controller the test
/// itself drives.
///
/// The system will make a synthetic `GCController`: a real controller object,
/// with a real profile, whose values a caller writes instead of a hand. It
/// never joins the system's own list, so the hub takes its list through a seam
/// the tests replace. That is what makes these tests real rather than a mock
/// of the framework, and it is also why the read path is polled: a synthetic
/// controller does **not** fire the system's change handlers, so a design
/// built on handlers could not be checked at all without hardware plugged in.
///
/// Serialized because there is one hub for the process, exactly as there is
/// one controller list for the process.
@MainActor
@Suite(.serialized) struct ControllerTests {

    // MARK: - The double itself

    /// Everything below leans on a synthetic controller behaving like a real
    /// one, so that is checked first and on its own. Without this, a break in
    /// the double would show up as every other test quietly passing over
    /// nothing.
    @Test func aSyntheticControllerCarriesARealProfile() {
        let pad = GCController.withExtendedGamepad()
        #expect(pad.isSnapshot)
        #expect(pad.extendedGamepad != nil,
                "a synthetic controller must carry an extended gamepad profile")
        #expect(pad.extendedGamepad?.allButtons.isEmpty == false)

        // And it must accept written values, since every test below writes.
        pad.extendedGamepad?.leftThumbstick.setValueForXAxis(0.5, yAxis: 0)
        #expect(pad.extendedGamepad?.leftThumbstick.xAxis.value == 0.5)

        // It is deliberately absent from the system's own list. If this ever
        // changes, the source seam below is measuring nothing.
        #expect(!GCController.controllers().contains(pad))
    }

    // MARK: - Nothing attached

    @Test func nothingAttachedReadsCenteredAndUnpressed() {
        let hub = staged([])
        let pad = hub.controller(player: 1, frame: 1)

        #expect(!pad.isConnected)
        #expect(pad.leftStick == .zero)
        #expect(pad.rightStick == .zero)
        #expect(pad.leftTrigger == 0)
        #expect(!pad.isDown(.a))
        #expect(!pad.anyButtonIsDown)
        #expect(pad.name == nil)
    }

    /// An empty slot is not a fault, so it names no reason. Only something
    /// genuinely wrong, like an export, gets to explain itself.
    @Test func anEmptySlotIsNotAnError() {
        let hub = staged([])
        #expect(hub.controller(player: 1, frame: 1).unavailableReason == nil)
    }

    // MARK: - Reading a stick

    @Test func aStickIsRead() {
        let (hub, gc) = stagedOne()
        gc.extendedGamepad?.leftThumbstick.setValueForXAxis(1, yAxis: 0)

        let pad = hub.controller(player: 1, frame: 1)
        #expect(pad.isConnected)
        #expect(abs(pad.leftStick.x - 1) < 0.001)
    }

    /// The one conversion in the whole tier: the system reports a stick with up
    /// positive, Ollin's canvas grows downward, so a sketch adding the stick to
    /// a position should move up the screen when the stick goes up.
    @Test func pushingUpGivesNegativeYSoItMatchesTheCanvas() {
        let (hub, gc) = stagedOne()
        gc.extendedGamepad?.leftThumbstick.setValueForXAxis(0, yAxis: 1)

        let pad = hub.controller(player: 1, frame: 1)
        #expect(pad.leftStick.y < 0, "up must read negative, the way canvas y does")
        #expect(abs(pad.leftStick.y + 1) < 0.001)
    }

    /// Its counterfactual: without the flip these two would agree.
    @Test func pushingDownGivesPositiveY() {
        let (hub, gc) = stagedOne()
        gc.extendedGamepad?.leftThumbstick.setValueForXAxis(0, yAxis: -1)
        #expect(hub.controller(player: 1, frame: 1).leftStick.y > 0)
    }

    // MARK: - The deadzone

    @Test func aRestingStickReadsAsCentered() {
        let (hub, gc) = stagedOne()
        gc.extendedGamepad?.leftThumbstick.setValueForXAxis(0.05, yAxis: 0.03)
        #expect(hub.controller(player: 1, frame: 1).leftStick == .zero)
    }

    /// The deadzone must not cost the top of the range: pushed all the way,
    /// the stick still reads a full 1.
    @Test func aFullyPushedStickStillReachesOne() {
        let (hub, gc) = stagedOne()
        gc.extendedGamepad?.leftThumbstick.setValueForXAxis(1, yAxis: 0)
        #expect(abs(hub.controller(player: 1, frame: 1).leftStick.x - 1) < 0.001)
    }

    /// Rescaled rather than cut: a stick just past the edge reads near zero and
    /// grows smoothly. A flat cut would jump straight to the deadzone's width.
    @Test func theDeadzoneRescalesRatherThanJumping() {
        let (hub, gc) = stagedOne()
        hub.deadzone = 0.2
        gc.extendedGamepad?.leftThumbstick.setValueForXAxis(0.21, yAxis: 0)

        let value = hub.controller(player: 1, frame: 1).leftStick.x
        #expect(value > 0, "just past the edge must register")
        #expect(value < 0.05, "and must start near zero, not jump to 0.21")
    }

    /// Radial, not per-axis: a stick held diagonally keeps its direction, where
    /// cutting each axis on its own would bend it toward the diagonal.
    @Test func theDeadzoneKeepsAStickPointingWhereItIsHeld() {
        let (hub, gc) = stagedOne()
        gc.extendedGamepad?.leftThumbstick.setValueForXAxis(0.6, yAxis: -0.6)

        let stick = hub.controller(player: 1, frame: 1).leftStick
        #expect(abs(stick.x - stick.y) < 0.001, "a 45° hold must stay at 45°")
    }

    @Test func aZeroDeadzoneReadsTheHardwareUntouched() {
        let (hub, gc) = stagedOne()
        hub.deadzone = 0
        gc.extendedGamepad?.leftThumbstick.setValueForXAxis(0.05, yAxis: 0)
        #expect(abs(hub.controller(player: 1, frame: 1).leftStick.x - 0.05) < 0.001)
    }

    // MARK: - Triggers

    @Test func aTriggerReadsHowFarItIsPulled() {
        let (hub, gc) = stagedOne()
        hub.deadzone = 0
        gc.extendedGamepad?.rightTrigger.setValue(0.75)
        #expect(abs(hub.controller(player: 1, frame: 1).rightTrigger - 0.75) < 0.001)
    }

    /// A trigger is both a level and a button, and the button half comes from
    /// the hardware's own threshold rather than from the deadzone.
    @Test func aPulledTriggerIsAlsoDown() {
        let (hub, gc) = stagedOne()
        gc.extendedGamepad?.rightTrigger.setValue(1)
        #expect(hub.controller(player: 1, frame: 1).isDown(.rightTrigger))
    }

    // MARK: - Buttons, and the edges between frames

    @Test func aHeldButtonReadsDown() {
        let (hub, gc) = stagedOne()
        gc.extendedGamepad?.buttonA.setValue(1)
        #expect(hub.controller(player: 1, frame: 1).isDown(.a))
    }

    /// The point of the whole difference-two-frames design: a press fires once,
    /// however long the button is held, so a sketch can drop one thing per
    /// press without tracking state itself.
    @Test func aPressIsReportedForExactlyOneFrame() {
        let (hub, gc) = stagedOne()
        _ = hub.controller(player: 1, frame: 1)

        gc.extendedGamepad?.buttonA.setValue(1)
        let pressFrame = hub.controller(player: 1, frame: 2)
        #expect(pressFrame.wasPressed(.a))
        #expect(pressFrame.isDown(.a))

        let heldFrame = hub.controller(player: 1, frame: 3)
        #expect(!heldFrame.wasPressed(.a), "a held button must not press again")
        #expect(heldFrame.isDown(.a), "but it is still down")
    }

    @Test func aReleaseIsReportedForExactlyOneFrame() {
        let (hub, gc) = stagedOne()
        gc.extendedGamepad?.buttonA.setValue(1)
        _ = hub.controller(player: 1, frame: 1)

        gc.extendedGamepad?.buttonA.setValue(0)
        let releaseFrame = hub.controller(player: 1, frame: 2)
        #expect(releaseFrame.wasReleased(.a))
        #expect(!releaseFrame.isDown(.a))

        #expect(!hub.controller(player: 1, frame: 3).wasReleased(.a))
    }

    /// Asking twice in one frame must give one answer, or a sketch reading
    /// `wasPressed` in two places would see the press in only one of them.
    @Test func everyReadWithinAFrameAgrees() {
        let (hub, gc) = stagedOne()
        _ = hub.controller(player: 1, frame: 1)
        gc.extendedGamepad?.buttonA.setValue(1)

        #expect(hub.controller(player: 1, frame: 2).wasPressed(.a))
        #expect(hub.controller(player: 1, frame: 2).wasPressed(.a),
                "the second read in the same frame must still see the press")
    }

    /// And the hardware is polled once, not once per question.
    @Test func theHardwareIsPolledOncePerFrame() {
        let gc = GCController.withExtendedGamepad()
        let hub = ControllerHub.shared
        hub.reset()
        var polls = 0
        hub.source = { polls += 1; return [gc] }

        _ = hub.controller(player: 1, frame: 7)
        _ = hub.controller(player: 2, frame: 7)
        _ = hub.controller(player: 1, frame: 7)
        #expect(polls == 1)

        _ = hub.controller(player: 1, frame: 8)
        #expect(polls == 2)
    }

    @Test func aButtonThisControllerLacksNeverReadsDown() {
        let (hub, _) = stagedOne()
        // A plain extended gamepad has no touchpad.
        #expect(!hub.controller(player: 1, frame: 1).isDown(.touchpad))
        #expect(!hub.controller(player: 1, frame: 1).hasTouchpad)
    }

    @Test func anyButtonIsDownSeesAnyOfThem() {
        let (hub, gc) = stagedOne()
        #expect(!hub.controller(player: 1, frame: 1).anyButtonIsDown)
        gc.extendedGamepad?.buttonY.setValue(1)
        #expect(hub.controller(player: 1, frame: 2).anyButtonIsDown)
    }

    // MARK: - More than one player

    @Test func twoControllersBecomeTwoPlayers() {
        let first = GCController.withExtendedGamepad()
        let second = GCController.withExtendedGamepad()
        let hub = staged([first, second])

        first.extendedGamepad?.buttonA.setValue(1)
        second.extendedGamepad?.buttonB.setValue(1)

        #expect(hub.controller(player: 1, frame: 1).isDown(.a))
        #expect(!hub.controller(player: 1, frame: 1).isDown(.b))
        #expect(hub.controller(player: 2, frame: 1).isDown(.b))
        #expect(hub.controllerCountForTest(frame: 1) == 2)
    }

    /// The reason slots are held rather than recomputed each frame: unplugging
    /// one controller must not renumber everybody else, or a two-player sketch
    /// swaps its players when one pad's battery dies.
    @Test func aPlayerLeavingDoesNotRenumberTheOthers() {
        let first = GCController.withExtendedGamepad()
        let second = GCController.withExtendedGamepad()
        let hub = ControllerHub.shared
        hub.reset()

        var attached = [first, second]
        hub.source = { attached }
        second.extendedGamepad?.buttonB.setValue(1)
        #expect(hub.controller(player: 2, frame: 1).isDown(.b))

        // Player one walks off with their controller.
        attached = [second]
        #expect(!hub.controller(player: 1, frame: 2).isConnected)
        #expect(hub.controller(player: 2, frame: 2).isDown(.b),
                "player two must still be player two")
    }

    /// And the freed number is what the next arrival takes.
    @Test func aNewControllerTakesTheLowestFreeNumber() {
        let first = GCController.withExtendedGamepad()
        let second = GCController.withExtendedGamepad()
        let hub = ControllerHub.shared
        hub.reset()

        var attached = [first, second]
        hub.source = { attached }
        _ = hub.controller(player: 1, frame: 1)

        attached = [second]
        _ = hub.controller(player: 1, frame: 2)

        let third = GCController.withExtendedGamepad()
        third.extendedGamepad?.buttonX.setValue(1)
        attached = [second, third]
        #expect(hub.controller(player: 1, frame: 3).isDown(.x),
                "the newcomer takes the empty slot 1, not a third one")
    }

    // MARK: - Arriving and leaving

    @Test func aControllerArrivingIsAnnouncedOnce() {
        let gc = GCController.withExtendedGamepad()
        let hub = ControllerHub.shared
        hub.reset()

        var attached: [GCController] = []
        hub.source = { attached }
        #expect(!hub.controller(player: 1, frame: 1).didConnect)

        attached = [gc]
        #expect(hub.controller(player: 1, frame: 2).didConnect)
        #expect(!hub.controller(player: 1, frame: 3).didConnect,
                "arriving is an event, not a state")
        #expect(hub.controller(player: 1, frame: 3).isConnected)
    }

    @Test func aControllerLeavingIsAnnouncedOnce() {
        let gc = GCController.withExtendedGamepad()
        let hub = ControllerHub.shared
        hub.reset()

        var attached = [gc]
        hub.source = { attached }
        _ = hub.controller(player: 1, frame: 1)

        attached = []
        #expect(hub.controller(player: 1, frame: 2).didDisconnect)
        #expect(!hub.controller(player: 1, frame: 3).didDisconnect)
    }

    // MARK: - Motion

    /// The sensors cost battery, so they stay off and read zero until a sketch
    /// asks. Without this, every sketch that never mentions motion would still
    /// pay for it.
    @Test func motionIsOffUntilItIsAskedFor() {
        let (hub, gc) = stagedOne()
        gc.motion?.setRotationRate(GCRotationRate(x: 1, y: 2, z: 3))

        let quiet = hub.controller(player: 1, frame: 1)
        #expect(!quiet.hasMotion)
        #expect(quiet.rotationRate == .zero)

        hub.motionEnabled = true
        let live = hub.controller(player: 1, frame: 2)
        #expect(live.hasMotion)
        #expect(abs(live.rotationRate.x - 1) < 0.001)
        #expect(abs(live.rotationRate.z - 3) < 0.001)
    }

    @Test func gravitySaysWhichWayTheControllerIsHeld() {
        let (hub, gc) = stagedOne()
        hub.motionEnabled = true
        gc.motion?.setGravity(GCAcceleration(x: 0, y: -1, z: 0))

        let pad = hub.controller(player: 1, frame: 1)
        #expect(abs(pad.gravity.y + 1) < 0.001)
    }

    // MARK: - Export

    /// A controller is live input, so an export reads it as untouched rather
    /// than baking in whatever a hand happened to be doing.
    @Test func anExportReadsNeutralAndSaysWhy() {
        let (hub, gc) = stagedOne()
        gc.extendedGamepad?.buttonA.setValue(1)
        gc.extendedGamepad?.leftThumbstick.setValueForXAxis(1, yAxis: 1)
        #expect(hub.controller(player: 1, frame: 1).isDown(.a), "held before the export")

        OllinApp.isRenderingHeadless = true
        defer { OllinApp.isRenderingHeadless = false }

        let exported = hub.controller(player: 1, frame: 2)
        #expect(!exported.isDown(.a))
        #expect(exported.leftStick == .zero)
        #expect(!exported.isConnected)
        #expect(exported.unavailableReason != nil, "and it must say why, not read as an empty slot")
    }

    // MARK: - Real hardware

    /// The one test that needs a controller in someone's hands.
    ///
    /// It is a condition on the test rather than an early return inside it, so
    /// a machine with nothing plugged in reports this as **skipped** and says
    /// so out loud. An `if attached.isEmpty { return }` would report a pass,
    /// which is the shape that lets an untested path look tested.
    @Test(.enabled(if: !GCController.controllers().isEmpty,
                   "no game controller is attached, so the hardware read path is unverified here"))
    func anAttachedControllerIsReadThroughTheSamePath() throws {
        let gc = try #require(GCController.controllers().first)
        let hub = ControllerHub.shared
        hub.reset()

        let pad = hub.controller(player: 1, frame: 1)
        #expect(pad.isConnected)
        #expect(pad.name == gc.vendorName)
        #expect(pad.leftStick.length <= 1.001, "a stick cannot read past its own range")
        #expect(pad.leftTrigger >= 0 && pad.leftTrigger <= 1)
    }

    // MARK: - Staging

    /// Point the hub at controllers the test owns.
    private func staged(_ controllers: [GCController]) -> ControllerHub {
        let hub = ControllerHub.shared
        hub.reset()
        hub.source = { controllers }
        return hub
    }

    private func stagedOne() -> (ControllerHub, GCController) {
        let gc = GCController.withExtendedGamepad()
        return (staged([gc]), gc)
    }
}

extension ControllerHub {
    /// The count, without a `Sketch` to ask through.
    func controllerCountForTest(frame: Int) -> Int { connectedCount(frame: frame) }
}
