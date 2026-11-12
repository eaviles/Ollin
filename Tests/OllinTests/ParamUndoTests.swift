import Foundation
import Testing
@testable import Ollin

/// The inspector's undo, driven the way the parameters list drives it: a row
/// writes the parameter, tells the journal, and tells the host. The clock and
/// the mouse button are the test's own, so a gesture, a pause with the button
/// held, and the quiet time that closes a step are all stated rather than
/// waited for.
@Suite
@MainActor
struct ParamUndoTests {
    final class Subject: Sketch {
        @Param(0 ... 200) var radius = 50.0
        @Param var visible = true
    }

    final class Smaller: Sketch {
        @Param var visible = true
    }

    /// A host that keeps a turned set, as a live session does, or none.
    @MainActor
    final class Desk {
        /// The sketch the desk opens on, which the hand turns.
        let subject = Subject()
        /// The sketch on stage: the subject, until a test swaps another in.
        var sketch: Sketch
        var handles: [ParamHandle]
        var tuned: Set<String> = []
        var heard: [(name: String, stored: ParamStored)] = []
        var manager = UndoManager()
        let journal = ParamUndoJournal()
        var clock = 0.0
        var pressed = false
        var name = "Subject"
        let tracksTuned: Bool

        init(tracksTuned: Bool = true) {
            self.tracksTuned = tracksTuned
            sketch = subject
            handles = subject.parameters()
            manager.groupsByEvent = false
            journal.now = { [unowned self] in clock }
            journal.isPressed = { [unowned self] in pressed }
            brief()
        }

        /// Hand the journal the present state, as the list does on every pass.
        func brief() {
            let reset = ParamResetAction(tuned: tuned) { [unowned self] names in
                sketch.resetParameters(named: names)
                tuned.subtract(names ?? handles.map(\.name))
            }
            journal.adopt(parameters: handles, sketch: name,
                          onChange: { [unowned self] name, stored in
                              tuned.insert(name)
                              heard.append((name, stored))
                          },
                          reset: tracksTuned ? reset : nil, undoManager: manager)
        }

        /// Turn the radius by hand: the row writes, the journal and the host hear.
        func turn(_ value: Double) {
            subject.radius = value
            report("radius", .number(subject.radius))
        }

        func flip() {
            subject.visible.toggle()
            report("visible", .boolean(subject.visible))
        }

        private func report(_ name: String, _ stored: ParamStored) {
            journal.edited(name, to: stored, wasTuned: tracksTuned ? tuned.contains(name) : true)
            tuned.insert(name)
            heard.append((name, stored))
            brief()
        }

        /// Let `seconds` pass and give the journal its tick.
        func elapse(_ seconds: Double = 1) {
            clock += seconds
            journal.tick()
        }

        func undo() { manager.undo(); brief() }
        func redo() { manager.redo(); brief() }
    }

    @Test func anEditGoesBackAndComesForward() {
        let desk = Desk()
        desk.turn(80)
        desk.elapse()
        #expect(desk.manager.undoActionName == "Change Radius")
        desk.undo()
        #expect(desk.subject.radius == 50)
        desk.redo()
        #expect(desk.subject.radius == 80)
        #expect(desk.manager.canRedo == false)
    }

    @Test func aDragIsOneStep() {
        let desk = Desk()
        for value in stride(from: 52.0, through: 120, by: 4) {
            desk.turn(value)
            desk.elapse(0.02)
        }
        desk.elapse()
        desk.undo()
        #expect(desk.subject.radius == 50, "one undo takes the whole drag back")
        #expect(desk.manager.canUndo == false, "the drag left more than one step")
    }

    @Test func aHeldButtonKeepsTheStepOpenThroughAPause() {
        let desk = Desk()
        desk.pressed = true
        desk.turn(60)
        desk.elapse(2)            // the hand rests, the button still down
        #expect(desk.journal.hasOpenStep)
        desk.turn(90)
        desk.pressed = false
        desk.elapse()
        #expect(!desk.journal.hasOpenStep)
        desk.undo()
        #expect(desk.subject.radius == 50)
        #expect(desk.manager.canUndo == false)
    }

    @Test func aNumberTypedSlowlyIsOneStep() {
        let desk = Desk()
        desk.journal.hold("radius", true)       // the first key
        desk.turn(1)
        desk.elapse(2)
        desk.turn(12)
        desk.elapse(2)
        desk.turn(120)
        #expect(desk.journal.hasOpenStep)
        desk.journal.hold("radius", false)      // Return
        desk.elapse()
        desk.undo()
        #expect(desk.subject.radius == 50)
        #expect(desk.manager.canUndo == false, "each digit of one number was a step of its own")
    }

    @Test func theCommitsOwnValueLandsInTheStep() {
        let desk = Desk()
        desk.journal.hold("radius", true)
        desk.turn(25)
        desk.elapse(2)
        desk.journal.hold("radius", false)      // Return, on "250": the commit clamps
        desk.turn(200)
        desk.elapse()
        desk.undo()
        #expect(desk.subject.radius == 50)
    }

