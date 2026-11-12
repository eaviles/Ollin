import Foundation
#if os(macOS)
import AppKit
#endif

/// The inspector's undo for parameters turned by hand: what the parameters
/// list writes down as its rows are edited, so the window's own Undo and Redo
/// put a value back and bring it forward again.
///
/// One gesture is one step. A row reports every value a drag passes through,
/// and stepping back through each of them would make undo useless, so edits
/// to one parameter join the step already open for it until the hand lets go:
/// the step closes once no edit has arrived for `quiet` seconds and no mouse
/// button is held. A press of a key that repeats is one step the same way, and
/// so is a number typed into a field, however slowly: the field writes the
/// parameter as each digit lands so the canvas follows, and it holds its
/// parameter's step open from the first key to the commit. A step that ends
/// where it began (a slider dragged away and back) is dropped, so no press of
/// Undo does nothing.
///
/// A step names its parameters, never the objects behind them, so it survives
/// a reload: the step is applied to whatever parameter has that name now, and
/// a name the sketch no longer declares is skipped. Another sketch in the
/// same list is not a reload, and starts with no steps: its `radius` is not
/// the one the last sketch's step was about. Each entry also remembers
/// whether the host counted the parameter as turned, so undoing the first
/// edit of a parameter takes its turned mark away with the value, and a reset
/// undone brings the marks back.
///
/// The steps live on the undo manager the list was handed (the window's), in
/// order with everything else that window can undo.
@MainActor
package final class ParamUndoJournal {
    /// One parameter in a step: the value to put back, and whether the host
    /// counted the parameter as turned while it held that value.
    package struct Entry: Equatable, Sendable {
        package let name: String
        package let value: ParamStored
        package let wasTuned: Bool

        package init(name: String, value: ParamStored, wasTuned: Bool) {
            self.name = name; self.value = value; self.wasTuned = wasTuned
        }
    }

    /// One step on the undo manager's stack. An object of its own, so the
    /// manager can be told to forget exactly this one.
    private final class Step {
        let entries: [Entry]
        let actionName: String
        init(entries: [Entry], actionName: String) {
            self.entries = entries; self.actionName = actionName
        }
    }

    /// How long a parameter must sit still, with no button held, before the
    /// step open for it closes.
    package static let quiet: TimeInterval = 0.3
    /// The most steps kept; past it the oldest is forgotten.
    package static let depth = 256

    /// The clock and the mouse, replaceable so a test can hold a button down
    /// and let time pass without either.
    package var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
    package var isPressed: () -> Bool = {
        #if os(macOS)
        NSEvent.pressedMouseButtons != 0
        #else
        false
        #endif
    }

    private var handles: [String: ParamHandle] = [:]
    private var identities: [ObjectIdentifier] = []
    private var sketch: String?
    private var onChange: (String, ParamStored) -> Void = { _, _ in }
    private var reset: ParamResetAction?
    private weak var manager: UndoManager?

    /// What each parameter held when it was last looked at, which is what an
    /// edit's step puts back: a row writes the parameter before it reports
    /// the edit, so by then the value before it is gone from the parameter.
    private var known: [String: ParamStored] = [:]
    /// Every step the manager may still hold, kept alive here because the
    /// manager does not keep its targets.
    private var steps: [Step] = []
    private var open: (step: Step, name: String, lastEdit: TimeInterval)?
    /// The parameter whose field is being typed in, if one is.
    private var heldName: String?
    private var timer: Timer?

    package init() {}

    isolated deinit {
        timer?.invalidate()
        if let manager {
            for step in steps { manager.removeAllActions(withTarget: step) }
        }
    }

    /// Whether a step is still taking edits (a gesture in progress).
    package var hasOpenStep: Bool { open != nil }

    // MARK: What the list hands over

    /// Take the list's present state: the parameters on screen, the name of
    /// the sketch they belong to, where an edit is reported, the host's
    /// reset, and the undo manager. Called on every pass of the list, so a
    /// reload's fresh parameters and the host's current turned set are the
    /// ones a later undo reads. Fresh parameters under the same name are a
    /// reload and keep the steps; another name, or another undo manager,
    /// starts clean.
    package func adopt(parameters: [ParamHandle], sketch: String? = nil,
                       onChange: @escaping (String, ParamStored) -> Void,
                       reset: ParamResetAction?, undoManager: UndoManager?) {
        self.onChange = onChange
        self.reset = reset
        if undoManager !== manager || sketch != self.sketch {
            forgetEverything()
            manager = undoManager
            self.sketch = sketch
        }
        let ids = parameters.map { ObjectIdentifier($0.param) }
        guard ids != identities else { return }
        // Fresh parameters: a reload, or another sketch in the same list.
        // The steps stay (they go by name); what each parameter holds is
        // read again, and a gesture cannot span the swap.
        heldName = nil
        seal()
        identities = ids
        handles = Dictionary(parameters.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        known = handles.mapValues { $0.param.stored }
    }

    /// Look at every parameter again. The list calls this on its own poll, so
    /// a value moved from outside the inspector (a fader, a cue, a track) is
    /// the value the next hand edit's step puts back.
    package func observe() {
        for (name, handle) in handles { known[name] = handle.param.stored }
        tick()
    }

    // MARK: What the rows report

    /// A row changed `name` by hand and it now holds `stored`. `wasTuned` is
    /// whether the host counted it as turned before this edit.
    package func edited(_ name: String, to stored: ParamStored, wasTuned: Bool) {
        defer { known[name] = stored }
        if let current = open, current.name == name {
            open?.lastEdit = now()
            return
        }
        seal()
        guard manager != nil, let before = known[name], before != stored else { return }
        let label = handles[name]?.label ?? ParamHandle.humanize(name)
        let step = Step(entries: [Entry(name: name, value: before, wasTuned: wasTuned)],
                        actionName: "Change \(label)")
        register(step)
        open = (step, name, now())
        startTimer()
    }

    /// A field of `name`'s row began taking keys (`true`) or committed what
    /// was typed (`false`). While it types, the step open for that parameter
    /// stays open. The commit only lets go: the step closes at the next tick
    /// that finds it quiet, so the value the commit itself writes (a number
    /// clamped into its range) still lands in it. The hold is one row's:
    /// another row's step closes as ever.
    package func hold(_ name: String, _ isTyping: Bool) {
        if isTyping {
            heldName = name
        } else if heldName == name {
            heldName = nil
        }
    }

    /// Run the host's reset of `names` (every parameter for `nil`) as one
    /// step, so undo brings back the values and the turned marks it took.
    package func resetting(_ names: [String]?, perform: () -> Void) {
        seal()
        let affected = handles.values.filter { names?.contains($0.name) ?? true }
        let tuned = reset?.tuned ?? []
        let before = affected.map { Entry(name: $0.name, value: $0.param.stored, wasTuned: tuned.contains($0.name)) }
        perform()
        // Only what the reset moved, or unmarked, is worth putting back.
        let entries = before.filter { entry in
            guard let handle = handles[entry.name] else { return false }
            return entry.wasTuned || handle.param.stored != entry.value
        }.sorted { $0.name < $1.name }
        for handle in affected { known[handle.name] = handle.param.stored }
        guard manager != nil, !entries.isEmpty else { return }
        let actionName: String
        if entries.count == 1, let handle = handles[entries[0].name] {
            actionName = "Reset \(handle.label)"
        } else {
            actionName = "Reset Parameters"
        }
        register(Step(entries: entries, actionName: actionName))
    }

    // MARK: Closing a step

    /// Close the open step once its parameter has sat still for `quiet`
    /// seconds with no button held and no field of its row being typed in.
    /// Called by the journal's own timer while a step is open, and by the
    /// list's poll.
    package func tick() {
        guard let current = open, current.name != heldName else { return }
        if now() - current.lastEdit >= Self.quiet, !isPressed() { seal() }
    }

    /// Close the open step now: the next edit, of any parameter, starts a new
    /// one. A step whose parameter is back where the step began is dropped.
    package func seal() {
        guard let current = close() else { return }
        let entry = current.entries[0]
        if let handle = handles[entry.name], handle.param.stored == entry.value {
            forget(current)
        }
    }

    /// Stop taking edits into the open step, and hand it back.
    @discardableResult
    private func close() -> Step? {
        guard let current = open else { return nil }
        open = nil
        timer?.invalidate()
        timer = nil
        return current.step
    }

    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // The common modes, so it also fires while a control tracks the mouse.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: The manager's side

    private func register(_ step: Step) {
        guard let manager else { return }
        steps.append(step)
        // A manager that groups by event (a window's) opens the group
        // itself; one that does not wants it opened by hand.
        let ownGroup = !manager.groupsByEvent
        if ownGroup { manager.beginUndoGrouping() }
        manager.registerUndo(withTarget: step) { [weak self] step in
            self?.apply(step)
        }
        manager.setActionName(step.actionName)
        if ownGroup { manager.endUndoGrouping() }
        while steps.count > Self.depth { forget(steps[0]) }
    }

    private func forget(_ step: Step) {
        manager?.removeAllActions(withTarget: step)
        steps.removeAll { $0 === step }
    }

    private func forgetEverything() {
        seal()
        if let manager {
            for step in steps { manager.removeAllActions(withTarget: step) }
        }
        steps.removeAll()
    }

    /// Undo or redo `step`: put each of its parameters back to the value and
    /// the mark the step holds, and register the reverse, which the manager
    /// files as the redo of an undo and the undo of a redo.
    private func apply(_ step: Step) {
        // The open step may be the one being applied (Undo pressed before
        // the gesture's quiet time ran out), so it is only closed here, never
        // dropped from under the manager that is running it.
        if let closed = close(), closed !== step {
            let entry = closed.entries[0]
            if let handle = handles[entry.name], handle.param.stored == entry.value { forget(closed) }
        }
        steps.removeAll { $0 === step }
        let tuned = reset?.tuned
        var reverse: [Entry] = []
        for entry in step.entries {
            guard let handle = handles[entry.name] else { continue }
            reverse.append(Entry(name: entry.name, value: handle.param.stored,
                                 wasTuned: tuned?.contains(entry.name) ?? true))
            if entry.wasTuned || reset == nil {
                handle.param.restore(entry.value)
                onChange(entry.name, handle.param.stored)
            } else {
                // It was not turned while it held this value. The host's own
                // reset is the one call that takes a turned mark away; the
                // value is then set past it, since a parameter moved from
                // outside the inspector can stand off its declared value
                // with no mark.
                reset?.perform([entry.name])
                handle.param.restore(entry.value)
            }
            known[entry.name] = handle.param.stored
        }
        guard !reverse.isEmpty else { return }
        register(Step(entries: reverse, actionName: step.actionName))
    }
}
