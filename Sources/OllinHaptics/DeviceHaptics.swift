import CoreHaptics
import Foundation

/// Plays a pattern on a full haptic engine, where strength, crispness, and
/// length all arrive as written.
///
/// A Mac reports no such engine today: its trackpad is reached through the
/// window system instead, and asking the haptic engine for hardware on this
/// machine answers `notSupported`. The path is here because it is the same
/// path a phone or a pad uses, and because the translation into it can be
/// checked without hardware: the pattern is built and read back in the tests.
///
/// Not on the main actor on purpose. The engine calls back from its own
/// thread when it stops or resets, and a closure built in a main-actor
/// context and then called from another thread ends the process.
final class DeviceHaptics: @unchecked Sendable {

    /// Whether this machine has an engine to play on.
    static var isSupported: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    private let lock = NSLock()
    private var engine: CHHapticEngine?
    private var players: [CHHapticPatternPlayer] = []

    init() {}

    /// Play a pattern now, starting the engine if it is not running.
    func play(_ pattern: HapticPattern, strength: Double) {
        guard let built = try? Self.makePattern(from: pattern, strength: strength) else { return }
        lock.lock()
        defer { lock.unlock() }
        do {
            let running = try startedEngine()
            let player = try running.makePlayer(with: built)
            try player.start(atTime: CHHapticTimeImmediate)
            players.append(player)
            if players.count > 32 { players.removeFirst(players.count - 32) }
        } catch {
            // A pattern that cannot be played is silence, not a crash: a
            // sketch keeps drawing.
            engine = nil
        }
    }

    /// Stop everything and let the engine go quiet.
    func stop() {
        lock.lock()
        defer { lock.unlock() }
        for player in players { try? player.cancel() }
        players.removeAll()
        engine?.stop(completionHandler: nil)
        engine = nil
    }

    private func startedEngine() throws -> CHHapticEngine {
        if let engine { return engine }
        let made = try CHHapticEngine()
        made.playsHapticsOnly = true
        made.isAutoShutdownEnabled = true
        made.stoppedHandler = { _ in }
        made.resetHandler = { [weak made] in try? made?.start() }
        try made.start()
        engine = made
        return made
    }

    // MARK: - The translation

    /// What went wrong on the way to the system.
    enum TranslationError: Error {
        /// Everything was silence, or was turned down to it.
        case nothingToPlay
    }

    /// The system pattern for one of ours.
    ///
    /// Throws when there is nothing left to play, which is what an empty
    /// pattern or one made only of silence comes to. The system itself accepts
    /// a pattern with no events, so this is our own guard: a player built on
    /// nothing starts an engine for silence.
    static func makePattern(from pattern: HapticPattern, strength: Double) throws -> CHHapticPattern {
        let events = events(from: pattern, strength: strength)
        guard !events.isEmpty else { throw TranslationError.nothingToPlay }
        return try CHHapticPattern(events: events, parameters: [])
    }

    /// The system events for ours, in order.
    ///
    /// A tap is an instant, so it carries strength and crispness only. A hum
    /// carries its length as well, and its fades ride the system's own
    /// envelope, which is measured as a share of the event rather than in
    /// seconds. So a fade arrives in the right direction and about the right
    /// size, not to the millisecond.
    static func events(from pattern: HapticPattern, strength: Double) -> [CHHapticEvent] {
        let scale = max(0, strength.finiteOrZero)
        return pattern.events.compactMap { event in
            let level = (event.intensity * scale).clamped01
            guard level > 0 else { return nil }

            var parameters = [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(level)),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(event.sharpness)),
            ]

            switch event.kind {
            case .tap:
                return CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: parameters,
                    relativeTime: event.time)
            case .hum:
                let span = max(event.duration, 0.001)
                parameters.append(CHHapticEventParameter(
                    parameterID: .attackTime, value: Float((event.fadeIn / span).clamped01)))
                parameters.append(CHHapticEventParameter(
                    parameterID: .releaseTime, value: Float((event.fadeOut / span).clamped01)))
                parameters.append(CHHapticEventParameter(parameterID: .sustained, value: 1))
                return CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: parameters,
                    relativeTime: event.time,
                    duration: event.duration)
            }
        }
    }
}