    @Test func aCommitClosesTheStepSoTheNextNumberIsItsOwn() {
        let desk = Desk()
        for value in [120.0, 80] {
            desk.journal.hold("radius", true)
            desk.turn(value)
            desk.journal.hold("radius", false)
            desk.elapse()
        }
        desk.undo()
        #expect(desk.subject.radius == 120)
        desk.undo()
        #expect(desk.subject.radius == 50)
    }

    @Test func aFieldLeftWithTheKeysDoesNotHoldAnotherRowsStep() {
        let desk = Desk()
        desk.journal.hold("radius", true)
        desk.turn(120)                          // never committed: the field keeps the keys
        desk.flip()
        desk.elapse()
        #expect(!desk.journal.hasOpenStep, "another row's step stayed open behind a field it does not own")
    }

    @Test func aStepStaysOpenUntilTheQuietTimeHasRun() {
        let desk = Desk()
        desk.turn(60)
        desk.elapse(ParamUndoJournal.quiet * 0.5)
        #expect(desk.journal.hasOpenStep)
        desk.elapse(ParamUndoJournal.quiet * 0.6)
        #expect(!desk.journal.hasOpenStep)
    }

    @Test func twoGesturesAreTwoSteps() {
        let desk = Desk()
        desk.turn(60)
        desk.elapse()
        desk.turn(90)
        desk.elapse()
        desk.undo()
        #expect(desk.subject.radius == 60)
        desk.undo()
        #expect(desk.subject.radius == 50)
    }

    @Test func anotherParameterClosesTheStep() {
        let desk = Desk()
        desk.turn(60)
        desk.flip()             // no time between them
        desk.turn(90)
        desk.elapse()
        desk.undo()
        #expect(desk.subject.radius == 60 && desk.subject.visible == false)
        desk.undo()
        #expect(desk.subject.radius == 60 && desk.subject.visible == true)
        desk.undo()
        #expect(desk.subject.radius == 50)
        #expect(desk.manager.canUndo == false)
    }

    @Test func aGestureThatEndsWhereItBeganLeavesNoStep() {
        let desk = Desk()
        desk.turn(60)
        desk.elapse(0.05)
        desk.turn(50)
        desk.elapse()
        #expect(desk.manager.canUndo == false, "a drag away and back left a step that undoes nothing")
    }

    @Test func undoBeforeTheQuietTimeTakesTheWholeGesture() {
        let desk = Desk()
        desk.turn(60)
        desk.turn(70)
        desk.undo()             // pressed at once, the step still open
        #expect(desk.subject.radius == 50)
        #expect(!desk.journal.hasOpenStep)
        desk.redo()
        #expect(desk.subject.radius == 70)
    }

    @Test func undoingAFirstEditTakesTheMarkWithIt() {
        let desk = Desk()
        desk.turn(80)
        desk.elapse()
        #expect(desk.tuned == ["radius"])
        let heard = desk.heard.count
        desk.undo()
        #expect(desk.subject.radius == 50)
        #expect(desk.tuned.isEmpty, "the row was not turned before the edit, and reads as turned after its undo")
        #expect(desk.heard.count == heard, "the host was told of a value nobody turned")
        desk.redo()
        #expect(desk.subject.radius == 80)
        #expect(desk.tuned == ["radius"])
        #expect(desk.heard.last?.stored == .number(80))
    }

    @Test func undoingALaterEditKeepsTheMark() {
        let desk = Desk()
        desk.turn(60)
        desk.elapse()
        desk.turn(90)
        desk.elapse()
        desk.undo()
        #expect(desk.subject.radius == 60)
        #expect(desk.tuned == ["radius"])
        #expect(desk.heard.last?.stored == .number(60), "the host keeps the value the undo put back")
    }

    @Test func aValueMovedFromOutsideIsWhatUndoPutsBack() {
        let desk = Desk()
        desk.subject.radius = 130       // a fader, a cue, a track: not the inspector
        desk.journal.observe()
        desk.turn(150)
        desk.elapse()
        desk.undo()
        #expect(desk.subject.radius == 130, "undo went to the declared value, not the one the hand turned from")
        #expect(desk.tuned.isEmpty)
    }

    @Test func aResetIsOneStepThatBringsTheMarksBack() {
        let desk = Desk()
        desk.turn(80)
        desk.elapse()
        desk.flip()
        desk.elapse()
        desk.journal.resetting(nil) {
            desk.sketch.resetParameters(named: nil)
            desk.tuned.removeAll()
        }
        desk.brief()
        #expect(desk.subject.radius == 50 && desk.subject.visible == true)
        #expect(desk.manager.undoActionName == "Reset Parameters")
        desk.undo()
        #expect(desk.subject.radius == 80 && desk.subject.visible == false)
        #expect(desk.tuned == ["radius", "visible"])
        desk.redo()
        #expect(desk.subject.radius == 50 && desk.subject.visible == true)
        #expect(desk.tuned.isEmpty)
    }

