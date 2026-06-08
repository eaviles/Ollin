import Foundation

/// An OSC time tag: a 64-bit NTP timestamp marking when a bundle's messages
/// should take effect. The special value `.immediate` means "act now" and is by
/// far the common case.
///
/// The raw form is NTP's fixed-point seconds-since-1900: the high 32 bits are
/// whole seconds, the low 32 bits a fraction of a second.
public struct OSCTimeTag: Sendable, Equatable {
    /// The raw 64-bit NTP value.
    public var raw: UInt64

    /// Seconds between the NTP epoch (1900-01-01) and the Unix epoch (1970-01-01).
    private static let ntpToUnix: Double = 2_208_988_800

    public init(raw: UInt64) { self.raw = raw }

    /// The "act immediately" tag — every bit zero but the lowest, per the spec.
    public static let immediate = OSCTimeTag(raw: 1)

    /// Whether this is the immediate sentinel.
    public var isImmediate: Bool { raw == 1 }

    /// Builds a time tag for a wall-clock instant.
    public init(_ date: Date) {
        let ntp = date.timeIntervalSince1970 + OSCTimeTag.ntpToUnix
        let seconds = UInt64(ntp.rounded(.down))
        let fraction = UInt64((ntp - Double(seconds)) * 4_294_967_296.0)   // 2^32
        self.raw = (seconds << 32) | (fraction & 0xFFFF_FFFF)
    }

    /// The wall-clock instant this tag refers to (`nil` for `.immediate`).
    public var date: Date? {
        guard !isImmediate else { return nil }
        let seconds = Double(raw >> 32)
        let fraction = Double(raw & 0xFFFF_FFFF) / 4_294_967_296.0
        return Date(timeIntervalSince1970: seconds + fraction - OSCTimeTag.ntpToUnix)
    }
}
