import SwiftUI
import AppKit
import Ollin

/// Shared chrome tokens for the live host.
private enum LiveChrome {
    /// Opacity for the frosted-chrome tints — the sidebar scrim and the reload
    /// toast. Shared with the standalone stats panel via `OllinInspector`, so the
    /// live host and the panel read as one translucency.
    static let tintOpacity = OllinInspector.chromeTintOpacity

    /// `--win-bg`: the stage fill behind the full-stage transient screens
    /// (compiling, compile error). Opaque, since they cover the canvas.
    static func stageBackground(_ scheme: ColorScheme) -> SwiftUI.Color {
        scheme == .dark
            ? SwiftUI.Color(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255)
            : SwiftUI.Color(red: 0xEC / 255, green: 0xEC / 255, blue: 0xEE / 255)
    }
}

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
    /// light `#F4F4F5`) at the shared chrome translucency.
    private var sidebarScrim: SwiftUI.Color {
        colorScheme == .dark
            ? SwiftUI.Color(red: 0x23 / 255, green: 0x23 / 255, blue: 0x25 / 255).opacity(LiveChrome.tintOpacity)
            : SwiftUI.Color(red: 0xF4 / 255, green: 0xF4 / 255, blue: 0xF5 / 255).opacity(LiveChrome.tintOpacity)
    }

    /// The leading title-bar accessory: a divider after the traffic lights and the
    /// sidebar toggle. Hoisted out of `body` (rather than inlined in the title-bar
    /// `.background`) so the nested view-builder closures stay shallow — deeply
    /// nested builders with leading-dot style inference (`.separator`, `.borderless`)
    /// can defeat the type-checker on older compilers, collapsing to an empty closure.
    @ViewBuilder private var leadingTitlebarAccessory: some View {
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
    }

    /// The trailing title-bar accessory: the inspector status chip.
    @ViewBuilder private var trailingTitlebarAccessory: some View {
        HStack(spacing: 0) {
            StatusChip(status: session.inspectorStatus)
            SwiftUI.Color.clear.frame(width: 22, height: 1)
        }
        .padding(.leading, 12)
        .frame(maxHeight: .infinity)
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
        .background {
            TitlebarAccessory(attribute: .leading, content: AnyView(leadingTitlebarAccessory))
        }
        .background {
            TitlebarAccessory(attribute: .trailing, content: AnyView(trailingTitlebarAccessory))
        }
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

                // Transient states play over the stage. Compiling covers it with
                // the design's clean rebuild screen; a compile error shows the
                // diagnostic. (Both also flip the title-bar status chip.)
                if session.inspectorStatus == .compiling {
                    CompilingState().transition(.opacity)
                } else if let error = session.errorMessage {
                    CompileErrorState(message: error).transition(.opacity)
                }

                if showReloadedToast {
                    ReloadedToast(count: session.reloadCount, buildSeconds: session.lastBuildSeconds)
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
                    CompilingState()
                }
            }
            .frame(width: OllinApp.defaultWindowSize.width, height: OllinApp.defaultWindowSize.height)
        }
    }

    private func flashReloadedToast() {
        withAnimation { showReloadedToast = true }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation { showReloadedToast = false }
        }
    }
}

// MARK: - Transient states

/// The "Compiling…" screen (the design's `.o-state`): a ring spinner, title, and
/// subtitle centered on the stage background, covering the canvas while a build is
/// in flight. Shown both at first launch (empty stage) and on every reload; the
/// title-bar status chip turns amber in concert.
private struct CompilingState: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 16) {
            RingSpinner()
            Text("Compiling…").font(.system(size: 15, weight: .semibold))
            Text("Rebuilding the sketch. The window stays open — your tuned values are preserved across the reload.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 280)
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LiveChrome.stageBackground(colorScheme))
    }
}

/// A thin ring spinner — a faint track ring with a rotating accent arc — matching
/// the design's `.o-spinner` (the macOS `ProgressView` is a different idiom).
private struct RingSpinner: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var spinning = false

    private var track: SwiftUI.Color {
        colorScheme == .dark ? .white.opacity(0.12) : .black.opacity(0.10)
    }

    var body: some View {
        ZStack {
            SwiftUI.Circle().stroke(track, lineWidth: 2.5)
            SwiftUI.Circle()
                .trim(from: 0, to: 0.28)
                .stroke(.purple, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
        .frame(width: 30, height: 30)
        .rotationEffect(.degrees(spinning ? 360 : 0))
        .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: spinning)
        .onAppear { spinning = true }
    }
}

