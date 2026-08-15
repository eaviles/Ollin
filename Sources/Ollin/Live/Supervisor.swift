import Foundation
import os

/// Starts the piece again when it stops badly.
///
/// A run at a desk ends when somebody quits it. A run on a wall ends in the
/// other ways: a crash at three in the morning, a frame that never finishes, a
/// memory the piece ran out of on day four. Nobody is there, so the piece stays
/// dark until somebody notices, which can be a day later.
///
/// The shape is the plain one. The process a person starts becomes a small
/// supervisor that owns no window, and the piece runs as its child. The
/// supervisor waits. When the child ends badly it starts another one, and the
/// checkpoint the run was already writing is what brings the piece back where
/// it was rather than back at the beginning.
///
/// Two things count as ending badly, and the second is the one the system
/// cannot see for itself:
///
/// - **A crash.** The child ends with a bad exit status, or on a signal.
/// - **A stall.** The child is still there, and no longer answering. It is
///   found with a heartbeat: the piece writes one file every couple of seconds
///   from the main thread, and a main thread stuck in a frame stops writing it.
///   The supervisor stops a child that has gone quiet, then starts another.
///
/// The supervisor only ever exists on the standalone `OllinApp.run` path, the
/// one where a sketch owns its own process. A sketch under the live host or the
/// gallery is a guest in somebody else's window, so it never gets one.
final class Supervisor: @unchecked Sendable {

    /// Set in the child's environment, so a child never supervises in turn.
    static let marker = "OLLIN_SUPERVISED"
    /// The heartbeat file's path, handed to the child the same way.
    static let heartbeatKey = "OLLIN_HEARTBEAT"

    /// Become the supervisor when the sketch asked for one, and never return.
    /// Return at once when it did not, or when this process is already the
    /// child, so the caller goes on and opens the window.
    static func superviseIfAsked(_ installation: Installation,
                                 environment: [String: String]
                                    = ProcessInfo.processInfo.environment) {
        guard let stalledAfter = stallLimit(watching: installation, in: environment) else { return }
        guard let executable = Bundle.main.executableURL else {
            ollinInstallationLog("cannot watch this run: the piece's own path is unknown")
            return
        }
        Supervisor(executable: executable,
                   arguments: Array(CommandLine.arguments.dropFirst()),
                   stalledAfter: stalledAfter).run()
    }

    /// The limit a supervisor would watch this run with, or `nil` when this
    /// process should simply run the piece: either nobody asked for a watch, or
    /// this process is already the child of one.
    static func stallLimit(watching installation: Installation,
                           in environment: [String: String]) -> Double? {
        guard case .onFailure(let stalledAfter) = installation.restarts else { return nil }
        guard environment[marker] == nil else { return nil }
        return stalledAfter
    }

    /// What the child runs with: this process's own environment, plus the two
    /// values that tell the child it is one.
    static func childEnvironment(_ base: [String: String], heartbeat: URL) -> [String: String] {
        var environment = base
        environment[marker] = "1"
        environment[heartbeatKey] = heartbeat.path
        return environment
    }

    private let executable: URL
    private let arguments: [String]
    /// How long the piece may go without answering before it is stopped and
    /// started again. Zero waits forever, for a piece that means to block.
    private let stalledAfter: Double
    private let heartbeat: URL

    /// What the signal handlers reach, from whatever thread they run on.
    private struct Shared { var child: pid_t?; var stopping = false }
    private let shared = OSAllocatedUnfairLock(initialState: Shared())
    private var signalSources: [DispatchSourceSignal] = []

    init(executable: URL, arguments: [String], stalledAfter: Double) {
        self.executable = executable
        self.arguments = arguments
        self.stalledAfter = stalledAfter
        self.heartbeat = FileManager.default.temporaryDirectory
            .appendingPathComponent("ollin-heartbeat-\(ProcessInfo.processInfo.processIdentifier)")
    }

    // MARK: Running

