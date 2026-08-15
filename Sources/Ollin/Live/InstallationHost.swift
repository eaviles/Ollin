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

    init(_ settings: Installation) {
        self.settings = settings
    }

    // MARK: Taking over

    /// Take over `window` for the run: fill the screen, hide the pointer, keep
    /// the display awake, and start watching for what the system does next.
    func take(over window: NSWindow) {
        self.window = window
        log("running unattended; Command-Q quits")

        if settings.fillsScreen { fillScreen(window) }
        if settings.hidesPointer { NSCursor.hide() }
        if settings.keepsDisplayAwake { keepAwake() }
        watchTheSystem()
    }

    /// Give everything back. A run that ends on its own never gets here, which
    /// is fine: the assertion and the hidden pointer both belong to the process.
    func release() {
        pendingScreenChange?.cancel()
        idleTimer?.invalidate()
        idleTimer = nil
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
        if settings.hidesPointer { NSCursor.unhide() }
        for observer in appObservers { NotificationCenter.default.removeObserver(observer) }
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        appObservers.removeAll()
        workspaceObservers.removeAll()
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
            OllinActiveSketch.runner?.displayChanged(to: window.screen)
        }
        pendingScreenChange = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func reassert() {
        guard settings.keepsDisplayAwake else { return }
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = nil
        idleTimer?.invalidate()
        idleTimer = nil
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

    /// One line on stdout, stamped, because the log is the only witness a piece
    /// running for a week has. Flushed on the spot: stdout piped to a file is
    /// buffered, so an unflushed line would reach the file hours later, or never
    /// if the run is killed, which is exactly when the log is wanted.
    private func log(_ message: String) {
        let stamp = InstallationHost.stamp.string(from: Date())
        print("Ollin installation [\(stamp)]: \(message)")
        fflush(stdout)
    }

    private static let stamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}
