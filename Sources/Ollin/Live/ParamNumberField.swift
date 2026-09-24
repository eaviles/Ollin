import Foundation

// The rules behind the inspector's number boxes, kept out of the views so they
// can be tested without a window: what a value reads as, what typed text means,
// how finely a drag moves, and what typing into a box does to the value.

/// Number text for a value box.
enum ParamNumberText {
    /// The most significant figures a box shows. A value typed or dragged in a
    /// box carries fewer, so it reads back exactly as it was put; the cap is for
    /// values that arrive from elsewhere (a MIDI binding, a rule, a smoothing
    /// glide), which carry a `Double`'s full precision and would fill the row.
    static let significantFigures = 6

    /// `value` as a box shows it: its own digits with the trailing zeros taken
    /// off, never a fixed count of decimals, never a grouping separator, and a
    /// point rather than a locale's comma, since it is the same literal the
    /// sketch's source spells.
    static func display(_ value: Double) -> String {
        guard value.isFinite else { return String(value) }
        let magnitude = abs(value)
        guard magnitude > 0 else { return "0" }
        let exponent = Int(floor(log10(magnitude)))
        let fractionDigits = Swift.min(Swift.max(significantFigures - 1 - exponent, 0), 12)
        var text = String(format: "%.\(fractionDigits)f", value)
        if text.contains(".") {
            while text.hasSuffix("0") { text.removeLast() }
            if text.hasSuffix(".") { text.removeLast() }
        }
        return text == "-0" ? "0" : text
    }

    /// What typed text means as a number, or nil while it is not one yet (an
    /// empty box, a lone minus sign, a stray letter). A comma is the decimal
    /// point where the locale writes it that way, and a grouping mark
    /// everywhere else, so "1,080" typed out of habit still reads as 1080.
    static func parse(_ text: String,
                      decimalSeparator: String = Locale.current.decimalSeparator ?? ".") -> Double? {
        var cleaned = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "\u{2212}", with: "-")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: " ", with: "")
        if decimalSeparator == ",", !cleaned.contains(".") {
            cleaned = cleaned.replacingOccurrences(of: ",", with: ".")
        } else {
            cleaned = cleaned.replacingOccurrences(of: ",", with: "")
        }
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite else { return nil }
        return value
    }

    /// The grid a drag lands on: the power of ten at or under `perPoint`, the
    /// distance one point of drag covers. It is finer than a pointer can place,
    /// so the drag still feels continuous, and it leaves the few digits a person
    /// would have typed rather than the sixteen a division produces.
    static func dragQuantum(perPoint: Double) -> Double? {
        guard perPoint.isFinite, perPoint > 0 else { return nil }
        return pow(10, floor(log10(perPoint)))
    }

    /// `value` on the nearest multiple of `quantum`, as the decimal it names:
    /// 0.01 × 196 is 1.9600000000000002 in binary, and this is 1.96.
    static func quantized(_ value: Double, quantum: Double) -> Double {
        guard quantum > 0, value.isFinite else { return value }
        let digits = Swift.min(Swift.max(-Int(floor(log10(quantum))), 0), 15)
        let steps = (value / quantum).rounded()
        return Double(String(format: "%.\(digits)f", steps * quantum)) ?? steps * quantum
    }

    /// A dragged value (a slider, a scrub, a pad) on the drag's grid and inside
    /// `range`. An end of the range stays exactly that end, so a drag reaches it
    /// whatever the grid.
    static func dragged(_ value: Double, perPoint: Double, in range: ClosedRange<Double>) -> Double {
        if value <= range.lowerBound { return range.lowerBound }
        if value >= range.upperBound { return range.upperBound }
        guard let quantum = dragQuantum(perPoint: perPoint) else { return value }
        return Swift.min(Swift.max(quantized(value, quantum: quantum), range.lowerBound), range.upperBound)
    }
}

/// A value box being typed in. While the keys are in the box, its text belongs
/// to the person typing: nothing the row learns (a clamp, a step, the sketch
/// moving the value) is written back into it, since a clamp written back would
/// turn a first "2" in a box over 10...375 into the floor before the second key
/// arrived. A number that reads and sits inside the range shows on the canvas
/// at once; anything else waits for the commit, which clamps. Escape puts back
/// the value the box started from.
struct ParamNumberEdit: Equatable {
    /// The value before the first key of the typing under way, which Escape
    /// puts back. Taken at that key rather than when the box took the keys, so
    /// it is the value the box showed whichever way the keys arrived.
    private(set) var original: Double = 0
    /// The typed text, or nil while the box shows the value itself.
    private(set) var draft: String?

    /// The text the box shows while the value is `value`.
    func text(for value: Double) -> String {
        draft ?? ParamNumberText.display(value)
    }

    /// The text changed under the keys, over a box holding `current`. Returns
    /// the value to show at once, or nil when the text is not yet a number
    /// inside `range` (or `accepts` turns it down), and the value then stays
    /// where it was.
    mutating func type(_ text: String, over current: Double, in range: ClosedRange<Double>,
                       accepts: (Double) -> Bool = { _ in true }) -> Double? {
        if draft == nil { original = current }
        draft = text
        guard let value = ParamNumberText.parse(text), range.contains(value), accepts(value) else {
            return nil
        }
        return value
    }

    /// Return, Tab, or a click away. Returns the value to set: the one typed,
    /// clamped to `range`, or the starting value when the text is not a number.
    /// Nil when nothing was typed, so a box the keys only passed through is
    /// never rewritten.
    mutating func commit(in range: ClosedRange<Double>) -> Double? {
        guard let text = draft else { return nil }
        draft = nil
        guard let typed = ParamNumberText.parse(text) else { return original }
        return Swift.min(Swift.max(typed, range.lowerBound), range.upperBound)
    }

    /// Escape. Returns the value to put back, or nil when nothing was typed.
    mutating func cancel() -> Double? {
        guard draft != nil else { return nil }
        draft = nil
        return original
    }
}

/// Which end of a min/max pair an edit set.
enum ParamRangeEnd {
    case lower, upper

    /// The pair after this end was set. The edited end stays where it was put,
    /// and when it crossed the other end, the other end moves to meet it.
    func ordered(lower: Double, upper: Double) -> ClosedRange<Double> {
        guard lower > upper else { return lower...upper }
        switch self {
        case .lower: return lower...lower
        case .upper: return upper...upper
        }
    }
}
