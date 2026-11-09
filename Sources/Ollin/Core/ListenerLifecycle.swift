import Foundation
import Network
import os

/// The life of a socket that listens, as one value: what a receiver's
/// `isRunning`, `boundPort`, and `lastError` read, written only by the
/// listener's own state handler and by its `start()` and `stop()`.
///
/// Shared by every receiver that opens an `NWListener` (OSC, and TUIO over it,
/// DMX, the laser's finder, the query server's HTTP side), so a port that was
/// taken reads the same way everywhere: the listener fails, `isRunning` turns
/// false, `boundPort` is `nil`, and `lastError` says which port and why. The
/// system reports that failure to the listener's handler a moment after
/// `start()` returns, which is too late to throw, so it has to be readable.
package final class ListenerLifecycle: @unchecked Sendable {

    /// Where the listener is in its life.
    package enum Phase: Sendable, Equatable {
        /// Not started, or stopped.
        case idle
        /// `start()` handed a listener to the system, which has not answered.
        case binding
        /// The system could not bind yet and is trying again on its own;
        /// `lastError` says what it is waiting on.
        case waiting
        /// Bound and receiving; `port` says where.
        case ready
        /// The bind failed for good; `lastError` says why. `start()` tries
        /// again with a new listener.
        case failed
    }

    private struct State: Sendable {
        var phase: Phase = .idle
        var requested: UInt16 = 0
        var port: UInt16?
        var lastError: String?
    }
    private let state = OSAllocatedUnfairLock(initialState: State())

    package init() {}

    package var phase: Phase { state.withLock { $0.phase } }

    /// The port in use once the listener is ready, or `nil`.
    package var port: UInt16? { state.withLock { $0.port } }

    /// Why the last bind failed, or what it is waiting on; `nil` once the
    /// listener is up, and until something goes wrong.
    package var lastError: String? { state.withLock { $0.lastError } }

    /// Whether the listener is alive: started, and neither failed nor stopped.
    package var isRunning: Bool {
        state.withLock { $0.phase == .binding || $0.phase == .waiting || $0.phase == .ready }
    }

    /// `start()` made a listener for `port` (0 for any) and handed it over.
    package func starting(port requested: UInt16) {
        state.withLock {
            $0.phase = .binding
            $0.requested = requested
            $0.port = nil
        }
    }

    /// The listener's own state, as its handler receives it. Returns `true`
    /// when the listener has failed and the caller should let it go, so that a
    /// later `start()` makes a new one rather than finding this one in the way.
    ///
    /// `port` is the listener's own number as the caller reads it off the
    /// listener it stored, which is `nil` until the listener is ready.
    @discardableResult
    package func listener(_ newState: NWListener.State, port: UInt16?) -> Bool {
        state.withLock { state in
            switch newState {
            case .setup:
                state.phase = .binding
            case .waiting(let error):
                state.phase = .waiting
                state.lastError = "waiting to open \(Self.name(of: state.requested)): \(Self.sentence(error))"
            case .ready:
                state.phase = .ready
                state.port = port
                state.lastError = nil
            case .failed(let error):
                state.phase = .failed
                state.port = nil
                state.lastError = "could not open \(Self.name(of: state.requested)): \(Self.sentence(error))"
                return true
            case .cancelled:
                // A failed listener is cancelled right after it fails, and a
                // stopped one after `stop()`: neither cancellation is news.
                if state.phase != .failed && state.phase != .idle {
                    state.phase = .idle
                    state.port = nil
                }
            @unknown default:
                break
            }
            return false
        }
    }

    /// `stop()` cancelled the listener. What went wrong last stays readable.
    package func stopped() {
        state.withLock {
            $0.phase = .idle
            $0.port = nil
        }
    }

    private static func name(of requested: UInt16) -> String {
        requested == 0 ? "a port" : "port \(requested)"
    }

    /// The system's error in the words `strerror` uses, for a sentence a sketch
    /// can draw: "Address already in use" rather than a code.
    package static func sentence(_ error: NWError) -> String {
        switch error {
        case .posix(let code):
            return String(cString: strerror(code.rawValue))
        case .dns(let code):
            return "DNS error \(code)"
        case .tls(let status):
            return "TLS error \(status)"
        default:
            return "\(error)"
        }
    }
}
