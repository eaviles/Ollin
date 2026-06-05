import SwiftUI
import AppKit

// The standalone "Show FPS" surface: a floating, frosted inspector panel — the
// live host's sidebar reborn as a detached utility window. The app shows just
// the sketch; toggling "Show FPS" (⌘/) summons this panel over it. It replaces
// the old on-canvas overlay chip: same shared `MonitorCardView` the live host's
// sidebar uses (so they never drift), plus the sketch's `@Param` knobs, tunable
// live. Used in the panel-less run modes (standalone `swift run`, gallery); the
// live host omits it because its inspector already shows the same content.

/// The detached panel's body: the monitor card (clock · stats) and the sketch's
/// parameters, with a steady-green `Running` chip (the panel has no file watcher,
/// so the watch/compile lifecycle doesn't apply). Frosted via `Material`.
struct DetachedInspectorView: View {
    let identity: MonitorIdentity
    let stats: FrameStats
    let params: [ParamHandle]

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Spacer()
                StatusChip(status: .running)
            }
            MonitorCardView(identity: identity, stats: stats)
            ParametersListView(params: params)
        }
        .padding(13)
        .frame(width: 300)
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

        let identity = MonitorIdentity(name: sketch.title)   // standalone: no source file
        let rootView = DetachedInspectorView(identity: identity, stats: stats,
                                             params: sketch.parameters())
        if let host {
            host.rootView = rootView
        } else {
            buildPanel(rootView)
        }
        panel?.orderFront(nil)
    }

    /// Tear the panel down (window closed / view disappeared).
    func close() {
        panel?.orderOut(nil)
    }

    private func buildPanel(_ rootView: DetachedInspectorView) {
        let host = NSHostingController(rootView: rootView)
        host.sizingOptions = [.preferredContentSize]   // panel adopts the SwiftUI size
        self.host = host

        let panel = NSPanel(contentViewController: host)
        panel.styleMask = [.titled, .closable, .utilityWindow, .nonactivatingPanel]
        panel.titlebarAppearsTransparent = true        // the Material shows through
        panel.titleVisibility = .visible
        panel.title = rootView.identity.name
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

        // Float top-right of the main screen, inset 16pt (matches the mockup).
        panel.layoutIfNeeded()
        if let screen = NSScreen.main {
            let area = screen.visibleFrame
            let size = panel.frame.size
            panel.setFrameOrigin(CGPoint(x: area.maxX - size.width - 16,
                                         y: area.maxY - size.height - 16))
        }
    }

    /// The user clicked the panel's close button — keep the menu toggle in sync
    /// (and stop `SketchView` from re-summoning it). Hiding via `close()`/`sync`
    /// uses `orderOut`, which doesn't fire this.
    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(false, forKey: OllinHUD.showStatsKey)
    }
}

/// The "Show FPS" menu command. Add it to a host's scene with
/// `.commands { OllinHUDCommands() }`; it binds to the shared preference the
/// detached panel reads, so the menu and panel stay in sync across run modes
/// (standalone, gallery) and the choice persists.
public struct OllinHUDCommands: Commands {
    @AppStorage(OllinHUD.showStatsKey) private var showStats = false

    public init() {}

    public var body: some Commands {
        CommandGroup(after: .toolbar) {
            Toggle("Show FPS", isOn: $showStats)
                .keyboardShortcut("/", modifiers: .command)
        }
    }
}
