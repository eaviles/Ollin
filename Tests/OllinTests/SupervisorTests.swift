import Foundation
import Testing
@testable import Ollin

/// Probes for the watch kept over a piece that has to get itself back up.
///
/// The supervisor itself starts processes, which no test should do, so what is
/// checked here is every rule it decides with: who watches whom, what counts as
/// a stall, what counts as an ordinary end, and how long it waits before trying
/// again. Each one is a small pure answer, and each one is a way the feature
/// fails silently if it is wrong: a watch that never starts, a piece killed for
/// loading a film, a dark wall reported as a tidy shutdown, a launch loop all
/// night.
@Suite
struct SupervisorTests {

    // MARK: Who watches whom

    @Test func aRunNobodyAskedToWatchIsNotWatched() {
        #expect(Supervisor.stallLimit(watching: .on, in: [:]) == nil)
        #expect(Supervisor.stallLimit(watching: .off, in: [:]) == nil)
        #expect(Supervisor.stallLimit(watching: Installation(restarts: .onFailure),
                                      in: [:]) == 30)
        #expect(Supervisor.stallLimit(watching: Installation(restarts: .onFailure(stalledAfter: 5)),
                                      in: [:]) == 5)
    }

    /// The one that would run away: a supervisor whose child supervises in turn
    /// makes a new process at every level. The marker in the child's own
    /// environment is what stops it, so it is checked through the environment
    /// the supervisor actually builds rather than a hand-written one.
    @Test func theChildOfASupervisorNeverSupervises() {
        let asked = Installation(restarts: .onFailure)
        let environment = Supervisor.childEnvironment(["PATH": "/usr/bin"],
                                                      heartbeat: URL(fileURLWithPath: "/tmp/beat"))
        #expect(Supervisor.stallLimit(watching: asked, in: environment) == nil)
        // And the child is still handed everything it had before.
        #expect(environment["PATH"] == "/usr/bin")
        #expect(environment[Supervisor.heartbeatKey] == "/tmp/beat")
    }

    /// Working on a piece that watches itself: the flag that puts it back in an
    /// ordinary window takes the watch off with it, so a crash stays crashed
    /// where you can read it.
    @Test @MainActor func theFlagThatEndsAnInstallationEndsTheWatch() {
        final class Watched: Sketch {
            override var installation: Installation { Installation(restarts: .onFailure) }
        }
        let ordinary = Installation.resolved(for: Watched(), arguments: ["x", "--no-installation"])
        #expect(Supervisor.stallLimit(watching: ordinary, in: [:]) == nil)
    }

    // MARK: What counts as a stall

    @Test func aPieceStillDrawingIsNotStalled() {
        #expect(!Supervisor.hasStalled(quietFor: 3, answered: true, limit: 30))
        #expect(Supervisor.hasStalled(quietFor: 31, answered: true, limit: 30))
    }

    /// A `setup()` that loads a model, a film, or a scene blocks the main thread
    /// before the first frame, so the piece cannot answer yet. Killing it there
    /// would leave a heavy piece unable to start at all, restarting for ever.
    @Test func aPieceStillLoadingGetsLongerThanTheLimit() {
        #expect(!Supervisor.hasStalled(quietFor: 60, answered: false, limit: 30))
        #expect(Supervisor.hasStalled(quietFor: Supervisor.startupGrace + 1,
                                      answered: false, limit: 30))
        // A limit longer than the grace is honored as stated.
        #expect(!Supervisor.hasStalled(quietFor: Supervisor.startupGrace + 1,
                                       answered: false, limit: 600))
    }

    @Test func aPieceThatMeansToBlockIsNeverStalled() {
        #expect(!Supervisor.hasStalled(quietFor: 86_400, answered: true, limit: 0))
    }

    /// How long the piece has been quiet: since its last answer, and since it
    /// started when it has not answered yet.
    @Test func quietIsMeasuredFromTheLastAnswer() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-test-beat-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        let now = Date()

        // Nothing written yet: measured from the start of the run.
        #expect(abs(Supervisor.quietFor(heartbeat: file,
                                        since: now.addingTimeInterval(-12),
                                        now: now) - 12) < 0.01)

        try Data("beat".utf8).write(to: file)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-40)], ofItemAtPath: file.path)
        #expect(abs(Supervisor.quietFor(heartbeat: file,
                                        since: now.addingTimeInterval(-3600),
                                        now: now) - 40) < 0.01)
    }

    // MARK: What counts as an ordinary end

    @Test func quittingThePieceEndsTheWatch() {
        #expect(Supervisor.Ending(status: 0, onSignal: false).isClean)
    }

    @Test func aCrashIsNotAnOrdinaryEnd() {
        #expect(!Supervisor.Ending(status: 1, onSignal: false).isClean)
        #expect(!Supervisor.Ending(status: SIGSEGV, onSignal: true).isClean)
    }

    /// The one that would leave a wall dark. A stalled piece is stopped with the
    /// same signal a person stops a run with, and a piece that saves its state
    /// on the way out answers it by exiting tidily. Read by the status alone,
    /// that is indistinguishable from somebody quitting the piece, and the
    /// supervisor would go home.
    @Test func aStalledPieceThatExitsTidilyStillCountsAsAFailure() {
        #expect(!Supervisor.Ending(status: 0, onSignal: false, stalled: true).isClean)
        #expect(Supervisor.Ending(status: 0, onSignal: false, stalled: true)
                    .reason == "stopped answering")
    }

    // MARK: How long it waits

    @Test func aPieceThatRanForDaysComesStraightBack() {
        var policy = RestartPolicy()
        #expect(policy.next(ranFor: 3 * 86_400) == .restart(after: 1))
        #expect(policy.strikes == 0)
    }

    /// A piece that fails a second after it starts is broken in a way that
    /// starting it again does not fix, so each try waits longer than the last
    /// and the fifth one stops.
    @Test func aFailureAtStartupBacksOffAndThenGivesUp() {
        var policy = RestartPolicy()
        var waits: [Double] = []
        for _ in 0..<4 {
            guard case .restart(let after) = policy.next(ranFor: 0.4) else {
                Issue.record("gave up too early")
                return
            }
            waits.append(after)
        }
        #expect(waits == waits.sorted())                 // each one waits longer
        #expect(waits.first! < waits.last!)              // measurably so
        #expect(policy.next(ranFor: 0.4) == .giveUp)
    }

    /// One good run clears the record, so a piece that fails once a week runs
    /// for ever rather than using up its tries over a month.
    @Test func aGoodRunClearsTheStrikes() {
        var policy = RestartPolicy()
        _ = policy.next(ranFor: 0.5)
        _ = policy.next(ranFor: 0.5)
        #expect(policy.strikes == 2)
        _ = policy.next(ranFor: 600)
        #expect(policy.strikes == 0)
    }

    // MARK: The piece's side

    @Test @MainActor func aRunNobodyIsWatchingDoesNotAnswer() {
        #expect(Heartbeat.start(environment: [:]) == nil)
        #expect(Heartbeat.start(environment: [Supervisor.heartbeatKey: ""]) == nil)
    }

    @Test @MainActor func aWatchedRunAnswersAtOnce() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-test-beat-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        let heartbeat = try #require(Heartbeat.start(
            environment: [Supervisor.heartbeatKey: file.path]))
        defer { heartbeat.stop() }
        // The first answer is written on the spot rather than a beat later: the
        // supervisor is already watching, and a piece that takes its first
        // couple of seconds to say anything is a piece already being counted as
        // slow to start.
        #expect(FileManager.default.fileExists(atPath: file.path))
    }
}
