import Foundation
import Ollin

/// What the phone's barometer reads: how hard the air presses, and how far the
/// phone has risen since it started measuring.
///
/// Every iPhone since the 6 has a barometer, and it is the one sensor here that
/// reads the room without looking at it. It needs no camera, so it arrives
/// beside whichever mode is running, once the capture app's **Air** switch is
/// on (the altimeter asks its own permission there).
///
/// `altitude` is relative on purpose, and it is the surprising one. A barometer
/// knows how the pressure has *changed* far better than it knows how high it is,
/// so the number starts at zero where the phone was switched on and answers
/// "how much higher than that", to about a tenth of a meter. Lift the phone off
/// a table and the number moves. It goes below zero going down.
///
/// ```swift
/// if let air = device.latestAir {
///     let lift = air.altitude            // meters above where it started
///     drawCircle(center: bounds.center, radius: 120 + lift * 200)
/// }
/// ```
///
/// `pressure` is the weather's own number, in kilopascals: about 101.3 at sea
/// level, falling roughly 0.12 for every ten meters up. A door opening in a
/// sealed room moves it, and so does a storm arriving over a day.
public struct PhoneAir: Sendable, Equatable {

    /// When the phone read it, in seconds on its own clock.
    public let timestamp: Double

    /// How hard the air presses, in kilopascals. Sea level is about 101.3.
    public let pressure: Double

    /// Meters above where the phone was when it started measuring. Negative
    /// going down.
    public let altitude: Double

    /// Stage a reading with no phone attached (the tests and the Guide figure do).
    public init(timestamp: Double, pressure: Double, altitude: Double) {
        self.timestamp = timestamp
        self.pressure = pressure
        self.altitude = altitude
    }

    /// Wrap a decoded wire sample.
    public init(_ sample: PhoneAirSample) {
        timestamp = sample.timestamp
        pressure = Double(sample.pressure)
        altitude = Double(sample.altitude)
    }

    /// The pressure in hectopascals, the unit a weather report uses (1 kPa is
    /// 10 hPa, so sea level reads about 1013).
    public var hectopascals: Double { pressure * 10 }
}