    private func run() -> Never {
        catchStops()
        ollinInstallationLog("watching this run"
                             + (stalledAfter > 0
                                ? "; a piece that stops answering for \(Int(stalledAfter))s "
                                  + "is started again"
                                : ""))
        var policy = RestartPolicy()
        while true {
            let startedAt = Date()
            guard let child = start() else { finish(70) }   // EX_SOFTWARE
            let end = wait(for: child)
            let ranFor = Date().timeIntervalSince(startedAt)

            if shared.withLock({ $0.stopping }) {
                ollinInstallationLog("stopped")
                finish(0)
            }
            if end.isClean {
                ollinInstallationLog("the piece ended; not starting it again")
                finish(0)
            }
            switch policy.next(ranFor: ranFor) {
            case .giveUp:
                ollinInstallationLog("the piece has failed \(policy.strikes) times in a row "
                                     + "without running for long; giving up (\(end.reason))")
                finish(end.status == 0 ? 70 : end.status)
            case .restart(let after):
                ollinInstallationLog("the piece \(end.reason) after \(Int(ranFor))s; "
                                     + "starting it again in \(Int(after))s")
                Thread.sleep(forTimeInterval: after)
            }
        }
    }

    /// End the watch, taking the heartbeat file with it: it is named after this
    /// process, so a run that left one behind would litter one a launch.
    private func finish(_ code: Int32) -> Never {
        try? FileManager.default.removeItem(at: heartbeat)
        exit(code)
    }

    /// Start one run of the piece, with the marker and the heartbeat path in its
    /// environment. Its output is this process's output, so a log piped to a
    /// file keeps every run in the one file, in order.
    private func start() -> Process? {
        // Gone rather than stale: a missing file is how the wait below knows the
        // piece has not answered yet, which buys a slow `setup()` its own grace.
        try? FileManager.default.removeItem(at: heartbeat)
        let child = Process()
        child.executableURL = executable
        child.arguments = arguments
        child.environment = Self.childEnvironment(ProcessInfo.processInfo.environment,
                                                  heartbeat: heartbeat)
        do {
            try child.run()
        } catch {
            ollinInstallationLog("could not start the piece: \(error)")
            return nil
        }
        shared.withLock { $0.child = child.processIdentifier }
        ollinInstallationLog("started the piece (pid \(child.processIdentifier))")
        return child
    }

    /// Wait for one run to end, stopping it first if it goes quiet.
    private func wait(for child: Process) -> Ending {
        let startedAt = Date()
        var stalled = false
        while child.isRunning {
            Thread.sleep(forTimeInterval: 1)
            guard !shared.withLock({ $0.stopping }) else {
                // Somebody stopped the watch, and the piece has been asked to
                // go. Insist here too, or a piece that is already stuck would
                // keep this process waiting on it for ever.
                stop(child)
                break
            }
            let quiet = Self.quietFor(heartbeat: heartbeat, since: startedAt, now: Date())
            if Self.hasStalled(quietFor: quiet, answered: answered, limit: stalledAfter) {
                ollinInstallationLog("the piece has not answered for \(Int(quiet))s; stopping it")
                stalled = true
                stop(child)
                break
            }
        }
        child.waitUntilExit()
        shared.withLock { $0.child = nil }
        return Ending(status: child.terminationStatus,
                      onSignal: child.terminationReason == .uncaughtSignal,
                      stalled: stalled)
    }

    /// Whether the piece has written its first heartbeat, so the wait knows
    /// whether it is watching a start or a running piece.
    private var answered: Bool {
        FileManager.default.fileExists(atPath: heartbeat.path)
    }

    /// Stop a run that has stopped answering: ask first, so its state goes down
    /// with it, and insist afterwards, because a main thread stuck in a frame
    /// never gets to the asking.
    private func stop(_ child: Process) {
        let pid = child.processIdentifier
        kill(pid, SIGTERM)
        let deadline = Date().addingTimeInterval(5)
        while child.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        if child.isRunning {
            ollinInstallationLog("it did not stop when asked; ending it")
            kill(pid, SIGKILL)
        }
    }

    /// Pass a stop on to the piece rather than leaving it running with nobody
    /// watching it. Control-C reaches both processes on its own, so this is for
    /// the other way a run is stopped: a signal sent to this one by name.
    private func catchStops() {
        for number in [SIGTERM, SIGINT] {
            // The default action has to go first, or this process dies before
            // the source ever runs, and the piece is left behind.
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler { [self] in
                shared.withLock {
                    $0.stopping = true
                    if let pid = $0.child { kill(pid, SIGTERM) }
                }
            }
            source.resume()
            signalSources.append(source)
        }
    }

    // MARK: The rules, on their own

