import SwiftUI
import Ollin

/// The live host's window: the sketch renders in the detail pane; the sidebar
/// inspector shows reload status. The sketch's `SketchRunner` is created here
/// (the detail view owns the `MTKView`) and handed to the session so the
/// watcher can drive hot-swaps.
struct LiveRootView: View {
    /// Fixed inspector width. The detail pane is pinned to the sketch's square, so
    /// the window is exactly `square + sidebarWidth` wide and can't be resized;
    /// collapsing the inspector narrows it to just the square.
    static let sidebarWidth: CGFloat = 280

    let session: LiveSession

    var body: some View {
        NavigationSplitView {
            InspectorPanel(session: session)
                .navigationSplitViewColumnWidth(Self.sidebarWidth)
        } detail: {
            detail.navigationTitle(session.title)
        }
        .task { session.start() }
    }

    // Lightweight until the first compile lands: a plain SwiftUI placeholder, not
    // a Metal view (mounting an MTKView at launch kept the window from surfacing).
    // Once `sketch` is set, the SketchView mounts and creates the runner.
    // Pinned to a fixed square so the sketch renders at its true size (never
    // stretched to fill the pane) and the window stays square across reloads.
    @ViewBuilder private var detail: some View {
        Group {
            if let sketch = session.sketch {
                SketchView(sketch) { runner in session.attach(runner) }
                    .frame(width: OllinApp.windowSize(for: sketch).width,
                           height: OllinApp.windowSize(for: sketch).height)
            } else if let error = session.errorMessage {
                ContentUnavailableView {
                    Label("Compile error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            } else {
                ProgressView("Compiling \(session.displayName)…")
            }
        }
        .frame(width: OllinApp.defaultWindowSize.width, height: OllinApp.defaultWindowSize.height)
    }
}