    @Test func aResetOfOneRowIsNamedForIt() {
        let desk = Desk()
        desk.turn(80)
        desk.elapse()
        desk.journal.resetting(["radius"]) {
            desk.sketch.resetParameters(named: ["radius"])
            desk.tuned.remove("radius")
        }
        desk.brief()
        #expect(desk.manager.undoActionName == "Reset Radius")
        desk.undo()
        #expect(desk.subject.radius == 80)
    }

    @Test func aResetThatMovesNothingLeavesNoStep() {
        let desk = Desk()
        desk.journal.resetting(nil) { desk.sketch.resetParameters(named: nil) }
        #expect(desk.manager.canUndo == false)
    }

    @Test func aStepSurvivesAReload() {
        let desk = Desk()
        desk.turn(60)
        desk.elapse()
        desk.turn(80)
        desk.elapse()
        // A reload: a fresh sketch, the turned value put back on it by the host.
        let gone = desk.subject
        let fresh = Subject()
        fresh.radius = 80
        desk.sketch = fresh
        desk.handles = fresh.parameters()
        desk.brief()
        desk.undo()
        // 60, which only the step knows: not the 50 a reset would give.
        #expect(fresh.radius == 60, "the step reached for the sketch that is gone")
        #expect(gone.radius == 80, "the sketch that is gone was written to")
        desk.undo()
        #expect(fresh.radius == 50)
        #expect(desk.tuned.isEmpty)
    }

    @Test func anotherSketchStartsWithNoSteps() {
        let desk = Desk()
        desk.turn(80)
        desk.elapse()
        // The host shows another sketch in the same list, with a radius of its own.
        let other = Subject()
        other.radius = 150
        desk.sketch = other
        desk.handles = other.parameters()
        desk.name = "Another"
        desk.brief()
        #expect(desk.manager.canUndo == false, "the last sketch's step would write this sketch's radius")
        #expect(other.radius == 150)
    }

    @Test func aJournalLetGoTakesItsStepsWithIt() {
        let manager = UndoManager()
        manager.groupsByEvent = false
        let sketch = Subject()
        do {
            let journal = ParamUndoJournal()
            journal.adopt(parameters: sketch.parameters(), onChange: { _, _ in }, reset: nil, undoManager: manager)
            sketch.radius = 80
            journal.edited("radius", to: .number(80), wasTuned: true)
            journal.seal()
            #expect(manager.canUndo)
        }
        #expect(manager.canUndo == false, "a list that is gone left its steps on the window's undo manager")
    }

    @Test func aParameterTheSketchDroppedIsSkipped() {
        let desk = Desk()
        desk.turn(80)
        desk.elapse()
        let smaller = Smaller()
        desk.sketch = smaller
        desk.handles = smaller.parameters()
        desk.brief()
        desk.manager.undo()
        #expect(smaller.visible == true)
        #expect(desk.manager.canRedo == false, "a step that put nothing back left a redo")
    }

    @Test func aHostThatKeepsNoMarksHearsEveryUndo() {
        let desk = Desk(tracksTuned: false)
        desk.turn(80)
        desk.elapse()
        desk.undo()
        #expect(desk.subject.radius == 50)
        #expect(desk.heard.last?.stored == .number(50))
    }

    @Test func anotherUndoManagerStartsClean() {
        let desk = Desk()
        desk.turn(80)
        desk.elapse()
        let old = desk.manager
        desk.manager = UndoManager()
        desk.manager.groupsByEvent = false
        desk.brief()
        #expect(old.canUndo == false, "the manager the list left still holds its steps")
        desk.turn(90)
        desk.elapse()
        desk.undo()
        #expect(desk.subject.radius == 80)
    }

    @Test func theOldestStepsAreForgottenPastTheDepth() {
        let desk = Desk()
        let extra = 4
        for step in 1 ... ParamUndoJournal.depth + extra {
            desk.turn(step.isMultiple(of: 2) ? 60 : 61 + Double(step % 7))
            desk.elapse()
        }
        var undone = 0
        while desk.manager.canUndo, undone < ParamUndoJournal.depth + extra + 1 {
            desk.manager.undo()
            undone += 1
        }
        #expect(undone == ParamUndoJournal.depth)
    }

    @Test func aJournalWithNoManagerWritesNothingDown() {
        let sketch = Subject()
        let journal = ParamUndoJournal()
        journal.adopt(parameters: sketch.parameters(), onChange: { _, _ in }, reset: nil, undoManager: nil)
        sketch.radius = 80
        journal.edited("radius", to: .number(80), wasTuned: true)
        #expect(!journal.hasOpenStep)
    }
}
