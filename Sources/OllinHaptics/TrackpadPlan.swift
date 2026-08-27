import Foundation

/// One knock asked of a trackpad, at a moment measured from the start of the
/// pattern.
public struct TrackpadKnock: Equatable, Sendable {

    /// Which of the three feelings the system offers.
    public enum Feel: String, Equatable, Sendable, CaseIterable {
        /// The softest of the three.
        case soft
        /// The middle one, the feel of a control passing a step.
        case level
        /// The crispest, the feel of an edge snapping into place.
        case crisp
    }

    /// When it fires, in seconds from the start of the pattern.
    public let time: Double

    /// How it should feel.
    public let feel: Feel

    public init(time: Double, feel: Feel) {
        self.time = time
        self.feel = feel
    }
}

/// Turns a pattern into the knocks a trackpad can actually deliver.
///
/// The trackpad is not a small speaker. It gives three fixed feelings and one
/// fixed strength, and it gives them one at a time. So a pattern is planned
/// before it is played, and the plan is where the honest translation happens:
///
/// - **Sharpness picks the feeling.** A dull event asks for the soft one, a
///   crisp event asks for the crisp one.
/// - **Strength becomes density.** The hardware has one strength, so a strong
///   hum arrives as a fast train of knocks and a weak one as a slow one. This
///   is rate coding: the hand reads a faster train as a stronger buzz.
/// - **A fade thins the train** rather than lowering it, for the same reason.
/// - **Anything under the floor is dropped**, so a pattern that fades to
///   nothing ends in silence instead of a last stray knock.
/// - **Knocks closer than the spacing are dropped**, so a sketch that asks for
///   more than the hardware can do gets the most it can do rather than a
///   backlog.
///
/// The plan is a pure function of the pattern, which is what makes the whole
/// translation testable with no hardware in the room.
public enum TrackpadPlan {

    /// Below this strength an event is not planned at all.
    public static let silenceFloor = 0.05

    /// The shortest gap between two knocks, in seconds. About 50 a second,
    /// which is past the rate a hand can separate.
    public static let minimumSpacing = 0.02

    /// The knock rate of the weakest hum that still gets planned.
    public static let slowestHum = 6.0

    /// The knock rate of a hum at full strength.
    public static let fastestHum = 30.0

    /// A ceiling on the knocks one pattern can plan, so a very long hum cannot
    /// grow without bound.
    static let maximumKnocks = 4096

    /// The knocks for one pattern, earliest first.
    ///
    /// - Parameters:
    ///   - pattern: what the sketch asked for.
    ///   - strength: an overall multiplier, the sketch's own volume knob.
    public static func knocks(for pattern: HapticPattern, strength: Double = 1) -> [TrackpadKnock] {
        let scale = max(0, strength.finiteOrZero)
        var planned: [TrackpadKnock] = []

        for event in pattern.events {
            switch event.kind {
            case .tap:
                let level = event.intensity * scale
                guard level >= silenceFloor else { continue }
                planned.append(TrackpadKnock(time: event.time, feel: feel(forSharpness: event.sharpness)))
            case .hum:
                planned.append(contentsOf: train(for: event, scale: scale))
            }
            if planned.count > maximumKnocks { break }
        }

        planned.sort { $0.time < $1.time }
        return spaced(planned)
    }

    /// The knocks that stand in for one hum.
    private static func train(for event: HapticEvent, scale: Double) -> [TrackpadKnock] {
        guard event.duration > 0 else { return [] }
        let feeling = feel(forSharpness: event.sharpness)
        var knocks: [TrackpadKnock] = []
        var offset = 0.0

        while offset <= event.duration, knocks.count < maximumKnocks {
            let level = event.strength(at: offset) * scale
            if level >= silenceFloor {
                knocks.append(TrackpadKnock(time: event.time + offset, feel: feeling))
                offset += 1 / rate(forStrength: level)
            } else {
                // Inside a fade the train has not started, or has ended. Step
                // by the slowest rate to find where it picks up again, rather
                // than crawling by the smallest gap.
                offset += 1 / slowestHum
            }
        }
        return knocks
    }

    /// How many knocks a second stand in for a given strength.
    static func rate(forStrength level: Double) -> Double {
        slowestHum + (fastestHum - slowestHum) * level.clamped01
    }

    /// Which feeling a sharpness asks for.
    static func feel(forSharpness sharpness: Double) -> TrackpadKnock.Feel {
        switch sharpness {
        case ..<(1.0 / 3.0): .soft
        case ..<(2.0 / 3.0): .level
        default: .crisp
        }
    }

    /// Drops any knock that lands too soon after the one before it.
    private static func spaced(_ knocks: [TrackpadKnock]) -> [TrackpadKnock] {
        var kept: [TrackpadKnock] = []
        kept.reserveCapacity(knocks.count)
        var last = -Double.infinity
        for knock in knocks where knock.time - last >= minimumSpacing {
            kept.append(knock)
            last = knock.time
        }
        return kept
    }
}
