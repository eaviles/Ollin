import SwiftUI
import AppKit
import Ollin

/// The performance window: the sketch letterboxed on a black stage, the code
/// riding over it as translucent text, and the transient chrome (status chip,
/// evaluated toast, error strip, recovery banner) as stage overlays so they
/// survive fullscreen, where the title bar hides. The optional inspector
/// docks on the trailing edge.
struct LiveCodingRootView: View {
    static let sidebarShownKey = "ollin.livecoding.sidebarShown"
    static let codeHiddenKey = "ollin.livecoding.codeHidden"
    static let fontSizeKey = "ollin.livecoding.fontSize"
    static let backdropKey = "ollin.livecoding.backdrop"

    let session: PerformanceSession

    @AppStorage(Self.sidebarShownKey) private var sidebarShown = false
    @AppStorage(Self.codeHiddenKey) private var codeHidden = false
    @AppStorage(Self.fontSizeKey) private var fontSize = 15.0
    @AppStorage(Self.backdropKey) private var backdrop = 0.55
    @SwiftUI.Environment(\.colorScheme) private var colorScheme

    @State private var showEvaluatedToast = false
    @State private var toastHide: Task<Void, Never>?

    private var sidebarScrim: SwiftUI.Color {
        colorScheme == .dark
            ? SwiftUI.Color(red: 0x23 / 255, green: 0x23 / 255, blue: 0x25 / 255)
                .opacity(OllinInspector.chromeTintOpacity)
            : SwiftUI.Color(red: 0xF4 / 255, green: 0xF4 / 255, blue: 0xF5 / 255)
                .opacity(OllinInspector.chromeTintOpacity)
    }

