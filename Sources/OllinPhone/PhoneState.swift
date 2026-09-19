import Foundation
import Ollin

/// What the phone says it is doing, and what it made of what the sketch asked for.
///
/// Every other stream here describes the room. This one describes the phone, and
/// it exists because the traffic that runs *down* the cable would otherwise fail
/// in silence. A sketch asks for a mode with `use(_:)` and declares the pictures
/// to look for with `look(for:)`; this is the answer. Without it, a poster ARKit
/// judges too plain to recognize simply never arrives, with nothing on the Mac to
/// say why.
///
/// ```swift
/// if let state = device.latestState {
///     state.mode                       // PhoneCaptureMode, what it is running
///     state.isSupported                // false when the hardware isn't there
///     state.referenceCount             // how many pictures it is looking for
///     state.notes                      // what it could not use, in sentences
/// }
/// ```
///
/// It arrives when something changes rather than every frame, so read it as
/// standing state, not as an event.
public struct PhoneState: Sendable, Equatable {

    /// When the phone said it, in seconds on its own clock.
    public let timestamp: Double

    /// The mode the phone is running right now. A tap on its screen moves this,
    /// so a sketch that asked for one mode may find the person in another.
    public let mode: PhoneCaptureMode

    /// Whether the device can do that mode at all. False means the phone switched
    /// but the hardware is not there: no LiDAR for the room, no TrueDepth for the
    /// face, no body tracking on an older chip.
    public let isSupported: Bool

    /// How many reference pictures and objects the phone is looking for.
    public let referenceCount: Int

    /// Whether those references came from a sketch over the cable, rather than
    /// from files somebody dropped into the capture app's own folder.
    public let referencesAreDeclared: Bool

    /// The sentence the phone's own screen is showing.
    public let statusMessage: String

    /// What the phone could not use and what it assumed, one plain sentence each:
    /// a picture too flat to be found, a file it could not read, a width it had to
    /// guess. Empty when it has nothing to report.
    public let notes: [String]

    /// Stage a reading with no phone attached (the tests and the Guide figure do).
    public init(timestamp: Double, mode: PhoneCaptureMode, isSupported: Bool = true,
                referenceCount: Int = 0, referencesAreDeclared: Bool = false,
                statusMessage: String = "", notes: [String] = []) {
        self.timestamp = timestamp
        self.mode = mode
        self.isSupported = isSupported
        self.referenceCount = referenceCount
        self.referencesAreDeclared = referencesAreDeclared
        self.statusMessage = statusMessage
        self.notes = notes
    }

    /// Wrap a decoded wire sample.
    public init(_ sample: PhoneStateSample) {
        timestamp = sample.timestamp
        mode = sample.mode
        isSupported = sample.isSupported
        referenceCount = sample.referenceCount
        referencesAreDeclared = sample.referencesAreDeclared
        statusMessage = sample.status
        notes = sample.notes
    }

    /// Whether the phone is looking for anything at all.
    public var isLookingForAnything: Bool { referenceCount > 0 }
}
