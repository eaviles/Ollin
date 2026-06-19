import SwiftUI
import AppKit

// The standalone "Show FPS" surface: a floating, frosted inspector panel — the
// live host's sidebar reborn as a detached utility window. The app shows just
// the sketch; toggling "Show FPS" (⌘/) summons this panel over it. It replaces
// the old on-canvas overlay chip: same shared `MonitorCardView` the live host's
// sidebar uses (so they never drift), plus the sketch's `@Param` knobs, tunable
// live. Used in the panel-less run modes (standalone `swift run`, gallery); the
// live host omits it because its inspector already shows the same content.

/// The detached panel's body: below a "Parameters" title bar, the same monitor
/// card (clock · stats) and parameter list as the OllinLive sidebar — a 1:1
/// mirror, built from the same shared views so the two never drift. Frosted via
/// `Material`.
struct DetachedInspectorView: View {
    let identity: MonitorIdentity
    let stats: FrameStats
    let params: [ParamHandle]

    @Environment(\.colorScheme) private var scheme

    /// A scrim toward the design's `--glass` tone, at the shared chrome opacity, so
    /// the frosted panel isn't too see-through over a bright sketch (the bare
    /// `Material` alone is).
    private var panelScrim: SwiftUI.Color {
        scheme == .dark
            ? SwiftUI.Color(red: 44 / 255, green: 42 / 255, blue: 48 / 255).opacity(OllinInspector.chromeTintOpacity)
            : SwiftUI.Color(red: 246 / 255, green: 246 / 255, blue: 248 / 255).opacity(OllinInspector.chromeTintOpacity)
    }

    var body: some View {
        // Below the native "Parameters"-less title bar (just the sketch title +
        // its hairline, the window's own `titlebarSeparatorStyle`), the OllinLive
        // sidebar's content verbatim: the same monitor card and parameter list,
        // same spacing and padding. The top inset clears the title bar; the
        // Material (+ scrim) fills behind it.
        VStack(spacing: 16) {
            MonitorCardView(identity: identity, stats: stats)
            ParametersListView(params: params)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)      // tight under the title bar (safe area already insets the rest)
        .padding(.bottom, 14)
        .frame(width: OllinInspector.sidebarWidth)
        .background(panelScrim)
        .background(.regularMaterial)
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
        if !panel.setFrameUsingName(autosaveName) {
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
        host.view.layoutSubtreeIfNeeded()
        let fit = host.view.fittingSize
        guard fit.width > 0, fit.height > 0 else { return }
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
        }
    }
}
