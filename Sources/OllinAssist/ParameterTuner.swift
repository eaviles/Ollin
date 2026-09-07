import Foundation
import Ollin

/// Moves a sketch's `@Param` parameters toward a look described in words.
///
/// ```swift
/// let tuning = try await ParameterTuner().tune(parameters(), toward: "warmer, and fewer rings")
/// print(tuning.summary)      // "Moved Tint from #8000FF to #FF4500 and Rings from 5 to 3."
/// tuning.revert()            // puts them back
/// ```
///
/// The words go to a model with every parameter described in plain terms (its
/// label, its range, what it holds now), and the model answers with new values
/// for the ones the words concern. Each value is then read against its
/// parameter's own kind and written through the same path the inspector's
/// controls use, so a smoothed parameter glides and a stepped one snaps. What
/// moved comes back by name, with the value before and after, and `revert()`
/// undoes the lot. Nothing else is touched: the model sees the parameters, never
/// the sketch's code, and writes values, never source.
///
/// The model that ships is the machine's own (`OnDeviceModel`, Apple's on-device
/// language model), so nothing leaves the Mac and no key is needed; any
/// `TuningModel` can stand in for it.
public struct ParameterTuner: Sendable {

    public let model: any TuningModel

    public init(model: any TuningModel = OnDeviceModel()) {
        self.model = model
    }

    /// Whether this machine's own model is here to answer. The inspector shows
    /// its field only when it is.
    public static var availability: TuningAvailability { OnDeviceModel.availability }

    /// Move the parameters `look` concerns, and say which. Throws a
    /// `TuningError` when the phrase is empty, no parameter is of a kind words
    /// can set, or the model cannot answer.
    @MainActor
    public func tune(_ parameters: [ParamHandle], toward look: String,
                     sketchName: String? = nil) async throws -> Tuning {
        let words = look.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { throw TuningError.emptyLook }
        let request = TuningRequest(parameters, look: words, sketchName: sketchName)
        guard !request.parameters.isEmpty else { throw TuningError.nothingToTune }
        let reply = try await model.propose(request)
        return Tuning.applying(reply, to: parameters, leftOut: request.leftOut)
    }
}

public extension TuningRequest {

    /// The request for these handles: one descriptor per parameter of a kind
    /// words can set, in inspector order, with the rest named in `leftOut`. A
    /// parameter whose show-rule currently hides it is left out silently, since
    /// the inspector is not showing it either.
    @MainActor
    init(_ handles: [ParamHandle], look: String, sketchName: String? = nil) {
        var parameters: [TunableParameter] = []
        var leftOut: [String] = []
        for handle in handles where handle.isShown {
            let kind: TunableParameter.Kind?
            switch handle.control {
            case .slider(let control):
                kind = .number(range: control.range, current: control.read())
            case .stepper(let control):
                kind = .integer(range: control.range, current: control.read())
            case .toggle(let control):
                kind = .bool(current: control.read())
            case .menu(let control):
                let index = control.read()
                let current = control.options.indices.contains(index) ? control.options[index] : ""
                kind = .choice(options: control.options, current: current)
            case .colorWell(let control):
                kind = .color(current: control.read())
            case .text(let control):
                kind = .text(current: control.read())
            case .vector, .vector3, .rectangle, .insets, .range, .swatches:
                kind = nil
            }
            if let kind {
                parameters.append(TunableParameter(name: handle.name, label: handle.label,
                                                   group: handle.group, kind: kind))
            } else {
                leftOut.append(handle.label)
            }
        }
        self.init(look: look, sketchName: sketchName, parameters: parameters, leftOut: leftOut)
    }
}

/// What one ask did: the parameters that moved, each with its value before and
/// after, and a sentence saying so.
public struct Tuning: Sendable {

    /// One parameter that changed.
    public struct Move: Sendable {
        public let name: String
        public let label: String
        public let before: ParamStored
        public let after: ParamStored
        let param: any AnyParam
    }