    var body: some View {
        HStack(spacing: 0) {
            stage
            if sidebarShown {
                sidebar
            }
        }
        .overlay(alignment: .top) {
            SwiftUI.Rectangle().fill(OllinInspector.separator(colorScheme)).frame(height: 0.5)
        }
        .frame(minWidth: 480, minHeight: 360)
        .navigationTitle(session.title)
        .background(WindowCustomizer { window in
            window.titlebarSeparatorStyle = .none
            // The stage is the projection surface: let the window go fullscreen
            // (neither sibling host does, so this is per-window, not shared).
            window.collectionBehavior.insert(.fullScreenPrimary)
            session.window = window
        })
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(session.title).font(.system(size: 13.5, weight: .semibold))
            }
            .sharedBackgroundVisibility(.hidden)   // drop the glass capsule around the title
        }
        .toolbarBackground(OllinInspector.titleBarGradient(colorScheme), for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .task { session.start() }
        .onChange(of: session.evaluateCount) { _, count in
            guard count > 0 else { return }
            flashEvaluatedToast()
        }
        .onChange(of: codeHidden) { _, hidden in
            // Projection mode hands the keys over: with the code away, a canvas
            // click gives the sketch the keyboard; showing the code takes it back.
            if hidden { session.editor.resignFocus() } else { session.editor.focus() }
        }
    }

    // MARK: - Stage

    private var stage: some View {
        ZStack {
            SwiftUI.Color.black

            if let sketch = session.core.sketch {
                SketchView(sketch, stats: session.core.stats,
                           showsInspectorPanel: false,
                           keyboardFocus: .onClick) { runner in
                    session.core.attach(runner)
                }
                // The letterbox must live here in layout: the canvas view
                // stretches to whatever frame it's given (and maps the mouse by
                // its bounds), so preserving the sketch's aspect at this level
                // keeps both rendering and mouse coordinates exact.
                .aspectRatio(session.stageFillsWindow ? nil : session.stageAspect,
                             contentMode: .fit)
            }

            // Hidden by opacity, never by structure: tearing the editor out of
            // the hierarchy would destroy the buffer and its undo stack.
            CodeEditorView(controller: session.editor,
                           fontSize: fontSize,
                           backdropOpacity: backdrop)
                .opacity(codeHidden ? 0 : 1)
                .allowsHitTesting(!codeHidden)
        }
        .overlay(alignment: .topTrailing) {
            VStack(alignment: .trailing, spacing: 8) {
                if session.chipStatus != .watching {
                    StatusChip(status: session.chipStatus)
                }
                if session.isRecording {
                    RecordingChip(session: session)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if let saved = session.recordingSaved {
                    SavedRecordingToast(name: saved)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if showEvaluatedToast {
                    EvaluatedToast(count: session.evaluateCount,
                                   buildSeconds: session.core.lastBuildSeconds)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(14)
            .animation(.easeInOut(duration: 0.18), value: session.chipStatus)
            .animation(.easeInOut(duration: 0.18), value: session.isRecording)
            .animation(.easeInOut(duration: 0.18), value: session.recordingSaved == nil)
        }
        .overlay(alignment: .bottom) {
            if !session.diagnostics.isEmpty || session.core.errorMessage != nil {
                DiagnosticsStrip(diagnostics: session.diagnostics,
                                 fallback: session.core.errorMessage) { diagnostic in
                    session.editor.jump(toLine: diagnostic.line, column: diagnostic.column)
                }
                .padding(.bottom, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .top) {
            if session.recoveryAvailable != nil {
                RecoveryBanner(restore: { session.restoreRecovery() },
                               discard: { session.discardRecovery() })
                    .padding(.top, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: session.diagnostics.isEmpty)
        .animation(.easeInOut(duration: 0.18), value: session.recoveryAvailable == nil)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sidebar: some View {
        ScrollView {
            GlassEffectContainer(spacing: 16) {
                VStack(spacing: 16) {
                    MonitorCardView(
                        identity: MonitorIdentity(name: session.displayName,
                                                  folder: session.folderDisplay),
                        stats: session.core.stats, reloads: session.core.reloadCount)
                    VariationCardView(stats: session.core.stats) { seed in
                        session.core.recordSeed(seed)
                    }
                    ParametersListView(params: session.core.params,
                                       onChange: { name, value in
                                           session.core.recordParam(name, value)
                                       },
                                       save: session.saveAction)
                }
            }
            .padding(14)
        }
        .frame(width: OllinInspector.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background {
            ZStack {
                SidebarVibrancy()
                sidebarScrim
            }
        }
        .overlay(alignment: .leading) {
            SwiftUI.Rectangle().fill(OllinInspector.separator(colorScheme)).frame(width: 0.5)
        }
    }

    private func flashEvaluatedToast() {
        toastHide?.cancel()
        withAnimation { showEvaluatedToast = true }
        toastHide = Task {
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            withAnimation { showEvaluatedToast = false }
        }
    }
}

/// The on-air light: a red dot and the take's elapsed time, ticking while the
/// stage is being recorded.
private struct RecordingChip: View {
    let session: PerformanceSession

    @SwiftUI.Environment(\.colorScheme) private var colorScheme

    private func clock(_ seconds: Double) -> String {
        let whole = Int(seconds)
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        return TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            HStack(spacing: 8) {
                SwiftUI.Circle().fill(OllinInspector.red).frame(width: 10, height: 10)
                Text("Recording").font(.system(size: 12, weight: .medium))
                Text(clock(session.core.currentSketch?.recordingElapsed ?? 0))
                    .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: shape)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.14), radius: 12, y: 5)
    }
}

/// A brief "the take is on disk" confirmation, named so it can be found.
private struct SavedRecordingToast: View {
    let name: String

    @SwiftUI.Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        return HStack(spacing: 8) {
            SwiftUI.Image(systemName: "film")
                .font(.system(size: 11)).foregroundStyle(OllinInspector.green)
            Text("Saved").font(.system(size: 12, weight: .medium))
            Text(name)
                .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: shape)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.14), radius: 12, y: 5)
    }
}

/// A brief "that ran" confirmation: check, evaluation number, build seconds.
private struct EvaluatedToast: View {
    let count: Int
    var buildSeconds: Double?

    @SwiftUI.Environment(\.colorScheme) private var colorScheme

    private var subtitle: String {
        if let buildSeconds { return String(format: "%.2fs · #%d", buildSeconds, count) }
        return "#\(count)"
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        return HStack(spacing: 8) {
            ZStack {
                SwiftUI.Circle().fill(OllinInspector.green).frame(width: 14, height: 14)
                SwiftUI.Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
            }
            Text("Evaluated").font(.system(size: 12, weight: .medium))
            Text(subtitle)
                .font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary)
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: shape)
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.14), radius: 12, y: 5)
    }
}

/// Offered once at launch when a newer autosave outlived the last session.
private struct RecoveryBanner: View {
    let restore: @MainActor () -> Void
    let discard: @MainActor () -> Void

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return HStack(spacing: 12) {
            SwiftUI.Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 13)).foregroundStyle(OllinInspector.amber)
            Text("Unsaved changes from the last session")
                .font(.system(size: 12, weight: .medium))
            Button("Restore") { restore() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(OllinInspector.accent)
            Button("Discard") { discard() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassEffect(.regular, in: shape)
    }
}
