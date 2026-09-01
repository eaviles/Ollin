import Foundation

/// An OSC message: an address pattern (a slash-delimited path like `/synth/freq`)
/// plus zero or more typed `arguments`. This is the unit a sketch sends and
/// receives.
///
/// ```swift
/// let move = OSCMessage("/cursor", 0.5, 0.5)   // two floats
/// sender.send(move)
/// ```
///
/// On receive, the typed getters read the first argument of the matching kind, so
/// the common "one value per address" case stays terse:
///
/// ```swift
/// if let level = receiver.message("/level")?.number { ... }
/// ```
public struct OSCMessage: Sendable, Equatable {
    /// The OSC address pattern, e.g. `/synth/1/freq`.
    public var address: String
    /// The typed arguments, in order.
    public var arguments: [OSCArgument]

    public init(_ address: String, arguments: [OSCArgument]) {
        self.address = address
        self.arguments = arguments
    }

    /// Builds a message from a list of arguments, which read as literals:
    /// `OSCMessage("/light", 0.8, 1, "on")`.
    public init(_ address: String, _ arguments: OSCArgument...) {
        self.address = address
        self.arguments = arguments
    }

    // MARK: First-argument convenience (coerced)

    /// The first argument as a `Double` (coercing across numeric tags).
    public var number: Double? { arguments.first?.number }
    /// The first argument as an `Int` (coercing across numeric tags).
    public var int: Int? { arguments.first?.int }
    /// The first argument as a `String`.
    public var text: String? { arguments.first?.text }
    /// The first argument as a `Bool`.
    public var bool: Bool? { arguments.first?.bool }
}
