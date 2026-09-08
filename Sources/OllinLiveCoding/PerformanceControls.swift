import Foundation
import Ollin
import Observation
import OllinMIDI
import OllinOSC

/// The host's own performance surface, reachable from a pad, a fader, or
/// another machine.
///
/// Evaluate, evaluate fresh, hide the code, ride the code's backdrop and
/// size, and record: the things a performer reaches for mid-set, each
/// answerable from MIDI or OSC as well as from the keyboard. A host
/// preference, never part of the sketch. A sketch's own `@Param` bindings
/// keep reaching MIDI and OSC through the satellites as before, and the two
/// never meet: the host reads its own inputs, the sketch reads its own.
///
/// OSC answers at fixed addresses under `/ollin/` whenever the port is open.
/// MIDI has no natural default for a pad, so a MIDI control is learned: pick
/// an action, press Learn, move the control, and the next message to arrive
/// is the binding. An OSC address can be learned the same way for a layout
/// that already has its own names. The map persists in the host's defaults.
///
/// Both receivers keep an inbox the host drains on the main thread, on a
/// timer, so nothing here runs on a callback thread.
@MainActor
@Observable
final class PerformanceControls {

    // MARK: - What the host can do

    /// One thing the host does from a control.
    enum Action: String, CaseIterable, Codable, Sendable, Identifiable {
        case evaluate, evaluateFresh, hideCode, backdrop, codeSize, record, cueNext, cuePrevious

        var id: String { rawValue }

        var title: String {
            switch self {
            case .evaluate:      return "Evaluate"
            case .evaluateFresh: return "Evaluate fresh"
            case .hideCode:      return "Hide code"
            case .backdrop:      return "Code backdrop"
            case .codeSize:      return "Code size"
            case .record:        return "Record"
            case .cueNext:       return "Next cue"
            case .cuePrevious:   return "Previous cue"
            }
        }

        /// Whether the action rides a value (a fader) rather than a press.
        var isContinuous: Bool { self == .backdrop || self == .codeSize }

        /// Whether a press turns the action over rather than firing it once.
        var isToggle: Bool { self == .hideCode || self == .record }

        /// The OSC address the host answers at with nothing learned.
        var address: String {
            switch self {
            case .evaluate:      return "/ollin/evaluate"
            case .evaluateFresh: return "/ollin/evaluate/fresh"
            case .hideCode:      return "/ollin/code/hidden"
            case .backdrop:      return "/ollin/code/backdrop"
            case .codeSize:      return "/ollin/code/size"
            case .record:        return "/ollin/record"
            case .cueNext:       return "/ollin/cue/next"
            case .cuePrevious:   return "/ollin/cue/previous"
            }
        }

        /// The address a cue is called at by name or number, with nothing to
        /// learn: `/ollin/cue "finale"` or `/ollin/cue 3`, an optional second
        /// argument the fade in seconds. A MIDI program change calls a cue by
        /// number the same way, on any channel.
        static let cueAddress = "/ollin/cue"

        /// The action a fixed address names, if it is one.
        static func named(by address: String) -> Action? {
            allCases.first { $0.address == address }
        }
    }

    /// A control that reaches an action.
    enum Trigger: Codable, Hashable, Sendable {
        /// A pad or key, on one channel (1...16).
        case note(Int, channel: Int)
        /// A knob, fader, or button sending a controller number, on one channel.
        case control(Int, channel: Int)
        /// A message at an address.
        case osc(String)

        var label: String {
            switch self {
            case .note(let note, let channel):       return "note \(note) ch \(channel)"
            case .control(let number, let channel):  return "CC \(number) ch \(channel)"
            case .osc(let address):                  return address
            }
        }
    }

    /// What the actions do. The session hands these over; a headless check
    /// hands over counters.
    struct Handlers {
        var evaluate: (_ fresh: Bool) -> Void
        /// `nil` turns the code over; a value sets it.
        var setCodeHidden: (Bool?) -> Void
        /// The backdrop's strength, `0...1`.
        var setBackdrop: (Double) -> Void
        /// The code's type size in points, `9...32`.
        var setCodeSize: (Double) -> Void
        /// `nil` turns recording over; a value sets it.
        var setRecording: (Bool?) -> Void
        /// Call a cue, over the fade the Cues card holds (or the one given).
        var cue: (CueRequest) -> Void
        /// A cue called with its own fade, from `/ollin/cue name seconds`.
        var cueOver: ((CueRequest, Double) -> Void)? = nil
    }

