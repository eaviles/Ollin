import AppKit
import Foundation
import IOKit.pwr_mgt

/// Holds off the things that end an unattended run, for a sketch that declares
/// an `Installation`: the screen saver, display sleep, a pointer parked over the
/// work, and a monitor that changes underneath the window.
///
/// Host chrome, like the stats panel beside it: it owns the window and the
/// system state around the run, and never draws into the canvas or reaches an
/// export. The clock's own long-run defences live in the runner and in
/// `Sketch.shaderClock`, because they matter to a headless run too.
@MainActor
final class InstallationHost {

    private let settings: Installation
    private weak var window: NSWindow?

    /// The held power assertion: it tells the system this process is doing
    /// something on purpose, so the display and the machine stay awake.
    private var activity: (any NSObjectProtocol)?

    /// Declares user activity on a slow repeat. The assertion above stops the
    /// display sleeping but not the screen saver, which starts from the idle
    /// timer that counts input. Declaring activity resets that timer, so the
    /// screen saver never arms over a piece nobody is touching.
    private var idleTimer: Timer?

    /// The assertion the declaration above hands back, kept so every later call
    /// refreshes that one rather than making another.
    private var userActivity: IOPMAssertionID = 0

    /// A screen change arrives as a burst rather than a single notification (a
    /// display waking can report a dozen arrivals and departures in a second),
    /// so the response is debounced and only the last one runs.
    private var pendingScreenChange: DispatchWorkItem?

    private var appObservers: [any NSObjectProtocol] = []
    private var workspaceObservers: [any NSObjectProtocol] = []

    /// Answers the supervisor watching this run, if there is one. Nothing at a
    /// desk: a run nobody is watching has nobody to answer.
    private var heartbeat: Heartbeat?

    /// Reads the clock for a piece that keeps hours.
    private var scheduleTimer: Timer?
    /// The running sketch, once its view has built one. Weak: the view owns it.
    private weak var sketchRunner: SketchRunner?
    /// Whether the piece is on screen, as the schedule last had it. `nil` until
    /// the first reading, so the run says out loud what it opened into.
    private var showing: Bool?

    /// The displays the piece is on, with the corner handles for each of them.
    private var wall: DisplayWall?
    /// Watches for the keys the handles answer to.
    private var keyMonitor: Any?

    init(_ settings: Installation) {
        self.settings = settings
    }

    // MARK: Taking over

    /// Take over `window` for the run: fill the screen, hide the pointer, keep
    /// the display awake, and start watching for what the system does next.
    ///
    /// The wall comes with it because the keys that line it up belong to the
    /// window: this one has no menu bar to hang a command on.
    func take(over window: NSWindow, wall: DisplayWall? = nil) {
        self.window = window
        self.wall = wall
        log("running unattended; Command-K lines it up, Command-Q quits")

        if settings.fillsScreen { fillScreen(window) }
        // Not while somebody is lining it up: the pointer is the tool.
        if settings.hidesPointer, !(wall?.calibrators.contains(where: \.isOpen) ?? false) {
            NSCursor.hide()
        }
        if settings.keepsDisplayAwake { keepAwake() }
        heartbeat = Heartbeat.start()
        watchKeys()
        watchTheSystem()
        if !settings.schedule.periods.isEmpty { watchTheClock() }
    }

    /// Give everything back. A run that ends on its own never gets here, which
    /// is fine: the assertion and the hidden pointer both belong to the process.
    func release() {
        pendingScreenChange?.cancel()
        scheduleTimer?.invalidate()
        scheduleTimer = nil
        heartbeat?.stop()
        heartbeat = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        wall?.close()
        releaseAwake()
        if settings.hidesPointer { NSCursor.unhide() }
        for observer in appObservers { NotificationCenter.default.removeObserver(observer) }
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        appObservers.removeAll()
        workspaceObservers.removeAll()
    }

    // MARK: The keys that line a wall up

