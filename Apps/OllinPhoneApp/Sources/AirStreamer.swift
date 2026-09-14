import Foundation
import CoreMotion

/// Streams the barometer: how hard the air presses, and how far the phone has
/// risen since it started measuring.
///
/// Every iPhone since the 6 has one, and it is the one sensor here that reads
/// the room without looking at it, so it needs no camera and rides beside
/// whichever mode is running. It is a switch rather than a mode for the reason
/// Hear is: the altimeter asks its own permission (Motion & Fitness), and a
/// permission sheet during a performance is the thing to avoid.
///
/// CoreMotion reports a reading about once a second, and the altitude it reports
/// is **relative**: meters above wherever the phone was when the updates began.
/// A barometer knows how the pressure changed far better than it knows how high
/// it is, so that is the honest number, and it is the useful one: lifting the
/// phone off a table moves it.
///
/// Updates are delivered on the main queue, so `onAir` fires on main.
final class AirStreamer {

    /// Fired (on the main thread) for each barometer reading.
    var onAir: ((PhoneAirSample) -> Void)?

    /// Fired (on the main thread) when readings cannot start, with the reason
    /// for the screen; `nil` once they are arriving.
    var onStatus: ((String?) -> Void)?

    private let altimeter = CMAltimeter()
    private(set) var isRunning = false

    /// Whether this phone has a barometer at all.
    static var isSupported: Bool { CMAltimeter.isRelativeAltitudeAvailable() }

    func start() {
        guard !isRunning else { return }
        guard Self.isSupported else {
            onStatus?("this device has no barometer")
            return
        }
        if CMAltimeter.authorizationStatus() == .denied {
            onStatus?("motion not allowed (Settings ▸ Ollin Capture)")
            return
        }
        isRunning = true
        onStatus?(nil)
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] reading, error in
            guard let self, self.isRunning else { return }
            guard let reading else {
                self.onStatus?(error.map { "the barometer stopped: \($0.localizedDescription)" }
                               ?? "the barometer stopped")
                return
            }
            // CoreMotion reports the pressure in kilopascals and the altitude in
            // meters, which is what the wire carries: no conversion, so nothing
            // to get wrong in two places.
            self.onAir?(PhoneAirSample(timestamp: reading.timestamp,
                                       pressure: reading.pressure.floatValue,
                                       altitude: reading.relativeAltitude.floatValue))
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        altimeter.stopRelativeAltitudeUpdates()
    }
}
