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

/// How a value box moves under the hand: how far a point of drag takes it,
/// the marks Shift lands it on, and the step an arrow key takes.
///
/// A plain drag covers the range in about a sidebar track's length, and a
/// stepped box no slower than a step per eight points, so a whole number over
/// 0...10000 crosses its range in the drag a slider takes. Shift keeps that pace and lands on round marks, four to
/// forty of them across the range, so it steps through the range instead of
/// running to an end. An arrow goes to the next mark on its grid: the declared
/// step, or a tenth of Shift's mark on a free box; Shift's mark under Shift;
/// a tenth again under Option, where there is no step to keep.
struct ParamStepping: Equatable {
    /// What a modifier key asks of a drag or an arrow: Option is `fine`,
    /// Shift is `coarse`.
    enum Pace: Equatable {
        case plain, fine, coarse
    }

    let range: ClosedRange<Double>
    /// The declared step, on a grid from the range's lower end, or nil.
    let step: Double?

    /// About how long a sidebar track is, in points.
    static let trackPoints = 250.0
    /// The slowest a stepped box drags: this many points to a step.
    static let pointsPerStep = 8.0

    init(range: ClosedRange<Double>, step: Double? = nil) {
        self.range = range
        self.step = step.flatMap { $0 > 0 && $0.isFinite ? $0 : nil }
    }

    private var span: Double { range.upperBound - range.lowerBound }

    /// Value per point of plain drag.
    var perPoint: Double {
        guard span > 0, span.isFinite else { return 0 }
        let track = span / Self.trackPoints
        guard let step else { return track }
        return Swift.max(track, step / Self.pointsPerStep)
    }

    /// The distance between Shift's marks: the power of ten (in whole steps on
    /// a stepped box) that leaves four to forty of them across the range, and
    /// never less than the step.
    var coarse: Double {
        let unitless = step ?? 1
        guard span > 0, span.isFinite, let power = Self.powerOfTen(atOrUnder: span / (4 * unitless)) else {
            return unitless
        }
        return step.map { $0 * Swift.max(1, power) } ?? power
    }

    /// The distance an arrow takes: the declared step, or a tenth of Shift's
    /// mark on a free box.
    var unit: Double { step ?? coarse / 10 }

    /// The value after a drag `points` long from `base`, at `pace`.
    func dragged(from base: Double, points: Double, pace: Pace) -> Double {
        let rate = pace == .fine ? perPoint / 10 : perPoint
        let moved = base + points * rate
        switch pace {
        case .coarse:
            return clamped(onGrid(moved, size: coarse, origin: coarseOrigin, rounding: .toNearestOrAwayFromZero))
        case .plain, .fine:
            if let step {
                return clamped(onGrid(moved, size: step, origin: range.lowerBound, rounding: .toNearestOrAwayFromZero))
            }
            return ParamNumberText.dragged(moved, perPoint: rate, in: range)
        }
    }

    /// The value after an arrow key from `value`, `direction` up (positive)
    /// or down: the next mark on the pace's grid strictly past the value, held
    /// to the range. A value already on a mark, binary noise and all, moves a
    /// whole mark.
    func nudged(_ value: Double, by direction: Int, pace: Pace) -> Double {
        guard direction != 0 else { return value }
        let size: Double, origin: Double
        switch pace {
        case .plain: (size, origin) = (unit, step == nil ? 0 : range.lowerBound)
        case .fine: (size, origin) = (step ?? unit / 10, step == nil ? 0 : range.lowerBound)
        case .coarse: (size, origin) = (coarse, coarseOrigin)
        }
        guard size > 0, size.isFinite, value.isFinite else { return clamped(value) }
        let marks = (value - origin) / size
        let tolerance = 1e-9 * Swift.max(1, abs(marks))
        let next = direction > 0 ? (marks + tolerance).rounded(.down) + 1
                                 : (marks - tolerance).rounded(.up) - 1
        return clamped(Self.decimal(origin + next * size, size: size, origin: origin))
    }

    /// Where Shift's marks count from: zero when zero is on the step's grid
    /// (or there is no step), so the marks are round numbers, and otherwise
    /// the range's lower end, where the step's own grid starts.
    private var coarseOrigin: Double {
        guard let step else { return 0 }
        let fromFloor = -range.lowerBound / step
        return abs(fromFloor - fromFloor.rounded()) < 1e-9 ? 0 : range.lowerBound
    }

    private func clamped(_ value: Double) -> Double {
        Swift.min(Swift.max(value, range.lowerBound), range.upperBound)
    }

    private func onGrid(_ value: Double, size: Double, origin: Double,
                        rounding: FloatingPointRoundingRule) -> Double {
        guard size > 0, size.isFinite, value.isFinite else { return value }
        let marks = ((value - origin) / size).rounded(rounding)
        return Self.decimal(origin + marks * size, size: size, origin: origin)
    }

    /// `pow(10, floor(log10(x)))`, or nil for a value with no logarithm.
    private static func powerOfTen(atOrUnder x: Double) -> Double? {
        guard x > 0, x.isFinite else { return nil }
        return pow(10, floor(log10(x)))
    }

    /// `value` as the decimal a grid of `size` from `origin` names, so three
    /// marks of 0.1 read 0.3 rather than 0.30000000000000004.
    private static func decimal(_ value: Double, size: Double, origin: Double) -> Double {
        let digits = Swift.max(fractionDigits(size), fractionDigits(origin))
        return Double(String(format: "%.\(digits)f", value)) ?? value
    }

    /// How many decimals `x` takes, up to twelve.
    private static func fractionDigits(_ x: Double) -> Int {
        guard x.isFinite else { return 0 }
        for digits in 0...12 {
            let scaled = x * pow(10, Double(digits))
            if abs(scaled - scaled.rounded()) < 1e-6 * Swift.max(1, abs(scaled)) { return digits }
        }
        return 12
    }
}

/// What the parameters list says after a save, and when it stops: a value
/// turned by hand, or put back, makes the sentence describe values that are no
/// longer the ones showing, so it goes.
struct ParamSaveNote: Equatable {
    private(set) var text: String?

    mutating func saved(_ sentence: String?) { text = sentence }

    mutating func changed() { text = nil }
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
