import Foundation

/// Decides, for one universe, whether this frame's channel data should go on
/// the wire. A sketch calls `send` every frame at the display rate, but both
/// wire specs ask for less: no faster than DMX itself refreshes (~44 Hz),
/// changed data only, a short tail of repeats after the last change so a
/// receiver that missed one still converges, then a keep-alive every 800 to
/// 1000 ms so nodes know the source is alive.
///
/// Pure on purpose: time comes in as an argument, so the cadence is tested
/// directly with no sockets and no clocks.
struct DMXPacer {

    /// The transmit ceiling, matching a DMX512 gateway's maximum refresh.
    var maxRate: Double = 44

    /// How often unchanged data is re-sent so receivers hold the look.
    var keepAliveInterval: Double = 0.9

    /// How many times unchanged data still goes out after a change before
    /// suppression starts (the E1.31 three-packet rule).
    static let repeatsAfterChange = 3

    private var lastChannels: [UInt8]?
    private var lastSendTime: Double?
    private var repeatsRemaining = 0

    /// Whether `channels` should be transmitted at `now` (seconds, any
    /// monotonic clock). A `true` also records the send.
    mutating func shouldSend(_ channels: [UInt8], now: Double) -> Bool {
        let changed = channels != lastChannels
        let elapsed = lastSendTime.map { now - $0 } ?? .infinity

        let due: Bool
        if changed || repeatsRemaining > 0 {
            due = elapsed >= 1 / maxRate
        } else {
            due = elapsed >= keepAliveInterval
        }
        guard due else { return false }

        if changed {
            repeatsRemaining = Self.repeatsAfterChange
        } else if repeatsRemaining > 0 {
            repeatsRemaining -= 1
        }
        lastChannels = channels
        lastSendTime = now
        return true
    }
}
