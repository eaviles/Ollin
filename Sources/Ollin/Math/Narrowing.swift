import Foundation

extension Double {
    /// This number as an `Int`, rounded by `rule`, or `nil` when it is not
    /// finite or does not fit in one.
    ///
    /// `Int(_:)` traps on a NaN, an infinity, or a magnitude past what an
    /// `Int` holds, and every one of those can arrive from outside: an OSC
    /// float whose bits spell NaN, an MQTT payload reading `1e300`, a JSON
    /// number in a parameter payload. A number that arrived from a wire, a
    /// file, or another program is read through this, so a value that is not
    /// a whole number a sketch can hold is simply not one, rather than the end
    /// of the show.
    package func int(rounded rule: FloatingPointRoundingRule = .towardZero) -> Int? {
        guard isFinite else { return nil }
        return Int(exactly: rounded(rule))
    }
}
