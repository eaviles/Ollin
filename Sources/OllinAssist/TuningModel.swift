import Foundation
import Ollin

// The seam between the parameter panel and whatever answers for it. A request
// is plain data: the look in the artist's words and every parameter the words
// may move, each described in the terms a reader would use (its label, its
// range, what it holds now). A reply is plain data too: new values by name.
// The on-device model is one answerer; a test writes its own in three lines.

/// One parameter as the model sees it: a name to answer under, the words the
/// inspector shows for it, and what kind of value it takes.
public struct TunableParameter: Equatable, Sendable {

    /// What a value of this parameter can be, with the range it keeps to and
    /// what it holds now. Only kinds a phrase can reasonably set are here: a
    /// point, a rectangle, an inset, a range, and a swatch strip are left out,
    /// and `TuningRequest.leftOut` names them.
    public enum Kind: Equatable, Sendable {
        case number(range: ClosedRange<Double>, current: Double)
        case integer(range: ClosedRange<Int>, current: Int)
        case bool(current: Bool)
        /// The choices as the inspector labels them, and the current one.
        case choice(options: [String], current: String)
        case color(current: Color)
        case text(current: String)
    }

    /// The property name, which is the key an answer comes back under.
    public let name: String
    /// The inspector label ("Noise Scale"), the words a phrase is likeliest to use.
    public let label: String
    /// The inspector group, when the parameter has one.
    public let group: String?
    public let kind: Kind

    public init(name: String, label: String, group: String? = nil, kind: Kind) {
        self.name = name
        self.label = label
        self.group = group
        self.kind = kind
    }

    /// The kind in words, the way the request describes it to the model:
    /// "a number from 0 to 200, now 120".
    public var description: String {
        switch kind {
        case .number(let range, let current):
            return "a number from \(plain(range.lowerBound)) to \(plain(range.upperBound)), now \(plain(current))"
        case .integer(let range, let current):
            return "a whole number from \(range.lowerBound) to \(range.upperBound), now \(current)"
        case .bool(let current):
            return "true or false, now \(current)"
        case .choice(let options, let current):
            return "one of \(options.joined(separator: ", ")); now \(current)"
        case .color(let current):
            return "a color as #RRGGBB, now \(ColorWords.hex(current)) (\(ColorWords.name(current)))"
        case .text(let current):
            return "text, now \"\(current)\""
        }
    }

    /// The one line the prompt gives this parameter.
    var promptLine: String {
        let place = group.map { ", in the \($0) group" } ?? ""
        return "- \(name): \(label)\(place). \(description)."
    }
}

/// Everything the model is told for one ask.
public struct TuningRequest: Equatable, Sendable {
    /// The look, in the artist's words.
    public let look: String
    /// The sketch's name, for context, when the caller knows it.
    public let sketchName: String?
    /// The parameters the words may move.
    public let parameters: [TunableParameter]
    /// The labels of the parameters that were left out because a phrase cannot
    /// set their kind (a point, a rectangle, an inset, a range, a swatch strip).
    public let leftOut: [String]

    public init(look: String, sketchName: String? = nil,
                parameters: [TunableParameter], leftOut: [String] = []) {
        self.look = look
        self.sketchName = sketchName
        self.parameters = parameters
        self.leftOut = leftOut
    }

    /// The standing instructions: what the model is for and the few rules that
    /// make a phrase land where a person would put it. The same for every ask.
    public static let instructions = """
        You operate the parameter panel of a generative art sketch. The artist describes the look they want in a few words. You decide which parameters those words concern and what their new values should be, and you touch nothing else.
        Rules:
        - A parameter is concerned only when the words clearly name it or clearly imply it. Most looks concern one or two parameters. If none fits, the answer is empty.
        - Keep each value inside its range.
        - Relative words move from the current value: "bigger" or "more" means clearly higher than now, "smaller" or "fewer" clearly lower, "slightly" a small step, "much" a large one.
        - "as big as it goes", "maximum", "all the way" means the top of the range; "as small as possible", "minimum", "none" means the bottom.
        - Colors are #RRGGBB. Warmer means toward red and orange, cooler toward blue, darker toward black, paler toward white.
        """

    /// The prompt for this ask: the sketch, one line per parameter, then the look.
    public var promptText: String {
        var lines: [String] = []
        if let sketchName { lines.append("Sketch: \(sketchName).") }
        lines.append("Parameters:")
        lines.append(contentsOf: parameters.map(\.promptLine))
        lines.append("")
        lines.append("Look: \"\(look)\"")
        return lines.joined(separator: "\n")
    }
}

/// One value the model answered with. Numbers arrive as numbers, a toggle as a
/// Boolean, and a choice, a color, or a text as text; the tuner reads each
/// against its parameter's own kind.
public enum TunedValue: Equatable, Sendable {
    case number(Double)
    case bool(Bool)
    case text(String)
}

