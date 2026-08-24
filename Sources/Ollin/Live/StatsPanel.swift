import SwiftUI
import AppKit

// The standalone "Show FPS" surface: a floating, frosted inspector panel — the
// live host's sidebar reborn as a detached utility window. The app shows just
// the sketch; toggling "Show FPS" (⌘/) summons this panel over it. It replaces
// the old on-canvas overlay chip: same shared `MonitorCardView` the live host's
// sidebar uses (so they never drift), plus the sketch's `@Param` knobs, tunable
// live. Used in the standalone `swift run` mode; the live host and the gallery
// omit it because their inspector sidebars already show the same content.

/// The detached panel's body: below a "Parameters" title bar, the same monitor
/// card (clock · stats) and parameter list as the OllinLive sidebar — a 1:1
/// mirror, built from the same shared views so the two never drift. Frosted via
/// `Material`.
struct DetachedInspectorView: View {
    let identity: MonitorIdentity
    let stats: FrameStats
    let params: [ParamHandle]

    @SwiftUI.Environment(\.colorScheme) private var scheme

    /// A scrim toward the design's `--glass` tone, at the shared chrome opacity, so
    /// the frosted panel isn't too see-through over a bright sketch (the bare
    /// `Material` alone is).
    private var panelScrim: SwiftUI.Color {
        scheme == .dark
            ? SwiftUI.Color(red: 44 / 255, green: 42 / 255, blue: 48 / 255).opacity(OllinInspector.chromeTintOpacity)
            : SwiftUI.Color(red: 246 / 255, green: 246 / 255, blue: 248 / 255).opacity(OllinInspector.chromeTintOpacity)
    }

    var body: some View {
        // A heavily knobbed sketch's parameter list can outgrow the screen, so
        // the content scrolls: `sizeToFit` caps the panel at the screen's
        // visible height and the scroll view carries what's past the cap.
        ScrollView {
            DetachedInspectorContent(identity: identity, stats: stats, params: params)
        }
        .background(panelScrim)
        .background(.regularMaterial)
    }
}

/// The panel's scrollable content: below the native title bar (just the sketch
/// title + its hairline, the window's own `titlebarSeparatorStyle`), the
/// OllinLive sidebar's content verbatim, the same monitor card and parameter
/// list with the same spacing and padding. Kept apart from the scroll view so
/// `sizeToFit` can measure the content's true height (a scroll view's own
/// fitting size collapses).
struct DetachedInspectorContent: View {
    let identity: MonitorIdentity
    let stats: FrameStats
    let params: [ParamHandle]

    var body: some View {
        VStack(spacing: 16) {
            MonitorCardView(identity: identity, stats: stats)
            VariationCardView(stats: stats)
            ParametersListView(params: params)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)      // tight under the title bar (safe area already insets the rest)
        .padding(.bottom, 14)
        .frame(width: OllinInspector.sidebarWidth)
    }
}