    /// The parameters that changed, in inspector order.
    public let moves: [Move]
    /// The labels of the parameters words cannot set (a point, a rectangle, an
    /// inset, a range, a swatch strip), which the model never saw.
    public let leftOut: [String]
    /// The labels the model answered for with a value that could not be read
    /// against the parameter (a color that was not hex, a choice not on the
    /// menu), so a wrong answer shows up rather than vanishing.
    public let unreadable: [String]

    /// One line for the inspector: what moved and from where, or why nothing did.
    public var summary: String {
        if moves.isEmpty {
            var line = "Nothing moved: no parameter fits those words."
            if !unreadable.isEmpty {
                line += " The answer for \(list(unreadable)) could not be read."
            }
            if !leftOut.isEmpty {
                line += " \(list(leftOut)) \(leftOut.count == 1 ? "is" : "are") not a kind words can set."
            }
            return line
        }
        let parts = moves.map { "\($0.label) from \(words(for: $0.before)) to \(words(for: $0.after))" }
        return "Moved \(list(parts))."
    }

    /// Put every moved parameter back where it was, instantly.
    public func revert() {
        for move in moves { move.param.restore(move.before) }
    }

    /// Write the reply into the handles and record what changed. A value is
    /// read against its parameter's kind and written through the control's own
    /// path; a name the sketch has no parameter for is ignored, and a value the
    /// kind cannot read is noted rather than guessed.
    @MainActor
    static func applying(_ reply: TuningReply, to handles: [ParamHandle], leftOut: [String]) -> Tuning {
        var moves: [Move] = []
        var unreadable: [String] = []
        for handle in handles where handle.isShown {
            guard let value = reply[handle.name] else { continue }
            let before = handle.param.stored
            guard write(value, through: handle.control) else {
                unreadable.append(handle.label)
                continue
            }
            let after = handle.param.stored
            if after != before {
                moves.append(Move(name: handle.name, label: handle.label,
                                  before: before, after: after, param: handle.param))
            }
        }
        return Tuning(moves: moves, leftOut: leftOut, unreadable: unreadable)
    }

    /// `true` when the value could be read for this control and was written.
    private static func write(_ value: TunedValue, through control: ParamControl) -> Bool {
        switch control {
        case .slider(let slider):
            guard let number = number(in: value) else { return false }
            slider.write(number)
        case .stepper(let stepper):
            guard let number = number(in: value) else { return false }
            stepper.write(Int(number.rounded()))
        case .toggle(let toggle):
            guard let flag = flag(in: value) else { return false }
            toggle.write(flag)
        case .menu(let menu):
            guard case .text(let text) = value,
                  let index = menu.options.firstIndex(where: { same($0, text) }) else { return false }
            menu.write(index)
        case .colorWell(let well):
            guard case .text(let text) = value,
                  let color = ColorWords.color(from: text, keepingAlphaOf: well.read()) else { return false }
            well.write(color)
        case .text(let box):
            guard case .text(let text) = value else { return false }
            box.write(text)
        case .vector, .vector3, .rectangle, .insets, .range, .swatches:
            return false
        }
        return true
    }

    private static func number(in value: TunedValue) -> Double? {
        switch value {
        case .number(let number): return number.isFinite ? number : nil
        case .text(let text): return Double(text.trimmingCharacters(in: .whitespaces))
        case .bool: return nil
        }
    }

    private static func flag(in value: TunedValue) -> Bool? {
        switch value {
        case .bool(let flag): return flag
        case .number(let number): return number != 0
        case .text(let text):
            switch text.trimmingCharacters(in: .whitespaces).lowercased() {
            case "true", "on", "yes": return true
            case "false", "off", "no": return false
            default: return nil
            }
        }
    }