    static let smallestCodeSize = 9.0
    static let largestCodeSize = 32.0

    // MARK: - State

    /// The learned controls, one per action at most.
    private(set) var map: [Action: Trigger] = [:]
    /// The action waiting for its control, while Learn is lit.
    private(set) var learning: Action?
    /// The last action a control reached, for the card to flash.
    private(set) var lastFired: Action?
    /// The UDP port OSC listens on; zero is off.
    var oscPort: Int {
        didSet {
            guard oscPort != oldValue else { return }
            defaults.set(oscPort, forKey: PerformanceControls.oscPortKey)
            if isRunning { openOSC() }
        }
    }
    /// What the OSC side is doing, for the card: off, listening, or why not.
    private(set) var oscStatus = "off"
    /// Whether MIDI opened; false when Core MIDI refused.
    private(set) var isListeningToMIDI = false
    private(set) var isRunning = false

    static let mapKey = "ollin.livecoding.controls"
    static let oscPortKey = "ollin.livecoding.oscPort"

    @ObservationIgnored private let handlers: Handlers
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let midi = MIDIInput(name: "OllinLiveCoding")
    @ObservationIgnored private var osc: OSCReceiver?
    @ObservationIgnored private var timer: Timer?
    /// The last value seen per controller, so a button on a controller
    /// (127 pressed, 0 released) fires once on the way up.
    @ObservationIgnored private var lastControlValues: [Trigger: Int] = [:]

    init(handlers: Handlers, defaults: UserDefaults = .standard) {
        self.handlers = handlers
        self.defaults = defaults
        self.oscPort = defaults.integer(forKey: PerformanceControls.oscPortKey)
        if let data = defaults.data(forKey: PerformanceControls.mapKey),
           let stored = try? JSONDecoder().decode([String: Trigger].self, from: data) {
            var loaded: [Action: Trigger] = [:]
            for (name, trigger) in stored {
                if let action = Action(rawValue: name) { loaded[action] = trigger }
            }
            map = loaded
        }
    }

    // MARK: - Lifecycle

    /// Opens MIDI, opens OSC if a port is set, and starts draining both.
    func start() {
        guard !isRunning else { return }
        isRunning = true
        do {
            try midi.start()
            isListeningToMIDI = true
        } catch {
            isListeningToMIDI = false
        }
        openOSC()
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        timer?.invalidate()
        timer = nil
        midi.stop()
        isListeningToMIDI = false
        osc?.stop()
        osc = nil
        oscStatus = "off"
    }

    private func openOSC() {
        osc?.stop()
        osc = nil
        guard oscPort > 0 else {
            oscStatus = "off"
            return
        }
        let receiver = OSCReceiver(port: oscPort)
        do {
            try receiver.start()
            osc = receiver
            oscStatus = "listening on \(oscPort)"
        } catch {
            oscStatus = "port \(oscPort) could not be opened"
        }
    }

    /// How many MIDI sources the Mac sees right now.
    var midiSourceCount: Int { isListeningToMIDI ? midi.sources.count : 0 }

    // MARK: - Learning and the map

    /// Lights Learn for an action: the next control to arrive is its binding.
    /// Asking for the action already lit puts the light out.
    func learn(_ action: Action) {
        learning = learning == action ? nil : action
    }

    func cancelLearning() {
        learning = nil
    }

    /// Takes the control off an action.
    func clear(_ action: Action) {
        map[action] = nil
        persistMap()
    }

    private func persistMap() {
        var stored: [String: Trigger] = [:]
        for (action, trigger) in map { stored[action.rawValue] = trigger }
        if let data = try? JSONEncoder().encode(stored) {
            defaults.set(data, forKey: PerformanceControls.mapKey)
        }
    }