/// Owns the floating `NSPanel` and shows/hides it in step with the "Show FPS"
/// toggle. Held by `SketchView`, which calls `sync(...)` whenever the toggle or
/// the hosted sketch changes.
@MainActor
final class StatsPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var host: NSHostingController<DetachedInspectorView>?

    /// Reflect the desired visibility: show the panel for `sketch`/`stats` when
    /// `visible`, otherwise hide it. Building the content is cheap and the
    /// `FrameStats` is `@Observable`, so the panel tracks the live numbers once up.
    func sync(visible: Bool, sketch: Sketch, stats: FrameStats) {
        guard visible else { panel?.orderOut(nil); return }

        // The card identifies the run by app name over the Ollin version (a
        // standalone sketch has no watched source file + path to name like the live
        // host does); the window title carries the sketch's own title.
        let identity = MonitorIdentity(name: ProcessInfo.processInfo.processName,
                                       folder: "Ollin \(OllinVersion.current)", icon: nil)
        let rootView = DetachedInspectorView(identity: identity, stats: stats,
                                             params: sketch.parameters())
        if let host {
            host.rootView = rootView
            sizeToFit()                      // re-fit: the new sketch may have a different parameter count
        } else {
            buildPanel(rootView)
        }
        panel?.title = sketch.title          // window title: "Ollin - <Sketch>"
        panel?.orderFront(nil)
    }

    /// Tear the panel down (window closed / view disappeared).
    func close() {
        panel?.orderOut(nil)
    }

    private func buildPanel(_ rootView: DetachedInspectorView) {
        let host = NSHostingController(rootView: rootView)
        // Size the panel ourselves (see `sizeToFit`), *not* continuously from the
        // SwiftUI content: `.preferredContentSize` resizes the window every time the
        // content's ideal size changes, and the live stats update ~10 Hz — enough to
        // drive the window's update-constraints pass into an exception loop that
        // hangs the app. We re-fit only when the hosted sketch changes.
        host.sizingOptions = []
        self.host = host

        let panel = NSPanel(contentViewController: host)
        // `.fullSizeContentView` so the content (and its `Material`) fills the whole
        // panel, *including under the title bar* — without it that top strip is the
        // panel's clear background showing through (a see-through title bar).
        panel.styleMask = [.titled, .closable, .utilityWindow, .nonactivatingPanel, .fullSizeContentView]
        panel.titlebarAppearsTransparent = true        // the Material shows through
        panel.titlebarSeparatorStyle = .line           // hairline under the title bar
        panel.titleVisibility = .visible               // title set per-sketch in `sync`
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false             // reuse across toggles
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.identifier = NSUserInterfaceItemIdentifier(OllinHUD.statsPanelID)
        panel.delegate = self
        self.panel = panel

        // Size to the content once, then place beside the sketch window by default;
        // once the user drags it, the frame autosave remembers that spot (so we only
        // auto-place when there's no saved position).
        sizeToFit()
        let autosaveName = "ollin.statsPanel.frame"
        if panel.setFrameUsingName(autosaveName) {
            // A saved frame carries the size it was saved at, and the card grows
            // a row whenever the framework does. Keep the remembered corner, take
            // the current size, or an older frame clips what was added.
            let corner = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
            sizeToFit()
            panel.setFrameTopLeftPoint(corner)
        } else {
            positionBesideSketch(panel)
        }
        panel.setFrameAutosaveName(autosaveName)
    }

    /// Size the panel to its content's fitting size — once, on build and whenever
    /// the hosted sketch changes (its parameter count sets the height; the width is
    /// fixed). Deliberately not driven by the per-frame stats updates: letting the
    /// window track the SwiftUI content's size live (`.preferredContentSize`) thrashed
    /// the update-constraints pass into an exception loop.
    private func sizeToFit() {
        guard let panel, let host else { return }
        // The hosted root is a scroll view, whose fitting size collapses, so
        // measure the inner content with a throwaway host instead. The height
        // gains the title-bar safe-area inset (the content starts below it),
        // then caps at the screen's visible height: past the cap the scroll
        // view takes over, so every knob stays reachable.
        let root = host.rootView
        let probe = NSHostingController(rootView: DetachedInspectorContent(
            identity: root.identity, stats: root.stats, params: root.params))
        probe.view.layoutSubtreeIfNeeded()
        var fit = probe.view.fittingSize
        guard fit.width > 0, fit.height > 0 else { return }
        fit.height += panel.contentView?.safeAreaInsets.top ?? 0
        if let area = (panel.screen ?? NSScreen.main)?.visibleFrame {
            fit.height = min(fit.height, area.height - 24)
        }
        panel.setContentSize(fit)
    }

    /// Default placement: just off the sketch window's right edge, top-aligned
    /// (flipping to the left edge if there's no room), and the screen's top-right as
    /// a fallback if the sketch window can't be found.
    private func positionBesideSketch(_ panel: NSPanel) {
        let size = panel.frame.size
        let gap: CGFloat = 12
        guard let sketch = NSApp.windows.first(where: {
            $0 !== panel && $0.isVisible && !($0 is NSPanel) && $0.styleMask.contains(.titled)
        }) else {
            if let area = NSScreen.main?.visibleFrame {
                panel.setFrameOrigin(CGPoint(x: area.maxX - size.width - 16,
                                             y: area.maxY - size.height - 16))
            }
            return
        }
        let frame = sketch.frame
        let area = (sketch.screen ?? NSScreen.main)?.visibleFrame
        var x = frame.maxX + gap
        if let area, x + size.width > area.maxX {
            x = frame.minX - gap - size.width   // no room on the right → go left
        }
        let y = frame.maxY - size.height        // top-aligned with the sketch window
        panel.setFrameOrigin(CGPoint(x: x, y: y))
    }

    /// The user clicked the panel's close button — keep the menu toggle in sync
    /// (and stop `SketchView` from re-summoning it). Hiding via `close()`/`sync`
    /// uses `orderOut`, which doesn't fire this.
    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(false, forKey: OllinHUD.showStatsKey)
    }
}