/// The compile-error state: the diagnostic lives here in the canvas (never the
/// sidebar). On a reload it floats over the dimmed last good frame.
private struct CompileErrorState: View {
    let message: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                SwiftUI.Circle().fill(OllinInspector.red.opacity(0.15)).frame(width: 46, height: 46)
                SwiftUI.Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 22)).foregroundStyle(OllinInspector.red)
            }
            Text("Compile failed").font(.system(size: 15, weight: .semibold))
            Text(formattedError)
                .font(.system(size: 11.5, design: .monospaced))
                .textSelection(.enabled)
                .multilineTextAlignment(.leading)
                .lineSpacing(4)
                .frame(maxWidth: 640, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(OllinInspector.red.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(OllinInspector.red.opacity(0.25), lineWidth: 0.5))
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LiveChrome.stageBackground(colorScheme))
    }

    /// Tidy the raw `swiftc` dump into the design's diagnostic: drop the redundant
    /// "compile failed —" lead, show paths as the bare filename (not the absolute
    /// path), and append the reassurance trailer — with `error:` in red and the
    /// trailer dimmed.
    private var formattedError: AttributedString {
        var text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        text = text.replacingOccurrences(of: #"^compile failed\s*—\s*"#, with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: #"/\S+/([^/\s]+\.swift)"#, with: "$1", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        let trailer = "Last good frame held until the next save."
        var attr = AttributedString(text + "\n\n" + trailer)
        var cursor = attr.startIndex
        while let range = attr[cursor...].range(of: "error:") {
            attr[range].foregroundColor = OllinInspector.red
            cursor = range.upperBound
        }
        if let range = attr.range(of: trailer) {
            attr[range].foregroundColor = .secondary
        }
        return attr
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
private struct TitlebarAccessory: NSViewRepresentable {
    var attribute: NSLayoutConstraint.Attribute = .trailing
    // A type-erased, eagerly built `AnyView` rather than a generic `@ViewBuilder`
    // closure: the caller wraps its content with `AnyView(...)` in the (main-actor)
    // `body`, so this type carries no generic `Content` to infer and no deferred
    // closure whose isolation the type-checker has to reason about. Older compilers
    // (the CI toolchain) choked on the generic builder form inside `.background`,
    // collapsing it to an empty closure; the erased value sidesteps that entirely.
    var content: AnyView

    private var tag: NSUserInterfaceItemIdentifier {
        NSUserInterfaceItemIdentifier(attribute == .leading ? "ollin.titlebar.leading" : "ollin.titlebar.trailing")
    }

    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }

    func updateNSView(_ nsView: NSView, context: Context) {
        sync(near: nsView, content: content, attempt: 0)
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

/// A brief frosted confirmation after a hot reload, top-center of the stage:
/// a green check, "Reloaded", and a muted `build {x}s · #{n}` readout — the
/// design's `.o-toast` (a `--hud` frosted rounded-rect with a hairline edge).
private struct ReloadedToast: View {
    let count: Int
    var buildSeconds: Double?

    @Environment(\.colorScheme) private var colorScheme

    /// `--hud`, dialed translucent at the shared chrome opacity: a dark tint over
    /// the material blur, light enough that the frosted blur reads through (the
    /// 0.78 design token looks opaque over a bright sketch).
    private var hudTint: SwiftUI.Color {
        colorScheme == .dark
            ? SwiftUI.Color(red: 20 / 255, green: 20 / 255, blue: 22 / 255).opacity(LiveChrome.tintOpacity)
            : SwiftUI.Color(red: 248 / 255, green: 248 / 255, blue: 250 / 255).opacity(LiveChrome.tintOpacity)
    }

    /// `--glass-stroke`: the hairline edge on the frosted surface.
    private var glassStroke: SwiftUI.Color {
        colorScheme == .dark ? .white.opacity(0.12) : .white.opacity(0.7)
    }

    private var subtitle: String {
        if let buildSeconds { return String(format: "build %.2fs · #%d", buildSeconds, count) }
        return "#\(count)"
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return HStack(spacing: 9) {
            ZStack {
                SwiftUI.Circle().fill(OllinInspector.green).frame(width: 16, height: 16)
                SwiftUI.Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
            }
            Text("Reloaded").font(.system(size: 12.5, weight: .medium))
            Text(subtitle)
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
        }
        .padding(.leading, 11)
        .padding(.trailing, 14)
        .padding(.vertical, 9)
        .background {
            shape.fill(.ultraThinMaterial)
                .overlay(shape.fill(hudTint))
                .overlay(shape.strokeBorder(glassStroke, lineWidth: 0.5))
        }
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }
}
