import Foundation

/// A probe that never returned a value before its time ran out.
package struct Timeout: Error, CustomStringConvertible {
    /// How long the wait was allowed.
    package var seconds: Double

    package init(seconds: Double) {
        self.seconds = seconds
    }

    package var description: String { "nothing arrived in \(seconds) s" }
}

/// Polls `probe` every five milliseconds until it returns a value, and throws
/// `Timeout` once `timeout` seconds have passed without one.
///
/// The probe comes before the clock is read, and the order is load-bearing. A
/// test body runs on the cooperative pool, and a full run can starve a task
/// past its own deadline without it having looked once; a deadline test placed
/// first then throws over an answer that is already sitting there. Measured on
/// 2026-08-29: thirteen feed tests threw together inside a 3,107-test run,
/// every one of them with the stub's answer in hand. Poll `>=` on a counter
/// rather than `==` for the same reason, since by the first look the counter
/// may have moved past the value the test wanted.
///
/// Three seconds is the budget for a value that arrives over a loopback on a
/// quiet machine. A suite that waits on something slower (a session converging
/// over multicast, a feed under a full run) names its own budget at the call,
/// or in a one-line forwarder that says why.
///
/// The wait runs on the caller's actor (`#isolation`), so a main-actor suite
/// can hand it a probe that reads main-actor state, and nothing crosses an
/// isolation boundary.
package func waitFor<T>(timeout: Double = 3.0, isolation: isolated (any Actor)? = #isolation,
                        _ probe: () -> T?) async throws -> T {
    let deadline = Date().addingTimeInterval(timeout)
    while true {
        if let value = probe() { return value }
        if Date() >= deadline { throw Timeout(seconds: timeout) }
        try await Task.sleep(nanoseconds: 5_000_000)
    }
}
