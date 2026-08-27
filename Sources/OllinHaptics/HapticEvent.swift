import Foundation

/// One felt moment: a tap you notice at an instant, or a hum you feel for a
/// while.
///
/// An event is a plain value. It knows when it happens, how strong it is, and
/// how crisp it is, and nothing about the hardware that will play it. Build
/// events into a ``HapticPattern`` and hand that to the sketch.
///
/// ```swift
/// let click = HapticEvent(.tap, at: 0, intensity: 0.9, sharpness: 0.8)
/// let purr = HapticEvent(.hum, at: 0.1, intensity: 0.4, sharpness: 0.1, duration: 0.5)
/// ```
public struct HapticEvent: Equatable, Sendable {

    /// What kind of moment this is.
    public enum Kind: String, Equatable, Sendable, CaseIterable {
        /// A single knock, felt at one instant. It has no length.
        case tap
        /// A sustained buzz that lasts as long as its duration.
        case hum
    }

    /// A tap or a hum.
    public let kind: Kind

    /// When it happens, in seconds from the start of the pattern.
    ///
    /// Never negative: an earlier time clamps to zero.
    public let time: Double

    /// How strong it feels, from 0 (nothing) to 1 (as much as the hardware
    /// gives).
    public let intensity: Double

    /// How crisp it feels, from 0 (a dull thud) to 1 (a tight click).
    public let sharpness: Double

    /// How long a hum lasts, in seconds. A tap is always 0.
    public let duration: Double

    /// How long a hum takes to arrive, in seconds. 0 starts it at full
    /// strength. Ignored by a tap.
    public let fadeIn: Double

    /// How long a hum takes to leave, in seconds. 0 cuts it off. Ignored by a
    /// tap.
    public let fadeOut: Double

    /// Build one event. Every number is clamped into range, so a pattern can
    /// be driven straight from a sketch value without guarding it first.
    public init(
        _ kind: Kind,
        at time: Double = 0,
        intensity: Double = 1,
        sharpness: Double = 0.5,
        duration: Double = 0,
        fadeIn: Double = 0,
        fadeOut: Double = 0
    ) {
        self.kind = kind
        self.time = max(0, time.finiteOrZero)
        self.intensity = intensity.finiteOrZero.clamped01
        self.sharpness = sharpness.finiteOrZero.clamped01
        // A tap is an instant, so it never carries a length or an envelope.
        let span = kind == .hum ? max(0, duration.finiteOrZero) : 0
        self.duration = span
        self.fadeIn = min(max(0, fadeIn.finiteOrZero), span)
        self.fadeOut = min(max(0, fadeOut.finiteOrZero), span)
    }

    /// When this event is over, in seconds from the start of the pattern.
    public var endTime: Double { time + duration }

    /// How strong this event is at a moment inside it, once its fades are
    /// applied. The offset is measured from the event's own start.
    ///
    /// A tap is an instant, so it is always at full strength. A hum follows
    /// its fades: it climbs over `fadeIn`, holds, and falls over `fadeOut`.
    /// Reach for it to draw a pattern, or to drive something else from the
    /// same shape the hand is being given.
    public func strength(at offset: Double) -> Double {
        guard kind == .hum, duration > 0 else { return intensity }
        var shape = 1.0
        if fadeIn > 0 { shape = min(shape, offset / fadeIn) }
        if fadeOut > 0 { shape = min(shape, (duration - offset) / fadeOut) }
        return intensity * shape.clamped01
    }

    /// The same event moved along the timeline.
    public func delayed(by seconds: Double) -> HapticEvent {
        moved(to: time + seconds)
    }

    /// The same event at a new time.
    func moved(to newTime: Double) -> HapticEvent {
        HapticEvent(
            kind,
            at: newTime,
            intensity: intensity,
            sharpness: sharpness,
            duration: duration,
            fadeIn: fadeIn,
            fadeOut: fadeOut)
    }

    /// The same event with its strength multiplied.
    func scaled(intensity factor: Double) -> HapticEvent {
        HapticEvent(
            kind,
            at: time,
            intensity: intensity * factor,
            sharpness: sharpness,
            duration: duration,
            fadeIn: fadeIn,
            fadeOut: fadeOut)
    }

    /// The same event with every time divided by `factor`, so 2 plays it twice
    /// as fast.
    func timeScaled(by factor: Double) -> HapticEvent {
        HapticEvent(
            kind,
            at: time / factor,
            intensity: intensity,
            sharpness: sharpness,
            duration: duration / factor,
            fadeIn: fadeIn / factor,
            fadeOut: fadeOut / factor)
    }
}

extension Double {
    /// A number that is safe to store. A calculation in a sketch can hand over
    /// a NaN or an infinity, and one of those in a pattern turns into a
    /// scheduling loop that never ends.
    var finiteOrZero: Double { isFinite ? self : 0 }

    var clamped01: Double { Swift.min(Swift.max(0, self), 1) }
}