    /// How long the piece has been quiet: since its last heartbeat, or since it
    /// started when it has not written one yet.
    static func quietFor(heartbeat: URL, since started: Date, now: Date) -> Double {
        let attributes = try? FileManager.default.attributesOfItem(atPath: heartbeat.path)
        let beat = attributes?[.modificationDate] as? Date
        return now.timeIntervalSince(beat ?? started)
    }

    /// Whether a quiet run counts as stalled.
    ///
    /// A piece that has not answered yet is starting, and `setup()` may load a
    /// model or a film before the first frame, so a start gets a longer wait
    /// than a running piece. A limit of zero never stalls.
    static func hasStalled(quietFor quiet: Double, answered: Bool, limit: Double) -> Bool {
        guard limit > 0 else { return false }
        return quiet > (answered ? limit : max(limit, startupGrace))
    }

    /// The longest a piece may take to draw its first frame before it counts as
    /// stalled, whatever the limit says. Long enough for a heavy `setup()`.
    static let startupGrace: Double = 120

    /// How one run of the piece ended.
    struct Ending {
        var status: Int32
        var onSignal: Bool
        /// Whether this supervisor stopped it for going quiet. A piece stopped
        /// that way can still exit tidily, saving its state on the way out, and
        /// a tidy exit must not read as somebody quitting the piece: it is the
        /// failure this whole file exists for.
        var stalled = false
        /// An ordinary end: somebody quit the piece, or it stopped itself.
        var isClean: Bool { status == 0 && !onSignal && !stalled }
        var reason: String {
            if stalled { return "stopped answering" }
            return onSignal ? "crashed (signal \(status))" : "ended with status \(status)"
        }
    }
}

/// How long to wait before starting the piece again, and when to stop trying.
///
/// The two failures are different. A piece that ran for two days and crashed
/// should come straight back. A piece that fails a second after it starts is
/// broken in a way that starting it again will not fix, and a tight loop of
/// launches is worse than a dark screen: it hides the real failure in a
/// thousand log lines and keeps the machine busy all night.
///
/// So a failure counts as a strike only when the run was short, a longer run
/// clears them, and each strike waits longer than the last.
struct RestartPolicy {

    /// A run shorter than this failed to start, rather than failing after a
    /// while.
    var short: Double = 30
    /// How many short runs in a row before it stops trying.
    var limit = 5
    /// How long to wait after each strike.
    var waits: [Double] = [1, 5, 15, 30, 60]

    private(set) var strikes = 0

    enum Decision: Equatable {
        case restart(after: Double)
        case giveUp
    }

    mutating func next(ranFor seconds: Double) -> Decision {
        guard seconds < short else {
            strikes = 0
            return .restart(after: waits[0])
        }
        strikes += 1
        guard strikes < limit else { return .giveUp }
        return .restart(after: waits[min(strikes - 1, waits.count - 1)])
    }
}

/// The piece's side of the watch: one file, touched from the main thread while
/// the main thread is still turning.
///
/// It says something narrower than "the process is alive", and the narrower
/// thing is the useful one. A run loop that stops turning is what a viewer sees
/// as a frozen piece, and the process is perfectly alive throughout. Riding the
/// run loop rather than the frame loop is also what lets a still sketch
/// (`noLoop()`) and a piece dark for the night keep answering: neither draws a
/// frame for hours, and both are working exactly as they should.
@MainActor
final class Heartbeat {

    private let url: URL
    private var timer: Timer?

    /// Start beating, for a run that has a supervisor watching it. `nil` when
    /// nothing is watching, which is every run at a desk.
    static func start(environment: [String: String] = ProcessInfo.processInfo.environment)
        -> Heartbeat? {
        guard let path = environment[Supervisor.heartbeatKey], !path.isEmpty else { return nil }
        let heartbeat = Heartbeat(url: URL(fileURLWithPath: path))
        heartbeat.begin()
        return heartbeat
    }

    private init(url: URL) { self.url = url }

    private func begin() {
        beat()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.beat() }
        }
        // `.common`, so a menu tracking or a window drag does not read as a
        // stalled piece.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// The file's contents are only ever read by a person looking at what
    /// happened; what the supervisor reads is the time it was last written.
    private func beat() {
        try? Data(String(Date().timeIntervalSince1970).utf8).write(to: url)
    }
}
