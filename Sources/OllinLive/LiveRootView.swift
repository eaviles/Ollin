import SwiftUI
import AppKit
import Ollin

/// The live host's window: the sketch renders in the detail pane; the sidebar
/// holds the monitor card + parameter knobs. The reload status sits in the
/// toolbar, and the transient states (compiling, compile error, just-reloaded)
/// play out over the stage so the last good frame stays visible behind them.
/// The sketch's `SketchRunner` is created here (the detail view owns the
/// `MTKView`) and handed to the session so the watcher can drive hot-swaps.
struct LiveRootView: View {
    /// Fixed inspector width (matches the redesign's 296pt sidebar). The detail
    /// pane is pinned to the sketch's square, so the window is exactly
    /// `square + sidebarWidth` wide; collapsing the inspector narrows it.
    static let sidebarWidth: CGFloat = 296

    let session: LiveSession

    /// Briefly shown after a successful hot reload.
    @State private var showReloadedToast = false
    /// Whether the inspector sidebar is shown. Owned here (not NavigationSplitView,
    /// which sizes the window from its own ideal and won't hug the sketch) so a
    /// plain `HStack` + `.windowResizability(.contentSize)` makes the window exactly
    /// the sketch (+ sidebar), non-resizable, and shrinks it to just the sketch on
    /// collapse.
    @State private var sidebarShown = true
    @Environment(\.colorScheme) private var colorScheme

    /// The sketch's on-screen size (or the default before one loads). The sidebar
    /// and sketch are framed to this height so the layout is rigid and
    /// `.windowResizability(.contentSize)` makes the window exactly that — no
    /// margin — and narrows it to just the sketch when the sidebar hides.
    private var sketchDisplaySize: CGSize {
        session.sketch.map { OllinApp.windowSize(for: $0) } ?? OllinApp.defaultWindowSize
    }

    /// A scrim laid over the sidebar vibrancy so the panel reads over a bright
    /// background. Tints toward the design's solid sidebar tone (dark `#232325`,
    /// light `#F4F4F5`) but keeps some translucency.
    private var sidebarScrim: SwiftUI.Color {
        colorScheme == .dark
            ? SwiftUI.Color(red: 0x23 / 255, green: 0x23 / 255, blue: 0x25 / 255).opacity(0.72)
            : SwiftUI.Color(red: 0xF4 / 255, green: 0xF4 / 255, blue: 0xF5 / 255).opacity(0.72)
    }