    /// Watch for the keys the handles answer to.
    ///
    /// A local monitor rather than a menu command: a piece on a wall is full
    /// screen and has no menu bar to hang one on. It reads the event before the
    /// canvas does, so Command-K works while the sketch holds the keyboard, and
    /// everything else is passed straight through unless the handles are up.
    ///
    /// One key raises the handles on every display at once, because a wall is
    /// lined up as one thing. The keys that move a corner go to the display
    /// somebody is actually working on, which is the window they last clicked.
    private func watchKeys() {
        guard keyMonitor == nil, let wall, !wall.calibrators.isEmpty else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let wall = self.wall else { return event }
            if event.modifierFlags.contains(.command),
               event.charactersIgnoringModifiers?.lowercased() == "k" {
                self.toggleHandles()
                return nil
            }
            let working = wall.outputs.first(where: \.isKeyWindow)?.calibrator
                ?? wall.calibrators.first
            return working?.handleKey(event) == true ? nil : event
        }
    }

    /// Raise the handles on every display, or put them all down.
    func toggleHandles() {
        guard let wall else { return }
        let opening = !wall.calibrators.contains(where: \.isOpen)
        for calibrator in wall.calibrators {
            opening ? calibrator.open() : calibrator.close()
        }
        // A window of the wall takes the keyboard only while it is being lined
        // up, so the arrow keys can be aimed at one display by clicking it.
        for output in wall.outputs { output.takeKeys(opening) }
        if !opening { window?.makeKeyAndOrderFront(nil) }
    }

    // MARK: The screen

    /// Fill the display the window opened on. Native full screen rather than a
    /// borderless window covering the same pixels: it takes the menu bar and
    /// the Dock with it, it survives a resolution change on its own, and the
    /// window keeps the keyboard (a borderless one cannot become key without a
    /// subclass, so a key-reading sketch would go deaf).
    ///
    /// The style mask and the size limits have to open up first: the standalone
    /// window pins its content size exactly, and a window that cannot resize
    /// ignores the request to go full screen.
    private func fillScreen(_ window: NSWindow) {
        window.styleMask.insert([.resizable, .fullSizeContentView])
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.contentMinSize = NSSize(width: 64, height: 64)
        window.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                       height: CGFloat.greatestFiniteMagnitude)
        // After the window is on screen: the toggle is a no-op on a window the
        // system has not finished showing.
        DispatchQueue.main.async {
            guard !window.styleMask.contains(.fullScreen) else { return }
            window.toggleFullScreen(nil)
        }
    }

    // MARK: Staying awake

    private func keepAwake() {
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled, .userInitiated],
            reason: "Ollin installation")
        declareActivity()
        // Well inside any screen-saver setting, and cheap: the shortest one the
        // system offers is a minute.
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.declareActivity() }
        }
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    /// One reset of the system's input-idle timer, which is the timer the screen
    /// saver arms off.
    ///
    /// The id from last time goes back in, because the call takes one: handing
    /// it a fresh zero every half minute creates a *new* assertion each time and
    /// keeps them all. Measured, since it is invisible from inside the process:
    /// five calls with a fresh id leave five assertions in `pmset -g assertions`
    /// and five with the same id leave one. Over a week that is twenty thousand
    /// of them, from the one feature whose whole job is surviving the week.
    private func declareActivity() {
        IOPMAssertionDeclareUserActivity("Ollin installation" as CFString,
                                         kIOPMUserActiveLocal, &userActivity)
    }

    /// Give the display and the machine back their own idleness, for the hours
    /// the piece is not on screen. Nothing is holding the screen saver off then,
    /// which is the point: a dark piece should let the panel rest.
    private func releaseAwake() {
        idleTimer?.invalidate()
        idleTimer = nil
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }

    // MARK: Keeping hours

    /// Follow the schedule's parts of the day. Twenty seconds is far finer than
    /// anything a schedule says, so a change lands well inside the minute it
    /// names, and the reading itself is a comparison of two clock times.
    private func watchTheClock() {
        applySchedule()
        let timer = Timer(timeInterval: 20, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.applySchedule() }
        }
        RunLoop.main.add(timer, forMode: .common)
        scheduleTimer = timer
    }

    private func applySchedule() {
        let now = Date()
        let shows = settings.schedule.shows(at: now)
        if shows != showing {
            showing = shows
            let until = settings.schedule.nextChange(at: now).map { " until \($0.text)" } ?? ""
            if shows {
                log("on screen\(until)")
                // Declaring activity here is also what wakes a display that
                // went to sleep during the dark hours: nothing else in the
                // process is touching the machine at nine in the morning.
                if settings.keepsDisplayAwake { keepAwake() }
                if settings.hidesPointer { NSCursor.hide() }
            } else {
                log("dark\(until)")
                // An ordinary pause, so the state goes down with it rather than
                // waiting on a cadence that has just stopped ticking.
                sketchRunner?.saveCheckpointNow()
                releaseAwake()
            }
        }
        // Pushed every reading rather than only on a change: the runner may
        // arrive after the window is taken over, and telling it nothing would
        // leave a piece drawing through its own dark hours.
        sketchRunner?.setShowing(shows)
    }

    /// The runner, handed over as soon as the view builds it, along with the
    /// schedule's opening state: a piece launched outside its hours must not
    /// show one frame and then have it taken away.
    ///
    /// Held here rather than read from `OllinActiveSketch`, which a piece only
    /// registers with on its first frame. A piece that opens outside its hours
    /// has no first frame to draw until the hours come round, so reading the
    /// global would find nothing at exactly the moment this needs it.
    func attach(_ runner: SketchRunner) {
        sketchRunner = runner
        if !settings.schedule.periods.isEmpty {
            runner.setShowing(settings.schedule.shows(at: Date()))
        }
    }

    // MARK: Watching the system

    private func watchTheSystem() {
        // A display added, removed, or re-resolved. The window has to be put
        // back on a screen that still exists, and the draw loop retimed to
        // whatever refresh rate it now faces.
        observe(NSApplication.didChangeScreenParametersNotification) { [weak self] in
            self?.screenChanged()
        }
        // Waking up. The assertion does not always survive a sleep, and the
        // screen saver may have armed while the display was off.
        observeWorkspace(NSWorkspace.didWakeNotification) { [weak self] in
            self?.log("the machine woke")
            self?.reassert()
        }
        observeWorkspace(NSWorkspace.screensDidWakeNotification) { [weak self] in
            self?.log("the screens woke")
            self?.reassert()
        }
    }

    /// Put the piece back on a screen and retime the loop, once the burst of
    /// notifications settles.
    private func screenChanged() {
        pendingScreenChange?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let window = self.window else { return }
            let screen = window.screen ?? NSScreen.main
            self.log("the displays changed: now \(NSScreen.screens.count) "
                     + "(\(Int(screen?.frame.width ?? 0))x\(Int(screen?.frame.height ?? 0)))")
            // A window whose display was unplugged can be left off every screen.
            if window.screen == nil, let home = NSScreen.main {
                window.setFrame(home.frame, display: true)
            }
            // Which display carries what has just changed, so the wall is worked
            // out again and its windows put back where the parts now are.
            self.wall?.displaysChanged()
            OllinActiveSketch.runner?.displayChanged(to: window.screen)
        }
        pendingScreenChange = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func reassert() {
        guard settings.keepsDisplayAwake else { return }
        // Nothing to hold awake while the piece is off screen: the schedule put
        // it down, and a wake in the small hours must not stand it back up.
        guard showing ?? true else { return }
        releaseAwake()
        keepAwake()
        if settings.hidesPointer { NSCursor.hide() }
    }

    // MARK: Plumbing

    private func observe(_ name: Notification.Name, _ body: @escaping @MainActor () -> Void) {
        appObservers.append(NotificationCenter.default.addObserver(
            forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { body() }
            })
    }

    private func observeWorkspace(_ name: Notification.Name, _ body: @escaping @MainActor () -> Void) {
        workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { body() }
            })
    }

    private func log(_ message: String) { ollinInstallationLog(message) }
}

/// One line on stdout, stamped, because the log is the only witness a piece
/// running for a week has. Flushed on the spot: stdout piped to a file is
/// buffered, so an unflushed line would reach the file hours later, or never if
/// the run is killed, which is exactly when the log is wanted.
func ollinInstallationLog(_ message: String) {
    let stamp = ollinLogStamp.string(from: Date())
    print("Ollin installation [\(stamp)]: \(message)")
    fflush(stdout)
}

private let ollinLogStamp: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return formatter
}()
