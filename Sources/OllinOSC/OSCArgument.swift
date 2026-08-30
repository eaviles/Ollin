import Foundation

/// A single typed value inside an `OSCMessage`. OSC carries each argument with a
/// one-character type tag, and this enum is one case per tag Ollin speaks.
///
/// The four everyday ones — `int`, `float`, `string`, `blob` — cover almost all
/// traffic; the rest (`double`, `int64`, `bool`, `null`, `impulse`) round out the
/// OSC 1.0 set so messages from other tools decode losslessly.
///
/// Literals build arguments directly, so a message reads without ceremony:
///
/// ```swift
/// OSCMessage("/light", 0.8, 1, "on", true)   // float, int, string, bool
/// ```
public enum OSCArgument: Sendable, Equatable {
    /// 32-bit integer (tag `i`).
    case int(Int32)
    /// 32-bit float (tag `f`) — the common case for continuous controls.
    case float(Float)
    /// A UTF-8 string (tag `s`).
    case string(String)
    /// Raw bytes (tag `b`), length-prefixed on the wire.
    case blob(Data)
    /// 64-bit float (tag `d`).
    case double(Double)
    /// 64-bit integer (tag `h`).
    case int64(Int64)
    /// Boolean — encoded as the tag itself (`T` or `F`), carrying no bytes.
    case bool(Bool)
    /// No value (tag `N`).
    case null
    /// "Bang" / infinitum (tag `I`), carrying no bytes — a bare trigger.
    case impulse

    /// The OSC type-tag character for this argument.
    var typeTag: Character {
        switch self {
        case .int: return "i"
        case .float: return "f"
        case .string: return "s"
        case .blob: return "b"
        case .double: return "d"
        case .int64: return "h"
        case .bool(let value): return value ? "T" : "F"
        case .null: return "N"
        case .impulse: return "I"
        }
    }

    // MARK: Coercing accessors

    /// The value as a `Float`, converting across the numeric tags (an `int`,
    /// `double`, or `int64` is coerced; a `bool` reads as 0/1). `nil` for the
    /// non-numeric tags.
    public var float: Float? {
        switch self {
        case .float(let value): return value
        case .int(let value): return Float(value)
        case .int64(let value): return Float(value)
        case .double(let value): return Float(value)
        case .bool(let value): return value ? 1 : 0
        default: return nil
        }
    }

    /// The value as an `Int`, converting across the numeric tags (a fractional
    /// `float`/`double` is rounded toward zero; a `bool` reads as 0/1). `nil` for
    /// the non-numeric tags.
    public var int: Int? {
        switch self {
        case .int(let value): return Int(value)
        case .int64(let value): return Int(value)
        case .float(let value): return Int(value)
        case .double(let value): return Int(value)
        case .bool(let value): return value ? 1 : 0
        default: return nil
        }
    }

    /// The value as a `String` — the payload of a `string`, or `nil` otherwise.
    public var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// The value as a `Bool`: a `bool` directly, `impulse` as `true`, or a numeric
    /// tag as "non-zero". `nil` for the rest.
    public var bool: Bool? {
        switch self {
        case .bool(let value): return value
        case .impulse: return true
        case .int(let value): return value != 0
        case .int64(let value): return value != 0
        case .float(let value): return value != 0
        case .double(let value): return value != 0
        default: return nil
        }
    }
}

// MARK: - Literals

extension OSCArgument: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int32) { self = .int(value) }
}

extension OSCArgument: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Float) { self = .float(value) }
}

extension OSCArgument: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

extension OSCArgument: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}
