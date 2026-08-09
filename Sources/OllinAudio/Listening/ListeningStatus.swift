import Foundation
import os

/// Tracks whether a listener can actually run here, so a sketch that hears
/// nothing can say why instead of sitting silently empty.
///
/// A listener starts assumed available and flips when something establishes it
/// cannot work: a speech model that has no assets for the chosen language, a
/// Core ML model that will not load, an export where nothing is playing. The
/// reason is a sentence a sketch can draw:
///
/// ```swift
/// if let reason = ears.unavailableReason { return drawStatus(reason, style: .warning) }
/// ```
///
/// `@unchecked Sendable`: all state lives under the lock.
final class ListeningStatus: @unchecked Sendable {

    private struct State {
        var reason: String?
        var logged = false
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Whether the listener is running.
    var isAvailable: Bool { state.withLock { $0.reason == nil } }

    /// Why it is not, or `nil` while it is.
    var reason: String? { state.withLock { $0.reason } }

    /// Something worked, so clear any prior reason (a model that finished
    /// installing recovers on its own).
    func recordSuccess() {
        state.withLock { if $0.reason != nil { $0.reason = nil } }
    }

    /// Record why the listener cannot run, logging once so it is also visible
    /// from `swift run`.
    func markUnavailable(_ reason: String) {
        let shouldLog = state.withLock { state -> Bool in
            state.reason = reason
            if state.logged { return false }
            state.logged = true
            return true
        }
        if shouldLog {
            FileHandle.standardError.write(Data("⚠️ OllinAudio: \(reason)\n".utf8))
        }
    }
}
