import Foundation

/// The identifier Bluetooth gives a service or a characteristic.
///
/// Two spellings mean the same thing and both are accepted. The standard
/// assigns short 16-bit numbers to the things everybody agreed on (`"180D"`
/// is the heart rate service), and anybody's own device invents a full
/// 128-bit one (`"6E400001-B5A3-F393-E0A9-E50E24DCCA9E"`). A short number is
/// the long one with the standard's base filled in around it, so both forms
/// compare equal here:
///
/// ```swift
/// BluetoothUUID("180D") == BluetoothUUID("0000180D-0000-1000-8000-00805F9B34FB")   // true
/// ```
///
/// Dashes, `0x`, and letter case are all optional on the way in. Anything
/// that is not a Bluetooth identifier keeps its own text and matches nothing,
/// and `isWellFormed` is `false` for it, so a typed-in UUID with a character
/// missing is a question you can ask rather than a device that never answers.
public struct BluetoothUUID: Hashable, Sendable, CustomStringConvertible {

    /// The long form, uppercase and dashed. A short number is expanded, so
    /// this is the one spelling everything downstream compares.
    public let string: String

    /// Whether the text given was a Bluetooth identifier at all.
    public let isWellFormed: Bool

    /// The 128-bit form every 16-bit and 32-bit number sits inside. The four
    /// leading digits are the short number; the rest is fixed by the standard.
    static let baseSuffix = "-0000-1000-8000-00805F9B34FB"

    /// Reads either spelling. Text that is neither is kept as given, so it
    /// can be shown back to the person who typed it.
    public init(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let expanded = BluetoothUUID.expand(trimmed) {
            string = expanded
            isWellFormed = true
        } else {
            string = trimmed.uppercased()
            isWellFormed = false
        }
    }

    /// Reads a short number directly, e.g. `BluetoothUUID(short: 0x180D)`.
    public init(short number: UInt16) {
        self.init(String(format: "%04X", number))
    }

    /// The short number when this identifier is one of the standard's own,
    /// and `nil` for a device's own 128-bit identifier.
    public var shortNumber: UInt16? {
        guard isWellFormed, string.hasSuffix(BluetoothUUID.baseSuffix) else { return nil }
        let head = string.prefix(8)
        guard head.hasPrefix("0000") else { return nil }
        return UInt16(head.suffix(4), radix: 16)
    }

    /// The shortest spelling that still names this identifier: the four-digit
    /// number for a standard one, the whole thing for anything else.
    public var description: String {
        if let short = shortNumber { return String(format: "%04X", short) }
        return string
    }

    /// Expands any accepted spelling into the long form, or returns `nil`
    /// when the text is not an identifier.
    private static func expand(_ text: String) -> String? {
        var body = text.uppercased()
        if body.hasPrefix("0X") { body.removeFirst(2) }
        let digits = body.filter { $0 != "-" }
        guard !digits.isEmpty, digits.allSatisfy(\.isHexDigit) else { return nil }

        switch digits.count {
        case 4:
            return "0000\(digits)\(baseSuffix)"
        case 8:
            return "\(digits)\(baseSuffix)"
        case 32:
            // Refuse a long identifier whose dashes sit in the wrong places,
            // rather than quietly accepting a mistyped one.
            if body.contains("-") && !isDashedCorrectly(body) { return nil }
            let d = Array(digits)
            let group = { (from: Int, count: Int) in String(d[from..<(from + count)]) }
            return [group(0, 8), group(8, 4), group(12, 4), group(16, 4), group(20, 12)]
                .joined(separator: "-")
        default:
            return nil
        }
    }

    /// The 8-4-4-4-12 shape a long identifier is written in.
    private static func isDashedCorrectly(_ body: String) -> Bool {
        let parts = body.split(separator: "-", omittingEmptySubsequences: false)
        return parts.map(\.count) == [8, 4, 4, 4, 12]
    }
}
