#if canImport(AppKit)

import AppKit
import MetalKit

extension OllinApp {
    /// Run a sketch as the desktop wallpaper: the piece drawn across every
    /// display, behind the icons, while the machine is used for everything
    /// else.
    ///
    /// ```swift
    /// @main
    /// enum DriftWallpaper {
    ///     @MainActor static func main() {
    ///         if OllinApp.handleCommandLine(makeSketch: { Drift() }) { return }
    ///         OllinApp.runAsWallpaper { Drift() }
    ///     }
    /// }
    /// ```
    ///
    /// `ollin new --kind wallpaper` writes that file and the wrapper that makes
    /// an app of it. See `Docs/Output/Wallpaper.md`.
    ///
    /// Each display gets a sketch of its own, made by the closure, so a canvas
    /// that follows its view is the size of its display and no other. The
    /// windows take no clicks and no keys: the desktop stays the desktop, with
    /// the piece for a floor. A small mark in the menu bar carries the one
    /// command a piece with no window of its own still needs, which is Quit.
    public static func runAsWallpaper(_ makeSketch: @escaping @MainActor () -> Sketch) {
        let app = NSApplication.shared
        // An accessory: the piece has no window of its own to put in the Dock
        // or the app switcher, and quitting lives in its menu-bar mark.
        app.setActivationPolicy(.accessory)
        let host = WallpaperHost(makeSketch: makeSketch)
        WallpaperHost.current = host
        app.delegate = host
        app.run()
    }
}

/// Whether a sketch keeps its own proportions on what it is put on. One that
/// follows its view already fills the surface; one that states a size of its
/// own is fitted at those proportions, centered on black, since a surface is
/// almost never the shape of a canvas. Shared by the hosts that own a surface
/// rather than a window.
@MainActor
func sketchKeepsItsShape(_ sketch: Sketch) -> Bool {
    if case .resizable = sketch.windowMode { return false }
    return true
}

/// The one command a piece living in the system still needs: a way to be put
/// away. Hung from a status item, since there is no Dock icon to quit from.
@MainActor
func surfaceQuitMenu(for title: String) -> NSMenu {
    let menu = NSMenu()
    // No action, so the row shows the piece's name and takes no click.
    menu.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: ""))
    menu.addItem(.separator())
    menu.addItem(NSMenuItem(title: "Quit \(title)",
                            action: #selector(NSApplication.terminate(_:)),
                            keyEquivalent: "q"))
    return menu
}

/// The program around a wallpaper run. It opens one pane per display, keeps
/// the panes matched to the displays as they come and go, and holds the
/// menu-bar mark that quits the piece.
@MainActor
final class WallpaperHost: NSObject, NSApplicationDelegate {

    /// The host of the run, held so the application's delegate lives as long
    /// as the application does.
    static var current: WallpaperHost?

    private let makeSketch: @MainActor () -> Sketch
    /// One per display, rebuilt when the displays change.
    private(set) var panes: [WallpaperPane] = []
    private var statusItem: NSStatusItem?

    init(makeSketch: @escaping @MainActor () -> Sketch) {
        self.makeSketch = makeSketch
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        openPanes()
        showPanes()
        installStatusItem()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        closePanes()
    }

    /// Build one pane per display. Separate from showing them so a test can
    /// look the panes over without covering the desktop of the machine the
    /// tests run on.
    func openPanes() {
        panes = NSScreen.screens.compactMap { screen in
            WallpaperPane(screen: screen, sketch: makeSketch())
        }
    }

    func showPanes() {
        panes.forEach { $0.show() }
    }

    func closePanes() {
        panes.forEach { $0.close() }
        panes = []
    }

    /// The displays changed. Rebuilt only when a screen's frame really moved:
    /// the notification also arrives for changes that leave every frame alone,
    /// and a piece restarted for one of those would jump for no visible
    /// reason.
    @objc private func screensChanged(_ notification: Notification) {
        guard NSScreen.screens.map(\.frame) != panes.map(\.screenFrame) else { return }
        closePanes()
        openPanes()
        showPanes()
    }

    private func installStatusItem() {
        let title = panes.first?.sketch.title ?? ProcessInfo.processInfo.processName
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "sparkles",
                                     accessibilityDescription: title)
        item.button?.toolTip = title
        item.menu = surfaceQuitMenu(for: title)
        statusItem = item
    }
}

/// One display's worth of the piece: a borderless window at desktop level,
/// with a running canvas for content.
@MainActor
final class WallpaperPane {

    let sketch: Sketch
    let window: NSWindow
    let canvas: OllinMTKView
    let runner: SketchRunner
    /// The frame of the display this pane was built for, so the host can tell
    /// a real display change from a notification about something else.
    let screenFrame: CGRect

    init?(screen: NSScreen, sketch: Sketch) {
        // No device, no picture. The host still runs, so the piece can be
        // quit from its menu-bar mark rather than found and killed.
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        self.sketch = sketch
        screenFrame = screen.frame

        let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        // Under the icons, over the picture the system keeps there.
        window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        window.isReleasedWhenClosed = false
        // The desktop stays the desktop: a click lands on the icons and the
        // windows above, never on the piece.
        window.ignoresMouseEvents = true
        window.backgroundColor = .black
        window.hasShadow = false
        // On every space, and left where it is by swipes and by the window
        // cycle: wallpaper does not scroll away.
        window.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                     .ignoresCycle, .fullScreenNone]

        let canvas = makeOllinMTKView(device: device, size: sketch.canvasSize.cgSize,
                                      sketch: sketch)
        canvas.ignoresInput = true
        canvas.claimsKeyboardOnAttach = false
        canvas.frame = CGRect(origin: .zero, size: screen.frame.size)
        canvas.autoresizingMask = [.width, .height]

        let runner = SketchRunner(sketch: sketch, view: canvas, device: device)
        canvas.delegate = runner
        // Fitted like a piece on a wall when the sketch states its own shape,
        // drawn across the whole display when it follows its view.
        if sketchKeepsItsShape(sketch) { runner.setProjection(.direct) }

        window.contentView?.addSubview(canvas)
        self.window = window
        self.canvas = canvas
        self.runner = runner
        runner.displayChanged(to: screen)
    }

    func show() {
        // Regardless of activation: an accessory application putting up a
        // desktop-level window is exactly the case the plain order-front
        // ignores.
        window.orderFrontRegardless()
    }

    func close() {
        canvas.isPaused = true
        canvas.delegate = nil
        canvas.removeFromSuperview()
        window.orderOut(nil)
        window.contentView = nil
    }
}

#endif