    /// Binds `trigger` to whatever is learning, if it can drive it: a press
    /// cannot ride a fader's action. Returns whether it was taken.
    private func takeForLearning(_ trigger: Trigger) -> Bool {
        guard let action = learning else { return false }
        if action.isContinuous, case .note = trigger { return false }
        // One control, one action: a control learned elsewhere moves.
        for (other, bound) in map where bound == trigger { map[other] = nil }
        map[action] = trigger
        learning = nil
        persistMap()
        return true
    }

    // MARK: - Draining

    /// Reads everything that arrived since the last call and acts on it.
    func poll() {
        for message in midi.messages() { handle(message) }
        if let osc {
            for message in osc.messages() { handle(message) }
        }
    }

    /// One MIDI message: learned first, then matched against the map.
    func handle(_ message: MIDIMessage) {
        switch message.kind {
        case .noteOn(let note, _):
            let trigger = Trigger.note(note, channel: message.channel)
            if takeForLearning(trigger) { return }
            for (action, bound) in map where bound == trigger {
                press(action)
            }
        case .controlChange(let number, let value):
            let trigger = Trigger.control(number, channel: message.channel)
            if takeForLearning(trigger) { return }
            let previous = lastControlValues[trigger]
            lastControlValues[trigger] = value
            for (action, bound) in map where bound == trigger {
                if action.isContinuous {
                    set(action, to: Double(value) / 127)
                } else if value >= 64, (previous ?? 0) < 64 {
                    press(action)
                }
            }
        case .programChange(let program):
            // A program change is a cue number; nothing else in the host reads one.
            handlers.cue(.number(program))
        default:
            break
        }
    }

    /// One OSC message: learned first, then the map, then the fixed addresses.
    func handle(_ message: OSCMessage) {
        let trigger = Trigger.osc(message.address)
        if takeForLearning(trigger) { return }
        if message.address == Action.cueAddress {
            // A name or a number, then an optional fade.
            let request: CueRequest?
            if let text = message.text {
                request = .named(text)
            } else if let number = message.int {
                request = .number(number)
            } else {
                request = nil
            }
            guard let request else { return }
            if message.arguments.count > 1, let fade = message.arguments[1].number, let cueOver = handlers.cueOver {
                cueOver(request, fade)
            } else {
                handlers.cue(request)
            }
            return
        }
        var actions: [Action] = []
        for (action, bound) in map where bound == trigger { actions.append(action) }
        if let fixed = Action.named(by: message.address), !actions.contains(fixed) {
            actions.append(fixed)
        }
        for action in actions {
            if action.isContinuous {
                if let value = message.number { set(action, to: value) }
            } else if action.isToggle, let wanted = message.bool ?? message.number.map({ $0 > 0.5 }) {
                // A layout's toggle says which way; a bare message turns it over.
                set(action, on: wanted)
            } else if message.arguments.isEmpty || (message.number ?? 1) > 0.5 {
                // A button sends its release too; only the press counts.
                press(action)
            }
        }
    }

    // MARK: - Acting

    private func press(_ action: Action) {
        lastFired = action
        switch action {
        case .evaluate:      handlers.evaluate(false)
        case .evaluateFresh: handlers.evaluate(true)
        case .hideCode:      handlers.setCodeHidden(nil)
        case .cueNext:       handlers.cue(.next)
        case .cuePrevious:   handlers.cue(.previous)
        case .record:        handlers.setRecording(nil)
        case .backdrop, .codeSize: break
        }
    }

    private func set(_ action: Action, on wanted: Bool) {
        lastFired = action
        switch action {
        case .hideCode: handlers.setCodeHidden(wanted)
        case .record:   handlers.setRecording(wanted)
        default:        break
        }
    }

    /// A value in `0...1` onto the action's own range.
    private func set(_ action: Action, to unit: Double) {
        lastFired = action
        let amount = min(max(0, unit), 1)
        switch action {
        case .backdrop:
            handlers.setBackdrop(amount)
        case .codeSize:
            let span = PerformanceControls.largestCodeSize - PerformanceControls.smallestCodeSize
            handlers.setCodeSize(PerformanceControls.smallestCodeSize + amount * span)
        default:
            break
        }
    }
}
