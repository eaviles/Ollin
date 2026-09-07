import Foundation

/// A point on the Earth: latitude and longitude in degrees.
///
/// North and east are positive, so Mexico City is
/// `Place(latitude: 19.43, longitude: -99.13)`. A `Weather` reads the sky over
/// one, and `sun(at:)` says where the sun is from there at any moment, with no
/// network at all.
public struct Place: Hashable, Sendable {

    /// Degrees north of the equator, `-90...90`.
    public var latitude: Double

    /// Degrees east of Greenwich, `-180...180`.
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Where the sun is in the sky from one place at one moment.
public struct SunPosition: Hashable, Sendable {

    /// Degrees above the horizon. Negative at night, up to 90 straight overhead.
    /// This is the geometric height of the sun's center; the air bends the
    /// light enough that the disc shows a little before it reaches zero.
    public var elevation: Double

    /// Degrees clockwise from north: 90 is east, 180 south, 270 west.
    public var azimuth: Double

    /// Whether any of the disc is showing. The sun's upper edge appears when
    /// its center is about 0.83 degrees below the horizon, refraction included.
    public var isUp: Bool { elevation > -0.833 }

    public init(elevation: Double, azimuth: Double) {
        self.elevation = elevation
        self.azimuth = azimuth
    }
}

extension Place {

    /// Where the sun is from here at `date`, computed rather than fetched.
    ///
    /// ```swift
    /// let sun = place.sun(at: Date())
    /// let y = horizon - sun.elevation / 90 * height * 0.7
    /// ```
    ///
    /// The position comes from the standard low-precision solar model (the
    /// one the NOAA solar calculator uses), good to a small fraction of a
    /// degree for any date within a few centuries of now. It is enough to put
    /// the sun where a viewer would look for it, and to know when it rises
    /// and sets, which is what a picture needs.
    public func sun(at date: Date = Date()) -> SunPosition {
        func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
        func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
        func wrapped(_ degrees: Double) -> Double {
            let m = degrees.truncatingRemainder(dividingBy: 360)
            return m < 0 ? m + 360 : m
        }

        // Julian day and the centuries since J2000, the model's clock.
        let julianDay = date.timeIntervalSince1970 / 86400 + 2440587.5
        let t = (julianDay - 2451545) / 36525

        // The sun's mean longitude and anomaly, then the correction that
        // turns the mean orbit into the real one.
        let meanLongitude = wrapped(280.46646 + t * (36000.76983 + t * 0.0003032))
        let meanAnomaly = 357.52911 + t * (35999.05029 - 0.0001537 * t)
        let eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let center = sin(radians(meanAnomaly)) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(radians(2 * meanAnomaly)) * (0.019993 - 0.000101 * t)
            + sin(radians(3 * meanAnomaly)) * 0.000289
        let node = 125.04 - 1934.136 * t
        let apparentLongitude = meanLongitude + center - 0.00569 - 0.00478 * sin(radians(node))

        // The tilt of the Earth's axis, and from it the sun's declination.
        let meanObliquity = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let obliquity = meanObliquity + 0.00256 * cos(radians(node))
        let declination = asin(sin(radians(obliquity)) * sin(radians(apparentLongitude)))

        // The equation of time, in minutes: how far sundial noon sits from
        // clock noon on this date.
        let y = tan(radians(obliquity / 2)) * tan(radians(obliquity / 2))
        let l0 = radians(meanLongitude), m = radians(meanAnomaly), e = eccentricity
        let equationOfTime = 4 * degrees(
            y * sin(2 * l0) - 2 * e * sin(m) + 4 * e * y * sin(m) * cos(2 * l0)
                - 0.5 * y * y * sin(4 * l0) - 1.25 * e * e * sin(2 * m))

        // True solar time here, then the hour angle: how far the sun is past
        // the local meridian.
        let dayFraction = (julianDay + 0.5) - floor(julianDay + 0.5)
        var solarMinutes = (dayFraction * 1440 + equationOfTime + 4 * longitude)
            .truncatingRemainder(dividingBy: 1440)
        if solarMinutes < 0 { solarMinutes += 1440 }
        let hourAngle = solarMinutes / 4 - 180

        let phi = radians(latitude)
        let cosZenith = sin(phi) * sin(declination)
            + cos(phi) * cos(declination) * cos(radians(hourAngle))
        let zenith = acos(max(-1, min(1, cosZenith)))
        let elevation = 90 - degrees(zenith)

        let sinZenith = sin(zenith)
        let azimuth: Double
        if abs(sinZenith) < 1e-9 || abs(cos(phi)) < 1e-9 {
            azimuth = 180
        } else {
            let cosAzimuth = (sin(phi) * cos(zenith) - sin(declination)) / (cos(phi) * sinZenith)
            let a = degrees(acos(max(-1, min(1, cosAzimuth))))
            azimuth = hourAngle > 0 ? wrapped(a + 180) : wrapped(540 - a)
        }
        return SunPosition(elevation: elevation, azimuth: azimuth)
    }
}
