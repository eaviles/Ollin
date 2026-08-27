import Foundation

/// A short piece of touch: some taps and hums laid out on a timeline.
///
/// A pattern is a value, like a color or a shape. You build one, compose it
/// with others, and play it from `draw()`:
///
/// ```swift
/// let heartbeat = HapticPattern
///     .tap(intensity: 1, sharpness: 0.8)
///     .then(.silence(0.12))
///     .then(.tap(intensity: 0.6, sharpness: 0.4))
///
/// override func draw() {
///     if beatJustLanded { playHaptic(heartbeat) }
/// }
/// ```
///
/// Good touch is designed, not derived. Nothing here reads the canvas and
/// guesses: you say what the hand should feel, the same way you say what the
/// eye should see.
public struct HapticPattern: Equatable, Sendable {

    /// The events, earliest first.
    public let events: [HapticEvent]

    /// How long the whole pattern lasts, in seconds, counting the tail of the
    /// last hum. An empty pattern lasts no time at all.
    public let duration: Double

    /// Build a pattern from events in any order. They are sorted for you.
    public init(_ events: [HapticEvent]) {
        let sorted = events.sorted { left, right in
            left.time == right.time ? left.kind.rawValue < right.kind.rawValue : left.time < right.time
        }
        self.events = sorted
        self.duration = sorted.map(\.endTime).max() ?? 0
    }

    /// A pattern with nothing in it.
    public static let none = HapticPattern([])

    /// True when there is nothing to play.
    public var isEmpty: Bool { events.isEmpty }

    // MARK: - Ready-made pieces

    /// One knock.
    ///
    /// - Parameters:
    ///   - intensity: how strong, 0 to 1.
    ///   - sharpness: how crisp, 0 for a dull thud and 1 for a tight click.
    public static func tap(intensity: Double = 1, sharpness: Double = 0.5) -> HapticPattern {
        HapticPattern([HapticEvent(.tap, intensity: intensity, sharpness: sharpness)])
    }

    /// One sustained buzz.
    ///
    /// - Parameters:
    ///   - seconds: how long it lasts.
    ///   - intensity: how strong, 0 to 1.
    ///   - sharpness: how crisp, 0 for a soft purr and 1 for a rough rattle.
    ///   - fadeIn: how long it takes to arrive. 0 starts at full strength.
    ///   - fadeOut: how long it takes to leave. 0 cuts it off.
    public static func hum(
        _ seconds: Double,
        intensity: Double = 0.6,
        sharpness: Double = 0.3,
        fadeIn: Double = 0,
        fadeOut: Double = 0
    ) -> HapticPattern {
        HapticPattern([
            HapticEvent(
                .hum,
                intensity: intensity,
                sharpness: sharpness,
                duration: seconds,
                fadeIn: fadeIn,
                fadeOut: fadeOut)
        ])
    }

    /// A run of evenly spaced taps.
    ///
    /// - Parameters:
    ///   - count: how many taps.
    ///   - seconds: the gap between one tap and the next.
    ///   - intensity: how strong, 0 to 1.
    ///   - sharpness: how crisp, 0 to 1.
    public static func pulses(
        _ count: Int,
        every seconds: Double,
        intensity: Double = 1,
        sharpness: Double = 0.5
    ) -> HapticPattern {
        guard count > 0 else { return .none }
        let gap = max(0, seconds.finiteOrZero)
        return HapticPattern((0..<count).map { index in
            HapticEvent(
                .tap,
                at: Double(index) * gap,
                intensity: intensity,
                sharpness: sharpness)
        })
    }

    /// A gap of nothing, to place between two pieces with ``then(_:)``.
    public static func silence(_ seconds: Double) -> HapticPattern {
        // A hum with no strength: it holds the time open and plays as nothing.
        HapticPattern([HapticEvent(.hum, intensity: 0, duration: seconds)])
    }

    // MARK: - Composing

    /// This pattern, then the other one after it.
    ///
    /// The second one starts where the first one ends, so pieces line up end
    /// to end like words in a sentence.
    public func then(_ other: HapticPattern) -> HapticPattern {
        guard !other.isEmpty else { return self }
        guard !isEmpty else { return other }
        return HapticPattern(events + other.events.map { $0.delayed(by: duration) })
    }

    /// This pattern and the other one at the same time, both starting
    /// together.
    public func over(_ other: HapticPattern) -> HapticPattern {
        HapticPattern(events + other.events)
    }

    /// The whole pattern moved later by some seconds.
    public func delayed(by seconds: Double) -> HapticPattern {
        guard seconds.finiteOrZero != 0 else { return self }
        return HapticPattern(events.map { $0.delayed(by: seconds) })
    }

    /// The pattern played several times, one after another.
    ///
    /// - Parameters:
    ///   - times: how many copies in total. 1 gives back the same pattern.
    ///   - seconds: how far apart the copies start. Left out, each copy
    ///     starts where the one before it ended.
    public func repeated(_ times: Int, every seconds: Double? = nil) -> HapticPattern {
        guard times > 1, !isEmpty else { return times < 1 ? .none : self }
        let step = seconds.map { max(0, $0.finiteOrZero) } ?? duration
        return HapticPattern((0..<times).flatMap { index in
            events.map { $0.delayed(by: Double(index) * step) }
        })
    }

    /// The same pattern, stronger or weaker throughout.
    ///
    /// Use it to turn one gesture down without writing it twice, or to let a
    /// sketch value drive how hard the whole thing lands.
    public func scaled(intensity factor: Double) -> HapticPattern {
        guard factor != 1 else { return self }
        return HapticPattern(events.map { $0.scaled(intensity: max(0, factor.finiteOrZero)) })
    }

    /// The same pattern played faster or slower. 2 plays it twice as fast.
    public func speed(_ factor: Double) -> HapticPattern {
        let rate = factor.finiteOrZero
        guard rate > 0, rate != 1 else { return self }
        return HapticPattern(events.map { $0.timeScaled(by: rate) })
    }

    /// The same pattern back to front, so what landed last now lands first.
    public func reversed() -> HapticPattern {
        guard !isEmpty else { return self }
        let span = duration
        return HapticPattern(events.map { $0.moved(to: span - $0.endTime) })
    }
}