    /// Two labels match when they agree letter for letter, ignoring case,
    /// spaces, and punctuation, so "deep blue" finds "Deep Blue" and "deepBlue".
    private static func same(_ a: String, _ b: String) -> Bool {
        func fold(_ s: String) -> String { s.lowercased().filter { $0.isLetter || $0.isNumber } }
        return fold(a) == fold(b)
    }
}

/// A stored value in the words the summary uses.
func words(for stored: ParamStored) -> String {
    switch stored {
    case .number(let value): return plain(value)
    case .boolean(let flag): return flag ? "on" : "off"
    case .option(let name): return name
    case .color(let red, let green, let blue, let alpha):
        return ColorWords.hex(Color(red: red, green: green, blue: blue, alpha: alpha))
    case .text(let text): return "\"\(text)\""
    case .vector(let x, let y): return "(\(plain(x)), \(plain(y)))"
    case .vector3(let x, let y, let z): return "(\(plain(x)), \(plain(y)), \(plain(z)))"
    case .rectangle(let x, let y, let width, let height):
        return "(\(plain(x)), \(plain(y)), \(plain(width)) by \(plain(height)))"
    case .insets(let top, let right, let bottom, let left):
        return "(\(plain(top)), \(plain(right)), \(plain(bottom)), \(plain(left)))"
    case .range(let lower, let upper): return "\(plain(lower)) to \(plain(upper))"
    case .colors(let stops, _): return "\(stops.count) colors"
    }
}

/// "a", "a and b", "a, b, and c".
func list(_ items: [String]) -> String {
    switch items.count {
    case 0: return ""
    case 1: return items[0]
    case 2: return "\(items[0]) and \(items[1])"
    default: return items.dropLast().joined(separator: ", ") + ", and " + items[items.count - 1]
    }
}

public extension Sketch {

    /// Move this sketch's parameters toward a look in words, on this machine's
    /// own model, and say which moved. The typed form is `ParameterTuner`.
    @MainActor
    func tuneParameters(toward look: String) async throws -> Tuning {
        try await ParameterTuner().tune(parameters(), toward: look,
                                        sketchName: String(describing: type(of: self)))
    }
}

public extension ParamTuneAction {

    /// The inspector's "describe a look" row over this machine's own model, or
    /// `nil` when the machine has none, so the row stays out of a panel that
    /// could not answer. `parameters` is read on every ask, since a reload hands
    /// a host fresh handles.
    @MainActor
    static func onDevice(sketchName: String? = nil,
                         parameters: @escaping @MainActor () -> [ParamHandle]) -> ParamTuneAction? {
        guard ParameterTuner.availability.isAvailable else { return nil }
        return ParamTuneAction(tuner: ParameterTuner(), sketchName: sketchName, parameters: parameters)
    }

    /// The row over any tuner, which is how a test drives it without the model.
    @MainActor
    init(tuner: ParameterTuner, sketchName: String? = nil,
         parameters: @escaping @MainActor () -> [ParamHandle]) {
        let perform: @MainActor (String) async -> ParamTuneOutcome = { look in
            await ParamTuneOutcome.tuning(parameters(), toward: look, sketchName: sketchName, with: tuner)
        }
        self.init(perform: perform)
    }
}

extension ParamTuneOutcome {

    /// One ask, as the row shows it: the summary, and Undo while something moved.
    @MainActor
    static func tuning(_ handles: [ParamHandle], toward look: String, sketchName: String?,
                       with tuner: ParameterTuner) async -> ParamTuneOutcome {
        let tuning: Tuning
        do {
            tuning = try await tuner.tune(handles, toward: look, sketchName: sketchName)
        } catch {
            return ParamTuneOutcome(message: error.localizedDescription)
        }
        guard !tuning.moves.isEmpty else { return ParamTuneOutcome(message: tuning.summary) }
        let back: @MainActor () -> Void = { tuning.revert() }
        return ParamTuneOutcome(message: tuning.summary, undo: back)
    }
}