    // A sidebar + sketch row under the redesign's tall gradient title bar. The bar
    // is a *unified* window toolbar (see `OllinLiveApp`) — genuinely taller, so
    // macOS centers the traffic lights and `.contentSize` accounts for it with no
    // dead space (hiding the native bar instead leaves its height reserved). The
    // toggle (leading) and status chip (trailing) ride as title-bar accessories so
    // they avoid the toolbar's button capsule; the title is the toolbar's principal
    // item; the gradient is the toolbar background. The sidebar is a translucent
    // vibrancy panel.
    var body: some View {
        HStack(spacing: 0) {
            if sidebarShown {
                InspectorPanel(session: session)
                    .frame(width: Self.sidebarWidth, height: sketchDisplaySize.height)
                    .background {
                        // Vibrancy keeps the translucent feel, but a scrim toward
                        // the design's solid sidebar tone keeps the panel readable
                        // when the window sits over a bright background (the
                        // `.behindWindow` material alone washes out over white).
                        ZStack {
                            SidebarVibrancy()
                            sidebarScrim
                        }
                    }
                    .overlay(alignment: .trailing) {
                        SwiftUI.Rectangle().fill(OllinInspector.separator(colorScheme)).frame(width: 0.5)
                    }
            }
            detail
        }
        // A hairline under the title bar, framing the content off the gradient
        // bar (the design's title-bar border-bottom). It reads over the dark
        // sidebar; over a light sketch the canvas edge already separates them.
        .overlay(alignment: .top) {
            SwiftUI.Rectangle().fill(OllinInspector.separator(colorScheme)).frame(height: 0.5)
        }
        .navigationTitle(session.title)
        .background(TitlebarAccessory(attribute: .leading) {
            HStack(spacing: 10) {
                SwiftUI.Rectangle().fill(.separator).frame(width: 1, height: 22)   // divider after the traffic lights
                Button { sidebarShown.toggle() } label: {
                    SwiftUI.Image(systemName: "sidebar.left").font(.system(size: 14))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }
            .padding(.leading, 8)
            .frame(maxHeight: .infinity)
        })
        .background(TitlebarAccessory(attribute: .trailing) {
            HStack(spacing: 0) {
                StatusChip(status: session.inspectorStatus)
                SwiftUI.Color.clear.frame(width: 22, height: 1)
            }
            .padding(.leading, 12)
            .frame(maxHeight: .infinity)
        })
        // The centered title is the unified toolbar's principal item; the gradient
        // is the toolbar background. (The taller bar comes from the unified toolbar
        // style in `OllinLiveApp`.)
        .toolbar {
            if #available(macOS 26.0, *) {
                ToolbarItem(placement: .principal) {
                    Text(session.title).font(.system(size: 13.5, weight: .semibold))
                }
                .sharedBackgroundVisibility(.hidden)   // drop the Tahoe glass capsule around the title
            } else {
                ToolbarItem(placement: .principal) {
                    Text(session.title).font(.system(size: 13.5, weight: .semibold))
                }
            }
        }
        .toolbarBackground(OllinInspector.titleBarGradient(colorScheme), for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .task { session.start() }
        .onChange(of: session.reloadCount) { _, _ in flashReloadedToast() }
    }

    // Lightweight until the first compile lands: a plain SwiftUI placeholder, not
    // a Metal view (mounting an MTKView at launch kept the window from surfacing).
    // Once `sketch` is set, the SketchView mounts and creates the runner. The
    // detail pane is sized *exactly* to the sketch (no surrounding margin), so the
    // right side of the window is just the sketch — and collapsing the sidebar
    // leaves the window showing only it.
    @ViewBuilder private var detail: some View {
        if let sketch = session.sketch {
            let size = OllinApp.windowSize(for: sketch)
            ZStack {
                // No detached panel here: the sidebar already shows these stats,
                // so it'd just duplicate them.
                SketchView(sketch, stats: session.stats, showsInspectorPanel: false) { runner in
                    session.attach(runner)
                }

                // Transient states play over the live canvas, holding the last
                // good frame behind them.
                if session.inspectorStatus == .compiling {
                    CompilingState().transition(.opacity)
                } else if let error = session.errorMessage {
                    CompileErrorState(message: error).transition(.opacity)
                }

                if showReloadedToast {
                    ReloadedToast(count: session.reloadCount)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .padding(.top, 18)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .frame(width: size.width, height: size.height)
            .animation(.easeInOut(duration: 0.18), value: session.inspectorStatus)
        } else {
            Group {
                if let error = session.errorMessage {
                    CompileErrorState(message: error)
                } else {
                    CompilingState(firstCompile: true, name: session.displayName)
                }
            }
            .frame(width: OllinApp.defaultWindowSize.width, height: OllinApp.defaultWindowSize.height)
        }
    }

    private func flashReloadedToast() {
        withAnimation { showReloadedToast = true }
        Task {
            try? await Task.sleep(for: .seconds(1.6))
            withAnimation { showReloadedToast = false }
        }
    }
}

// MARK: - Transient states

/// Centered spinner shown while a build is in flight. On the first compile it
/// owns the stage; on a reload it floats as a frosted card over the held frame.
private struct CompilingState: View {
    var firstCompile = false
    var name = ""

    var body: some View {
        VStack(spacing: 14) {
            ProgressView().controlSize(.large)
            Text("Compiling…").font(.system(size: 15, weight: .semibold))
            if firstCompile {
                Text("Building \(name) — the window stays open and your tuned values are preserved across the reload.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }
        .padding(26)
        .background(firstCompile ? AnyShapeStyle(.clear) : AnyShapeStyle(.regularMaterial),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(firstCompile ? 0 : 0.25), radius: 16, y: 6)
    }
}

/// The compile-error state: the diagnostic lives here in the canvas (never the
/// sidebar). On a reload it floats over the dimmed last good frame.
private struct CompileErrorState: View {
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                SwiftUI.Circle().fill(OllinInspector.red.opacity(0.15)).frame(width: 46, height: 46)
                SwiftUI.Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 20)).foregroundStyle(OllinInspector.red)
            }
            Text("Compile failed").font(.system(size: 15, weight: .semibold))
            Text(message)
                .font(.system(size: 11.5, design: .monospaced))
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
                .padding(12)
                .background(OllinInspector.red.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(OllinInspector.red.opacity(0.25), lineWidth: 0.5))
            Text("Last good frame held until the next save.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        .padding(26)
        .frame(maxWidth: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 18, y: 6)
        .padding(24)
    }
}

// MARK: - Window chrome

/// A translucent vibrancy panel — the native sidebar look (sampling what's behind
/// the window), used as the inspector sidebar's background.
private struct SidebarVibrancy: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

/// Hosts a SwiftUI view as a leading or trailing title-bar accessory — a real spot
/// in the title bar with no toolbar-item button chrome. It owns its `NSHostingView`
/// so any view holding the window can update the content in place, keeping it a
/// single instance per edge even if SwiftUI re-creates the representable.
private final class TitlebarAccessoryVC: NSTitlebarAccessoryViewController {
    let tag: NSUserInterfaceItemIdentifier
    private let host = NSHostingView(rootView: AnyView(EmptyView()))

    /// Title-bar height, so the content's `maxHeight: .infinity` centers vertically.
    var titleBarHeight: CGFloat = 28 { didSet { resize() } }

    init(attribute: NSLayoutConstraint.Attribute, tag: NSUserInterfaceItemIdentifier) {
        self.tag = tag
        super.init(nibName: nil, bundle: nil)
        layoutAttribute = attribute
        host.identifier = tag
        view = host
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(_ content: AnyView) {
        host.rootView = content
        resize()
    }

    private func resize() {
        host.setFrameSize(NSSize(width: host.fittingSize.width, height: titleBarHeight))
    }
}

/// Mounts a SwiftUI view as a leading or trailing title-bar accessory. The host is
/// invisible (zero-size); attach with `.background(...)`. Idempotent at the window
/// level: one accessory per edge, updated in place.
private struct TitlebarAccessory<Content: View>: NSViewRepresentable {
    var attribute: NSLayoutConstraint.Attribute = .trailing
    @ViewBuilder var content: Content

    private var tag: NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier(attribute == .leading ? "ollin.titlebar.leading" : "ollin.titlebar.trailing")
    }

    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ nsView: NSView, context: Context) {
        sync(near: nsView, content: AnyView(content), attempt: 0)
    }

    @MainActor
    private func sync(near nsView: NSView, content: AnyView, attempt: Int) {
        let window = nsView.window ?? NSApp.windows.first {
            $0.isVisible && !($0 is NSPanel) && $0.styleMask.contains(.titled)
        }
        guard let window else {
            guard attempt < 10 else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak nsView] in
                guard let nsView else { return }
                sync(near: nsView, content: content, attempt: attempt + 1)
            }
            return
        }
        // We draw our own hairline under the title bar (the content's top overlay
        // in `body`), in the design's `--sep` tone — so suppress the system one,
        // which doesn't read against the custom gradient and would risk a double line.
        window.titlebarSeparatorStyle = .none
        let titleBarHeight = max(28, window.frame.height - window.contentLayoutRect.height)
        let tag = self.tag
        if let existing = window.titlebarAccessoryViewControllers
            .compactMap({ $0 as? TitlebarAccessoryVC }).first(where: { $0.tag == tag }) {
            existing.titleBarHeight = titleBarHeight
            existing.update(content)
        } else {
            let accessory = TitlebarAccessoryVC(attribute: attribute, tag: tag)
            accessory.titleBarHeight = titleBarHeight
            accessory.update(content)
            window.addTitlebarAccessoryViewController(accessory)
        }
    }
}

/// A brief frosted confirmation after a hot reload, top-center of the stage.
private struct ReloadedToast: View {
    let count: Int

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                SwiftUI.Circle().fill(OllinInspector.green).frame(width: 16, height: 16)
                SwiftUI.Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
            }
            Text("Reloaded").font(.system(size: 12.5, weight: .medium))
            Text("#\(count)")
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
    }
}