/// New values by parameter name. A parameter the model leaves out is a
/// parameter the words did not concern.
public typealias TuningReply = [String: TunedValue]

/// Whatever answers a request. The on-device model is the one that ships; a
/// test, or a sketch with its own idea, writes another.
public protocol TuningModel: Sendable {
    func propose(_ request: TuningRequest) async throws -> TuningReply
}

/// Why an ask could not be answered, each as the sentence the inspector shows.
public enum TuningError: Error, Equatable, LocalizedError {
    /// The model is not on this machine, and the sentence says why.
    case unavailable(String)
    /// The phrase was empty.
    case emptyLook
    /// The sketch has no parameter of a kind words can set.
    case nothingToTune
    /// More parameters than the model can read in one ask.
    case tooMuchToDescribe
    /// The model declined the phrase.
    case refused
    /// The model does not read the phrase's language.
    case unsupportedLanguage
    /// Anything else, with the system's own words.
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let reason): return reason
        case .emptyLook: return "Describe the look in a few words first."
        case .nothingToTune: return "This sketch has no parameter that words can set."
        case .tooMuchToDescribe: return "This sketch has more parameters than the model can read in one ask."
        case .refused: return "The model declined that phrase. Try other words."
        case .unsupportedLanguage: return "The model does not read that language yet."
        case .failed(let message): return message
        }
    }
}

/// Whether an on-device model is here to answer.
public enum TuningAvailability: Equatable, Sendable {
    case available
    /// Not available, with the sentence to show for it.
    case unavailable(reason: String)

    public var isAvailable: Bool { self == .available }
}

// MARK: - Words for values

/// A number written the short way: whole when it is whole, otherwise trimmed to
/// three decimals. The prompt and the summary both read better without `120.0`.
func plain(_ value: Double) -> String {
    if value == value.rounded(), abs(value) < 1e15 { return String(Int(value)) }
    var text = String(format: "%.3f", value)
    while text.hasSuffix("0") { text.removeLast() }
    if text.hasSuffix(".") { text.removeLast() }
    return text
}

/// A color in words and as hex, for the prompt and the summary.
enum ColorWords {

    /// `#RRGGBB`, from the sRGB components; an alpha below 1 is appended as two
    /// more digits, since the model is told the six-digit form and reads either.
    static func hex(_ color: Color) -> String {
        func byte(_ v: Double) -> String { String(format: "%02X", Int((min(max(v, 0), 1) * 255).rounded())) }
        let rgb = "#" + byte(color.red) + byte(color.green) + byte(color.blue)
        return color.alpha < 0.999 ? rgb + byte(color.alpha) : rgb
    }

    /// A `#RRGGBB` or `#RRGGBBAA` (the `#` optional) read back, or `nil`.
    static func color(from text: String, keepingAlphaOf current: Color) -> Color? {
        var digits = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if digits.hasPrefix("#") { digits.removeFirst() }
        guard digits.count == 6 || digits.count == 8, digits.allSatisfy(\.isHexDigit),
              let value = UInt64(digits, radix: 16) else { return nil }
        let hasAlpha = digits.count == 8
        let shift = hasAlpha ? 8 : 0
        let red = Double((value >> (16 + UInt64(shift))) & 0xFF) / 255
        let green = Double((value >> (8 + UInt64(shift))) & 0xFF) / 255
        let blue = Double((value >> UInt64(shift)) & 0xFF) / 255
        let alpha = hasAlpha ? Double(value & 0xFF) / 255 : current.alpha
        return Color(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// A coarse name ("dark blue", "pale orange", "gray"), so a small model
    /// reads the current color without decoding hex in its head.
    static func name(_ color: Color) -> String {
        let r = min(max(color.red, 0), 1), g = min(max(color.green, 0), 1), b = min(max(color.blue, 0), 1)
        let high = max(r, g, b), low = min(r, g, b)
        let lightness = (high + low) / 2
        let chroma = high - low
        let saturation = chroma == 0 ? 0 : chroma / (1 - abs(2 * lightness - 1))
        if saturation < 0.12 {
            switch lightness {
            case ..<0.08: return "black"
            case ..<0.35: return "dark gray"
            case ..<0.7: return "gray"
            case ..<0.94: return "light gray"
            default: return "white"
            }
        }
        var hue: Double
        if high == r { hue = (g - b) / chroma }
        else if high == g { hue = 2 + (b - r) / chroma }
        else { hue = 4 + (r - g) / chroma }
        hue = (hue * 60 + 360).truncatingRemainder(dividingBy: 360)
        let base: String
        switch hue {
        case ..<15, 345...: base = "red"
        case ..<45: base = "orange"
        case ..<70: base = "yellow"
        case ..<165: base = "green"
        case ..<200: base = "cyan"
        case ..<255: base = "blue"
        case ..<290: base = "purple"
        default: base = "magenta"
        }
        if lightness < 0.3 { return "dark \(base)" }
        if lightness > 0.75 { return "pale \(base)" }
        return base
    }
}
