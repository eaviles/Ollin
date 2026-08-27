import AppKit
import Foundation
import IOKit
import Ollin

/// What is on the other end of a pattern.
public enum HapticHardware: String, Equatable, Sendable {

    /// A full haptic engine, which plays a pattern as it was written:
    /// strength, crispness, and length all arrive.
    case engine

    /// A trackpad that knocks. It has three feelings and one strength, so a
    /// pattern is translated before it is played (see ``TrackpadPlan``).
    case trackpad

    /// Nothing that can be felt.
    case none
}

/// Holds the one thing a machine can shake, and plays patterns on it.
///
/// One hub for the process, because there is one actuator: two sketches, or
/// two calls in one frame, are asking the same piece of hardware. Patterns
/// laid over each other merge into one stream of knocks, which is what the
/// hardware does anyway.
@MainActor
final class HapticHub {

    static let shared = HapticHub()

    // MARK: - Seams the tests replace

    /// Where a trackpad knock goes.
    var performer: NSHapticFeedbackPerformer = NSHapticFeedbackManager.defaultPerformer

    /// How a knock is put off until its moment. Tests replace this to read the
    /// timeline without waiting for it.
    var schedule: (Double, @escaping @MainActor () -> Void) -> Void = { delay, body in
        guard delay > 0 else { return body() }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated(body)
        }
    }

    /// The clock the spacing rule reads.
    var clock: () -> Double = { CFAbsoluteTimeGetCurrent() }

    /// Whether this machine has a trackpad that can knock. Tests replace it.
    var trackpadIsPresent: () -> Bool = { HapticHub.machineHasActuatingTrackpad() }

    /// Whether this machine has a full haptic engine. Tests replace it.
    var engineIsPresent: () -> Bool = { DeviceHaptics.isSupported }

    // MARK: - State

    /// An overall multiplier on everything played, the sketch's volume knob.
    var strength = 1.0

    private var engine: DeviceHaptics?
    private var hardwareCache: HapticHardware?
    private var generation = 0
    private var lastKnock = -Double.infinity
    private var notedSilence = false

    private init() {}

    // MARK: - Asking

    /// What this machine can do, worked out once and remembered.
    var hardware: HapticHardware {
        if let hardwareCache { return hardwareCache }
        let found: HapticHardware =
            if OllinApp.isRenderingHeadless { .none }
            else if engineIsPresent() { .engine }
            else if trackpadIsPresent() { .trackpad }
            else { .none }
        hardwareCache = found
        return found
    }

    /// Why nothing can be felt, or nil when something can.
    var unavailableReason: String? {
        guard hardware == .none else { return nil }
        if OllinApp.isRenderingHeadless {
            return "touch is felt at the moment it happens, so an export has nowhere to put it."
        }
        return "this machine has no trackpad that knocks and no haptic engine."
    }

    /// Forget what the hardware is, so it is worked out again. Tests call it
    /// after replacing a seam.
    func forgetHardware() {
        hardwareCache = nil
        engine = nil
    }

    // MARK: - Playing

    /// Play a pattern, starting now.
    func play(_ pattern: HapticPattern) {
        guard !pattern.isEmpty else { return }

        switch hardware {
        case .none:
            noteSilenceOnce()
        case .engine:
            if engine == nil { engine = DeviceHaptics() }
            engine?.play(pattern, strength: strength)
        case .trackpad:
            playOnTrackpad(pattern)
        }
    }

    /// Stop everything in flight.
    func stop() {
        generation += 1
        // Nothing is playing now, so the next knock has nothing to wait for.
        lastKnock = -Double.infinity
        engine?.stop()
    }

    private func playOnTrackpad(_ pattern: HapticPattern) {
        let mine = generation
        for knock in TrackpadPlan.knocks(for: pattern, strength: strength) {
            schedule(knock.time) { [weak self] in
                guard let self, mine == self.generation else { return }
                self.deliver(knock)
            }
        }
    }

    /// Send one knock, unless the hardware was asked for one too recently.
    ///
    /// The plan already spaces the knocks inside one pattern. This guards the
    /// other case: a sketch calling every frame, where each pattern is legal
    /// on its own and the pile of them is not.
    private func deliver(_ knock: TrackpadKnock) {
        let now = clock()
        guard now - lastKnock >= TrackpadPlan.minimumSpacing else { return }
        lastKnock = now
        performer.perform(knock.feel.systemPattern, performanceTime: .now)
    }

    private func noteSilenceOnce() {
        guard !notedSilence, let unavailableReason else { return }
        notedSilence = true
        FileHandle.standardError.write(Data(
            "⚠️ OllinHaptics: \(unavailableReason) The sketch runs, and plays nothing.\n".utf8))
    }

    // MARK: - Finding the hardware

    /// True when some pointing device attached to this machine can knock.
    ///
    /// The system hands back a performer whatever the machine is, and a
    /// machine with no actuator takes the call and does nothing, so asking the
    /// performer proves nothing. The device registry is the one place that
    /// says whether an actuator is there.
    nonisolated static func machineHasActuatingTrackpad() -> Bool {
        guard let matching = IOServiceMatching("AppleMultitouchDevice") else { return false }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return false
        }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            let value = IORegistryEntryCreateCFProperty(
                service, "ActuationSupported" as CFString, kCFAllocatorDefault, 0)
            if let flag = value?.takeRetainedValue() as? Bool, flag { return true }
        }
        return false
    }
}

extension TrackpadKnock.Feel {

    /// The system feeling this asks for.
    var systemPattern: NSHapticFeedbackManager.FeedbackPattern {
        switch self {
        case .soft: .generic
        case .level: .levelChange
        case .crisp: .alignment
        }
    }
}