/// The "Show Inspector" menu command. Add it to a host's scene with
/// `.commands { OllinHUDCommands() }`; it binds to the shared preference the
/// detached panel reads, so the menu and panel stay in sync across run modes
/// (standalone, gallery) and the choice persists.
public struct OllinHUDCommands: Commands {
    @AppStorage(OllinHUD.showStatsKey) private var showStats = false

    public init() {}

    public var body: some Commands {
        CommandGroup(after: .toolbar) {
            Toggle("Show Inspector", isOn: $showStats)
                .keyboardShortcut("/", modifiers: .command)
            // A one-shot action rather than a toggle: the runner takes the flag
            // on the next frame, wraps that frame in a Metal capture, and clears
            // it. The trace lands in the directory the sketch was run from.
            Button("Capture GPU Frame") {
                UserDefaults.standard.set(true, forKey: OllinHUD.captureFrameKey)
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
        }
    }
}

/// The "Camera" menu: snap the running 3D sketch to a canonical inspection view
/// the way a modeling tool's numpad does. Add it to a host's scene with
/// `.commands { OllinCameraCommands() }`; each item reaches the running sketch
/// through `OllinActiveSketch`, so it works in every host (standalone examples,
/// the gallery, OllinLive) with no per-scene wiring. A 2D sketch, or one that
/// drives the camera by hand rather than through the rig, simply ignores it.
public struct OllinCameraCommands: Commands {
    @AppStorage(OllinHUD.orthographicKey) private var orthographic = false
    @AppStorage(OllinHUD.showAxisKey) private var showAxis = false
    @AppStorage(OllinHUD.showGridKey) private var showGrid = false

    public init() {}

    public var body: some Commands {
        CommandMenu("Camera") {
            Button("Reset View") { Self.snap(.reset) }
                .keyboardShortcut("0", modifiers: .command)
            Divider()
            Button("Front")  { Self.snap(.front) }.keyboardShortcut("1", modifiers: .command)
            Button("Back")   { Self.snap(.back) }.keyboardShortcut("2", modifiers: .command)
            Button("Right")  { Self.snap(.right) }.keyboardShortcut("3", modifiers: .command)
            Button("Left")   { Self.snap(.left) }.keyboardShortcut("4", modifiers: .command)
            Button("Top")    { Self.snap(.top) }.keyboardShortcut("5", modifiers: .command)
            Button("Bottom") { Self.snap(.bottom) }.keyboardShortcut("6", modifiers: .command)
            Button("Isometric") { Self.snap(.isometric) }
                .keyboardShortcut("7", modifiers: .command)
            Divider()
            Toggle("Orthographic", isOn: $orthographic)
                .keyboardShortcut("8", modifiers: .command)
            Divider()
            Toggle("Show Axis", isOn: $showAxis)
            Toggle("Show Ground Grid", isOn: $showGrid)
        }
    }

    @MainActor private static func snap(_ view: CameraView) {
        OllinActiveSketch.runner?.requestCameraView(view)
    }
}
